import 'dart:math' as math;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Where the user stands on their daily practice streak.
class StreakInfo {
  /// Consecutive days practised, counting today if already practised.
  final int current;

  /// Longest run of practised days in the lookback window.
  final int best;
  final bool practisedToday;

  /// This week's free streak freeze hasn't been used yet.
  final bool freezeReady;

  const StreakInfo({required this.current, required this.best, required this.practisedToday, this.freezeReady = false});

  static const none = StreakInfo(current: 0, best: 0, practisedToday: false);

  /// A live streak the user will lose if they skip today.
  bool get atRisk => current > 0 && !practisedToday;
}

/// Derives the practice streak from the per-day activity counters the app
/// already writes — feed answers (`feed_answered_count_<yyyy-mm-dd>`) and
/// flashcard reviews (`flashcard_reviewed_count_<yyyy-mm-dd>`) — so it is
/// earned by practising and can never drift from the real activity. A day
/// counts if at least one question was answered or revealed, or one
/// flashcard was reviewed; a streak stays alive until the end of the
/// following day.
///
/// Streak freeze: once a week, a single missed day is forgiven. When the
/// streak is read and the user missed only yesterday, yesterday is recorded
/// as frozen (if this week's freeze is unused) and counts as practised. Two
/// missed days in a row still end the streak.
class StreakService {
  StreakService({DateTime Function()? clock}) : _clock = clock ?? DateTime.now;

  static const lookbackDays = 400;

  static const _frozenKey = 'streak_frozen_days';

  /// The streak a freeze just saved, waiting to be announced once.
  static const _announceKey = 'streak_freeze_announce';

  final DateTime Function() _clock;

  /// The preference key the feed writes for [day]'s answered count.
  static String countKey(DateTime day) => 'feed_answered_count_${_date(day)}';

  /// The preference key [recordFlashcardReview] bumps for [day].
  static String flashcardKey(DateTime day) => 'flashcard_reviewed_count_${_date(day)}';

  static String _date(DateTime day) {
    final y = day.year.toString().padLeft(4, '0');
    final m = day.month.toString().padLeft(2, '0');
    final d = day.day.toString().padLeft(2, '0');
    return '$y-$m-$d';
  }

  /// Counts one flashcard review toward today's activity.
  Future<void> recordFlashcardReview() async {
    final prefs = await SharedPreferences.getInstance();
    final key = flashcardKey(_clock());
    await prefs.setInt(key, (prefs.getInt(key) ?? 0) + 1);
  }

  /// Flashcards reviewed over the last [days] days, including today.
  Future<int> flashcardsReviewed({int days = 7}) async {
    final prefs = await SharedPreferences.getInstance();
    final now = _clock();
    var total = 0;
    for (var i = 0; i < days; i++) {
      total += prefs.getInt(flashcardKey(DateTime(now.year, now.month, now.day - i))) ?? 0;
    }
    return total;
  }

  static DateTime _weekStart(DateTime day) => DateTime(day.year, day.month, day.day - (day.weekday - 1));

  Set<String> _frozen(SharedPreferences prefs) => (prefs.getStringList(_frozenKey) ?? const []).toSet();

  /// Whether a freeze has been used in the week (Monday to Sunday) of [day].
  bool _weekFrozen(Set<String> frozen, DateTime day) {
    final start = _weekStart(day);
    for (var i = 0; i < 7; i++) {
      if (frozen.contains(_date(DateTime(start.year, start.month, start.day + i)))) return true;
    }
    return false;
  }

  /// Uses this week's freeze on yesterday when it is the only day missed,
  /// and returns the streak it saved; null when nothing needed saving or the
  /// freeze for that week is already used.
  Future<int?> applyFreezeIfNeeded() async {
    final prefs = await SharedPreferences.getInstance();
    final now = _clock();
    final frozen = _frozen(prefs);
    DateTime day(int ago) => DateTime(now.year, now.month, now.day - ago);
    bool active(int ago) =>
        (prefs.getInt(countKey(day(ago))) ?? 0) > 0 ||
        (prefs.getInt(flashcardKey(day(ago))) ?? 0) > 0 ||
        frozen.contains(_date(day(ago)));

    if (active(1) || !active(2)) return null;
    final yesterday = day(1);
    if (_weekFrozen(frozen, yesterday)) return null;

    final kept = ([...frozen, _date(yesterday)]..sort()).reversed.take(60).toList();
    await prefs.setStringList(_frozenKey, kept);
    frozen.add(_date(yesterday));
    var saved = 0;
    for (var i = 1; i < lookbackDays && active(i); i++) {
      saved++;
    }
    await prefs.setInt(_announceKey, saved);
    return saved;
  }

  /// The streak a freeze saved since the last call, once; null otherwise.
  Future<int?> takeFreezeAnnouncement() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getInt(_announceKey);
    if (saved != null) await prefs.remove(_announceKey);
    return saved;
  }

  Future<StreakInfo> getStreak() async {
    await applyFreezeIfNeeded();
    final prefs = await SharedPreferences.getInstance();
    final now = _clock();
    final frozen = _frozen(prefs);

    bool practised(int daysAgo) {
      final day = DateTime(now.year, now.month, now.day - daysAgo);
      return (prefs.getInt(countKey(day)) ?? 0) > 0 ||
          (prefs.getInt(flashcardKey(day)) ?? 0) > 0 ||
          frozen.contains(_date(day));
    }

    final practisedToday = practised(0);
    var current = 0;
    for (var i = practisedToday ? 0 : 1; i < lookbackDays && practised(i); i++) {
      current++;
    }

    var best = 0;
    var run = 0;
    for (var i = lookbackDays - 1; i >= 0; i--) {
      run = practised(i) ? run + 1 : 0;
      best = math.max(best, run);
    }

    return StreakInfo(
      current: current,
      best: math.max(best, current),
      practisedToday: practisedToday,
      freezeReady: !_weekFrozen(frozen, now),
    );
  }
}

final streakServiceProvider = Provider<StreakService>((ref) => StreakService());

/// The live streak, refreshed whenever a question is answered.
final streakProvider = FutureProvider<StreakInfo>((ref) {
  return ref.watch(streakServiceProvider).getStreak();
});
