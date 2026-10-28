import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../../feed/models/topic_mastery.dart';
import '../../feed/services/daily_challenge_service.dart';
import '../../feed/services/feed_stats_service.dart';
import '../../feed/services/mistakes_service.dart';
import '../../feed/services/streak_service.dart';
import '../../mocktest/services/mock_test_service.dart';
import '../models/badge.dart';

/// Works out which badges are earned, from what the app already records,
/// and remembers when each was first earned. A badge is never taken away.
class BadgeService {
  BadgeService({
    StreakService? streaks,
    FeedStatsService? stats,
    DailyChallengeService? daily,
    MockTestService? mock,
    MistakesService? mistakes,
    DateTime Function()? clock,
  }) : _streaks = streaks ?? StreakService(),
       _stats = stats ?? FeedStatsService(),
       _daily = daily ?? DailyChallengeService(),
       _mock = mock ?? MockTestService(),
       _mistakes = mistakes ?? MistakesService(),
       _clock = clock ?? DateTime.now;

  static const _key = 'badges_v1';

  final StreakService _streaks;
  final FeedStatsService _stats;
  final DailyChallengeService _daily;
  final MockTestService _mock;
  final MistakesService _mistakes;
  final DateTime Function() _clock;

  static int _sumOf(SharedPreferences prefs, String prefix) {
    var total = 0;
    for (final key in prefs.getKeys()) {
      if (key.startsWith(prefix)) total += prefs.getInt(key) ?? 0;
    }
    return total;
  }

  Future<BadgeMetrics> metrics() async {
    final prefs = await SharedPreferences.getInstance();
    final streak = await _streaks.getStreak();
    final daily = await _daily.history();
    final topicStats = await _stats.getTopicStats();
    final mastered = topicStats.entries
        .where(
          (e) =>
              TopicMastery(topic: e.key, attempts: e.value.attempts, accuracy: e.value.accuracy).level ==
              MasteryLevel.mastered,
        )
        .length;
    final mocks = await _mock.history();
    return BadgeMetrics(
      totalAnswers: _sumOf(prefs, 'feed_answered_count_'),
      bestStreak: streak.best,
      dailyPlayed: daily.played,
      dailyPerfect: daily.perfect,
      masteredTopics: mastered,
      flashcardsReviewed: _sumOf(prefs, 'flashcard_reviewed_count_'),
      mockTests: mocks.length,
      bestMockPercent: mocks.fold(0, (best, r) => r.percent > best ? r.percent : best),
      mistakesFixed: await _mistakes.fixedCount(),
    );
  }

  /// When each badge was earned (milliseconds since epoch).
  Future<Map<BadgeId, int>> earned() async {
    final prefs = await SharedPreferences.getInstance();
    try {
      final raw = prefs.getString(_key);
      if (raw == null) return {};
      final map = Map<String, dynamic>.from(jsonDecode(raw) as Map);
      return {
        for (final id in BadgeId.values)
          if (map[id.name] is int) id: map[id.name] as int,
      };
    } catch (_) {
      return {};
    }
  }

  /// Saves any badge newly reached and returns those, in catalog order.
  Future<List<BadgeId>> check({BadgeMetrics? metrics}) async {
    final m = metrics ?? await this.metrics();
    final have = await earned();
    final fresh = [
      for (final def in BadgeDef.catalog)
        if (!have.containsKey(def.id) && def.reached(m)) def.id,
    ];
    if (fresh.isEmpty) return const [];
    final now = _clock().millisecondsSinceEpoch;
    final updated = {for (final e in have.entries) e.key.name: e.value, for (final id in fresh) id.name: now};
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, jsonEncode(updated));
    return fresh;
  }

  /// Every badge with its progress, earned ones first.
  Future<List<BadgeStatus>> statuses() async {
    final m = await metrics();
    await check(metrics: m);
    final have = await earned();
    final all = [
      for (final def in BadgeDef.catalog)
        BadgeStatus(
          def: def,
          progress: def.progress(m),
          earnedAt: have[def.id] == null ? null : DateTime.fromMillisecondsSinceEpoch(have[def.id]!),
        ),
    ];
    return [...all.where((b) => b.earned), ...all.where((b) => !b.earned)];
  }
}
