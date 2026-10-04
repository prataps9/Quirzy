import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

class TopicStat {
  final int attempts;
  final int correct;

  const TopicStat({this.attempts = 0, this.correct = 0});

  double get accuracy => attempts == 0 ? 0 : (correct / attempts) * 100;
}

/// Per-topic accuracy (drives "My Weak Topics"), plus the local content
/// moderation state (muted topics, reported/deprioritized questions) and
/// "why was I wrong" reason tally (PRD §F5, §F12, §8).
class FeedStatsService {
  static const _statsKey = 'feed_topic_stats';
  static const _mutedKey = 'feed_muted_topics';
  static const _reportedKey = 'feed_reported_questions';
  static const _deprioritizedKey = 'feed_deprioritized_questions';
  static const _wrongReasonKey = 'feed_wrong_reasons';

  Future<void> recordAttempt(String? topic, bool correct) async {
    final t = (topic == null || topic.trim().isEmpty) ? 'General' : topic;
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_statsKey);
    final Map<String, dynamic> map = raw != null && raw.isNotEmpty
        ? jsonDecode(raw) as Map<String, dynamic>
        : <String, dynamic>{};
    final entry = Map<String, dynamic>.from(
      map[t] as Map<String, dynamic>? ?? {'attempts': 0, 'correct': 0},
    );
    entry['attempts'] = (entry['attempts'] as int? ?? 0) + 1;
    if (correct) entry['correct'] = (entry['correct'] as int? ?? 0) + 1;
    map[t] = entry;
    await prefs.setString(_statsKey, jsonEncode(map));
  }

  Future<Map<String, TopicStat>> getTopicStats() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_statsKey);
    if (raw == null || raw.isEmpty) return {};
    final map = jsonDecode(raw) as Map<String, dynamic>;
    return map.map(
      (key, value) => MapEntry(
        key,
        TopicStat(
          attempts: (value as Map<String, dynamic>)['attempts'] as int? ?? 0,
          correct: value['correct'] as int? ?? 0,
        ),
      ),
    );
  }

  /// Topics with accuracy < [threshold]% across at least [minAttempts] tries.
  Future<Set<String>> getWeakTopics({
    int minAttempts = 10,
    double threshold = 55,
  }) async {
    final stats = await getTopicStats();
    return stats.entries
        .where((e) => e.value.attempts >= minAttempts && e.value.accuracy < threshold)
        .map((e) => e.key)
        .toSet();
  }

  Future<Set<String>> _readSet(String key) async {
    final prefs = await SharedPreferences.getInstance();
    return (prefs.getStringList(key) ?? const []).toSet();
  }

  Future<void> _addToSet(String key, String value) async {
    final prefs = await SharedPreferences.getInstance();
    final set = (prefs.getStringList(key) ?? const []).toSet()..add(value);
    await prefs.setStringList(key, set.toList());
  }

  Future<void> muteTopic(String topic) => _addToSet(_mutedKey, topic);
  Future<Set<String>> getMutedTopics() => _readSet(_mutedKey);

  Future<void> unmuteTopic(String topic) async {
    final prefs = await SharedPreferences.getInstance();
    final set = (prefs.getStringList(_mutedKey) ?? const []).toSet()
      ..remove(topic);
    await prefs.setStringList(_mutedKey, set.toList());
  }

  Future<void> reportQuestion(String questionId) =>
      _addToSet(_reportedKey, questionId);
  Future<Set<String>> getReportedQuestions() => _readSet(_reportedKey);

  Future<void> deprioritizeQuestion(String questionId) =>
      _addToSet(_deprioritizedKey, questionId);
  Future<Set<String>> getDeprioritizedQuestions() => _readSet(_deprioritizedKey);

  Future<void> recordWrongReason(String reason) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_wrongReasonKey);
    final Map<String, dynamic> map = raw != null && raw.isNotEmpty
        ? jsonDecode(raw) as Map<String, dynamic>
        : <String, dynamic>{};
    map[reason] = (map[reason] as int? ?? 0) + 1;
    await prefs.setString(_wrongReasonKey, jsonEncode(map));
  }

  /// Questions answered per day for the last [days] days (oldest first) —
  /// reconstructed from the same daily counters FeedController already
  /// writes, so My Prep's activity trend needs no new storage format.
  Future<List<int>> getDailyAnsweredCounts({int days = 7}) async {
    final prefs = await SharedPreferences.getInstance();
    final now = DateTime.now();
    final counts = <int>[];
    for (var i = days - 1; i >= 0; i--) {
      final date = now.subtract(Duration(days: i));
      final dateStr = date.toIso8601String().split('T').first;
      counts.add(prefs.getInt('feed_answered_count_$dateStr') ?? 0);
    }
    return counts;
  }

  Future<int> getTodayAnsweredCount() async {
    final counts = await getDailyAnsweredCounts(days: 1);
    return counts.first;
  }
}
