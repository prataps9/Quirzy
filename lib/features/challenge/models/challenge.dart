import 'dart:convert';
import 'dart:io' show gzip;

import '../../feed/models/feed_models.dart';

/// A set of questions someone sent, with their score to beat. It travels
/// entirely inside a `quirzy://challenge?d=…` link: no server involved.
class Challenge {
  /// Who sent it (first name), if known.
  final String? from;

  /// Their score out of [questions.length]; null when they just shared the
  /// questions.
  final int? score;
  final List<PracticeQuestion> questions;

  const Challenge({this.from, this.score, required this.questions});

  int get total => questions.length;

  Challenge copyWith({String? from, int? score}) =>
      Challenge(from: from ?? this.from, score: score ?? this.score, questions: questions);
}

/// Turns a [Challenge] into a link and back. Everything read from a link is
/// checked: a broken, oversized or tampered link is rejected with a
/// [FormatException] rather than half-loaded.
class ChallengeCodec {
  static const scheme = 'quirzy';
  static const host = 'challenge';
  static const version = 1;

  static const maxQuestions = 10;
  static const maxQuestionLength = 500;
  static const maxOptionLength = 200;
  static const maxExplanationLength = 300;
  static const maxNameLength = 30;
  static const maxTopicLength = 60;
  static const maxLinkData = 16000;

  static String _cut(String text, int max) => text.length <= max ? text : '${text.substring(0, max - 1)}…';

  static Uri encode(Challenge challenge) {
    final questions = challenge.questions.take(maxQuestions).toList();
    final json = {
      'v': version,
      if (challenge.from != null && challenge.from!.trim().isNotEmpty) 'f': _cut(challenge.from!.trim(), maxNameLength),
      if (challenge.score != null) 's': challenge.score!.clamp(0, questions.length),
      'q': [
        for (final q in questions)
          {
            't': _cut(q.questionText, maxQuestionLength),
            'o': [for (final o in q.options.take(6)) _cut(o, maxOptionLength)],
            'c': q.correctIndex,
            if (q.explanation.trim().isNotEmpty) 'e': _cut(q.explanation.trim(), maxExplanationLength),
            if (q.topic != null) 'p': _cut(q.topicName, maxTopicLength),
          },
      ],
    };
    final packed = base64Url.encode(gzip.encode(utf8.encode(jsonEncode(json)))).replaceAll('=', '');
    return Uri(scheme: scheme, host: host, queryParameters: {'d': packed});
  }

  /// Whether [uri] is a challenge link at all (it may still be broken).
  static bool isChallenge(Uri uri) => uri.scheme == scheme && uri.host == host;

  static Challenge decode(Uri uri) {
    if (!isChallenge(uri)) throw const FormatException('Not a challenge link');
    final data = uri.queryParameters['d'];
    if (data == null || data.isEmpty || data.length > maxLinkData) {
      throw const FormatException('Missing or oversized challenge data');
    }
    final Object? json;
    try {
      final padded = data.padRight(data.length + (4 - data.length % 4) % 4, '=');
      final bytes = gzip.decode(base64Url.decode(padded));
      if (bytes.length > maxLinkData * 8) throw const FormatException('Too big');
      json = jsonDecode(utf8.decode(bytes));
    } catch (_) {
      throw const FormatException('Unreadable challenge data');
    }
    if (json is! Map || json['v'] != version) throw const FormatException('Unknown challenge version');

    final raw = json['q'];
    if (raw is! List || raw.isEmpty || raw.length > maxQuestions) throw const FormatException('Bad questions');
    final questions = <PracticeQuestion>[];
    for (var i = 0; i < raw.length; i++) {
      final q = raw[i];
      if (q is! Map) throw const FormatException('Bad question');
      final text = q['t'];
      final options = q['o'];
      final correct = q['c'];
      final explanation = q['e'] ?? '';
      final topic = q['p'];
      if (text is! String || text.trim().isEmpty || text.length > maxQuestionLength) {
        throw const FormatException('Bad question text');
      }
      if (options is! List || options.length < 2 || options.length > 6) throw const FormatException('Bad options');
      if (options.any((o) => o is! String || o.trim().isEmpty || o.length > maxOptionLength)) {
        throw const FormatException('Bad option');
      }
      if (correct is! int || correct < 0 || correct >= options.length) throw const FormatException('Bad answer');
      if (explanation is! String || explanation.length > maxExplanationLength) {
        throw const FormatException('Bad explanation');
      }
      if (topic != null && (topic is! String || topic.length > maxTopicLength)) {
        throw const FormatException('Bad topic');
      }
      questions.add(
        PracticeQuestion(
          id: 'challenge_${text.hashCode.toUnsigned(32)}_$i',
          questionText: text,
          options: List<String>.from(options),
          correctIndex: correct,
          explanation: explanation,
          topic: topic as String?,
        ),
      );
    }

    final from = json['f'];
    final score = json['s'];
    if (from != null && (from is! String || from.length > maxNameLength)) throw const FormatException('Bad name');
    if (score != null && (score is! int || score < 0 || score > questions.length)) {
      throw const FormatException('Bad score');
    }
    return Challenge(
      from: (from as String?)?.trim().isEmpty ?? true ? null : from as String,
      score: score as int?,
      questions: questions,
    );
  }

  /// Finds the first challenge link in a pasted message, if any.
  static Uri? findIn(String text) {
    final match = RegExp(r'quirzy://challenge\?d=[A-Za-z0-9_\-]+').firstMatch(text);
    return match == null ? null : Uri.parse(match.group(0)!);
  }

  /// What gets shared: a line to beat, the link, and how to open it if the
  /// chat app doesn't make the link tappable.
  static String shareText(Challenge challenge) {
    final link = encode(challenge).toString();
    final lead = challenge.score != null
        ? 'Beat my ${challenge.score}/${challenge.total} on Quirzy!'
        : challenge.total == 1
        ? 'Can you get this one? Try it on Quirzy.'
        : 'Try these ${challenge.total} questions on Quirzy.';
    return '$lead\n\n$link\n\n'
        "If the link doesn't open, copy this message and tap \"Got a challenge?\" on Quirzy's Home.";
  }
}
