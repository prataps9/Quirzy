import 'dart:math' as math;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quirzy/features/feed/models/feed_models.dart';
import 'package:quirzy/features/feed/providers/feed_providers.dart';
import 'package:quirzy/features/feed/services/feed_ranker.dart';
import 'package:quirzy/features/feed/services/streak_service.dart';
import 'package:quirzy/features/feed/services/xp_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

PracticeQuestion _q(String topic, int n) => PracticeQuestion(
  id: '${topic}_$n',
  questionText: '$topic question $n',
  options: const ['A', 'B', 'C', 'D'],
  correctIndex: 0,
  topic: topic,
);

Future<ProviderContainer> _loadedFeed(List<PracticeQuestion> pool) async {
  final container = ProviderContainer(
    overrides: [
      feedQuestionPoolProvider.overrideWith((ref) async => pool),
      feedRankerProvider.overrideWithValue(
        FeedRanker(random: math.Random(1)),
      ),
    ],
  );
  addTearDown(container.dispose);
  container.read(feedControllerProvider);
  for (var i = 0; i < 100 && container.read(feedControllerProvider).loading; i++) {
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
  return container;
}

int _countTopic(Iterable<FeedCardState> cards, String topic) =>
    cards.where((c) => c.question.topicName == topic).length;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  final pool = [
    for (var i = 0; i < 30; i++) _q('Physics', i),
    for (var i = 0; i < 30; i++) _q('History', i),
  ];

  test('For You loads ranked cards with reasons', () async {
    final container = await _loadedFeed(pool);
    final state = container.read(feedControllerProvider);
    expect(state.lane.type, FeedLaneType.forYou);
    expect(state.cards, hasLength(8));
    expect(state.hasMore, isTrue);
    expect(state.cards.every((c) => c.reason != null), isTrue);
  });

  test('"Show less" moves the upcoming cards away from that topic', () async {
    final container = await _loadedFeed(pool);
    final controller = container.read(feedControllerProvider.notifier);
    controller.activate(0);
    final topic = container.read(feedControllerProvider).cards.first.question.topicName;

    controller.showLessOf(topic);

    final upcoming = container.read(feedControllerProvider).cards.skip(1).toList();
    expect(upcoming, hasLength(8));
    expect(_countTopic(upcoming, topic), lessThan(upcoming.length ~/ 2));
  });

  test('two quick swipe-pasts on a topic re-rank what comes next', () async {
    final container = await _loadedFeed(pool);
    final controller = container.read(feedControllerProvider.notifier);
    FeedState state() => container.read(feedControllerProvider);

    // Swipe straight past unanswered cards (well under the quick-pass
    // threshold) until one topic has been passed twice.
    final passes = <String, int>{};
    controller.activate(0);
    for (var index = 1; index < 20; index++) {
      final leaving = state().cards[index - 1].question.topicName;
      final queuedBefore = state().cards.skip(index + 1).map((c) => c.uid).toSet();
      controller.activate(index);
      passes[leaving] = (passes[leaving] ?? 0) + 1;
      if (passes[leaving] == 2) {
        final queuedAfter = state().cards.skip(index + 1).map((c) => c.uid);
        expect(queuedAfter, isNotEmpty);
        expect(queuedAfter.where(queuedBefore.contains), isEmpty,
            reason: 'cards after the current one should be re-ranked');
        return;
      }
    }
    fail('no topic was passed twice');
  });

  group('habit loop', () {
    // Answers the active card correctly (option 0 is correct in _q).
    Future<void> answer(ProviderContainer container, int index, {bool correct = true}) async {
      final controller = container.read(feedControllerProvider.notifier);
      controller.activate(index);
      await controller.selectOption(index, correct ? 0 : 1);
    }

    test('the first answer of the day extends the streak and says so', () async {
      final container = await _loadedFeed(pool);
      await answer(container, 0);

      final state = container.read(feedControllerProvider);
      expect(state.todayAnswered, 1);
      expect(state.reward?.kind, FeedRewardKind.streak);
      expect(state.reward?.value, 1);
      expect((await container.read(streakProvider.future)).current, 1);
    });

    test('five correct answers in a row earn a combo milestone with bonus XP', () async {
      final container = await _loadedFeed(pool);
      for (var i = 0; i < 5; i++) {
        await answer(container, i);
      }

      final state = container.read(feedControllerProvider);
      expect(state.combo, 5);
      expect(state.reward?.kind, FeedRewardKind.comboMilestone);
      expect(state.reward?.value, 5);

      final xp = await container.read(xpServiceProvider).getXPTotal();
      expect(xp, 5 * kFeedXpPerCorrect + kFeedComboBonusXp);
    });

    test('a wrong answer resets the combo and earns no XP', () async {
      final container = await _loadedFeed(pool);
      await answer(container, 0);
      await answer(container, 1);
      expect(container.read(feedControllerProvider).combo, 2);

      await answer(container, 2, correct: false);
      expect(container.read(feedControllerProvider).combo, 0);
      expect(
        await container.read(xpServiceProvider).getXPTotal(),
        2 * kFeedXpPerCorrect,
      );
    });

    test('revealing the answer keeps the combo and still counts as practice', () async {
      final container = await _loadedFeed(pool);
      final controller = container.read(feedControllerProvider.notifier);
      await answer(container, 0);
      controller.activate(1);
      await controller.skipCurrent(1);

      final state = container.read(feedControllerProvider);
      expect(state.combo, 1);
      expect(state.todayAnswered, 2);
    });

    test('crossing the daily goal celebrates once', () async {
      SharedPreferences.setMockInitialValues({
        StreakService.countKey(DateTime.now()): kFeedDailyTarget - 1,
      });
      final container = await _loadedFeed(pool);
      expect(container.read(feedControllerProvider).todayAnswered, kFeedDailyTarget - 1);

      await answer(container, 0);
      expect(container.read(feedControllerProvider).reward?.kind, FeedRewardKind.dailyGoal);
      final firstId = container.read(feedControllerProvider).reward!.id;

      await answer(container, 1);
      expect(container.read(feedControllerProvider).reward?.id, firstId);
    });
  });

  test('liking a card is remembered on the card', () async {
    final container = await _loadedFeed(pool);
    final controller = container.read(feedControllerProvider.notifier);
    controller.activate(0);
    controller.like(0);
    controller.like(0);
    expect(container.read(feedControllerProvider).cards.first.liked, isTrue);
    controller.toggleLike(0);
    expect(container.read(feedControllerProvider).cards.first.liked, isFalse);
  });
}
