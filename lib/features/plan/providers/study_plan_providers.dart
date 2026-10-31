import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../shared/providers/exam_provider.dart';
import '../../feed/models/feed_models.dart';
import '../../feed/providers/feed_providers.dart';
import '../../feed/services/activity_log.dart';
import '../../feed/services/feed_engagement_service.dart';
import '../../mocktest/providers/mock_test_providers.dart';
import '../models/study_plan.dart';
import '../services/study_plan_service.dart';

final studyPlanServiceProvider = Provider<StudyPlanService>((ref) => StudyPlanService());

/// Today's plan. Rebuilt whenever today's answer count moves (the feed) or a
/// mock test finishes.
final studyPlanProvider = FutureProvider.autoDispose<StudyPlan>((ref) async {
  ref.watch(feedControllerProvider.select((s) => s.todayAnswered));
  ref.watch(mockHistoryProvider);

  final now = DateTime.now();
  final pool = await ref.watch(feedQuestionPoolProvider.future);
  final engagement = ref.read(feedEngagementServiceProvider);
  await engagement.load();
  final seen = engagement.seen;
  final mastery = await ref.watch(topicMasteryProvider.future);
  final insight = await ref.watch(mistakeInsightProvider.future);
  final examDate = await ref.watch(examDateProvider.future);
  final daily = await ref.watch(dailyChallengeProvider.future);
  final stats = ref.read(feedStatsServiceProvider);
  final counts = await stats.getDailyAnsweredCounts(days: 8);
  final today = await ActivityLog().day(now);

  final poolTopics = <String, int>{};
  var unseen = 0;
  for (final q in pool) {
    poolTopics[q.topicName] = (poolTopics[q.topicName] ?? 0) + 1;
    if (!seen.containsKey(q.engagementKey)) unseen++;
  }

  return StudyPlanService.build(
    StudyPlanInputs(
      now: now,
      examDate: examDate,
      poolTopics: poolTopics,
      unseenQuestions: unseen,
      mastery: mastery,
      mistakesOpen: insight.open,
      mistakesReviewedToday: await ref.read(mistakesServiceProvider).reviewedOn(now),
      revisionDue: await ref.read(feedRevisionServiceProvider).getDueCount(),
      revisionReviewedToday: await ref.read(feedRevisionServiceProvider).reviewedToday(),
      daily: daily,
      todayByTopic: {for (final e in today.topics.entries) e.key: e.value.$1},
      todayAnswered: counts.last,
      lastWeek: counts.take(7).toList(),
    ),
  );
});
