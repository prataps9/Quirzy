import 'dart:math' as math;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quirzy/features/feed/models/feed_models.dart';
import 'package:quirzy/features/feed/providers/feed_providers.dart';
import 'package:quirzy/features/feed/services/feed_mixer.dart';
import 'package:quirzy/features/feed/services/feed_ranker.dart';
import 'package:quirzy/features/flashcards/services/flashcard_cache.dart';
import 'package:quirzy/features/flashcards/services/srs_service.dart';
import 'package:quirzy/features/feed/services/streak_service.dart';
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

Future<ProviderContainer> _loadedFeed(
  List<PracticeQuestion> pool, {
  FakeLeaderboardSync? leaderboard,
  FakeNotificationScheduler? scheduler,
  FeedMixer? mixer,
}) async {
  final container = ProviderContainer(
    overrides: [
      feedQuestionPoolProvider.overrideWith((ref) async => pool),
      ...sideEffectOverrides(leaderboard: leaderboard, scheduler: scheduler, mixer: mixer),
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

  test('quick swipe-pasts re-rank even though activation happens at scroll end', () async {
    final container = await _loadedFeed(pool);
    final controller = container.read(feedControllerProvider.notifier);
    // On a real device the scroll-end notification arrives while the
    // position still reports scrolling — exactly when activate() runs.
    controller.isScrollIdle = () => false;
    FeedState state() => container.read(feedControllerProvider);

    final passes = <String, int>{};
    controller.activate(0);
    for (var index = 1; index < 20; index++) {
      final leaving = state().cards[index - 1].question.topicName;
      passes[leaving] = (passes[leaving] ?? 0) + 1;
      final queuedBefore = state().cards.skip(index + 1).map((c) => c.uid).toSet();
      controller.activate(index);
      if (passes[leaving] == 2) {
        // The re-rank is due now and runs on this activation.
        final queuedAfter = state().cards.skip(index + 1).map((c) => c.uid);
        expect(queuedAfter.where(queuedBefore.contains), isEmpty);
        return;
      }
    }
    fail('no topic was passed twice');
  });

  test('liking an earlier card never replaces cards already reached', () async {
    final container = await _loadedFeed(pool);
    final controller = container.read(feedControllerProvider.notifier);
    for (var i = 0; i <= 5; i++) {
      controller.activate(i);
    }
    final reached = container.read(feedControllerProvider).cards.take(6).map((c) => c.uid).toList();

    // Scroll back up to card 2 and like it: that re-ranks what comes next.
    controller.activate(2);
    controller.like(2);

    final after = container.read(feedControllerProvider).cards.take(6).map((c) => c.uid).toList();
    expect(after, reached);
  });

  test('a slower lane switch never overwrites a newer one', () async {
    final container = await _loadedFeed(pool);
    final controller = container.read(feedControllerProvider.notifier);
    final first = controller.switchLane(
      const FeedLane(type: FeedLaneType.topic, id: 'topic:History', label: 'History'),
    );
    final second = controller.refreshForYou();
    await Future.wait([first, second]);
    expect(container.read(feedControllerProvider).lane.type, FeedLaneType.forYou);
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

    test('answers sync the leaderboard and only the first one moves the streak alert', () async {
      final leaderboard = FakeLeaderboardSync();
      final scheduler = FakeNotificationScheduler();
      final container = await _loadedFeed(pool, leaderboard: leaderboard, scheduler: scheduler);
      await answer(container, 0);
      await answer(container, 1);
      await container.read(feedControllerProvider.notifier).skipCurrent(2);

      expect(leaderboard.scheduled, 3);
      expect(scheduler.practisedToday, 1);
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

  group('mixed cards', () {
    test('True/False answers count as practice and earn half XP', () async {
      final container = await _loadedFeed(
        pool,
        mixer: FeedMixer(random: math.Random(2), trueFalseShare: 1),
      );
      final controller = container.read(feedControllerProvider.notifier);
      final cards = container.read(feedControllerProvider).cards;
      final index = cards.indexWhere((c) => c.kind == FeedCardKind.trueFalse);
      expect(index, greaterThanOrEqualTo(0));
      final card = cards[index];

      controller.activate(index);
      await controller.answerTrueFalse(index, card.tfStatementTrue);

      final state = container.read(feedControllerProvider);
      expect(state.cards[index].isResolved, isTrue);
      expect(state.cards[index].isCorrect, isTrue);
      expect(state.combo, 1);
      expect(state.todayAnswered, 1);
      expect(await container.read(xpServiceProvider).getXPTotal(), kFeedXpPerTrueFalse);

      // Option taps don't apply to a True/False card.
      await controller.selectOption(index, 0);
      expect(container.read(feedControllerProvider).todayAnswered, 1);
    });

    test('a wrong True/False verdict resets the combo', () async {
      final container = await _loadedFeed(
        pool,
        mixer: FeedMixer(random: math.Random(2), trueFalseShare: 1),
      );
      final controller = container.read(feedControllerProvider.notifier);
      final cards = container.read(feedControllerProvider).cards;
      final index = cards.indexWhere((c) => c.kind == FeedCardKind.trueFalse);
      await controller.answerTrueFalse(index, !cards[index].tfStatementTrue);

      final state = container.read(feedControllerProvider);
      expect(state.cards[index].isCorrect, isFalse);
      expect(state.combo, 0);
      expect(await container.read(xpServiceProvider).getXPTotal(), 0);
    });

    test('due flashcards are mixed in and rating one counts toward the streak', () async {
      await FlashcardCache.save({
        'id': 'set1',
        'title': 'Optics',
        'cards': [
          {'front': 'Focal length of a plane mirror?', 'back': 'Infinite'},
        ],
      });
      // Started yesterday and due now.
      await SrsService().rateCard('set1', 0, SrsRating.again);
      final prefs = await SharedPreferences.getInstance();
      final srs = prefs.getString('srs_v1')!.replaceAll(RegExp(r'"d":"[^"]+"'), '"d":"2020-01-01T00:00:00.000"');
      await prefs.setString('srs_v1', srs);
      await prefs.remove(StreakService.flashcardKey(DateTime.now()));

      final container = await _loadedFeed(pool);
      final controller = container.read(feedControllerProvider.notifier);
      final cards = container.read(feedControllerProvider).cards;
      final index = cards.indexWhere((c) => c.kind == FeedCardKind.flashcard);
      expect(index, greaterThanOrEqualTo(FeedMixer.minQuizBetween));
      expect(cards[index].flashcard!.back, 'Infinite');
      expect(cards[index].question.topicName, 'Optics');

      controller.activate(index);
      controller.flipFlashcard(index);
      await controller.rateFlashcard(index, SrsRating.good);

      final state = container.read(feedControllerProvider);
      expect(state.cards[index].rated, isTrue);
      expect(state.todayAnswered, 0, reason: 'flashcards are not feed answers');
      expect((await container.read(streakProvider.future)).practisedToday, isTrue);
      expect(await SrsService().dueStartedKeys(), isEmpty);
    });

    test('a flashcard reviewed in Cards meanwhile is not rated twice', () async {
      await FlashcardCache.save({
        'id': 'set1',
        'title': 'Optics',
        'cards': [
          {'front': 'Focal length of a plane mirror?', 'back': 'Infinite'},
        ],
      });
      await SrsService().rateCard('set1', 0, SrsRating.again);
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        'srs_v1',
        prefs.getString('srs_v1')!.replaceAll(RegExp(r'"d":"[^"]+"'), '"d":"2020-01-01T00:00:00.000"'),
      );

      final container = await _loadedFeed(pool);
      final controller = container.read(feedControllerProvider.notifier);
      final index = container.read(feedControllerProvider).cards.indexWhere((c) => c.kind == FeedCardKind.flashcard);
      expect(index, greaterThanOrEqualTo(0));

      // Reviewed in the Cards tab while the feed card was waiting.
      await SrsService().rateCard('set1', 0, SrsRating.good);
      final reps = (await SrsService().getCard('set1', 0)).repetitions;

      await controller.rateFlashcard(index, SrsRating.good);
      expect(container.read(feedControllerProvider).cards[index].rated, isTrue);
      expect((await SrsService().getCard('set1', 0)).repetitions, reps);
    });

    test('a due flashcard that was never reached comes back after a lane switch', () async {
      await FlashcardCache.save({
        'id': 'set1',
        'title': 'Optics',
        'cards': [
          {'front': 'Focal length of a plane mirror?', 'back': 'Infinite'},
        ],
      });
      await SrsService().rateCard('set1', 0, SrsRating.again);
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        'srs_v1',
        prefs.getString('srs_v1')!.replaceAll(RegExp(r'"d":"[^"]+"'), '"d":"2020-01-01T00:00:00.000"'),
      );

      final container = await _loadedFeed(pool);
      final controller = container.read(feedControllerProvider.notifier);
      bool hasFlashcard() =>
          container.read(feedControllerProvider).cards.any((c) => c.kind == FeedCardKind.flashcard);
      expect(hasFlashcard(), isTrue);

      controller.activate(0);
      await controller.switchLane(
        const FeedLane(type: FeedLaneType.topic, id: 'topic:History', label: 'History'),
      );
      await controller.refreshForYou();
      expect(hasFlashcard(), isTrue);
    });

    test('a fact never shows a question that is due as a quiz', () async {
      final why = 'Option A is right because it follows from the definition used in class.';
      final factPool = [
        for (var i = 0; i < 30; i++)
          PracticeQuestion(
            id: 'f$i',
            questionText: 'Fact question $i',
            options: const ['A', 'B', 'C', 'D'],
            correctIndex: 0,
            explanation: why,
            topic: 'Physics',
          ),
      ];
      final container = await _loadedFeed(factPool);
      final controller = container.read(feedControllerProvider.notifier);
      await controller.selectOption(0, 1);
      final missedId = container.read(feedControllerProvider).cards[0].question.id;

      // Make that miss due today: it may now come back as a quiz, so it
      // must not also appear as a fact.
      final prefs = await SharedPreferences.getInstance();
      final vault = prefs.getString('feed_revision_vault')!;
      await prefs.setString(
        'feed_revision_vault',
        vault.replaceAll(RegExp(r'"dueDate":"[^"]+"'), '"dueDate":"2020-01-01T00:00:00.000"'),
      );
      await controller.refreshForYou();

      final cards = container.read(feedControllerProvider).cards;
      expect(cards.where((c) => c.kind == FeedCardKind.fact && c.question.id == missedId), isEmpty);
    });

    test('facts are read, not answered', () async {
      final why = 'Option A is right because it follows from the definition used in class.';
      final factPool = [
        for (var i = 0; i < 30; i++)
          PracticeQuestion(
            id: 'f$i',
            questionText: 'Fact question $i',
            options: const ['A', 'B', 'C', 'D'],
            correctIndex: 0,
            explanation: why,
            topic: 'Physics',
          ),
      ];
      final container = await _loadedFeed(factPool);
      final controller = container.read(feedControllerProvider.notifier);
      // Miss one so it lands in the revision vault, then reload For You.
      await controller.selectOption(0, 1);
      await controller.refreshForYou();

      final cards = container.read(feedControllerProvider).cards;
      final index = cards.indexWhere((c) => c.kind == FeedCardKind.fact);
      expect(index, greaterThanOrEqualTo(0));
      final before = container.read(feedControllerProvider).todayAnswered;
      controller.acknowledgeFact(index);
      final state = container.read(feedControllerProvider);
      expect(state.cards[index].isResolved, isTrue);
      expect(state.todayAnswered, before);
    });
  });
}
