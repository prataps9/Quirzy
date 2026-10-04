import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../feed/services/streak_service.dart';
import '../../feed/services/xp_service.dart';
import '../../content/providers/content_providers.dart';

class HomeStats {
  final int streak;
  final bool streakAtRisk;
  final int xpToday;
  final int quizzesToday;

  const HomeStats({
    this.streak = 0,
    this.streakAtRisk = false,
    this.xpToday = 0,
    this.quizzesToday = 0,
  });
}

final homeStatsProvider = FutureProvider<HomeStats>((ref) async {
  final xpService = ref.read(xpServiceProvider);
  final generationLimitService = ref.read(generationLimitServiceProvider);

  final streak = await ref.read(streakServiceProvider).getStreak();
  final quizzesToday = await generationLimitService.getTodayCount();
  final xpToday = await xpService.getXPToday();

  return HomeStats(
    streak: streak.current,
    streakAtRisk: streak.atRisk,
    xpToday: xpToday,
    quizzesToday: quizzesToday,
  );
});
