import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../../../shared/appwrite/leaderboard/leaderboard_service.dart';
import 'feed_stats_service.dart';
import 'streak_service.dart';
import 'xp_service.dart';

/// Pushes the user's local XP and streak to the global leaderboard.
///
/// [schedule] is cheap to call after every answer: bursts are coalesced
/// into one upload after [debounce]. Every failure (offline, signed out,
/// backend down) is swallowed — the next sync simply tries again.
class LeaderboardSync {
  LeaderboardSync({
    LeaderboardService? service,
    XpService? xp,
    StreakService? streaks,
    FeedStatsService? stats,
    Future<String?> Function(String key)? readSecure,
    this.debounce = const Duration(seconds: 5),
  })  : _service = service,
        _xp = xp ?? XpService(),
        _streaks = streaks ?? StreakService(),
        _stats = stats ?? FeedStatsService(),
        _readSecure = readSecure ?? _secureRead;

  final Duration debounce;
  LeaderboardService? _service;
  final XpService _xp;
  final StreakService _streaks;
  final FeedStatsService _stats;
  final Future<String?> Function(String key) _readSecure;
  Timer? _timer;

  static Future<String?> _secureRead(String key) =>
      const FlutterSecureStorage().read(key: key);

  /// Syncs once [debounce] after the last call.
  void schedule() {
    _timer?.cancel();
    _timer = Timer(debounce, syncNow);
  }

  /// Syncs immediately (cancelling any pending [schedule]). Never throws.
  Future<void> syncNow() async {
    _timer?.cancel();
    _timer = null;
    try {
      final userId = await _readSecure('user_id');
      if (userId == null || userId.isEmpty) return;
      final userName = await _readSecure('user_name');
      final totalXp = await _xp.getXPTotal();
      final streak = await _streaks.getStreak();
      final topicStats = await _stats.getTopicStats();
      final answered = topicStats.values.fold<int>(0, (sum, s) => sum + s.attempts);

      _service ??= LeaderboardService();
      await _service!.updateLeaderboard(
        userId: userId,
        userName: (userName == null || userName.trim().isEmpty) ? 'Learner' : userName,
        totalXP: totalXp,
        quizzesCompleted: answered,
        currentStreak: streak.current,
        rank: XpLevel.fromTotal(totalXp).title,
      );
    } catch (e) {
      debugPrint('LeaderboardSync: sync failed: $e');
    }
  }

  void dispose() {
    _timer?.cancel();
    _timer = null;
  }
}

final leaderboardSyncProvider = Provider<LeaderboardSync>((ref) {
  final sync = LeaderboardSync(
    xp: ref.read(xpServiceProvider),
    streaks: ref.read(streakServiceProvider),
  );
  ref.onDispose(sync.dispose);
  return sync;
});
