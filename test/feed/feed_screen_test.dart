import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:quirzy/features/feed/models/feed_models.dart';
import 'package:quirzy/features/feed/providers/feed_providers.dart';
import 'package:quirzy/features/feed/screens/feed_screen.dart';
import 'package:quirzy/shared/services/connectivity_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

PracticeQuestion _q(String topic, int n, {bool long = false}) {
  final text = long
      ? 'In a long-form $topic question number $n, which of the following '
            'statements best explains the observed behaviour when every '
            'condition described in the passage above holds at once?'
      : 'What is the answer to $topic question $n?';
  String option(String letter) => long
      ? 'Option $letter: a deliberately long answer choice that wraps '
            'onto a second line on a small phone'
      : 'Option $letter';
  return PracticeQuestion(
    id: '${topic}_$n',
    questionText: text,
    options: [option('A'), option('B'), option('C'), option('D')],
    correctIndex: 0,
    explanation: 'Because A is correct for $topic question $n.',
    topic: topic,
  );
}

Future<void> _pumpFeed(WidgetTester tester, List<PracticeQuestion> pool) async {
  tester.view
    ..physicalSize = const Size(1080, 1920)
    ..devicePixelRatio = 3;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        feedQuestionPoolProvider.overrideWith((ref) async => pool),
        isOnlineProvider.overrideWith((ref) => Stream.value(true)),
      ],
      child: const MaterialApp(home: FeedScreen()),
    ),
  );
  for (var i = 0; i < 5; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

/// Lets pending timers (peek, heart, snackbars, debounced saves) finish
/// and disposes the tree so nothing is left running after the test.
Future<void> _tearDown(WidgetTester tester) async {
  await tester.pump(const Duration(seconds: 6));
  await tester.pumpWidget(const SizedBox());
  await tester.pump(const Duration(seconds: 6));
}

Future<void> _swipeUp(WidgetTester tester) async {
  await tester.fling(find.byType(PageView), const Offset(0, -500), 1500);
  for (var i = 0; i < 10; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    GoogleFonts.config.allowRuntimeFetching = false;
  });

  testWidgets('For You renders on a 360x640 phone with long content', (tester) async {
    final pool = [
      for (var i = 0; i < 10; i++) _q('Physics', i, long: true),
      for (var i = 0; i < 10; i++) _q('History', i, long: true),
    ];
    await _pumpFeed(tester, pool);

    expect(find.text('For You'), findsOneWidget);
    expect(find.byIcon(Icons.favorite_border_rounded), findsWidgets);
    expect(tester.takeException(), isNull);

    // Long content scrolls inside the card; answer wrong and the
    // explanation peek and reason chips must still lay out cleanly.
    final optionB = find.descendant(
      of: find.byKey(const ValueKey('feed_card_0')),
      matching: find.textContaining('Option B'),
    );
    await tester.ensureVisible(optionB);
    await tester.pump(const Duration(milliseconds: 100));
    await tester.tap(optionB);
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Silly mistake'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await _tearDown(tester);
  });

  testWidgets('double-tap likes the card and the heart fills', (tester) async {
    await _pumpFeed(tester, [for (var i = 0; i < 20; i++) _q('Math', i)]);

    final question = find.textContaining('What is the answer').first;
    await tester.tap(question);
    await tester.pump(const Duration(milliseconds: 50));
    await tester.tap(question);
    await tester.pump(const Duration(milliseconds: 400));

    final feed = ProviderScope.containerOf(
      tester.element(find.byType(FeedScreen)),
    ).read(feedControllerProvider);
    expect(feed.cards.first.liked, isTrue);
    expect(find.byIcon(Icons.favorite_rounded), findsWidgets);

    await _tearDown(tester);
  });

  testWidgets('For You keeps going past the first batch', (tester) async {
    await _pumpFeed(tester, [
      for (var i = 0; i < 15; i++) _q('Bio', i),
      for (var i = 0; i < 15; i++) _q('Chem', i),
    ]);
    final container = ProviderScope.containerOf(
      tester.element(find.byType(FeedScreen)),
    );
    final firstBatch = container.read(feedControllerProvider).cards.length;

    for (var i = 0; i < 9; i++) {
      await _swipeUp(tester);
    }

    final state = container.read(feedControllerProvider);
    expect(state.cards.length, greaterThan(firstBatch));
    expect(state.hasMore, isTrue);
    expect(find.text("You've practiced all 30"), findsNothing);
    expect(tester.takeException(), isNull);

    await _tearDown(tester);
  });

  testWidgets('a tiny pool plays once and then shows the end page', (tester) async {
    await _pumpFeed(tester, [for (var i = 0; i < 3; i++) _q('Art', i)]);

    for (var i = 0; i < 3; i++) {
      await _swipeUp(tester);
    }

    expect(find.text("You've practiced all 3"), findsOneWidget);
    expect(find.text('Go again'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await _tearDown(tester);
  });
}
