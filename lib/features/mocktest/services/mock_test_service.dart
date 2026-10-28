import 'dart:convert';
import 'dart:math' as math;

import 'package:shared_preferences/shared_preferences.dart';

import '../../feed/models/feed_models.dart';
import '../../feed/services/feed_revision_service.dart';
import '../../feed/services/feed_stats_service.dart';
import '../../feed/services/mistakes_service.dart';
import '../../feed/services/streak_service.dart';
import '../../feed/services/xp_service.dart';
import '../models/mock_test.dart';

/// Builds, saves and scores mock tests. A finished test counts like
/// practice: topic stats, the Mistakes notebook, the Revision Vault, today's
/// answers (so it keeps the streak) and XP.
class MockTestService {
  MockTestService({
    math.Random? random,
    FeedStatsService? stats,
    MistakesService? mistakes,
    FeedRevisionService? revision,
    XpService? xp,
    DateTime Function()? clock,
  }) : _random = random ?? math.Random(),
       _stats = stats ?? FeedStatsService(),
       _mistakes = mistakes ?? MistakesService(),
       _revision = revision ?? FeedRevisionService(),
       _xp = xp ?? XpService(),
       _clock = clock ?? DateTime.now;

  static const lengths = [10, 20, 30];

  /// Time allowed per question.
  static const secondsPerQuestion = 60;
  static const maxHistory = 20;

  static const _inProgressKey = 'mock_test_in_progress';
  static const _historyKey = 'mock_test_history';

  final math.Random _random;
  final FeedStatsService _stats;
  final MistakesService _mistakes;
  final FeedRevisionService _revision;
  final XpService _xp;
  final DateTime Function() _clock;

  static bool _usable(PracticeQuestion q) =>
      q.options.length >= 2 && q.correctIndex >= 0 && q.correctIndex < q.options.length;

  /// A test of up to [length] questions from [topics] (all topics when
  /// empty), spread evenly across them, in a random order.
  MockTest build(List<PracticeQuestion> pool, {Set<String> topics = const {}, int length = 20}) {
    final byTopic = <String, List<PracticeQuestion>>{};
    for (final q in pool.where(_usable)) {
      if (topics.isNotEmpty && !topics.contains(q.topicName)) continue;
      byTopic.putIfAbsent(q.topicName, () => []).add(q);
    }
    for (final list in byTopic.values) {
      list.shuffle(_random);
    }
    // Round-robin over the topics so each gets a fair share.
    final names = byTopic.keys.toList()..shuffle(_random);
    final picked = <PracticeQuestion>[];
    var round = 0;
    while (picked.length < length) {
      var added = false;
      for (final name in names) {
        final list = byTopic[name]!;
        if (round < list.length && picked.length < length) {
          picked.add(list[round]);
          added = true;
        }
      }
      if (!added) break;
      round++;
    }
    picked.shuffle(_random);
    return MockTest(
      id: 'mock_${_clock().millisecondsSinceEpoch}',
      questions: picked,
      limitSeconds: picked.length * secondsPerQuestion,
    );
  }

  Future<MockTest?> loadInProgress() async {
    final prefs = await SharedPreferences.getInstance();
    try {
      final raw = prefs.getString(_inProgressKey);
      if (raw == null) return null;
      return MockTest.fromJson(Map<String, dynamic>.from(jsonDecode(raw) as Map));
    } catch (_) {
      return null;
    }
  }

  Future<void> saveInProgress(MockTest test) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_inProgressKey, jsonEncode(test.toJson()));
  }

  Future<void> discardInProgress() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_inProgressKey);
  }

  Future<List<MockResult>> history() async {
    final prefs = await SharedPreferences.getInstance();
    try {
      final raw = prefs.getString(_historyKey);
      if (raw == null) return [];
      return [for (final r in jsonDecode(raw) as List) MockResult.fromJson(Map<String, dynamic>.from(r as Map))];
    } catch (_) {
      return [];
    }
  }

  /// Scores [test] (unanswered questions count as wrong), records every
  /// answer as practice and adds the result to the history, newest first.
  Future<MockResult> finish(MockTest test) async {
    final topics = <String, (int, int)>{};
    for (var i = 0; i < test.total; i++) {
      final q = test.questions[i];
      final right = test.isRight(i);
      final (c, n) = topics[q.topicName] ?? (0, 0);
      topics[q.topicName] = (c + (right ? 1 : 0), n + 1);

      // Only answered questions count as attempts; a blank says nothing
      // about what the user knows, but it is still a miss on the test.
      if (test.answers.containsKey(i)) {
        await _stats.recordAttempt(q.topic, right, now: _clock());
        await _revision.recordOutcome(q, right);
        await _mistakes.recordAnswer(q, correct: right, pick: right ? null : test.answers[i], now: _clock());
      }
    }

    final prefs = await SharedPreferences.getInstance();
    if (test.answeredCount > 0) {
      final key = StreakService.countKey(_clock());
      await prefs.setInt(key, (prefs.getInt(key) ?? 0) + test.answeredCount);
    }
    final correct = test.correct;
    if (correct > 0) await _xp.addXPToday(correct * kFeedXpPerCorrect);

    final result = MockResult(
      id: test.id,
      finishedMs: _clock().millisecondsSinceEpoch,
      correct: correct,
      total: test.total,
      usedSeconds: math.min(test.usedSeconds, test.limitSeconds),
      topics: [for (final e in topics.entries) TopicScore(topic: e.key, correct: e.value.$1, total: e.value.$2)]
        ..sort((a, b) => a.topic.compareTo(b.topic)),
    );
    final past = await history();
    final updated = [result, ...past.where((r) => r.id != result.id)].take(maxHistory).toList();
    await prefs.setString(_historyKey, jsonEncode([for (final r in updated) r.toJson()]));
    await prefs.remove(_inProgressKey);
    return result;
  }
}
