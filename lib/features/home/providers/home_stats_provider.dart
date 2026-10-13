import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../feed/services/streak_service.dart';
import '../../feed/services/xp_service.dart';
import '../../subscription/services/usage_limits.dart';

class HomeStats {
  final int streak;
  final bool streakAtRisk;
  final int xpToday;
  final int topicsToday;

  const HomeStats({
    this.streak = 0,
    this.streakAtRisk = false,
    this.xpToday = 0,
    this.topicsToday = 0,
  });
}

final homeStatsProvider = FutureProvider<HomeStats>((ref) async {
  final xpService = ref.read(xpServiceProvider);

  final streak = await ref.read(streakServiceProvider).getStreak();
  final usage = await ref.read(usageLimitsProvider.future);
  final xpToday = await xpService.getXPToday();

  return HomeStats(
    streak: streak.current,
    streakAtRisk: streak.atRisk,
    xpToday: xpToday,
    topicsToday: usage.usedToday(UsageKind.topic),
  );
});
