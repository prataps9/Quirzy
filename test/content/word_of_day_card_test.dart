import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:quirzy/features/content/services/exam_bank_service.dart';
import 'package:quirzy/features/content/widgets/word_of_day_card.dart';
import 'package:quirzy/features/feed/models/feed_models.dart';
import 'package:quirzy/features/feed/providers/feed_providers.dart';
import 'package:quirzy/features/flashcards/services/saved_cards_service.dart';
import 'package:quirzy/shared/providers/providers.dart';
import 'package:quirzy/shared/theme/app_theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/side_effect_fakes.dart';

final _day = DateTime(2026, 11, 2);

void main() {
  setUp(() => GoogleFonts.config.allowRuntimeFetching = false);

  Future<ProviderContainer> pumpCard(WidgetTester tester, {String exam = 'sat', bool keepStorage = false}) async {
    if (!keepStorage) SharedPreferences.setMockInitialValues({'selected_exam': exam});
    tester.view
      ..physicalSize = const Size(1080, 2400)
      ..devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    final pool = [
      for (var i = 0; i < 6; i++)
        PracticeQuestion(
          id: 'q$i',
          questionText: 'Q$i?',
          options: const ['A', 'B'],
          correctIndex: 0,
          topic: 'Vocabulary',
        ),
    ];
    await tester.pumpWidget(
      ProviderScope(
        overrides: [feedQuestionPoolProvider.overrideWith((ref) async => pool), ...sideEffectOverrides()],
        child: MaterialApp(
          theme: AppTheme.dark,
          home: Scaffold(
            body: ListView(children: [WordOfDayCard(today: _day)]),
          ),
        ),
      ),
    );
    final container = ProviderScope.containerOf(tester.element(find.byType(ListView)));
    container.listen(feedControllerProvider, (_, _) {});
    for (var i = 0; i < 12; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    return container;
  }

  Future<void> close(WidgetTester tester) async {
    await tester.pump(const Duration(seconds: 6));
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 6));
  }

  testWidgets('shows today\'s word with its meaning and example', (tester) async {
    await pumpCard(tester);
    final word = ExamBankService.wordOfTheDay('sat', _day)!;
    expect(find.text('Word of the day'), findsOneWidget);
    expect(find.text(word.word), findsOneWidget);
    expect(find.text(word.meaning), findsOneWidget);
    expect(find.text(word.example), findsOneWidget);
    await close(tester);
  });

  testWidgets('saving makes a flashcard, and the card remembers it', (tester) async {
    await pumpCard(tester);
    final word = ExamBankService.wordOfTheDay('sat', _day)!;
    await tester.tap(find.text('Save'));
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(find.text('Saved'), findsOneWidget);
    expect(await SavedCardsService().isSaved(word.question), isTrue);
    await close(tester);

    // Coming back later: already saved.
    await pumpCard(tester, keepStorage: true);
    expect(find.text('Saved'), findsOneWidget);
    expect(find.text('Save'), findsNothing);
    await close(tester);
  });

  testWidgets('More words opens the Vocabulary lane in Practice', (tester) async {
    final container = await pumpCard(tester);
    container.read(tabIndexProvider.notifier).state = 3;
    await tester.tap(find.text('More words'));
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(container.read(feedControllerProvider).lane.label, 'Vocabulary');
    expect(container.read(tabIndexProvider), 0);
    await close(tester);
  });

  testWidgets('nothing is shown for an exam without English words', (tester) async {
    await pumpCard(tester, exam: 'jee');
    expect(find.text('Word of the day'), findsNothing);
    await close(tester);
  });
}
