import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../shared/providers/exam_provider.dart';
import '../../../shared/services/notification_scheduler.dart';
import '../../../shared/services/smart_notification_service.dart';
import '../../../shared/theme/app_palette.dart';
import '../../../shared/utils/user_messages.dart';
import '../../../shared/widgets/app_widgets.dart';
import '../../progress/widgets/exam_date_card.dart';

class NotificationSettingsScreen extends ConsumerStatefulWidget {
  const NotificationSettingsScreen({super.key});

  @override
  ConsumerState<NotificationSettingsScreen> createState() =>
      _NotificationSettingsScreenState();
}

class _NotificationSettingsScreenState
    extends ConsumerState<NotificationSettingsScreen> {
  final _svc = SmartNotificationService();
  bool _loading = true;
  bool _loadFailed = false;
  Map<String, bool> _prefs = {};
  int _studyHour = 20;
  int _studyMinute = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _loadFailed = false;
    });
    try {
      final prefs = await _svc.getChannelPrefs();
      final (h, m) = await _svc.getStudyTime();
      if (!mounted) return;
      setState(() {
        _prefs = prefs;
        _studyHour = h;
        _studyMinute = m;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _loadFailed = true;
      });
    }
  }

  static const _permissionDeniedMessage =
      'Allow notifications for Quirzy in your phone settings to get reminders.';

  Future<void> _toggle(String key, bool value) async {
    HapticFeedback.lightImpact();
    final previous = _prefs[key] ?? false;
    setState(() => _prefs[key] = value);
    try {
      if (value) {
        // Turned on: ask for permission first. Without it the reminder
        // can never fire, so leave the switch off and say why.
        final granted = await _svc.requestPermission();
        if (!granted) {
          await _svc.setChannelPref(key, false);
          if (!mounted) return;
          setState(() => _prefs[key] = false);
          showAppSnack(context, _permissionDeniedMessage);
          return;
        }
      }
      await _svc.setChannelPref(key, value);
      if (!value) return;

      // Schedule it right away.
      await ref.read(notificationSchedulerProvider).reschedule(key);

      if (key == NotificationScheduler.examCountdown &&
          ref.read(examDateProvider).value == null &&
          mounted) {
        await pickExamDate(context, ref);
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _prefs[key] = previous);
      showAppSnack(
        context,
        "Couldn't update that reminder. Please try again.",
        onRetry: () => _toggle(key, value),
      );
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
    try {
      await _svc.setChannelPref('notif_study_time', true);
      await _svc.scheduleStudyTimeReminder(
          hour: picked.hour, minute: picked.minute);
    } catch (e) {
      if (!mounted) return;
      showAppSnack(
        context,
        "Couldn't set your reminder time. Please try again.",
        onRetry: _pickStudyTime,
      );
    }
  }

  Widget _buildLoadError() {
    final t = Theme.of(context).textTheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpace.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              "Couldn't load your notification settings. Please try again.",
              textAlign: TextAlign.center,
              style: t.bodyMedium,
            ),
            const SizedBox(height: AppSpace.lg),
            AppButton.secondary(
              label: 'Retry',
              icon: Icons.refresh_rounded,
              expanded: false,
              onPressed: _load,
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final t = Theme.of(context).textTheme;
    final examDate = ref.watch(examDateProvider).value;

    return Scaffold(
      appBar: AppBar(title: const Text('Notifications')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _loadFailed
          ? _buildLoadError()
          : ListView(
              padding: const EdgeInsets.all(20),
              children: [
                _header(
                  'Only what matters',
                  'Quirzy sends a few useful reminders, never hourly spam.',
                ),

                _section('Revision', [
                  _channelTile(
                    icon: Icons.style_rounded,
                    iconColor: p.accentText,
                    title: 'Revision due reminders',
                    subtitle:
                        'Tells you how many practice questions are due and estimated time',
                    prefKey: 'notif_srs',
                  ),
                ]),

                _section('Streak and motivation', [
                  _channelTile(
                    icon: Icons.local_fire_department_rounded,
                    iconColor: p.streak,
                    title: 'Streak protection',
                    subtitle:
                        'Alert at 9 PM if you haven\'t studied yet — saves your streak',
                    prefKey: 'notif_streak',
                  ),
                  _channelTile(
                    icon: Icons.calendar_today_rounded,
                    iconColor: p.success,
                    title: 'Exam countdown',
                    subtitle: examDate == null
                        ? 'Weekly days-left reminder. Needs your exam date.'
                        : 'Sunday morning reminder of the days left to ${examDisplayName(ref.watch(examProvider))}',
                    prefKey: 'notif_exam_countdown',
                  ),
                  if (examDate == null &&
                      _prefs['notif_exam_countdown'] == true)
                    _examDatePrompt(),
                ]),

                _section('Progress and insights', [
                  _channelTile(
                    icon: Icons.bar_chart_rounded,
                    iconColor: p.accentText,
                    title: 'Weekly digest',
                    subtitle: 'Sunday morning: questions practised and your streak',
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

                _section('Study time reminder', [
                  _channelTile(
                    icon: Icons.alarm_rounded,
                    iconColor: p.like,
                    title: 'Daily study alarm',
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
          style: t.labelLarge!.copyWith(
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

  Widget _examDatePrompt() {
    final p = context.palette;
    final t = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: AppCard(
        color: p.accentSoft,
        borderColor: p.accentText.withValues(alpha: 0.3),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        onTap: () => pickExamDate(context, ref),
        child: Row(
          children: [
            Icon(Icons.event_rounded, color: p.accentText, size: 20),
            const SizedBox(width: 12),
            Expanded(
              child: Text('Add your exam date to get the countdown',
                  style: t.titleSmall),
            ),
            Text(
              'Set date',
              style: t.labelMedium!.copyWith(
                fontWeight: FontWeight.w800,
                color: p.accentText,
              ),
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
                'Reminder at ${TimeOfDay(hour: _studyHour, minute: _studyMinute).format(context)}',
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
