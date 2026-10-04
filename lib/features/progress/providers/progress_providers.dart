import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../feed/providers/feed_providers.dart';
import '../../feed/services/feed_stats_service.dart';
import '../../feed/services/streak_service.dart';
import '../../feed/services/xp_service.dart';
import '../../home/providers/home_stats_provider.dart';

class MyPrepStats {
  final int streak;
  final int bestStreak;
  final bool streakAtRisk;
  final int xpToday;
  final XpLevel level;
  final int todayAnswered;
  final List<int> dailyAnsweredLast7;
  final Map<String, TopicStat> topicStats;
  final int revisionDueCount;
  final int bookmarkCount;

  const MyPrepStats({
    required this.streak,
    required this.bestStreak,
    required this.streakAtRisk,
    required this.xpToday,
    required this.level,
    required this.todayAnswered,
    required this.dailyAnsweredLast7,
    required this.topicStats,
    required this.revisionDueCount,
    required this.bookmarkCount,
  });

  double get dailyTargetProgress =>
      (todayAnswered / kFeedDailyTarget).clamp(0.0, 1.0);
}

final myPrepStatsProvider = FutureProvider<MyPrepStats>((ref) async {
  final streak = await ref.watch(streakProvider.future);
  final homeStats = await ref.watch(homeStatsProvider.future);
  final xpService = ref.watch(xpServiceProvider);
  final statsService = ref.watch(feedStatsServiceProvider);
  final revisionService = ref.watch(feedRevisionServiceProvider);
  final bookmarkService = ref.watch(feedBookmarkServiceProvider);

  final results = await Future.wait([
    xpService.getLevel(),
    statsService.getTodayAnsweredCount(),
    statsService.getDailyAnsweredCounts(days: 7),
    statsService.getTopicStats(),
    revisionService.getDueCount(),
    bookmarkService.getCount(),
  ]);

  return MyPrepStats(
    streak: streak.current,
    bestStreak: streak.best,
    streakAtRisk: streak.atRisk,
    xpToday: homeStats.xpToday,
    level: results[0] as XpLevel,
    todayAnswered: results[1] as int,
    dailyAnsweredLast7: results[2] as List<int>,
    topicStats: results[3] as Map<String, TopicStat>,
    revisionDueCount: results[4] as int,
    bookmarkCount: results[5] as int,
  );
});
