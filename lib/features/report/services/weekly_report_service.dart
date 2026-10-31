import 'package:shared_preferences/shared_preferences.dart';

import '../../feed/services/activity_log.dart';
import '../../mocktest/services/mock_test_service.dart';
import '../../progress/services/badge_service.dart';
import '../models/weekly_report.dart';

/// Builds the week's report from what the app already records: daily answer
/// counts, the activity log (topics, results, hours), XP per day, mock tests
/// and badge dates.
class WeeklyReportService {
  WeeklyReportService({DateTime Function()? clock}) : _clock = clock ?? DateTime.now;

  final DateTime Function() _clock;

  /// How far back the week switcher goes.
  static const maxWeeksBack = 8;

  /// Monday of the week [weeksAgo] weeks before this one.
  static DateTime weekStart(DateTime now, [int weeksAgo = 0]) =>
      DateTime(now.year, now.month, now.day - (now.weekday - DateTime.monday) - 7 * weeksAgo);

  Future<WeeklyReport> week([int weeksAgo = 0]) async {
    final start = weekStart(_clock(), weeksAgo);
    final prefs = await SharedPreferences.getInstance();
    final log = ActivityLog();
    final days = await log.range(start, DateTime(start.year, start.month, start.day + 6));
    final previous = await _totals(prefs, log, DateTime(start.year, start.month, start.day - 7));

    final topics = <String, (int, int)>{};
    final parts = <DayPart, int>{};
    var graded = 0, correct = 0, xp = 0;
    final answered = <int>[];
    for (final d in days) {
      answered.add(_answeredOn(prefs, d));
      graded += d.answered;
      correct += d.correct;
      xp += prefs.getInt('xp_today_${ActivityLog.dateKey(d.day)}') ?? 0;
      for (final e in d.topics.entries) {
        final (a, c) = topics[e.key] ?? (0, 0);
        topics[e.key] = (a + e.value.$1, c + e.value.$2);
      }
      for (var h = 0; h < 24; h++) {
        final n = d.atHour(h);
        if (n > 0) parts.update(DayPart.of(h), (v) => v + n, ifAbsent: () => n);
      }
    }

    final from = start.millisecondsSinceEpoch;
    final to = DateTime(start.year, start.month, start.day + 7).millisecondsSinceEpoch;
    bool inWeek(int ms) => ms >= from && ms < to;
    final mocks = (await MockTestService().history()).where((m) => inWeek(m.finishedMs)).length;
    final badges = (await BadgeService().earned()).values.where(inWeek).length;

    return WeeklyReport(
      start: start,
      answeredByDay: answered,
      graded: graded,
      correct: correct,
      xp: xp,
      topics: [for (final e in topics.entries) TopicWeek(e.key, e.value.$1, e.value.$2)]
        ..sort((a, b) => b.answered != a.answered ? b.answered.compareTo(a.answered) : a.topic.compareTo(b.topic)),
      parts: parts,
      mockTests: mocks,
      badges: badges,
      previousAnswered: previous.$1,
      previousAccuracy: previous.$2,
    );
  }

  /// The last seven days against the seven before, for the Sunday
  /// notification: (answered, accuracy, change in answers in percent).
  Future<(int, int?, int?)> lastSevenDays() async {
    final now = _clock();
    final prefs = await SharedPreferences.getInstance();
    final log = ActivityLog();
    final (answered, accuracy) = await _totals(prefs, log, DateTime(now.year, now.month, now.day - 6));
    final (before, _) = await _totals(prefs, log, DateTime(now.year, now.month, now.day - 13));
    final change = before == 0 ? null : ((answered - before) * 100 / before).round();
    return (answered, accuracy, change);
  }

  /// Answers on a day: the feed's daily counter, or the log if it has more
  /// (mock tests and challenges are logged but not counted by the feed).
  static int _answeredOn(SharedPreferences prefs, DayActivity d) {
    final counted = prefs.getInt('feed_answered_count_${ActivityLog.dateKey(d.day)}') ?? 0;
    return counted > d.answered ? counted : d.answered;
  }

  /// Answers and accuracy over the seven days from [from].
  Future<(int, int?)> _totals(SharedPreferences prefs, ActivityLog log, DateTime from) async {
    final days = await log.range(from, DateTime(from.year, from.month, from.day + 6));
    var answered = 0, graded = 0, correct = 0;
    for (final d in days) {
      answered += _answeredOn(prefs, d);
      graded += d.answered;
      correct += d.correct;
    }
    return (answered, graded == 0 ? null : (correct * 100 / graded).round());
  }
}
