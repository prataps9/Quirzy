import '../../feed/models/feed_models.dart';

/// A timed, exam-style test: a fixed set of questions, the user's picks and
/// how much time has been used. Saved as it goes so it can be resumed.
class MockTest {
  final String id;
  final List<PracticeQuestion> questions;

  /// Question index to the option picked.
  final Map<int, int> answers;

  /// Questions marked to come back to.
  final Set<int> flagged;

  /// The whole time allowed, and how much of it has been used. The clock
  /// only runs while the test is on screen.
  final int limitSeconds;
  final int usedSeconds;

  /// Where the user was, so a resumed test opens on the same question.
  final int current;

  const MockTest({
    required this.id,
    required this.questions,
    required this.limitSeconds,
    this.answers = const {},
    this.flagged = const {},
    this.usedSeconds = 0,
    this.current = 0,
  });

  int get total => questions.length;
  int get answeredCount => answers.length;
  int get unanswered => total - answeredCount;
  int get remainingSeconds => (limitSeconds - usedSeconds).clamp(0, limitSeconds);
  bool get timeUp => usedSeconds >= limitSeconds;

  bool isRight(int index) => answers[index] == questions[index].correctIndex;
  int get correct => [for (var i = 0; i < total; i++) i].where(isRight).length;

  MockTest copyWith({Map<int, int>? answers, Set<int>? flagged, int? usedSeconds, int? current}) => MockTest(
    id: id,
    questions: questions,
    limitSeconds: limitSeconds,
    answers: answers ?? this.answers,
    flagged: flagged ?? this.flagged,
    usedSeconds: usedSeconds ?? this.usedSeconds,
    current: current ?? this.current,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'qs': [for (final q in questions) q.toJson()],
    'answers': {for (final e in answers.entries) '${e.key}': e.value},
    'flagged': flagged.toList(),
    'limit': limitSeconds,
    'used': usedSeconds,
    'current': current,
  };

  factory MockTest.fromJson(Map<String, dynamic> json) => MockTest(
    id: json['id'] as String,
    questions: [for (final q in json['qs'] as List) PracticeQuestion.fromJson(Map<String, dynamic>.from(q as Map))],
    answers: {for (final e in (json['answers'] as Map).entries) int.parse(e.key as String): e.value as int},
    flagged: {for (final f in json['flagged'] as List) f as int},
    limitSeconds: json['limit'] as int,
    usedSeconds: json['used'] as int? ?? 0,
    current: json['current'] as int? ?? 0,
  );
}

/// How one topic went in a finished test.
class TopicScore {
  final String topic;
  final int correct;
  final int total;

  const TopicScore({required this.topic, required this.correct, required this.total});

  double get share => total == 0 ? 0 : correct / total;
}

/// A finished test, kept in the history.
class MockResult {
  final String id;
  final int finishedMs;
  final int correct;
  final int total;
  final int usedSeconds;
  final List<TopicScore> topics;

  const MockResult({
    required this.id,
    required this.finishedMs,
    required this.correct,
    required this.total,
    required this.usedSeconds,
    required this.topics,
  });

  int get percent => total == 0 ? 0 : (correct * 100 / total).round();

  /// The topic with the lowest score (ties: the one with more questions).
  TopicScore? get weakest {
    if (topics.isEmpty) return null;
    final sorted = [...topics]
      ..sort((a, b) {
        final byShare = a.share.compareTo(b.share);
        return byShare != 0 ? byShare : b.total.compareTo(a.total);
      });
    return sorted.first.share < 1 ? sorted.first : null;
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'at': finishedMs,
    'correct': correct,
    'total': total,
    'used': usedSeconds,
    'topics': [
      for (final t in topics) {'t': t.topic, 'c': t.correct, 'n': t.total},
    ],
  };

  factory MockResult.fromJson(Map<String, dynamic> json) => MockResult(
    id: json['id'] as String,
    finishedMs: json['at'] as int,
    correct: json['correct'] as int,
    total: json['total'] as int,
    usedSeconds: json['used'] as int? ?? 0,
    topics: [
      for (final t in json['topics'] as List)
        TopicScore(topic: (t as Map)['t'] as String, correct: t['c'] as int, total: t['n'] as int),
    ],
  );
}
