import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/feed_models.dart';

class PracticeContentKeys {
  /// Old single-blob pool (pre per-topic redesign) — read once for a
  /// one-time migration, then cleared.
  static const String legacyQuestionPool = 'daily_challenge_question_pool';
  static const String topicsStore = 'feed_topics_store_v2';
  static const String lastPoolRefreshDate = 'daily_challenge_pool_refresh_date';
}

/// The feed's local content store: questions are grouped by topic, each
/// topic capped independently, so practicing many topics can no longer
/// silently evict an older topic's questions the way one shared cap did.
/// A topic marked "downloaded" is protected from eviction entirely.
class PracticeContentService {
  static PracticeContentService? _instance;
  static PracticeContentService get instance =>
      _instance ??= PracticeContentService._();

  PracticeContentService._();

  static const String _generalTopic = 'General';
  static const int maxQuestionsPerTopic = 200;
  static const int maxTopics = 15;

  String get todayString => DateTime.now().toIso8601String().split('T').first;

  Future<Map<String, dynamic>> _loadStore(SharedPreferences prefs) async {
    final raw = prefs.getString(PracticeContentKeys.topicsStore);
    if (raw != null && raw.isNotEmpty) {
      return jsonDecode(raw) as Map<String, dynamic>;
    }
    return _migrateLegacyPool(prefs);
  }

  /// One-time migration from the old flat, globally-capped pool into
  /// per-topic buckets, bucketing by each question's own `topic` field.
  Future<Map<String, dynamic>> _migrateLegacyPool(SharedPreferences prefs) async {
    final store = <String, dynamic>{
      'topics': <String, dynamic>{},
      'downloaded': <String>[],
    };

    final legacyRaw = prefs.getString(PracticeContentKeys.legacyQuestionPool);
    if (legacyRaw == null || legacyRaw.isEmpty) return store;

    final legacyList = List<Map<String, dynamic>>.from(jsonDecode(legacyRaw));
    final topics = store['topics'] as Map<String, dynamic>;
    final now = DateTime.now().toIso8601String();

    for (final q in legacyList) {
      final rawTopic = q['topic'] as String?;
      final topicName = (rawTopic == null || rawTopic.trim().isEmpty) ? _generalTopic : rawTopic;
      final bucket = topics.putIfAbsent(
        topicName,
        () => {'questions': <Map<String, dynamic>>[], 'lastUpdated': now},
      ) as Map<String, dynamic>;
      (bucket['questions'] as List).add(q);
    }

    await _saveStore(prefs, store);
    await prefs.remove(PracticeContentKeys.legacyQuestionPool);
    return store;
  }

  Future<void> _saveStore(SharedPreferences prefs, Map<String, dynamic> store) async {
    await prefs.setString(PracticeContentKeys.topicsStore, jsonEncode(store));
  }

  /// Parses one stored question, or returns null when it can't be shown
  /// correctly (no text, fewer than two options, or an answer index that
  /// doesn't point at an option) — one bad item must not break the feed.
  PracticeQuestion? _toPracticeQuestion(Map<String, dynamic> q, String topicName, int fallbackIndex) {
    final options = [for (final o in (q['options'] as List? ?? const [])) o.toString()];
    final rawIndex = q['correctIndex'] ?? q['correctAnswer'] ?? 0;
    final correctIndex = rawIndex is int ? rawIndex : int.tryParse(rawIndex.toString());
    final questionText = (q['questionText'] ?? q['question'] ?? '').toString();
    if (questionText.trim().isEmpty || options.length < 2) return null;
    if (correctIndex == null || correctIndex < 0 || correctIndex >= options.length) return null;
    return PracticeQuestion(
      id: q['id']?.toString() ?? '${topicName}_$fallbackIndex',
      questionText: questionText,
      options: options,
      correctIndex: correctIndex,
      explanation: (q['explanation'] ?? '').toString(),
      sourceTopicId: q['sourceTopicId']?.toString() ?? q['originalQuizId']?.toString() ?? q['quizId']?.toString(),
      topic: topicName,
    );
  }

  /// The full local question pool (all topics flattened), as typed
  /// models — the data source for the practice feed.
  Future<List<PracticeQuestion>> getQuestionPool() async {
    final prefs = await SharedPreferences.getInstance();
    final store = await _loadStore(prefs);
    final topics = store['topics'] as Map<String, dynamic>;

    final all = <PracticeQuestion>[];
    for (final entry in topics.entries) {
      final bucket = entry.value as Map<String, dynamic>;
      final questions = List<Map<String, dynamic>>.from(bucket['questions'] ?? const []);
      for (var i = 0; i < questions.length; i++) {
        final question = _toPracticeQuestion(questions[i], entry.key, i);
        if (question != null) all.add(question);
      }
    }
    return all;
  }

  /// One row per topic bucket — for the lane switcher / download UI.
  Future<List<TopicSummary>> getTopicSummaries() async {
    final prefs = await SharedPreferences.getInstance();
    final store = await _loadStore(prefs);
    final topics = store['topics'] as Map<String, dynamic>;
    final downloaded = List<String>.from(store['downloaded'] ?? const []);

    return topics.entries.map((entry) {
      final bucket = entry.value as Map<String, dynamic>;
      final questions = List.from(bucket['questions'] ?? const []);
      return TopicSummary(
        topic: entry.key,
        count: questions.length,
        downloaded: downloaded.contains(entry.key),
        lastUpdated: DateTime.tryParse(bucket['lastUpdated']?.toString() ?? '') ?? DateTime.now(),
      );
    }).toList();
  }

  /// Marks a topic as protected from eviction ("downloaded for offline")
  /// or releases that protection.
  Future<void> setDownloaded(String topic, bool value) async {
    final prefs = await SharedPreferences.getInstance();
    final store = await _loadStore(prefs);
    final downloaded = List<String>.from(store['downloaded'] ?? const []);

    if (value && !downloaded.contains(topic)) {
      downloaded.add(topic);
    } else if (!value) {
      downloaded.remove(topic);
    }

    store['downloaded'] = downloaded;
    await _saveStore(prefs, store);
  }

  /// Adds newly generated/added questions to [topic]'s bucket — called
  /// right after a topic is generated or manual questions are added, so
  /// the feed always has fresh content to practice.
  Future<void> addToQuestionPool(
    List<Map<String, dynamic>> questions, {
    String? topicId,
    String? topic,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final store = await _loadStore(prefs);
    final topics = store['topics'] as Map<String, dynamic>;
    final downloaded = List<String>.from(store['downloaded'] ?? const []);

    final topicName = (topic == null || topic.trim().isEmpty) ? _generalTopic : topic;
    final existingBucket = topics[topicName] as Map<String, dynamic>?;
    final existingQuestions = List<Map<String, dynamic>>.from(existingBucket?['questions'] ?? const []);

    final newQuestions = <Map<String, dynamic>>[];
    for (var i = 0; i < questions.length; i++) {
      final q = questions[i];
      newQuestions.add({
        'id': q['id'] ?? '${topicId}_${existingQuestions.length + i}',
        'questionText': q['questionText'] ?? q['question'] ?? '',
        'options': q['options'] ?? ['A', 'B', 'C', 'D'],
        'correctIndex':
            q['correctIndex'] ?? q['correctAnswer'] ?? q['correctOption'] ?? 0,
        'explanation': q['explanation'] ?? '',
        'sourceTopicId': topicId ?? q['topicId'],
        'topic': topicName,
      });
    }

    final existingIds = existingQuestions.map((q) => q['id'].toString()).toSet();
    final uniqueNew = newQuestions.where((q) => !existingIds.contains(q['id'].toString()));
    final merged = [...existingQuestions, ...uniqueNew];
    final trimmed = merged.length > maxQuestionsPerTopic
        ? merged.sublist(merged.length - maxQuestionsPerTopic)
        : merged;

    topics[topicName] = {
      'questions': trimmed,
      'lastUpdated': DateTime.now().toIso8601String(),
    };

    _evictLruTopicIfNeeded(topics, downloaded, keepTopic: topicName);

    store['topics'] = topics;
    store['downloaded'] = downloaded;
    await _saveStore(prefs, store);
    await prefs.setString(PracticeContentKeys.lastPoolRefreshDate, todayString);
  }

  /// If the number of distinct topics exceeds [maxTopics], drops the
  /// least-recently-updated topic that isn't downloaded and isn't the
  /// one just written to. Downloaded topics are never evicted — if every
  /// topic is downloaded, the cap is simply exceeded rather than
  /// removing protected content.
  void _evictLruTopicIfNeeded(
    Map<String, dynamic> topics,
    List<String> downloaded, {
    required String keepTopic,
  }) {
    if (topics.length <= maxTopics) return;

    final candidates = topics.keys
        .where((k) => k != keepTopic && !downloaded.contains(k))
        .toList();
    if (candidates.isEmpty) return;

    candidates.sort((a, b) {
      final aTime = DateTime.tryParse((topics[a] as Map)['lastUpdated']?.toString() ?? '') ?? DateTime(0);
      final bTime = DateTime.tryParse((topics[b] as Map)['lastUpdated']?.toString() ?? '') ?? DateTime(0);
      return aTime.compareTo(bTime);
    });

    topics.remove(candidates.first);
  }
}

/// Provider for [PracticeContentService]
final practiceContentServiceProvider = Provider<PracticeContentService>((ref) {
  return PracticeContentService.instance;
});
