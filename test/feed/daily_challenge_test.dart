import 'dart:math' as math;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quirzy/features/feed/models/daily_challenge.dart';
import 'package:quirzy/features/feed/models/feed_models.dart';
import 'package:quirzy/features/feed/providers/feed_providers.dart';
import 'package:quirzy/features/feed/services/daily_challenge_service.dart';
import 'package:quirzy/features/feed/services/feed_ranker.dart';
import 'package:quirzy/features/feed/services/xp_service.dart';
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

  final pool = [
    for (var i = 0; i < 20; i++) _q('Physics', i),
    for (var i = 0; i < 20; i++) _q('History', i),
  ];
  final monday = DateTime(2026, 10, 26, 9);
  final tuesday = DateTime(2026, 10, 27, 9);

  group('DailyChallengeService', () {
    test('picks five distinct questions', () async {
      final c = (await DailyChallengeService().today(pool, now: monday))!;
      expect(c.total, DailyChallengeService.size);
      expect(c.keys.toSet(), hasLength(5));
      expect(c.date, '2026-10-26');
      expect(c.answered, 0);
      expect(c.completed, isFalse);
    });

    test('is the same all day, however the pool is ordered', () async {
      final service = DailyChallengeService();
      final first = (await service.today(pool, now: monday))!;
      final again = (await service.today(pool.reversed.toList(), now: monday))!;
      expect(again.keys, first.keys);

      SharedPreferences.setMockInitialValues({});
      final fresh = (await DailyChallengeService().today(pool.reversed.toList(), now: monday))!;
      expect(fresh.keys.toSet(), first.keys.toSet());
    });

    test('a new day gets a new set', () async {
      final service = DailyChallengeService();
      final a = (await service.today(pool, now: monday))!;
      final b = (await service.today(pool, now: tuesday))!;
      expect(b.date, '2026-10-27');
      expect(b.keys, isNot(a.keys));
    });

    test('leans on weak topics', () async {
      final c = (await DailyChallengeService().today(pool, weakTopics: {'History'}, now: monday))!;
      final weak = c.keys.where((k) => k.contains('History')).length;
      expect(weak, DailyChallengeService.weakShare);
    });

    test('with few weak questions the rest comes from the other topics', () async {
      final small = [_q('History', 0), for (var i = 0; i < 10; i++) _q('Physics', i)];
      final c = (await DailyChallengeService().today(small, weakTopics: {'History'}, now: monday))!;
      expect(c.total, 5);
      expect(c.keys.where((k) => k.contains('History')), hasLength(1));
    });

    test('a small pool gives a smaller challenge, and an empty one gives none', () async {
      final three = (await DailyChallengeService().today([for (var i = 0; i < 3; i++) _q('Art', i)], now: monday))!;
      expect(three.total, 3);

      SharedPreferences.setMockInitialValues({});
      expect(await DailyChallengeService().today(const [], now: monday), isNull);
    });

    test('questions with no valid answer are never picked', () async {
      final broken = const PracticeQuestion(id: 'x', questionText: 'x', options: ['only one'], correctIndex: 0, topic: 'Art');
      final c = (await DailyChallengeService().today([broken, _q('Art', 1)], now: monday))!;
      expect(c.total, 1);
      expect(c.keys.single, contains('Art'));
    });

    test('keeps your answers, ignores repeats, and drops questions that left the pool', () async {
      final service = DailyChallengeService();
      var c = (await service.today(pool, now: monday))!;
      c = await service.record(c, c.keys[0], true);
      c = await service.record(c, c.keys[0], false); // already answered
      c = await service.record(c, 'nope|nope', true); // not in the challenge
      expect(c.answered, 1);
      expect(c.correct, 1);

      final resumed = (await service.today(pool, now: monday))!;
      expect(resumed.answered, 1);
      expect(resumed.results[c.keys[0]], isTrue);

      final gone = c.keys[1];
      final shrunk = pool.where((q) => q.engagementKey != gone).toList();
      final trimmed = (await service.today(shrunk, now: monday))!;
      expect(trimmed.total, 4);
      expect(trimmed.keys, isNot(contains(gone)));
      expect(trimmed.results[c.keys[0]], isTrue);
    });

    test('the bonus depends on how many were right', () {
      DailyChallenge result(int right) => DailyChallenge(
        date: '2026-10-26',
        keys: ['a', 'b', 'c', 'd', 'e'],
        results: {for (var i = 0; i < 5; i++) 'abcde'[i]: i < right},
      );
      expect(DailyChallengeService.bonusFor(result(5)), DailyChallengeService.strongXp);
      expect(DailyChallengeService.bonusFor(result(4)), DailyChallengeService.strongXp);
      expect(DailyChallengeService.bonusFor(result(3)), DailyChallengeService.completeXp);
      expect(DailyChallengeService.bonusFor(result(0)), DailyChallengeService.completeXp);
    });
  });

  group('Daily 5 lane', () {
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

    const lane = FeedLane(type: FeedLaneType.daily, id: FeedLane.dailyId, label: 'Daily 5', count: 5);

    Future<void> answerAll(ProviderContainer container, {required int right}) async {
      final controller = container.read(feedControllerProvider.notifier);
      final count = container.read(feedControllerProvider).cards.length;
      for (var i = 0; i < count; i++) {
        controller.activate(i);
        await controller.selectOption(i, i < right ? 0 : 1);
      }
    }

    test('lists the five questions and shows the lane in the lane list', () async {
      final container = await loaded();
      final lanes = await container.read(feedLanesProvider.future);
      expect(lanes[1].type, FeedLaneType.daily);
      expect(lanes[1].label, 'Daily 5');

      await container.read(feedControllerProvider.notifier).switchLane(lane);
      final state = container.read(feedControllerProvider);
      expect(state.lane.type, FeedLaneType.daily);
      expect(state.cards, hasLength(5));
      expect(state.hasMore, isFalse);
      expect(state.daily!.answered, 0);
    });

    test('finishing it records the score and pays the bonus once', () async {
      final container = await loaded();
      final controller = container.read(feedControllerProvider.notifier);
      await controller.switchLane(lane);
      final xpBefore = await XpService().getXPToday();

      await answerAll(container, right: 4);

      final state = container.read(feedControllerProvider);
      expect(state.daily!.completed, isTrue);
      expect(state.daily!.correct, 4);
      expect(state.daily!.bonusXp, DailyChallengeService.strongXp);
      // 4 correct answers at the usual XP, plus the bonus.
      final xpAfter = await XpService().getXPToday();
      expect(xpAfter - xpBefore, 4 * kFeedXpPerCorrect + DailyChallengeService.strongXp);

      // Re-opening it later lists nothing left and pays nothing more.
      await controller.switchLane(lane);
      final again = container.read(feedControllerProvider);
      expect(again.cards, isEmpty);
      expect(again.daily!.completed, isTrue);
      expect(await XpService().getXPToday(), xpAfter);
    });

    test('stopping half way keeps your place: only the rest is listed', () async {
      final container = await loaded();
      final controller = container.read(feedControllerProvider.notifier);
      await controller.switchLane(lane);
      controller.activate(0);
      await controller.selectOption(0, 0);
      controller.activate(1);
      await controller.selectOption(1, 1);

      await controller.switchLane(FeedLane.forYou);
      await controller.switchLane(lane);

      final state = container.read(feedControllerProvider);
      expect(state.cards, hasLength(3));
      expect(state.daily!.answered, 2);
      expect(state.daily!.completed, isFalse);
      expect(state.daily!.bonusXp, isNull);
    });

    test('answers in other lanes do not count towards it', () async {
      final container = await loaded();
      final controller = container.read(feedControllerProvider.notifier);
      controller.activate(0);
      await controller.selectOption(0, 0);

      await controller.switchLane(lane);
      expect(container.read(feedControllerProvider).daily!.answered, 0);
    });
  });
}
