import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:quirzy/features/feed/models/feed_models.dart';
import 'package:quirzy/features/feed/providers/feed_providers.dart';
import 'package:quirzy/features/feed/screens/feed_screen.dart';
import 'package:quirzy/features/feed/services/feed_mixer.dart';
import 'package:quirzy/shared/providers/providers.dart';
import 'package:quirzy/shared/services/connectivity_service.dart';
import 'package:quirzy/shared/services/settings_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/side_effect_fakes.dart';

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

Future<void> _pumpFeed(
  WidgetTester tester,
  List<PracticeQuestion> pool, {
  FakeFeedAudio? audio,
  FeedMixer? mixer,
}) async {
  tester.view
    ..physicalSize = const Size(1080, 1920)
    ..devicePixelRatio = 3;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        feedQuestionPoolProvider.overrideWith((ref) async => pool),
        ...sideEffectOverrides(audio: audio, mixer: mixer),
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

double _page(WidgetTester tester) => tester.widget<PageView>(find.byType(PageView)).controller!.page!;

Future<void> _answer(WidgetTester tester, String option) async {
  final target = find.descendant(
    of: find.byKey(const ValueKey('feed_card_0')),
    matching: find.text(option),
  );
  await tester.tap(target);
  await tester.pump(const Duration(milliseconds: 50));
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    GoogleFonts.config.allowRuntimeFetching = false;
    // SettingsService is a process-wide singleton: reset feed preferences.
    SettingsService()
      ..setAutoAdvance(true)
      ..setReadAloud(false)
      ..setSoundEffects(false);
  });

  group('auto-scroll', () {
    final pool = [for (var i = 0; i < 20; i++) _q('Math', i)];

    testWidgets('a correct answer moves to the next card on its own', (tester) async {
      await _pumpFeed(tester, pool);
      await _answer(tester, 'Option A');
      expect(_page(tester), 0);
      await tester.pump(const Duration(milliseconds: 1300));
      await tester.pump(const Duration(milliseconds: 500));
      expect(_page(tester), closeTo(1, 0.01));
      await _tearDown(tester);
    });

    testWidgets('a wrong answer stays put so the explanation can be read', (tester) async {
      await _pumpFeed(tester, pool);
      await _answer(tester, 'Option B');
      await tester.pump(const Duration(seconds: 3));
      expect(_page(tester), 0);
      await _tearDown(tester);
    });

    testWidgets('does nothing when turned off in Profile', (tester) async {
      SettingsService().setAutoAdvance(false);
      await _pumpFeed(tester, pool);
      await _answer(tester, 'Option A');
      await tester.pump(const Duration(seconds: 3));
      expect(_page(tester), 0);
      await _tearDown(tester);
    });

    testWidgets('refreshing right after a correct answer never skips the new first card', (tester) async {
      await _pumpFeed(tester, pool);
      await _answer(tester, 'Option A');
      await tester.tap(find.text('For You'));
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(seconds: 3));
      expect(_page(tester), 0);
      await _tearDown(tester);
    });

    testWidgets('any touch after answering cancels the move', (tester) async {
      await _pumpFeed(tester, pool);
      await _answer(tester, 'Option A');
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tapAt(const Offset(180, 40));
      await tester.pump(const Duration(seconds: 3));
      expect(_page(tester), 0);
      await _tearDown(tester);
    });
  });

  testWidgets('True/False cards answer with one tap and move on when right', (tester) async {
    await _pumpFeed(
      tester,
      [for (var i = 0; i < 20; i++) _q('Math', i)],
      mixer: FeedMixer(random: math.Random(4), trueFalseShare: 1),
    );
    final card = find.byKey(const ValueKey('feed_card_0'));
    expect(find.descendant(of: card, matching: find.text('Is this the answer?')), findsOneWidget);

    // The shown option is right only if it is "Option A".
    final saysTrue = find.descendant(of: card, matching: find.text('Option A')).evaluate().isNotEmpty;
    await tester.tap(find.descendant(of: card, matching: find.text(saysTrue ? 'True' : 'False')));
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.descendant(of: card, matching: find.text('+5 XP')), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.pump(const Duration(milliseconds: 1300));
    await tester.pump(const Duration(milliseconds: 500));
    expect(_page(tester), closeTo(1, 0.01));
    await _tearDown(tester);
  });

  group('sound', () {
    final pool = [for (var i = 0; i < 20; i++) _q('Math', i)];

    testWidgets('reads the card aloud, and stops when you swipe on', (tester) async {
      SettingsService()
        ..setReadAloud(true)
        ..setAutoAdvance(false);
      final audio = FakeFeedAudio();
      await _pumpFeed(tester, pool, audio: audio);
      await tester.pump(const Duration(milliseconds: 100));
      expect(audio.spoken, isNotEmpty);
      expect(audio.spoken.first, contains('What is the answer'));
      expect(audio.spoken.first, contains('A. Option A.'));

      final stopsBefore = audio.stops;
      await _swipeUp(tester);
      expect(audio.stops, greaterThan(stopsBefore));
      expect(audio.spoken.length, greaterThanOrEqualTo(2));
      await _tearDown(tester);
    });

    testWidgets('reads each card once, and goes quiet while another tab is open', (tester) async {
      SettingsService()
        ..setReadAloud(true)
        ..setAutoAdvance(false);
      final audio = FakeFeedAudio();
      await _pumpFeed(tester, pool, audio: audio);
      await tester.pump(const Duration(milliseconds: 100));
      expect(audio.spoken, hasLength(1));

      // A small nudge that settles back on the same card doesn't restart it.
      await tester.drag(find.byType(PageView), const Offset(0, -40));
      for (var i = 0; i < 20; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }
      expect(_page(tester), closeTo(0, 0.01));
      expect(audio.spoken, hasLength(1));

      final container = ProviderScope.containerOf(tester.element(find.byType(FeedScreen)));
      final stopsBefore = audio.stops;
      container.read(tabIndexProvider.notifier).state = 1;
      await tester.pump(const Duration(milliseconds: 100));
      expect(audio.stops, greaterThan(stopsBefore));

      container.read(tabIndexProvider.notifier).state = 0;
      await tester.pump(const Duration(milliseconds: 100));
      expect(audio.spoken, hasLength(2), reason: 'coming back reads the card again');
      await _tearDown(tester);
    });

    testWidgets('plays the right or wrong sound only when turned on', (tester) async {
      final audio = FakeFeedAudio();
      await _pumpFeed(tester, pool, audio: audio);
      await _answer(tester, 'Option B');
      expect(audio.sounds, isEmpty);
      expect(audio.spoken, isEmpty, reason: 'read-aloud is off by default');
      await _tearDown(tester);

      SettingsService().setSoundEffects(true);
      final audio2 = FakeFeedAudio();
      await _pumpFeed(tester, pool, audio: audio2);
      await _answer(tester, 'Option B');
      expect(audio2.sounds, [false]);
      await _tearDown(tester);
    });
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
