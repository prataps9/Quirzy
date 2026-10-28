import 'dart:async';

import 'package:flutter_riverpod/misc.dart';
import 'package:quirzy/features/feed/providers/feed_providers.dart';
import 'package:quirzy/features/feed/models/feed_models.dart';
import 'package:quirzy/features/feed/services/feed_audio.dart';
import 'package:quirzy/features/feed/services/feed_mixer.dart';
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

  /// Payloads to deliver as notification taps.
  final tapController = StreamController<String>.broadcast();
  String? launchPayload;

  @override
  Stream<String> get taps => tapController.stream;

  @override
  Future<String?> takeLaunchPayload() async {
    final payload = launchPayload;
    launchPayload = null;
    return payload;
  }
}

/// Records what would be spoken or played instead of using the plugins.
class FakeFeedAudio extends FeedAudio {
  final List<String> spoken = [];
  final List<bool> sounds = [];
  int stops = 0;

  @override
  Future<void> speak(FeedCardState card) async => spoken.add(FeedAudio.script(card));

  @override
  Future<void> stop() async => stops++;

  @override
  Future<void> playAnswer({required bool correct}) async => sounds.add(correct);

  @override
  void dispose() {}
}

/// Overrides that keep tests away from the network and platform plugins,
/// and keep the feed to plain questions unless a test passes its own
/// [mixer].
List<Override> sideEffectOverrides({
  FakeLeaderboardSync? leaderboard,
  FakeNotificationScheduler? scheduler,
  FeedMixer? mixer,
  FakeFeedAudio? audio,
}) => [
  feedAudioProvider.overrideWithValue(audio ?? FakeFeedAudio()),
  feedMixerProvider.overrideWithValue(mixer ?? FeedMixer(trueFalseShare: 0)),
  leaderboardSyncProvider.overrideWithValue(leaderboard ?? FakeLeaderboardSync()),
  notificationSchedulerProvider.overrideWithValue(scheduler ?? FakeNotificationScheduler()),
];
