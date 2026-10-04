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

  const StreakInfo({
    required this.current,
    required this.best,
    required this.practisedToday,
  });

  static const none = StreakInfo(current: 0, best: 0, practisedToday: false);

  /// A live streak the user will lose if they skip today.
  bool get atRisk => current > 0 && !practisedToday;
}

/// Derives the practice streak from the per-day answer counters the feed
/// already writes (`feed_answered_count_<yyyy-mm-dd>`), so it is earned by
/// practising and can never drift from the real activity. A day counts if
/// at least one question was answered or revealed; a streak stays alive
/// until the end of the following day.
class StreakService {
  StreakService({DateTime Function()? clock}) : _clock = clock ?? DateTime.now;

  static const lookbackDays = 400;

  final DateTime Function() _clock;

  /// The preference key the feed writes for [day]'s answered count.
  static String countKey(DateTime day) {
    final y = day.year.toString().padLeft(4, '0');
    final m = day.month.toString().padLeft(2, '0');
    final d = day.day.toString().padLeft(2, '0');
    return 'feed_answered_count_$y-$m-$d';
  }

  Future<StreakInfo> getStreak() async {
    final prefs = await SharedPreferences.getInstance();
    final now = _clock();

    bool practised(int daysAgo) {
      final day = DateTime(now.year, now.month, now.day - daysAgo);
      return (prefs.getInt(countKey(day)) ?? 0) > 0;
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
    );
  }
}

final streakServiceProvider = Provider<StreakService>((ref) => StreakService());

/// The live streak, refreshed whenever a question is answered.
final streakProvider = FutureProvider<StreakInfo>((ref) {
  return ref.watch(streakServiceProvider).getStreak();
});
