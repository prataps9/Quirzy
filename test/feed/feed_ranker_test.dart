import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:quirzy/features/feed/models/feed_models.dart';
import 'package:quirzy/features/feed/services/feed_ranker.dart';
import 'package:quirzy/features/feed/services/feed_stats_service.dart';

final _now = DateTime(2026, 10, 4, 12);

PracticeQuestion _q(String topic, int n) => PracticeQuestion(
  id: '${topic}_$n',
  questionText: '$topic question $n',
  options: const ['A', 'B', 'C', 'D'],
  correctIndex: 0,
  topic: topic,
);

List<PracticeQuestion> _topic(String topic, int count) =>
    List.generate(count, (i) => _q(topic, i));

FeedRanker _ranker([int seed = 7]) =>
    FeedRanker(random: math.Random(seed), clock: () => _now);

/// Share of [topic] across many independent first batches.
double _share(
  RankerSnapshot snapshot,
  String topic,
  void Function(RankerSession session) setUpSession,
) {
  final ranker = _ranker();
  var hits = 0;
  var total = 0;
  for (var i = 0; i < 300; i++) {
    final session = RankerSession();
    setUpSession(session);
    for (final pick in ranker.nextBatch(snapshot, session).picks) {
      total++;
      if (pick.question.topicName == topic) hits++;
    }
  }
  return hits / total;
}

void main() {
  test('empty pool gives an empty batch', () {
    final batch = _ranker().nextBatch(
      const RankerSnapshot(pool: []),
      RankerSession(),
    );
    expect(batch.picks, isEmpty);
  });

  test('single topic fills the batch with distinct questions', () {
    final batch = _ranker().nextBatch(
      RankerSnapshot(pool: _topic('Physics', 20)),
      RankerSession(),
    );
    final keys = batch.picks.map((p) => p.question.engagementKey).toSet();
    expect(batch.picks, hasLength(8));
    expect(keys, hasLength(8));
    expect(batch.unseenRemaining, 12);
  });

  test('without recycling a tiny pool is shown once and then ends', () {
    final ranker = _ranker();
    final session = RankerSession();
    final snapshot = RankerSnapshot(pool: _topic('Math', 5));
    final first = ranker.nextBatch(
      snapshot,
      session,
      size: 5,
      allowRecycle: false,
    );
    final second = ranker.nextBatch(snapshot, session, allowRecycle: false);
    expect(first.picks.map((p) => p.question.id).toSet(), hasLength(5));
    expect(second.picks, isEmpty);
  });

  test('when everything is seen, the least recently seen comes first', () {
    final pool = _topic('History', 4);
    final seen = {
      for (var i = 0; i < pool.length; i++)
        pool[i].engagementKey: SeenRecord(
          lastSeenMs: _now
              .subtract(Duration(hours: 10 - i))
              .millisecondsSinceEpoch,
          count: 1,
        ),
    };
    final batch = _ranker().nextBatch(
      RankerSnapshot(pool: pool, seen: seen),
      RankerSession(),
      size: 4,
    );
    expect(
      batch.picks.map((p) => p.question.id),
      ['History_0', 'History_1', 'History_2', 'History_3'],
    );
    expect(batch.picks.every((p) => p.recycled), isTrue);
    expect(batch.picks.first.reason, 'Worth another look');
  });

  test('quick passes on a topic shrink its share', () {
    final snapshot = RankerSnapshot(
      pool: [..._topic('A', 50), ..._topic('B', 50)],
    );
    final baseline = _share(snapshot, 'A', (_) {});
    final passed = _share(
      snapshot,
      'A',
      (session) => session.quickPassStreak['A'] = 2,
    );
    expect(baseline, closeTo(0.5, 0.08));
    expect(passed, lessThan(baseline - 0.15));
  });

  test('likes this session grow a topic and explain why', () {
    final snapshot = RankerSnapshot(
      pool: [..._topic('A', 50), ..._topic('B', 50)],
    );
    final liked = _share(snapshot, 'A', (session) => session.likes['A'] = 3);
    expect(liked, greaterThan(0.6));

    final session = RankerSession()..likes['A'] = 3;
    final reasons = _ranker()
        .nextBatch(snapshot, session)
        .picks
        .where((p) => p.question.topicName == 'A')
        .map((p) => p.reason);
    expect(reasons, contains('Because you liked A'));
  });

  test('a huge interest score is capped so other topics still appear', () {
    final snapshot = RankerSnapshot(
      pool: [..._topic('A', 50), ..._topic('B', 50)],
      interest: const {'A': 1000},
    );
    final share = _share(snapshot, 'B', (_) {});
    expect(share, greaterThan(0.05));
  });

  test('too-easy questions are only used when nothing else is left', () {
    final pool = _topic('Bio', 3);
    final snapshot = RankerSnapshot(pool: pool, tooEasyIds: {pool[0].id});
    final session = RankerSession();
    final first = _ranker().nextBatch(
      snapshot,
      session,
      size: 2,
      allowRecycle: false,
    );
    expect(first.picks.map((p) => p.question.id), isNot(contains('Bio_0')));
    final second = _ranker().nextBatch(snapshot, session, allowRecycle: false);
    expect(second.picks.single.question.id, 'Bio_0');
  });

  test('recycling never repeats a question back to back', () {
    final ranker = _ranker();
    final session = RankerSession();
    final snapshot = RankerSnapshot(
      pool: [..._topic('A', 2), ..._topic('B', 1)],
    );
    final keys = <String>[];
    for (var i = 0; i < 40; i++) {
      keys.addAll(
        ranker
            .nextBatch(snapshot, session, size: 3)
            .picks
            .map((p) => p.question.engagementKey),
      );
    }
    expect(keys.length, greaterThan(60));
    for (var i = 1; i < keys.length; i++) {
      expect(keys[i], isNot(keys[i - 1]), reason: 'repeat at $i');
    }
  });

  test('a single-question pool ends instead of looping', () {
    final ranker = _ranker();
    final session = RankerSession();
    final snapshot = RankerSnapshot(pool: _topic('Solo', 1));
    expect(ranker.nextBatch(snapshot, session).picks, hasLength(1));
    expect(ranker.nextBatch(snapshot, session).picks, isEmpty);
  });

  test('due revision items take the revision slot', () {
    final pool = [..._topic('A', 20), ..._topic('B', 20)];
    final due = pool[25];
    final batch = _ranker().nextBatch(
      RankerSnapshot(pool: pool, dueKeys: {due.engagementKey}),
      RankerSession(),
    );
    final index = batch.picks.indexWhere((p) => p.question.id == due.id);
    expect(index, inInclusiveRange(0, 2));
    expect(batch.picks[index].reason, 'Revision due');
  });

  test('weak topics are labelled as practice where you are weak', () {
    final snapshot = RankerSnapshot(
      pool: _topic('Chem', 20),
      topicStats: const {'Chem': TopicStat(attempts: 10, correct: 3)},
    );
    final reasons = _ranker(3)
        .nextBatch(snapshot, RankerSession())
        .picks
        .map((p) => p.reason);
    expect(reasons, contains("Practice where you're weak"));
  });

  test('released cards become candidates again', () {
    final ranker = _ranker();
    final session = RankerSession();
    final snapshot = RankerSnapshot(pool: _topic('Geo', 4));
    final batch = ranker.nextBatch(
      snapshot,
      session,
      size: 4,
      allowRecycle: false,
    );
    session.release(batch.picks.skip(1).map((p) => p.question.engagementKey));
    final again = ranker.nextBatch(snapshot, session, allowRecycle: false);
    expect(again.picks, hasLength(3));
  });
}
