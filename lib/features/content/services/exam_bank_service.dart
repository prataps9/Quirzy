import 'package:shared_preferences/shared_preferences.dart';

import '../../feed/models/feed_models.dart';
import '../../feed/services/practice_content_service.dart';
import '../data/exam_bank.dart';

/// An English word with its meaning and an example sentence, taken from a
/// bundled "What does X mean?" question.
class WordOfDay {
  final String word;
  final String meaning;
  final String example;

  /// The question it came from, for saving it as a flashcard.
  final PracticeQuestion question;

  const WordOfDay({required this.word, required this.meaning, required this.example, required this.question});
}

/// Puts the bundled exam questions (SAT, GMAT, CAT and the shared aptitude
/// and English-words sets) into the feed's question store for the exam the
/// learner picked, so they have real exam-style practice before generating
/// anything of their own.
class ExamBankService {
  /// Bumped when questions are added, so existing installs pick them up
  /// (questions already stored are never duplicated: ids are stable).
  static const version = 1;

  /// Exams that practise the same material as another.
  static const aliases = {'mba': 'cat'};

  /// Which topics to add first when there is room for only some of them.
  static const topicPriority = [
    'Vocabulary',
    'Arithmetic',
    'Algebra',
    'Grammar & Usage',
    'Reading Comprehension',
    'Data Interpretation',
    'Geometry',
    'Number Systems',
    'Data Sufficiency',
    'Critical Reasoning',
    'Logical Reasoning',
  ];

  static String examKey(String exam) {
    final id = exam.toLowerCase();
    return aliases[id] ?? id;
  }

  /// The bundled questions for [exam], in bank order.
  static List<BankQuestion> forExam(String exam) {
    final id = examKey(exam);
    return [
      for (final q in examBank)
        if (q.examIds.contains(id)) q,
    ];
  }

  /// The topics [exam] has bundled questions for, most important first.
  static List<String> topicsFor(String exam) {
    final topics = {for (final q in forExam(exam)) q.topic};
    final ordered = [
      for (final t in topicPriority)
        if (topics.contains(t)) t,
    ];
    return [...ordered, ...topics.where((t) => !ordered.contains(t))];
  }

  /// A stable id for the question at [index] in [examBank]: its position
  /// among the bank's questions in the same topic.
  static String idOf(int index) {
    final q = examBank[index];
    var n = 0;
    for (var i = 0; i < index; i++) {
      if (examBank[i].topic == q.topic) n++;
    }
    final slug = q.topic.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '_').replaceAll(RegExp(r'^_|_$'), '');
    return 'bank_${slug}_${n + 1}';
  }

  static String _seededKey(String exam) => 'exam_bank_seeded_${examKey(exam)}_v$version';

  /// Adds [exam]'s questions to the store, once per exam and version.
  /// Learners' own topics are never pushed out: if the store is nearly
  /// full only as many bundled topics as fit are added, most important
  /// first, and the rest are tried again next time. Returns how many topics
  /// were added or topped up.
  Future<int> seed(String exam, {PracticeContentService? content}) async {
    final service = content ?? PracticeContentService.instance;
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool(_seededKey(exam)) ?? false) return 0;

    final topics = topicsFor(exam);
    if (topics.isEmpty) return 0;

    final existing = {for (final t in await service.getTopicSummaries()) t.topic};
    final others = existing.where((t) => !topics.contains(t)).length;
    final room = (PracticeContentService.maxTopics - others).clamp(0, topics.length);
    final chosen = topics.take(room).toList();

    final id = examKey(exam);
    for (final topic in chosen) {
      final questions = <Map<String, dynamic>>[];
      for (var i = 0; i < examBank.length; i++) {
        final q = examBank[i];
        if (q.topic != topic || !q.examIds.contains(id)) continue;
        questions.add({
          'id': idOf(i),
          'questionText': q.text,
          'options': q.options,
          'correctIndex': q.correct,
          'explanation': q.explanation,
        });
      }
      await service.addToQuestionPool(questions, topicId: 'exam_bank', topic: topic);
      // Bundled topics stay put when the store trims old topics.
      await service.setDownloaded(topic, true);
    }
    if (chosen.length == topics.length) await prefs.setBool(_seededKey(exam), true);
    return chosen.length;
  }

  static final _wordQuestion = RegExp(r'^What does "(.+)" mean\?$');

  /// Every word [exam] has a meaning question for, in bank order.
  static List<WordOfDay> wordsFor(String exam) {
    final id = examKey(exam);
    final words = <WordOfDay>[];
    for (var i = 0; i < examBank.length; i++) {
      final q = examBank[i];
      if (q.topic != 'Vocabulary' || !q.examIds.contains(id)) continue;
      final match = _wordQuestion.firstMatch(q.text);
      if (match == null) continue;
      final at = q.explanation.indexOf('Example: ');
      words.add(
        WordOfDay(
          word: match.group(1)!,
          meaning: q.options[q.correct],
          example: at < 0 ? '' : q.explanation.substring(at + 'Example: '.length),
          question: PracticeQuestion(
            id: idOf(i),
            questionText: q.text,
            options: q.options,
            correctIndex: q.correct,
            explanation: q.explanation,
            topic: q.topic,
          ),
        ),
      );
    }
    return words;
  }

  /// Today's word: the same all day, a new one each day, cycling through
  /// every word. Null when [exam] has no words.
  static WordOfDay? wordOfTheDay(String exam, DateTime day) {
    final words = wordsFor(exam);
    if (words.isEmpty) return null;
    final days = DateTime.utc(day.year, day.month, day.day).difference(DateTime.utc(2025)).inDays;
    return words[days % words.length];
  }
}
