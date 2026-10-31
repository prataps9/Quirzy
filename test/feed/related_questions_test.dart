import 'dart:math' as math;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quirzy/features/feed/models/feed_models.dart';
import 'package:quirzy/features/feed/providers/feed_providers.dart';
import 'package:quirzy/features/feed/services/feed_ranker.dart';
import 'package:quirzy/features/feed/services/mistakes_service.dart';
import 'package:quirzy/features/feed/services/related_questions.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/side_effect_fakes.dart';

PracticeQuestion _q(
  String id,
  String text, {
  String? topic = 'History',
  List<String> options = const ['Yes', 'No'],
  String explanation = '',
}) => PracticeQuestion(
  id: id,
  questionText: text,
  options: options,
  correctIndex: 0,
  explanation: explanation,
  topic: topic,
);

List<String> _ids(List<RelatedQuestion> r) => [for (final x in r) x.question.id];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('RelatedQuestions.rank', () {
    final plassey = _q(
      'plassey',
      'Who won the Battle of Plassey in 1757?',
      explanation: 'Robert Clive defeated Siraj ud-Daulah.',
    );

    test('a shared rare word beats the same topic with nothing in common', () {
      final pool = [
        _q('same-topic', 'Which dynasty built Konark temple?'),
        _q('rare-word', 'Which general lost the Battle of Buxar?', topic: 'Polity'),
        _q('other', 'What is the capital of Peru?', topic: 'Geography'),
      ];
      final ranked = RelatedQuestions.rank(plassey, pool);
      expect(ranked.first.question.id, 'rare-word', reason: 'shares "battle" even in another topic');
    });

    test('rare words count more than common ones', () {
      final pool = [
        for (var i = 0; i < 8; i++) _q('common$i', 'Which river is longest in region $i?'),
        _q('rare', 'Siraj ud-Daulah ruled which region?'),
      ];
      final question = _q('q', 'Which region did Siraj ud-Daulah rule?');
      final ranked = RelatedQuestions.rank(question, pool);
      expect(ranked.first.question.id, 'rare');
    });

    test('stop words and short words alone do not make questions related', () {
      final pool = [_q('a', 'What is the cat?', topic: 'Art')];
      final question = _q('q', 'Which of the following is true?', topic: 'Science');
      expect(RelatedQuestions.rank(question, pool), isEmpty, reason: 'different topic, no meaningful shared word');
    });

    test('looks in options and explanations too, but weighs the question text more', () {
      final pool = [
        _q('in-text', 'Clive commanded which army?'),
        _q('in-explanation', 'Who was the victor?', explanation: 'Clive won.'),
      ];
      final question = _q('q', 'Who is Clive?');
      final ranked = RelatedQuestions.rank(question, pool);
      expect(_ids(ranked), ['in-text', 'in-explanation']);
    });

    test('never offers the question itself, a copy of its text, reported questions or muted topics', () {
      final pool = [
        plassey,
        _q('copy', 'Who won the Battle of Plassey in 1757?'),
        _q('reported', 'Which Battle of 1764 followed Plassey?'),
        _q('muted', 'Which Battle of Panipat came after Plassey?', topic: 'Muted'),
        _q('fine', 'Who lost the Battle of Plassey?'),
      ];
      final ranked = RelatedQuestions.rank(plassey, pool, excludedIds: {'reported'}, mutedTopics: {'Muted'});
      expect(_ids(ranked), ['fine']);
    });

    test('missed questions come before new ones, and answered ones last', () {
      final base = 'Battle of Plassey and the East India Company';
      final pool = [_q('answered', 'First $base?'), _q('fresh', 'Second $base?'), _q('missed', 'Third $base?')];
      final question = _q('q', base);
      final ranked = RelatedQuestions.rank(
        question,
        pool,
        seen: {pool[0].engagementKey, pool[2].engagementKey},
        missed: {pool[2].engagementKey},
      );
      expect(_ids(ranked), ['missed', 'fresh', 'answered']);
      expect([for (final r in ranked) r.status], [RelatedStatus.missed, RelatedStatus.fresh, RelatedStatus.answered]);
      expect([for (final s in RelatedStatus.values) s.label], ['New', 'Missed', 'Answered']);
    });

    test('fills from the same topic when few questions share words', () {
      final pool = [
        _q('one-match', 'The Battle of Buxar was fought when?'),
        _q('t1', 'Name the first Governor General.'),
        _q('t2', 'Name the founder of the Maurya empire.'),
        _q('elsewhere', 'Capital of Peru?', topic: 'Geography'),
      ];
      final ranked = RelatedQuestions.rank(plassey, pool, limit: 3);
      expect(_ids(ranked).first, 'one-match');
      expect(_ids(ranked).toSet(), {'one-match', 't1', 't2'});
      expect(ranked.any((r) => r.question.id == 'elsewhere'), isFalse);
    });

    test('a question without a topic still gets word matches, but no topic filler', () {
      final question = _q('q', 'Who won the Battle of Plassey?', topic: null);
      final pool = [_q('match', 'Battle of Buxar year?', topic: null), _q('no', 'Capital of Peru?', topic: null)];
      expect(_ids(RelatedQuestions.rank(question, pool)), ['match']);
    });

    test('respects the limit, is stable, and handles an empty pool', () {
      final pool = [for (var i = 0; i < 12; i++) _q('b$i', 'Battle number $i of the Plassey war?')];
      final first = RelatedQuestions.rank(plassey, pool, limit: 4);
      expect(first, hasLength(4));
      expect(_ids(RelatedQuestions.rank(plassey, pool.reversed.toList(), limit: 4)), _ids(first));
      expect(RelatedQuestions.rank(plassey, const []), isEmpty);
      expect(RelatedQuestions.rank(plassey, pool, limit: 0), isEmpty);
    });
  });

  group('FeedController related questions', () {
    final pool = [
      for (var i = 0; i < 6; i++) _q('h$i', 'Battle number $i of the Plassey war?'),
      for (var i = 0; i < 6; i++) _q('g$i', 'River number $i of the Ganga basin?', topic: 'Geography'),
    ];

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

    test('relatedTo leaves out muted topics and marks missed questions', () async {
      await FeedStatsServiceMute.mute('Geography');
      await MistakesService().recordAnswer(pool[1], correct: false);
      final container = await loaded();
      final controller = container.read(feedControllerProvider.notifier);
      final related = await controller.relatedTo(pool[0], limit: 5);
      expect(related, hasLength(5));
      expect(related.every((r) => r.question.topicName == 'History'), isTrue);
      expect(related.first.question.id, 'h1');
      expect(related.first.status, RelatedStatus.missed);
    });

    test('queueNext puts the questions next, in order, without duplicates', () async {
      final container = await loaded();
      final controller = container.read(feedControllerProvider.notifier);
      controller.activate(0);
      final picks = [pool[8], pool[9], pool[10]];
      expect(controller.queueNext(0, picks), 3);
      List<String> ids() => [for (final c in container.read(feedControllerProvider).cards) c.question.id];
      expect(ids().sublist(1, 4), [for (final q in picks) q.id]);
      expect(container.read(feedControllerProvider).cards[1].reason, 'Related question');

      // Queueing them again moves nothing new in: they are already next.
      final before = ids();
      controller.queueNext(0, picks);
      expect(ids(), before);
      expect(ids().where((id) => id == pool[8].id), hasLength(1));
    });
  });
}

/// Mutes a topic the way the feed does, through the stored list.
class FeedStatsServiceMute {
  static Future<void> mute(String topic) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList('feed_muted_topics', [topic]);
  }
}
