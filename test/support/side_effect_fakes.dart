import 'package:flutter_riverpod/misc.dart';
import 'package:quirzy/features/feed/services/leaderboard_sync.dart';
import 'package:quirzy/shared/services/notification_scheduler.dart';

/// Records leaderboard syncs instead of calling Appwrite.
class FakeLeaderboardSync extends LeaderboardSync {
  int scheduled = 0;

  @override
  void schedule() => scheduled++;

  @override
  Future<void> syncNow() async {}
}

/// Records scheduler calls instead of touching the notifications plugin.
class FakeNotificationScheduler extends NotificationScheduler {
  int practisedToday = 0;

  @override
  Future<void> onPractisedToday() async => practisedToday++;

  @override
  Future<void> onAppOpen() async {}
}

/// Overrides that keep tests away from the network and platform plugins.
List<Override> sideEffectOverrides({
  FakeLeaderboardSync? leaderboard,
  FakeNotificationScheduler? scheduler,
}) => [
  leaderboardSyncProvider.overrideWithValue(leaderboard ?? FakeLeaderboardSync()),
  notificationSchedulerProvider.overrideWithValue(scheduler ?? FakeNotificationScheduler()),
];
