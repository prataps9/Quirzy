import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quirzy/features/content/data/exam_bank.dart';
import 'package:quirzy/features/content/services/exam_bank_service.dart';
import 'package:quirzy/features/feed/models/feed_models.dart';
import 'package:quirzy/features/feed/providers/feed_providers.dart';
import 'package:quirzy/features/feed/services/practice_content_service.dart';
import 'package:quirzy/features/feed/services/related_questions.dart';
import 'package:quirzy/shared/providers/exam_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/side_effect_fakes.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('the bundled questions', () {
    test('every question can be shown and has one clear answer', () {
      final texts = <String>{};
      for (final q in examBank) {
        final label = q.text.split('\n').first;
        expect(q.text.trim(), isNotEmpty, reason: label);
        expect(q.options.length, inInclusiveRange(4, 5), reason: label);
        expect(q.options.toSet().length, q.options.length, reason: 'no repeated option: $label');
        expect(q.options.every((o) => o.trim().isNotEmpty), isTrue, reason: label);
        expect(q.correct, inInclusiveRange(0, q.options.length - 1), reason: label);
        expect(q.explanation.trim().length, greaterThan(15), reason: 'explains the answer: $label');
        expect(texts.add(q.text), isTrue, reason: 'duplicate question: $label');
        expect(q.examIds, isNotEmpty);
      }
    });

    test('ids are unique and stay the same between runs', () {
      final ids = [for (var i = 0; i < examBank.length; i++) ExamBankService.idOf(i)];
      expect(ids.toSet(), hasLength(examBank.length));
      expect(ids.every((id) => id.startsWith('bank_')), isTrue);
      expect(ExamBankService.idOf(0), 'bank_vocabulary_1');
    });

    test('Data Sufficiency questions use the five standard answers', () {
      final ds = examBank.where((q) => q.topic == 'Data Sufficiency').toList();
      expect(ds, isNotEmpty);
      for (final q in ds) {
        expect(q.options, hasLength(5));
        expect(q.options.first, startsWith('Only (1)'));
        expect(q.options.last, startsWith('Not sufficient'));
      }
    });

    test('each exam has aptitude and English words', () {
      for (final exam in ['sat', 'gmat', 'cat']) {
        final topics = ExamBankService.topicsFor(exam);
        expect(
          topics,
          containsAll(['Vocabulary', 'Grammar & Usage', 'Reading Comprehension', 'Algebra', 'Arithmetic']),
          reason: exam,
        );
        expect(ExamBankService.forExam(exam).length, greaterThan(60), reason: exam);
      }
      expect(ExamBankService.topicsFor('gmat'), containsAll(['Data Sufficiency', 'Critical Reasoning']));
      expect(ExamBankService.topicsFor('cat'), contains('Logical Reasoning'));
      expect(ExamBankService.topicsFor('sat'), isNot(contains('Data Sufficiency')));
    });

    test('more than thirty English words, each asking for a meaning or a fitting word', () {
      final vocab = examBank.where((q) => q.topic == 'Vocabulary').toList();
      expect(vocab.length, greaterThanOrEqualTo(30));
      expect(vocab.every((q) => q.text.startsWith('What does') || q.text.startsWith('Choose the word')), isTrue);
    });

    test('MBA practises the CAT set, and unrelated exams get none', () {
      expect(ExamBankService.forExam('mba').length, ExamBankService.forExam('cat').length);
      expect(ExamBankService.forExam('jee'), isEmpty);
      expect(ExamBankService.topicsFor('ielts'), containsAll(['Vocabulary', 'Grammar & Usage']));
    });
  });

  group('Word of the day', () {
    test('every word has a meaning and an example', () {
      final words = ExamBankService.wordsFor('sat');
      expect(words.length, greaterThanOrEqualTo(40));
      for (final w in words) {
        expect(w.word, isNotEmpty);
        expect(w.meaning, isNotEmpty);
        expect(w.example.length, greaterThan(10), reason: w.word);
        expect(w.question.options[w.question.correctIndex], w.meaning);
      }
      final ephemeral = words.firstWhere((w) => w.word == 'ephemeral');
      expect(ephemeral.meaning, 'Lasting a very short time');
      expect(ephemeral.example, startsWith('The ephemeral beauty'));
      expect(ephemeral.question.id, 'bank_vocabulary_1', reason: 'old words keep their ids');
    });

    test('is the same all day, changes each day and cycles through every word', () {
      final morning = ExamBankService.wordOfTheDay('sat', DateTime(2026, 11, 2, 6));
      final night = ExamBankService.wordOfTheDay('sat', DateTime(2026, 11, 2, 23, 59));
      expect(morning!.word, night!.word);
      final next = ExamBankService.wordOfTheDay('sat', DateTime(2026, 11, 3));
      expect(next!.word, isNot(morning.word));

      final count = ExamBankService.wordsFor('sat').length;
      final seen = {
        for (var d = 0; d < count; d++) ExamBankService.wordOfTheDay('sat', DateTime(2026, 11, 2 + d))!.word,
      };
      expect(seen, hasLength(count));
      expect(ExamBankService.wordOfTheDay('sat', DateTime(2026, 11, 2 + count))!.word, morning.word);
    });

    test('exams without English words get none', () {
      expect(ExamBankService.wordOfTheDay('jee', DateTime(2026, 11, 2)), isNull);
      expect(ExamBankService.wordOfTheDay('mba', DateTime(2026, 11, 2)), isNotNull);
    });
  });

  group('ExamBankService.seed', () {
    Future<List<PracticeQuestion>> pool() => PracticeContentService.instance.getQuestionPool();

    test('adds the exam\'s topics once, protected from trimming, and is safe to repeat', () async {
      final added = await ExamBankService().seed('sat');
      expect(added, ExamBankService.topicsFor('sat').length);
      final questions = await pool();
      expect(questions, hasLength(ExamBankService.forExam('sat').length));
      expect({for (final q in questions) q.topicName}, ExamBankService.topicsFor('sat').toSet());
      final summaries = await PracticeContentService.instance.getTopicSummaries();
      expect(summaries.every((s) => s.downloaded), isTrue);

      final aSatWord = questions.firstWhere((q) => q.questionText.contains('ephemeral'));
      expect(aSatWord.options[aSatWord.correctIndex], 'Lasting a very short time');

      expect(await ExamBankService().seed('sat'), 0, reason: 'already added');
      expect(await pool(), hasLength(questions.length), reason: 'no duplicates');
    });

    test('switching exams adds what is new and shares the English words', () async {
      await ExamBankService().seed('sat');
      final before = (await pool()).length;
      await ExamBankService().seed('gmat');
      final after = await pool();
      final gmatOnly = ExamBankService.forExam('gmat').where((q) => !q.examIds.contains('sat')).length;
      expect(after.length, before + gmatOnly, reason: 'questions in both exams are added once');
      expect(after.where((q) => q.topicName == 'Data Sufficiency'), isNotEmpty);
    });

    test('never pushes out the learner\'s own topics when the store is nearly full', () async {
      final service = PracticeContentService.instance;
      for (var i = 0; i < PracticeContentService.maxTopics - 1; i++) {
        await service.addToQuestionPool([
          {
            'id': 'mine_$i',
            'questionText': 'Mine $i?',
            'options': ['A', 'B'],
            'correctIndex': 0,
          },
        ], topic: 'My topic $i');
      }
      final added = await ExamBankService().seed('cat');
      expect(added, 1, reason: 'only one slot was free');
      final topics = {for (final s in await service.getTopicSummaries()) s.topic};
      expect(topics, hasLength(PracticeContentService.maxTopics));
      expect(topics.where((t) => t.startsWith('My topic')), hasLength(PracticeContentService.maxTopics - 1));
      expect(topics, contains('Vocabulary'), reason: 'the most important topic goes first');
    });

    test('an exam with no bundled questions changes nothing', () async {
      expect(await ExamBankService().seed('jee'), 0);
      expect(await pool(), isEmpty);
    });

    test('questions are ranked sensibly against each other', () async {
      await ExamBankService().seed('gmat');
      final all = await pool();
      final ds = all.firstWhere((q) => q.topicName == 'Data Sufficiency');
      final related = RelatedQuestions.rank(ds, all, limit: 5);
      expect(
        related.every((r) => r.question.topicName == 'Data Sufficiency'),
        isTrue,
        reason: 'shared wording and topic keep Data Sufficiency together',
      );
    });
  });

  test('choosing an exam adds its questions to the feed', () async {
    final container = ProviderContainer(overrides: sideEffectOverrides());
    addTearDown(container.dispose);
    container.read(feedControllerProvider);
    for (var i = 0; i < 100 && container.read(feedControllerProvider).loading; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    expect(await container.read(feedQuestionPoolProvider.future), isEmpty);

    await container.read(examProvider.notifier).setExam('sat');
    expect(examDisplayName('sat'), 'SAT');
    final pool = await container.read(feedQuestionPoolProvider.future);
    expect(pool, hasLength(ExamBankService.forExam('sat').length));
    for (var i = 0; i < 100 && container.read(feedControllerProvider).loading; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    expect(container.read(feedControllerProvider).cards, isNotEmpty, reason: 'the empty feed starts showing them');
  });
}
