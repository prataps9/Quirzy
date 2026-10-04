import 'dart:math' as math;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quirzy/features/feed/models/feed_models.dart';
import 'package:quirzy/features/feed/providers/feed_providers.dart';
import 'package:quirzy/features/feed/services/feed_ranker.dart';
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
