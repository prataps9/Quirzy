import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:timezone/data/latest.dart' as tz_data;
import 'package:shared_preferences/shared_preferences.dart';

// Notification IDs (stable — never reuse an ID for a different purpose)
class _NIds {
  static const int srsReminder = 100;
  static const int streakWarning = 200;
  static const int streakLost = 201;
  static const int examCountdown = 300;
  static const int weeklyDigest = 400;
  static const int reEngagement = 500;
  static const int studyTime = 700;
}

// Notification channel IDs
class _Channels {
  static const String srs = 'srs_reminders';
  static const String streak = 'streak_protection';
  static const String exam = 'exam_countdown';
  static const String digest = 'weekly_digest';
  static const String reEngage = 're_engagement';
  static const String study = 'study_time';
}

class SmartNotificationService {
  static final SmartNotificationService _instance =
      SmartNotificationService._internal();
  factory SmartNotificationService() => _instance;
  SmartNotificationService._internal();

  final _plugin = FlutterLocalNotificationsPlugin();
  bool _ready = false;

  // ── Init ───────────────────────────────────────────────────────────────────

  Future<void> init() async {
    if (_ready) return;
    tz_data.initializeTimeZones();
    await _setLocalLocation();

    const android = AndroidInitializationSettings('@mipmap/ic_launcher');
    const ios = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );

    await _plugin.initialize(
      const InitializationSettings(android: android, iOS: ios),
    );
    _ready = true;
  }

  /// Points `tz.local` at the device's zone so scheduled times are local,
  /// not UTC. Falls back to a zone whose current offset matches the device.
  Future<void> _setLocalLocation() async {
    try {
      final info = await FlutterTimezone.getLocalTimezone();
      tz.setLocalLocation(tz.getLocation(info.identifier));
      return;
    } catch (e) {
      debugPrint('SmartNotificationService: timezone plugin failed: $e');
    }
    try {
      final now = DateTime.now();
      final offsetMs = now.timeZoneOffset.inMilliseconds;
      final matches = tz.timeZoneDatabase.locations.values
          .where((l) => l.currentTimeZone.offset == offsetMs)
          .toList();
      if (matches.isEmpty) return;
      final byAbbreviation = matches.where(
          (l) => l.currentTimeZone.abbreviation == now.timeZoneName);
      tz.setLocalLocation(
          byAbbreviation.isNotEmpty ? byAbbreviation.first : matches.first);
    } catch (e) {
      debugPrint('SmartNotificationService: timezone fallback failed: $e');
    }
  }

  Future<void> _ensureReady() async {
    if (!_ready) await init();
  }

  // ── Permission request ─────────────────────────────────────────────────────

  Future<bool> requestPermission() async {
    await _ensureReady();
    final android = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    final granted = await android?.requestNotificationsPermission();
    return granted ?? true;
  }

  // ── SRS Reminders ─────────────────────────────────────────────────────────
  // Called on app open; shows immediately if cards are due.

  Future<void> scheduleSrsReminder({
    required int dueCount,
    required int studyHour,
    required int studyMinute,
  }) async {
    await _ensureReady();
    await _plugin.cancel(_NIds.srsReminder);
    if (dueCount == 0) return;

    final prefs = await SharedPreferences.getInstance();
    if (!(prefs.getBool('notif_srs') ?? true)) return;

    final body = dueCount == 1
        ? '1 question is ready for revision'
        : '$dueCount questions are ready for revision — takes ~${(dueCount * 0.4).ceil()} min';

    await _plugin.zonedSchedule(
      _NIds.srsReminder,
      'Revision due',
      body,
      _todayAt(studyHour, studyMinute),
      _details(_Channels.srs, 'Revision Reminders',
          'Spaced repetition review reminders'),
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      matchDateTimeComponents: DateTimeComponents.time,
    );
  }

  // ── Streak Protection ─────────────────────────────────────────────────────
  // 9 PM today if the user hasn't studied yet. Once they have, pass
  // [studiedToday] = true to move the alert to 9 PM tomorrow instead.

  Future<void> scheduleStreakProtection({
    required int currentStreak,
    required bool studiedToday,
    bool freezeReady = false,
  }) async {
    await _ensureReady();
    await _plugin.cancel(_NIds.streakWarning);

    final prefs = await SharedPreferences.getInstance();
    if (!(prefs.getBool('notif_streak') ?? true)) return;

    final now = tz.TZDateTime.now(tz.local);
    var fireAt = tz.TZDateTime(tz.local, now.year, now.month, now.day, 21);
    if (studiedToday) {
      fireAt = tz.TZDateTime(tz.local, now.year, now.month, now.day + 1, 21);
    } else if (fireAt.isBefore(now)) {
      // Too late for tonight's alert; tomorrow's would describe a streak
      // that has already ended.
      if (currentStreak > 0) return;
      fireAt = tz.TZDateTime(tz.local, now.year, now.month, now.day + 1, 21);
    }

    final body = currentStreak <= 1
        ? 'Start your streak today — just 5 minutes of practice.'
        : freezeReady
        ? "Practise today to keep your $currentStreak-day streak. Miss it and this week's streak freeze steps in, once."
        : 'Your $currentStreak-day streak ends at midnight. A quick practice keeps it going.';

    await _plugin.zonedSchedule(
      _NIds.streakWarning,
      currentStreak > 1 ? 'Streak at risk' : 'Build your streak',
      body,
      fireAt,
      _details(_Channels.streak, 'Streak Protection',
          'Alerts when your daily streak is at risk'),
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
    );
  }

  Future<void> showStreakLostNotification(int lostStreak) async {
    await _ensureReady();
    final prefs = await SharedPreferences.getInstance();
    if (!(prefs.getBool('notif_streak') ?? true)) return;

    await _plugin.show(
      _NIds.streakLost,
      'Streak lost',
      'Your $lostStreak-day streak ended. Start fresh today!',
      _details(_Channels.streak, 'Streak Protection',
          'Alerts when your daily streak is at risk'),
    );
  }

  // ── Exam Countdown ────────────────────────────────────────────────────────
  // Next Sunday 8 AM, one-shot. Re-scheduled on every app open so the day
  // count in the text is always measured from the day it fires.

  Future<void> scheduleExamCountdown({
    required String examName,
    required DateTime examDate,
  }) async {
    await _ensureReady();
    await _plugin.cancel(_NIds.examCountdown);

    final prefs = await SharedPreferences.getInstance();
    if (!(prefs.getBool('notif_exam_countdown') ?? true)) return;

    final fireAt = _nextWeekday(DateTime.sunday, 8, 0);
    final daysLeft = DateTime.utc(examDate.year, examDate.month, examDate.day)
        .difference(DateTime.utc(fireAt.year, fireAt.month, fireAt.day))
        .inDays;
    if (daysLeft <= 0) return;

    final days = daysLeft == 1 ? '1 day' : '$daysLeft days';
    String body;
    if (daysLeft <= 7) {
      body = '$examName is in $days. Focus on your weak topics.';
    } else if (daysLeft <= 30) {
      body = '$days to $examName. Practise and review your weak topics.';
    } else {
      body = '$days to $examName. Steady daily practice adds up.';
    }

    await _plugin.zonedSchedule(
      _NIds.examCountdown,
      '$examName countdown',
      body,
      fireAt,
      _details(_Channels.exam, 'Exam Countdown',
          'Weekly countdown to your exam date'),
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
    );
  }

  Future<void> cancelExamCountdown() async {
    await _ensureReady();
    await _plugin.cancel(_NIds.examCountdown);
  }

  // ── Weekly Digest ─────────────────────────────────────────────────────────
  // Sunday 9 AM — your week in numbers.

  Future<void> scheduleWeeklyDigest({
    required int questionsThisWeek,
    required int flashcardsReviewed,
    required int bestStreak,
  }) async {
    await _ensureReady();
    await _plugin.cancel(_NIds.weeklyDigest);

    final prefs = await SharedPreferences.getInstance();
    if (!(prefs.getBool('notif_weekly_digest') ?? true)) return;

    final parts = [
      '$questionsThisWeek questions',
      if (flashcardsReviewed > 0) '$flashcardsReviewed cards',
      '$bestStreak-day streak',
    ];
    final body = '${parts.join(' · ')}. Keep the momentum!';

    await _plugin.zonedSchedule(
      _NIds.weeklyDigest,
      'Your weekly study wrap-up',
      body,
      _nextWeekday(DateTime.sunday, 9, 0),
      _details(_Channels.digest, 'Weekly Digest',
          'Sunday summary of your study activity'),
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      matchDateTimeComponents: DateTimeComponents.dayOfWeekAndTime,
    );
  }

  // ── Re-engagement ─────────────────────────────────────────────────────────
  // Fires 48 hours after last activity.

  Future<void> scheduleReEngagement() async {
    await _ensureReady();
    await _plugin.cancel(_NIds.reEngagement);

    final prefs = await SharedPreferences.getInstance();
    if (!(prefs.getBool('notif_re_engage') ?? true)) return;

    final messages = [
      'A few minutes of practice keeps it fresh. 5 questions?',
      'Back to studying? Your progress is waiting.',
      'Quick practice to warm up? Just 5 questions.',
    ];
    final idx = DateTime.now().day % messages.length;

    final fireAt = tz.TZDateTime.now(tz.local).add(const Duration(hours: 48));

    await _plugin.zonedSchedule(
      _NIds.reEngagement,
      'Still prepping for your exam?',
      messages[idx],
      fireAt,
      _details(_Channels.reEngage, 'Re-engagement',
          'Gentle nudges after inactivity'),
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
    );
  }

  Future<void> cancelReEngagement() async {
    await _ensureReady();
    await _plugin.cancel(_NIds.reEngagement);
  }

  // ── Custom Study Time ─────────────────────────────────────────────────────

  Future<void> scheduleStudyTimeReminder({
    required int hour,
    required int minute,
    String? customMessage,
  }) async {
    await _ensureReady();
    await _plugin.cancel(_NIds.studyTime);

    final prefs = await SharedPreferences.getInstance();
    if (!(prefs.getBool('notif_study_time') ?? true)) return;

    await _saveStudyTime(hour, minute);

    final body = customMessage ?? 'Time to study. Even 20 minutes compounds.';

    await _plugin.zonedSchedule(
      _NIds.studyTime,
      'Study reminder',
      body,
      _todayAt(hour, minute),
      _details(_Channels.study, 'Study Time', 'Daily study reminders'),
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      matchDateTimeComponents: DateTimeComponents.time,
    );
  }

  Future<void> cancelStudyTimeReminder() async {
    await _ensureReady();
    await _plugin.cancel(_NIds.studyTime);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('notif_study_time', false);
  }

  // ── Cancel all ─────────────────────────────────────────────────────────────

  Future<void> cancelAll() async {
    await _ensureReady();
    await _plugin.cancelAll();
  }

  // ── Preferences helpers ───────────────────────────────────────────────────

  Future<Map<String, bool>> getChannelPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    return {
      'notif_srs': prefs.getBool('notif_srs') ?? true,
      'notif_streak': prefs.getBool('notif_streak') ?? true,
      'notif_exam_countdown': prefs.getBool('notif_exam_countdown') ?? true,
      'notif_weekly_digest': prefs.getBool('notif_weekly_digest') ?? true,
      'notif_re_engage': prefs.getBool('notif_re_engage') ?? true,
      'notif_study_time': prefs.getBool('notif_study_time') ?? false,
    };
  }

  Future<void> setChannelPref(String key, bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(key, value);
    if (!value) {
      // Cancel the relevant notification
      switch (key) {
        case 'notif_srs':
          await _plugin.cancel(_NIds.srsReminder);
          break;
        case 'notif_streak':
          await _plugin.cancel(_NIds.streakWarning);
          await _plugin.cancel(_NIds.streakLost);
          break;
        case 'notif_exam_countdown':
          await _plugin.cancel(_NIds.examCountdown);
          break;
        case 'notif_weekly_digest':
          await _plugin.cancel(_NIds.weeklyDigest);
          break;
        case 'notif_re_engage':
          await _plugin.cancel(_NIds.reEngagement);
          break;
        case 'notif_study_time':
          await _plugin.cancel(_NIds.studyTime);
          break;
      }
    }
  }

  Future<(int, int)> getStudyTime() async {
    final prefs = await SharedPreferences.getInstance();
    final h = prefs.getInt('study_reminder_hour') ?? 20;
    final m = prefs.getInt('study_reminder_minute') ?? 0;
    return (h, m);
  }

  Future<void> _saveStudyTime(int hour, int minute) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('study_reminder_hour', hour);
    await prefs.setInt('study_reminder_minute', minute);
  }

  // ── Internal helpers ──────────────────────────────────────────────────────

  NotificationDetails _details(
      String channelId, String channelName, String description) {
    return NotificationDetails(
      android: AndroidNotificationDetails(
        channelId,
        channelName,
        channelDescription: description,
        importance: Importance.high,
        priority: Priority.high,
        icon: '@mipmap/ic_launcher',
      ),
      iOS: const DarwinNotificationDetails(
        presentAlert: true,
        presentBadge: true,
        presentSound: true,
      ),
    );
  }

  tz.TZDateTime _todayAt(int hour, int minute) {
    final now = tz.TZDateTime.now(tz.local);
    var t = tz.TZDateTime(tz.local, now.year, now.month, now.day, hour, minute);
    if (t.isBefore(now)) t = t.add(const Duration(days: 1));
    return t;
  }

  tz.TZDateTime _nextWeekday(int weekday, int hour, int minute) {
    var now = tz.TZDateTime.now(tz.local);
    var t = tz.TZDateTime(tz.local, now.year, now.month, now.day, hour, minute);
    while (t.weekday != weekday || t.isBefore(now)) {
      t = t.add(const Duration(days: 1));
    }
    return t;
  }
}
