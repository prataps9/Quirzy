import 'dart:math' as math;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quirzy/features/feed/models/daily_challenge.dart';
import 'package:quirzy/features/feed/models/feed_models.dart';
import 'package:quirzy/features/feed/providers/feed_providers.dart';
import 'package:quirzy/features/feed/services/daily_challenge_service.dart';
import 'package:quirzy/features/feed/services/feed_ranker.dart';
import 'package:quirzy/features/feed/services/mistakes_service.dart';
import 'package:quirzy/features/feed/services/streak_service.dart';
import 'package:quirzy/features/progress/models/badge.dart';
import 'package:quirzy/features/progress/services/badge_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/side_effect_fakes.dart';

PracticeQuestion _q(String topic, int n) => PracticeQuestion(
  id: '${topic}_$n',
  questionText: '$topic question $n',
  options: const ['A', 'B', 'C', 'D'],
  correctIndex: 0,
  topic: topic,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  final today = DateTime.now();
  DateTime daysAgo(int n) => DateTime(today.year, today.month, today.day - n);

  group('BadgeService', () {
    test('reads its numbers from what the app already records', () async {
      SharedPreferences.setMockInitialValues({
        StreakService.countKey(daysAgo(0)): 60,
        StreakService.countKey(daysAgo(1)): 50,
        StreakService.countKey(daysAgo(2)): 10,
        StreakService.flashcardKey(daysAgo(0)): 7,
      });
      final daily = DailyChallengeService();
      await daily.saveBonus(
        const DailyChallenge(date: 'd', keys: ['a', 'b'], results: {'a': true, 'b': true}),
        25,
      );
      final mistakes = MistakesService();
      await mistakes.recordAnswer(_q('Art', 1), correct: false);
      await mistakes.recordAnswer(_q('Art', 1), correct: true);
      await mistakes.recordAnswer(_q('Art', 1), correct: true);

      final m = await BadgeService().metrics();
      expect(m.totalAnswers, 120);
      expect(m.bestStreak, 3);
      expect(m.flashcardsReviewed, 7);
      expect(m.dailyPlayed, 1);
      expect(m.dailyPerfect, 1);
      expect(m.mistakesFixed, 1);
    });

    test('a badge is earned once and kept', () async {
      final service = BadgeService();
      const m = BadgeMetrics(totalAnswers: 120, bestStreak: 3);
      final first = await service.check(metrics: m);
      expect(first, [BadgeId.firstAnswer, BadgeId.answers100, BadgeId.streak3]);
      expect(await service.check(metrics: m), isEmpty);
      // Never taken away, even if a number goes down.
      expect(await service.check(metrics: const BadgeMetrics()), isEmpty);
      expect((await service.earned()).keys, containsAll(first));
    });

    test('statuses list earned badges first, with progress for the rest', () async {
      SharedPreferences.setMockInitialValues({StreakService.countKey(daysAgo(0)): 37});
      final statuses = await BadgeService().statuses();
      expect(statuses.first.def.id, BadgeId.firstAnswer);
      expect(statuses.first.earned, isTrue);
      final century = statuses.firstWhere((s) => s.def.id == BadgeId.answers100);
      expect(century.earned, isFalse);
      expect(century.progress, 37);
      expect(statuses, hasLength(BadgeDef.catalog.length));
    });
  });

  group('in the feed', () {
    final pool = [for (var i = 0; i < 20; i++) _q('Physics', i), for (var i = 0; i < 20; i++) _q('History', i)];

    Future<ProviderContainer> loaded() async {
      final container = ProviderContainer(
        overrides: [
          feedQuestionPoolProvider.overrideWith((ref) async => pool),
          ...sideEffectOverrides(),
          feedRankerProvider.overrideWithValue(FeedRanker(random: math.Random(1))),
        ],
      );
      addTearDown(container.dispose);
      container.read(feedControllerProvider);
      for (var i = 0; i < 100 && container.read(feedControllerProvider).loading; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
      return container;
    }

    test('a newly earned badge is celebrated when nothing else is', () async {
      // Already practised today (so no streak banner), never earned a badge.
      SharedPreferences.setMockInitialValues({StreakService.countKey(today): 1});
      final container = await loaded();
      final controller = container.read(feedControllerProvider.notifier);
      controller.activate(0);
      await controller.selectOption(0, 1);

      final reward = container.read(feedControllerProvider).reward!;
      expect(reward.kind, FeedRewardKind.badge);
      expect(BadgeDef.catalog[reward.value].id, BadgeId.firstAnswer);
    });

    test('opening the feed after missing yesterday announces the streak freeze', () async {
      SharedPreferences.setMockInitialValues({
        StreakService.countKey(daysAgo(2)): 3,
        StreakService.countKey(daysAgo(3)): 3,
      });
      final container = await loaded();
      for (var i = 0; i < 20 && container.read(feedControllerProvider).reward == null; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
      final reward = container.read(feedControllerProvider).reward!;
      expect(reward.kind, FeedRewardKind.freezeUsed);
      expect(reward.value, 3);
    });
  });
}
