import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:quirzy/features/feed/models/feed_models.dart';
import 'package:quirzy/features/feed/providers/feed_providers.dart';
import 'package:quirzy/features/feed/screens/feed_screen.dart';
import 'package:quirzy/features/feed/services/explain_service.dart';
import 'package:quirzy/features/feed/services/question_notes_service.dart';
import 'package:quirzy/features/flashcards/services/saved_cards_service.dart';
import 'package:quirzy/shared/services/connectivity_service.dart';
import 'package:quirzy/shared/utils/user_messages.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/side_effect_fakes.dart';

PracticeQuestion _q(int n) => PracticeQuestion(
  id: 'Math_$n',
  questionText: 'What is the answer to Math question $n?',
  options: const ['Option A', 'Option B', 'Option C', 'Option D'],
  correctIndex: 0,
  explanation: 'Because A is correct for Math question $n.',
  topic: 'Math',
);

String _today() {
  final now = DateTime.now();
  return '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
}

Future<void> _openSolution(WidgetTester tester, ExplainService explain) async {
  tester.view
    ..physicalSize = const Size(1080, 1920)
    ..devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        feedQuestionPoolProvider.overrideWith((ref) async => [for (var i = 0; i < 10; i++) _q(i)]),
        explainServiceProvider.overrideWithValue(explain),
        ...sideEffectOverrides(),
        isOnlineProvider.overrideWith((ref) => Stream.value(true)),
      ],
      child: const MaterialApp(home: FeedScreen()),
    ),
  );
  for (var i = 0; i < 10; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
  await tester.fling(find.text('Option C'), const Offset(-300, 0), 1500);
  for (var i = 0; i < 8; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
  expect(find.text('Solution'), findsOneWidget);
}

Finder _chip(String label) => find.widgetWithText(ChoiceChip, label);

Future<void> _scrollTo(WidgetTester tester, Finder target) async {
  // The sheet's own list: text fields inside it have scrollables of their own.
  final sheetList = find.descendant(of: find.byType(DraggableScrollableSheet), matching: find.byType(Scrollable));
  await tester.scrollUntilVisible(target, 120, scrollable: sheetList.first);
  await tester.pump(const Duration(milliseconds: 100));
}

Future<void> _close(WidgetTester tester) async {
  await tester.pump(const Duration(seconds: 6));
  await tester.pumpWidget(const SizedBox());
  await tester.pump(const Duration(seconds: 6));
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    GoogleFonts.config.allowRuntimeFetching = false;
  });

  testWidgets('Ask AI shows the answer, and asking again is free', (tester) async {
    final calls = <String>[];
    final explain = ExplainService(call: (payload) async {
      calls.add(payload['mode'] as String);
      return 'Imagine A as the first step.';
    });
    await _openSolution(tester, explain);

    await _scrollTo(tester, _chip('Explain simpler'));
    await tester.tap(_chip('Explain simpler'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('Imagine A as the first step.'), findsOneWidget);
    expect(find.text('4 left today'), findsOneWidget);

    await tester.tap(_chip('Explain simpler'));
    await tester.pump(const Duration(milliseconds: 200));
    expect(calls, ['simpler']);
    expect(find.text('4 left today'), findsOneWidget);
    await _close(tester);
  });

  testWidgets('a failed Ask AI shows a calm message with Retry', (tester) async {
    var attempts = 0;
    final explain = ExplainService(call: (_) async {
      if (++attempts == 1) throw Exception('boom: stack trace');
      return 'Worked the second time.';
    });
    await _openSolution(tester, explain);

    await _scrollTo(tester, _chip('Give an example'));
    await tester.tap(_chip('Give an example'));
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('Something went wrong. Please try again.'), findsOneWidget);
    expect(find.textContaining('boom'), findsNothing);

    await tester.tap(find.text('Retry'));
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('Worked the second time.'), findsOneWidget);
    await _close(tester);
  });

  testWidgets('a missing function says Ask AI is unavailable', (tester) async {
    final explain = ExplainService(
      call: (_) async => throw const UserFacingException("Ask AI isn't available right now. Please try again later."),
    );
    await _openSolution(tester, explain);
    await _scrollTo(tester, _chip('Memory trick'));
    await tester.tap(_chip('Memory trick'));
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text("Ask AI isn't available right now. Please try again later."), findsOneWidget);
    await _close(tester);
  });

  testWidgets('a free user who has used today\'s allowance sees the limit sheet, not an AI call', (tester) async {
    SharedPreferences.setMockInitialValues({'daily_ai_explain_count': 5, 'last_ai_explain_date': _today()});
    var calls = 0;
    final explain = ExplainService(call: (_) async => 'x${++calls}');
    await _openSolution(tester, explain);

    await _scrollTo(tester, _chip('Explain simpler'));
    await tester.tap(_chip('Explain simpler'));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.textContaining("today's free AI answers"), findsOneWidget);
    expect(calls, 0);
    await _close(tester);
  });

  testWidgets('typing a follow-up question sends it', (tester) async {
    Map<String, dynamic>? sent;
    final explain = ExplainService(call: (payload) async {
      sent = payload;
      return 'Because B is a distractor.';
    });
    await _openSolution(tester, explain);

    await _scrollTo(tester, find.text('Ask AI'));
    await tester.enterText(find.widgetWithText(TextField, '').first, 'Why not B?');
    await tester.tap(find.byTooltip('Send'));
    await tester.pump(const Duration(milliseconds: 100));

    expect(sent?['mode'], 'followUp');
    expect(sent?['followUp'], 'Why not B?');
    expect(find.text('Because B is a distractor.'), findsOneWidget);
    await _close(tester);
  });

  testWidgets('a note is saved as you type and shown next time', (tester) async {
    await _openSolution(tester, ExplainService(call: (_) async => 'x'));
    await _scrollTo(tester, find.text('My note'));
    await tester.enterText(find.widgetWithText(TextField, 'Add a note to remember this').hitTestable(), 'Carry the one');
    await tester.pump(const Duration(seconds: 1));

    final shown = _q(0);
    final notes = QuestionNotesService();
    final saved = await tester.runAsync(() async {
      for (var i = 0; i < 10; i++) {
        final text = await notes.noteFor(_q(i));
        if (text.isNotEmpty) return text;
      }
      return '';
    });
    expect(saved, 'Carry the one', reason: 'note for ${shown.id}');
    await _close(tester);
  });

  testWidgets('Save as flashcard adds it to the saved set once', (tester) async {
    await _openSolution(tester, ExplainService(call: (_) async => 'x'));
    await _scrollTo(tester, find.text('Save as flashcard'));
    await tester.tap(find.text('Save as flashcard'));
    await tester.pump(const Duration(milliseconds: 200));

    expect(find.text('Saved to Cards'), findsOneWidget);
    final count = await tester.runAsync(() => SavedCardsService().count());
    expect(count, 1);
    await _close(tester);
  });
}
