import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../feed/providers/feed_providers.dart';
import '../../feed/services/streak_service.dart';
import '../../feed/services/xp_service.dart';
import '../../home/providers/home_stats_provider.dart';
import '../../progress/providers/progress_providers.dart';
import '../models/mock_test.dart';
import '../services/mock_test_service.dart';

final mockTestServiceProvider = Provider<MockTestService>(
  (ref) => MockTestService(
    stats: ref.read(feedStatsServiceProvider),
    mistakes: ref.read(mistakesServiceProvider),
    revision: ref.read(feedRevisionServiceProvider),
    xp: ref.read(xpServiceProvider),
  ),
);

/// Finished tests, newest first.
final mockHistoryProvider = FutureProvider<List<MockResult>>((ref) {
  return ref.watch(mockTestServiceProvider).history();
});

/// A test the user left part-way, if any.
final mockInProgressProvider = FutureProvider.autoDispose<MockTest?>((ref) {
  return ref.watch(mockTestServiceProvider).loadInProgress();
});

/// Everything a finished test changes: refresh what shows it.
void refreshAfterMockTest(WidgetRef ref) {
  ref
    ..invalidate(mockHistoryProvider)
    ..invalidate(mockInProgressProvider)
    ..invalidate(streakProvider)
    ..invalidate(xpTotalProvider)
    ..invalidate(homeStatsProvider)
    ..invalidate(mistakeInsightProvider)
    ..invalidate(myPrepStatsProvider)
    ..invalidate(feedLanesProvider);
}
