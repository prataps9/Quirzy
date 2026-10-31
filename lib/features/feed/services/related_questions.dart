import 'dart:math' as math;

import '../../search/models/search_index.dart';
import '../models/feed_models.dart';

/// Where a related question stands for this user.
enum RelatedStatus {
  fresh('New'),
  missed('Missed'),
  answered('Answered');

  const RelatedStatus(this.label);
  final String label;
}

class RelatedQuestion {
  final PracticeQuestion question;
  final RelatedStatus status;
  final double score;

  const RelatedQuestion(this.question, this.status, this.score);
}

/// Picks the questions most worth doing next to the one being studied.
///
/// "Related" means it shares meaningful words with the question, its options
/// and its explanation. Rare words count for more than common ones, the
/// same topic is a boost, and what the user has done with a question
/// decides ties: missed ones first, then new ones, answered ones last.
class RelatedQuestions {
  static const _titleWeight = 1.0;
  static const _bodyWeight = 0.5;
  static const _topicBoost = 0.3;
  static const _missedBoost = 0.5;
  static const _freshBoost = 0.15;
  static const _answeredPenalty = 0.3;

  static const _stopWords = {
    'the', 'and', 'for', 'are', 'was', 'were', 'with', 'that', 'this', 'from', 'which', 'what', 'who', 'whom', //
    'when', 'where', 'why', 'how', 'does', 'did', 'has', 'have', 'had', 'its', 'not', 'but', 'can', 'will', //
    'following', 'statements', 'statement', 'correct', 'incorrect', 'true', 'false', 'none', 'all', 'above', //
    'below', 'these', 'those', 'than', 'then', 'into', 'about', 'also', 'one', 'two', 'both', 'either', 'neither', //
    'yes', 'option', 'options', 'answer', 'question', //
  };

  /// The distinct meaningful words of [text].
  static Set<String> _words(String text) =>
      SearchIndex.terms(text).where((w) => w.length >= 3 && !_stopWords.contains(w)).toSet();

  static String _flat(String text) => SearchIndex.terms(text).join(' ');

  /// Up to [limit] questions from [pool] related to [question], best first.
  ///
  /// [seen] and [missed] are engagement keys (`PracticeQuestionKeys.engagementKey`).
  /// Reported questions ([excludedIds]) and muted topics are never offered.
  static List<RelatedQuestion> rank(
    PracticeQuestion question,
    List<PracticeQuestion> pool, {
    Set<String> seen = const {},
    Set<String> missed = const {},
    Set<String> excludedIds = const {},
    Set<String> mutedTopics = const {},
    int limit = 5,
  }) {
    final ownKey = question.engagementKey;
    final ownText = _flat(question.questionText);
    final texts = <String>{ownText};
    final candidates = <_Candidate>[];
    for (final q in pool) {
      if (q.id == question.id || q.engagementKey == ownKey) continue;
      if (excludedIds.contains(q.id) || mutedTopics.contains(q.topicName)) continue;
      if (!texts.add(_flat(q.questionText))) continue; // the same question again
      candidates.add(_Candidate(q, _words(q.questionText), _words([...q.options, q.explanation].join(' '))));
    }
    if (candidates.isEmpty || limit <= 0) return const [];

    final queryTitle = _words(question.questionText);
    final queryBody = _words([...question.options, question.explanation].join(' '))..removeAll(queryTitle);
    final queryWeights = <String, double>{
      for (final w in queryBody) w: _bodyWeight,
      for (final w in queryTitle) w: _titleWeight,
    };

    // How many questions each word appears in, for "rare words count more".
    final documents = <String, int>{};
    for (final w in queryWeights.keys) {
      documents[w] = 1;
    }
    for (final c in candidates) {
      for (final w in c.all) {
        if (queryWeights.containsKey(w)) documents[w] = (documents[w] ?? 0) + 1;
      }
    }
    final total = candidates.length + 1;
    double idf(String w) => math.log(1 + total / (documents[w] ?? 1));

    RelatedStatus statusOf(PracticeQuestion q) {
      final key = q.engagementKey;
      if (missed.contains(key)) return RelatedStatus.missed;
      return seen.contains(key) ? RelatedStatus.answered : RelatedStatus.fresh;
    }

    double adjust(RelatedStatus s) => switch (s) {
      RelatedStatus.missed => _missedBoost,
      RelatedStatus.fresh => _freshBoost,
      RelatedStatus.answered => -_answeredPenalty,
    };

    final hasTopic = question.topic != null && question.topic!.trim().isNotEmpty;
    final matched = <RelatedQuestion>[];
    final unmatched = <_Candidate>[];
    for (final c in candidates) {
      var shared = 0.0;
      for (final w in queryWeights.keys) {
        final inTitle = c.title.contains(w);
        if (!inTitle && !c.body.contains(w)) continue;
        shared += idf(w) * math.min(queryWeights[w]!, inTitle ? _titleWeight : _bodyWeight);
      }
      if (shared == 0) {
        unmatched.add(c);
        continue;
      }
      final status = statusOf(c.question);
      final sameTopic = hasTopic && c.question.topic == question.topic;
      final score = shared / math.sqrt(c.all.length + 5) + (sameTopic ? _topicBoost : 0) + adjust(status);
      matched.add(RelatedQuestion(c.question, status, score));
    }
    matched.sort(_byScore);

    final picked = matched.take(limit).toList();
    if (picked.length < limit && hasTopic) {
      // Too few share words: fill with the same topic, missed first.
      final fill = unmatched.where((c) => c.question.topic == question.topic).map((c) {
        final s = statusOf(c.question);
        return RelatedQuestion(c.question, s, adjust(s) - 1);
      }).toList()..sort(_byScore);
      picked.addAll(fill.take(limit - picked.length));
    }
    return picked;
  }

  static int _byScore(RelatedQuestion a, RelatedQuestion b) {
    final byScore = b.score.compareTo(a.score);
    return byScore != 0 ? byScore : a.question.id.compareTo(b.question.id);
  }
}

class _Candidate {
  final PracticeQuestion question;
  final Set<String> title;
  final Set<String> body;
  late final Set<String> all = {...title, ...body};

  _Candidate(this.question, this.title, this.body);
}
