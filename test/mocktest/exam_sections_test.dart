import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:quirzy/features/content/data/exam_bank.dart';
import 'package:quirzy/features/content/services/exam_bank_service.dart';
import 'package:quirzy/features/feed/models/feed_models.dart';
import 'package:quirzy/features/feed/providers/feed_providers.dart';
import 'package:quirzy/features/mocktest/models/exam_sections.dart';
import 'package:quirzy/features/mocktest/screens/mock_test_screen.dart';
import 'package:quirzy/shared/theme/app_theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/side_effect_fakes.dart';

List<PracticeQuestion> _bank(String exam) => [
  for (var i = 0; i < examBank.length; i++)
    if (examBank[i].examIds.contains(ExamBankService.examKey(exam)))
      PracticeQuestion(
        id: ExamBankService.idOf(i),
        questionText: examBank[i].text,
        options: examBank[i].options,
        correctIndex: examBank[i].correct,
        explanation: examBank[i].explanation,
        topic: examBank[i].topic,
      ),
];

Map<String, int> _counts(String exam) {
  final counts = <String, int>{};
  for (final q in ExamBankService.forExam(exam)) {
    counts[q.topic] = (counts[q.topic] ?? 0) + 1;
  }
  return counts;
}

void main() {
  group('ExamSections', () {
    test('real sections for each exam, and MBA shares CAT', () {
      expect([for (final s in ExamSections.forExam('sat')) s.name], ['Reading & Writing', 'Math']);
      expect([for (final s in ExamSections.forExam('gmat')) s.name], ['Quantitative', 'Verbal', 'Data Insights']);
      expect([for (final s in ExamSections.forExam('cat')) s.name], ['VARC', 'DILR', 'QA']);
      expect([for (final s in ExamSections.forExam('MBA')) s.name], ['VARC', 'DILR', 'QA']);
      expect(ExamSections.forExam('jee'), isEmpty);
      expect(ExamSections.forExam(null), isEmpty);
    });

    test('every section topic exists in the bundled questions for that exam', () {
      for (final exam in ['sat', 'gmat', 'cat', 'gre']) {
        final topics = ExamBankService.topicsFor(exam).toSet();
        for (final s in ExamSections.forExam(exam)) {
          for (final t in s.topics) {
            expect(topics, contains(t), reason: '$exam ${s.name}: $t');
          }
          expect(
            s.questionCount(_counts(exam)),
            greaterThanOrEqualTo(10),
            reason: '$exam ${s.name} has enough to test',
          );
        }
      }
    });

    test('only topics with questions count, and empty sections are hidden', () {
      const counts = {'Algebra': 5, 'Geometry': 3, 'Vocabulary': 9};
      final math = ExamSections.forExam('sat').last;
      expect(math.available(counts), ['Algebra', 'Geometry']);
      expect(math.questionCount(counts), 8);
      expect([for (final s in ExamSections.withQuestions('sat', counts)) s.name], ['Reading & Writing', 'Math']);
      expect(ExamSections.withQuestions('sat', const {'History': 4}), isEmpty);
    });
  });

  group('section chips on the mock test setup', () {
    setUp(() => GoogleFonts.config.allowRuntimeFetching = false);

    Future<void> pump(WidgetTester tester, String exam) async {
      SharedPreferences.setMockInitialValues({'selected_exam': exam});
      tester.view
        ..physicalSize = const Size(1080, 2400)
        ..devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [feedQuestionPoolProvider.overrideWith((ref) async => _bank(exam)), ...sideEffectOverrides()],
          child: MaterialApp(theme: AppTheme.dark, home: const MockTestScreen()),
        ),
      );
      for (var i = 0; i < 12; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
    }

    FilterChip topicChip(WidgetTester tester, String label) => tester.widget<FilterChip>(
      find.ancestor(of: find.textContaining('$label ('), matching: find.byType(FilterChip)).first,
    );

    testWidgets('picking a section selects exactly its topics; changing a topic clears it', (tester) async {
      await pump(tester, 'sat');
      expect(find.text('Exam sections'), findsOneWidget);

      await tester.ensureVisible(find.widgetWithText(ChoiceChip, 'Math'));
      await tester.tap(find.widgetWithText(ChoiceChip, 'Math'));
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('Algebra, Arithmetic, Geometry, Data Interpretation'), findsOneWidget);
      expect(topicChip(tester, 'Algebra').selected, isTrue);
      expect(topicChip(tester, 'Vocabulary').selected, isFalse);

      // Another section replaces it.
      await tester.tap(find.widgetWithText(ChoiceChip, 'Reading & Writing'));
      await tester.pump(const Duration(milliseconds: 300));
      expect(topicChip(tester, 'Vocabulary').selected, isTrue);
      expect(topicChip(tester, 'Algebra').selected, isFalse);

      // Tapping the chosen section again goes back to everything.
      await tester.tap(find.widgetWithText(ChoiceChip, 'Reading & Writing'));
      await tester.pump(const Duration(milliseconds: 300));
      expect(topicChip(tester, 'Algebra').selected, isTrue);

      // Picking a topic by hand leaves the section.
      await tester.tap(find.widgetWithText(ChoiceChip, 'Math'));
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.textContaining('Vocabulary ('));
      await tester.pump(const Duration(milliseconds: 300));
      final math = tester.widget<ChoiceChip>(find.widgetWithText(ChoiceChip, 'Math'));
      expect(math.selected, isFalse);
      expect(find.text('Algebra, Arithmetic, Geometry, Data Interpretation'), findsNothing);
    });

    testWidgets('a section test only uses that section\'s topics', (tester) async {
      await pump(tester, 'cat');
      await tester.ensureVisible(find.widgetWithText(ChoiceChip, 'DILR'));
      await tester.tap(find.widgetWithText(ChoiceChip, 'DILR'));
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.text('10 questions'));
      await tester.pump();
      await tester.drag(find.byType(ListView), const Offset(0, -400));
      await tester.pump();
      await tester.tap(find.text('Start test'));
      for (var i = 0; i < 6; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(find.text('1 of 10'), findsOneWidget);
      final stored = (await SharedPreferences.getInstance()).getString('mock_test_in_progress')!;
      final topics = RegExp(r'"topic":"([^"]+)"').allMatches(stored).map((m) => m.group(1)).toSet();
      expect(topics, {'Data Interpretation', 'Logical Reasoning'});
      await tester.pump(const Duration(seconds: 6));
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 6));
    });

    testWidgets('no section row for an exam without sections', (tester) async {
      await pump(tester, 'jee');
      expect(find.text('Exam sections'), findsNothing);
    });
  });
}
