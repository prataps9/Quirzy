import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:quirzy/features/feed/models/feed_models.dart';
import 'package:quirzy/features/feed/providers/feed_providers.dart';
import 'package:quirzy/features/feed/services/feed_ranker.dart';
import 'package:quirzy/features/feed/services/mistakes_service.dart';
import 'package:quirzy/features/progress/screens/mistakes_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/side_effect_fakes.dart';

PracticeQuestion _q(String topic, int n) => PracticeQuestion(
  id: '${topic}_$n',
  questionText: '$topic question $n',
  options: const ['A', 'B', 'C', 'D'],
  correctIndex: 0,
  explanation: 'A is right for $topic $n.',
  topic: topic,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('MistakesService', () {
    test('a wrong answer is kept with what was picked', () async {
      final service = MistakesService();
      await service.recordAnswer(_q('Art', 1), correct: false, pick: 2);
      final entry = (await service.all()).single;
      expect(entry.timesWrong, 1);
      expect(entry.pickedText, 'C');
      expect(entry.fixed, isFalse);
    });

    test('a right answer to a question never missed adds nothing', () async {
      final service = MistakesService();
      await service.recordAnswer(_q('Art', 1), correct: true);
      expect(await service.all(), isEmpty);
    });

    test('two right answers in a row fix it; a new miss reopens it', () async {
      final service = MistakesService();
      final q = _q('Art', 1);
      await service.recordAnswer(q, correct: false, pick: 1);
      await service.recordAnswer(q, correct: true);
      expect((await service.all()).single.fixed, isFalse);
      await service.recordAnswer(q, correct: true);
      expect((await service.all()).single.fixed, isTrue);
      expect(await service.toRetry(), isEmpty);

      await service.recordAnswer(q, correct: false, pick: 3);
      final entry = (await service.all()).single;
      expect(entry.fixed, isFalse);
      expect(entry.timesWrong, 2);
      expect(entry.pickedText, 'D');
    });

    test('the reason is kept per question and cleared by a new miss', () async {
      final service = MistakesService();
      final q = _q('Art', 1);
      await service.recordAnswer(q, correct: false);
      await service.setReason(q, 'Misread it');
      expect((await service.all()).single.reason, 'Misread it');
      await service.recordAnswer(q, correct: false);
      expect((await service.all()).single.reason, isNull);
    });

    test('the insight names the most common slip and topic', () async {
      final service = MistakesService();
      for (var i = 0; i < 3; i++) {
        await service.recordAnswer(_q('Art', i), correct: false);
        await service.setReason(_q('Art', i), i < 2 ? 'Misread it' : 'Silly mistake');
      }
      await service.recordAnswer(_q('Math', 1), correct: false);

      final insight = await service.insight();
      expect(insight.open, 4);
      expect(insight.topReason, 'Misread it');
      expect(insight.topReasonPercent, 67);
      expect(insight.topTopic, 'Art');
    });

    test('keeps at most the cap, dropping fixed and old ones first', () async {
      final service = MistakesService();
      final fixedQ = _q('Old', 0);
      await service.recordAnswer(fixedQ, correct: false, now: DateTime(2026, 1, 1));
      await service.recordAnswer(fixedQ, correct: true);
      await service.recordAnswer(fixedQ, correct: true);
      for (var i = 0; i < MistakesService.maxEntries; i++) {
        await service.recordAnswer(_q('New', i), correct: false, now: DateTime(2026, 2, 1).add(Duration(minutes: i)));
      }
      final all = await service.all();
      expect(all, hasLength(MistakesService.maxEntries));
      expect(all.any((e) => e.key == fixedQ.engagementKey), isFalse);
    });
  });

  group('in the feed', () {
    final pool = [for (var i = 0; i < 20; i++) _q('Physics', i), for (var i = 0; i < 20; i++) _q('History', i)];

    Future<ProviderContainer> loaded() async {
      final container = ProviderContainer(
        overrides: [
          feedQuestionPoolProvider.overrideWith((ref) async => pool),
          ...sideEffectOverrides(),
          feedRankerProvider.overrideWithValue(FeedRanker(random: math.Random(1))),
        ],
      );
      addTearDown(container.dispose);
      container.read(feedControllerProvider);
      for (var i = 0; i < 100 && container.read(feedControllerProvider).loading; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
      return container;
    }

    test('a wrong answer and its reason land in the notebook, and a Mistakes lane appears', () async {
      final container = await loaded();
      final controller = container.read(feedControllerProvider.notifier);
      final question = container.read(feedControllerProvider).cards.first.question;
      controller.activate(0);
      await controller.selectOption(0, 2);
      await controller.recordWrongReason(0, 'Ran out of time');

      final entry = (await MistakesService().all()).single;
      expect(entry.key, question.engagementKey);
      expect(entry.pickedText, 'C');
      expect(entry.reason, 'Ran out of time');

      final lanes = await container.read(feedLanesProvider.future);
      final mistakes = lanes.firstWhere((l) => l.type == FeedLaneType.mistakes);
      expect(mistakes.count, 1);

      await controller.switchLane(FeedLane.mistakes);
      expect(container.read(feedControllerProvider).cards.single.question.engagementKey, question.engagementKey);
    });
  });

  group('MistakesScreen', () {
    Future<void> pumpScreen(WidgetTester tester) async {
      GoogleFonts.config.allowRuntimeFetching = false;
      tester.view
        ..physicalSize = const Size(1080, 2400)
        ..devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      final service = MistakesService();
      await tester.runAsync(() async {
        await service.recordAnswer(_q('Art', 1), correct: false, pick: 1);
        await service.setReason(_q('Art', 1), 'Misread it');
        await service.recordAnswer(_q('Math', 1), correct: false, pick: 2);
        await service.recordAnswer(_q('Math', 2), correct: false);
        await service.recordAnswer(_q('Math', 2), correct: true);
        await service.recordAnswer(_q('Math', 2), correct: true);
      });
      await tester.pumpWidget(
        ProviderScope(
          overrides: [feedQuestionPoolProvider.overrideWith((ref) async => const []), ...sideEffectOverrides()],
          child: const MaterialApp(home: MistakesScreen()),
        ),
      );
      for (var i = 0; i < 5; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
    }

    testWidgets('shows what you picked, the right answer and your reason', (tester) async {
      await pumpScreen(tester);
      expect(find.text('Art question 1'), findsOneWidget);
      expect(find.text('You picked: B'), findsOneWidget);
      expect(find.text('Misread it'), findsOneWidget);
      expect(find.text('Retry the 2 to fix'), findsOneWidget);
      // A fixed one is hidden from "To fix" ...
      expect(find.text('Math question 2'), findsNothing);
      // ... and shown, marked fixed, under All.
      await tester.tap(find.text('All (3)'));
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.text('Math question 2'), findsOneWidget);
      expect(find.text('Fixed'), findsOneWidget);
      // Topic filter.
      await tester.ensureVisible(find.widgetWithText(ChoiceChip, 'Art'));
      await tester.pump(const Duration(milliseconds: 100));
      await tester.tap(find.widgetWithText(ChoiceChip, 'Art'));
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.text('Math question 1'), findsNothing);
      expect(find.text('Art question 1'), findsOneWidget);
    });
  });
}
