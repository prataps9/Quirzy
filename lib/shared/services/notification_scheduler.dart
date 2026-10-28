import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../features/feed/services/feed_revision_service.dart';
import '../../features/feed/services/feed_stats_service.dart';
import '../../features/feed/services/streak_service.dart';
import '../providers/exam_provider.dart';
import 'smart_notification_service.dart';

/// The one place that decides what local notifications are scheduled.
/// Screens call into this instead of talking to [SmartNotificationService]
/// directly. Every type still respects its on/off toggle (checked inside
/// [SmartNotificationService]), and no method here ever throws.
class NotificationScheduler {
  NotificationScheduler({
    SmartNotificationService? notifications,
    StreakService? streaks,
    FeedStatsService? stats,
    FeedRevisionService? revision,
  })  : _svc = notifications ?? SmartNotificationService(),
        _streaks = streaks ?? StreakService(),
        _stats = stats ?? FeedStatsService(),
        _revision = revision ?? FeedRevisionService();

  /// Payloads (see [NotificationRoute]) of notifications tapped while the
  /// app is running.
  Stream<String> get taps => _svc.taps;

  /// The payload of the notification that opened the app, once.
  Future<String?> takeLaunchPayload() async {
    try {
      return await _svc.takeLaunchPayload();
    } catch (e) {
      debugPrint('NotificationScheduler: launch payload unavailable: $e');
      return null;
    }
  }

  /// Pref keys of the per-type toggles, as used by [reschedule].
  static const srs = 'notif_srs';
  static const streak = 'notif_streak';
  static const examCountdown = 'notif_exam_countdown';
  static const weeklyDigest = 'notif_weekly_digest';
  static const reEngage = 'notif_re_engage';
  static const studyTime = 'notif_study_time';

  static const _lastStreakKey = 'notif_last_seen_streak';
  static const _permissionAskedKey = 'notif_permission_asked';

  final SmartNotificationService _svc;
  final StreakService _streaks;
  final FeedStatsService _stats;
  final FeedRevisionService _revision;

  /// Refreshes everything on app open: revision due, streak protection,
  /// streak lost, weekly digest, exam countdown and the 48h re-engagement.
  Future<void> onAppOpen() async {
    await _guard('re-engagement', _scheduleReEngagement);
    await _guard('streak', () async {
      final info = await _streaks.getStreak();
      await _checkStreakLost(info);
      await _scheduleStreak(info);
    });
    await _guard('srs', _scheduleSrs);
    await _guard('weekly digest', _scheduleDigest);
    await _guard('exam countdown', _scheduleExamCountdown);
  }

  /// The user practised today: move the streak alert to tomorrow evening.
  Future<void> onPractisedToday() async {
    await _guard('streak', () async {
      final info = await _streaks.getStreak();
      await _rememberStreak(info.current);
      await _svc.scheduleStreakProtection(
        currentStreak: info.current,
        studiedToday: true,
        freezeReady: info.freezeReady,
      );
    });
  }

  /// Asks for notification permission the first time only.
  Future<void> requestPermissionOnce() async {
    await _guard('permission', () async {
      final prefs = await SharedPreferences.getInstance();
      if (prefs.getBool(_permissionAskedKey) ?? false) return;
      await prefs.setBool(_permissionAskedKey, true);
      await _svc.requestPermission();
    });
  }

  /// Schedules one type right away, e.g. after its toggle is switched on.
  /// [prefKey] is one of the static keys above (`notif_srs`, ...).
  Future<void> reschedule(String prefKey) async {
    await _guard(prefKey, () async {
      switch (prefKey) {
        case srs:
          await _scheduleSrs();
        case streak:
          await _scheduleStreak(await _streaks.getStreak());
        case examCountdown:
          await _scheduleExamCountdown();
        case weeklyDigest:
          await _scheduleDigest();
        case reEngage:
          await _scheduleReEngagement();
        case studyTime:
          final (h, m) = await _svc.getStudyTime();
          await _svc.scheduleStudyTimeReminder(hour: h, minute: m);
        default:
          debugPrint('NotificationScheduler: unknown type $prefKey');
      }
    });
  }

  // ── Per-type scheduling ───────────────────────────────────────────────────

  Future<void> _scheduleReEngagement() => _svc.scheduleReEngagement();

  Future<void> _scheduleStreak(StreakInfo info) {
    return _svc.scheduleStreakProtection(
      currentStreak: info.current,
      studiedToday: info.practisedToday,
      freezeReady: info.freezeReady,
    );
  }

  Future<void> _scheduleSrs() async {
    final dueCount = await _revision.getDueCount();
    await _svc.scheduleSrsReminder(dueCount: dueCount, studyHour: 9, studyMinute: 0);
  }

  Future<void> _scheduleDigest() async {
    final weekCounts = await _stats.getDailyAnsweredCounts(days: 7);
    final info = await _streaks.getStreak();
    await _svc.scheduleWeeklyDigest(
      questionsThisWeek: weekCounts.fold<int>(0, (a, b) => a + b),
      flashcardsReviewed: await _streaks.flashcardsReviewed(days: 7),
      bestStreak: info.best,
    );
  }

  Future<void> _scheduleExamCountdown() async {
    final date = await readExamDate();
    if (date == null) {
      await _svc.cancelExamCountdown();
      return;
    }
    final prefs = await SharedPreferences.getInstance();
    await _svc.scheduleExamCountdown(
      examName: examDisplayName(prefs.getString('selected_exam')),
      examDate: date,
    );
  }

  /// Shows "streak lost" once when a streak of 2+ days broke since the
  /// last time we looked.
  Future<void> _checkStreakLost(StreakInfo info) async {
    final prefs = await SharedPreferences.getInstance();
    final last = prefs.getInt(_lastStreakKey);
    if (last != null && last >= 2 && info.current == 0) {
      await _svc.showStreakLostNotification(last);
    }
    await _rememberStreak(info.current);
  }

  Future<void> _rememberStreak(int current) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_lastStreakKey, current);
  }

  Future<void> _guard(String what, Future<void> Function() body) async {
    try {
      await body();
    } catch (e) {
      debugPrint('NotificationScheduler: $what failed: $e');
    }
  }
}

final notificationSchedulerProvider =
    Provider<NotificationScheduler>((ref) => NotificationScheduler());
