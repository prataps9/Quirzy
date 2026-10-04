import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../shared/services/smart_notification_service.dart';
import '../../../shared/theme/app_palette.dart';
import '../../../shared/widgets/app_widgets.dart';

class NotificationSettingsScreen extends StatefulWidget {
  const NotificationSettingsScreen({super.key});

  @override
  State<NotificationSettingsScreen> createState() =>
      _NotificationSettingsScreenState();
}

class _NotificationSettingsScreenState
    extends State<NotificationSettingsScreen> {
  final _svc = SmartNotificationService();
  bool _loading = true;
  Map<String, bool> _prefs = {};
  int _studyHour = 20;
  int _studyMinute = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final prefs = await _svc.getChannelPrefs();
    final (h, m) = await _svc.getStudyTime();
    if (!mounted) return;
    setState(() {
      _prefs = prefs;
      _studyHour = h;
      _studyMinute = m;
      _loading = false;
    });
  }

  Future<void> _toggle(String key, bool value) async {
    HapticFeedback.lightImpact();
    setState(() => _prefs[key] = value);
    await _svc.setChannelPref(key, value);

    // Re-schedule study time when turned back on
    if (key == 'notif_study_time' && value) {
      await _svc.scheduleStudyTimeReminder(
          hour: _studyHour, minute: _studyMinute);
    }
  }

  Future<void> _pickStudyTime() async {
    HapticFeedback.lightImpact();
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: _studyHour, minute: _studyMinute),
    );
    if (picked == null || !mounted) return;
    setState(() {
      _studyHour = picked.hour;
      _studyMinute = picked.minute;
      _prefs['notif_study_time'] = true;
    });
    await _svc.scheduleStudyTimeReminder(
        hour: picked.hour, minute: picked.minute);
  }

  String _fmt(int h, int m) {
    final suffix = h < 12 ? 'AM' : 'PM';
    final hh = h == 0 ? 12 : (h > 12 ? h - 12 : h);
    final mm = m.toString().padLeft(2, '0');
    return '$hh:$mm $suffix';
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final t = Theme.of(context).textTheme;

    return Scaffold(
      appBar: AppBar(title: const Text('Notifications')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(20),
              children: [
                _header(
                  'What other apps miss',
                  'Most apps send hourly spam. ExamAI sends only what matters.',
                ),

                _section('Revision', [
                  _channelTile(
                    icon: Icons.style_rounded,
                    iconColor: p.accentText,
                    title: 'Revision Due Reminders',
                    subtitle:
                        'Tells you how many practice questions are due and estimated time',
                    prefKey: 'notif_srs',
                  ),
                ]),

                _section('Streak & Motivation', [
                  _channelTile(
                    icon: Icons.local_fire_department_rounded,
                    iconColor: p.streak,
                    title: 'Streak Protection',
                    subtitle:
                        'Alert at 9 PM if you haven\'t studied yet — saves your streak',
                    prefKey: 'notif_streak',
                  ),
                  _channelTile(
                    icon: Icons.calendar_today_rounded,
                    iconColor: p.success,
                    title: 'Exam Countdown',
                    subtitle: 'Weekly tip with days left to your target exam',
                    prefKey: 'notif_exam_countdown',
                  ),
                ]),

                _section('Progress & Insights', [
                  _channelTile(
                    icon: Icons.bar_chart_rounded,
                    iconColor: p.accentText,
                    title: 'Weekly Digest',
                    subtitle: 'Sunday morning: questions practiced, streak',
                    prefKey: 'notif_weekly_digest',
                  ),
                  _channelTile(
                    icon: Icons.wb_twilight_rounded,
                    iconColor: p.accentText,
                    title: 'Re-engagement',
                    subtitle: 'Gentle nudge after 48 hours of inactivity',
                    prefKey: 'notif_re_engage',
                  ),
                ]),

                _section('Study Time Reminder', [
                  _channelTile(
                    icon: Icons.alarm_rounded,
                    iconColor: p.like,
                    title: 'Daily Study Alarm',
                    subtitle: 'Fires every day at your chosen time',
                    prefKey: 'notif_study_time',
                  ),
                  if (_prefs['notif_study_time'] == true) _timePicker(),
                ]),

                const SizedBox(height: 24),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: Text(
                    'Notifications respect your schedule. No hourly spam, ever.',
                    style: t.bodySmall!.copyWith(height: 1.5),
                    textAlign: TextAlign.center,
                  ),
                ),
                const SizedBox(height: 40),
              ],
            ),
    );
  }

  Widget _header(String title, String subtitle) {
    final p = context.palette;
    final t = Theme.of(context).textTheme;
    return AppCard(
      padding: const EdgeInsets.all(18),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: p.accentSoft,
              borderRadius: BorderRadius.circular(AppRadius.chip),
            ),
            child: Icon(
              Icons.notifications_active_rounded,
              color: p.accentText,
              size: 22,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: t.titleSmall),
                const SizedBox(height: 3),
                Text(subtitle, style: t.bodySmall),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _section(String title, List<Widget> children) {
    final p = context.palette;
    final t = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 20),
        Text(
          title,
          style: t.labelMedium!.copyWith(
            fontSize: 13,
            color: p.textMuted,
            letterSpacing: 0.5,
          ),
        ),
        const SizedBox(height: 10),
        ...children,
      ],
    );
  }

  Widget _channelTile({
    required IconData icon,
    required Color iconColor,
    required String title,
    required String subtitle,
    required String prefKey,
  }) {
    final p = context.palette;
    final t = Theme.of(context).textTheme;
    final enabled = _prefs[prefKey] ?? false;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: AppCard(
        child: Row(
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: iconColor.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(AppRadius.chip),
              ),
              child: Icon(icon, color: iconColor, size: 20),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: t.titleSmall),
                  const SizedBox(height: 2),
                  Text(subtitle, style: t.bodySmall),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Switch.adaptive(
              value: enabled,
              onChanged: (val) => _toggle(prefKey, val),
              activeTrackColor: p.accent,
            ),
          ],
        ),
      ),
    );
  }

  Widget _timePicker() {
    final p = context.palette;
    final t = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: AppCard(
        color: p.accentSoft,
        borderColor: p.accentText.withValues(alpha: 0.3),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            Icon(Icons.access_time_rounded, color: p.accentText, size: 20),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                'Reminder at ${_fmt(_studyHour, _studyMinute)}',
                style: t.titleSmall,
              ),
            ),
            GestureDetector(
              onTap: _pickStudyTime,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                decoration: BoxDecoration(
                  color: p.accent,
                  borderRadius: BorderRadius.circular(AppRadius.pill),
                ),
                child: Text(
                  'Change',
                  style: t.labelMedium!.copyWith(
                    fontWeight: FontWeight.w800,
                    color: p.onAccent,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
