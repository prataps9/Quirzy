import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:quirzy/features/feed/models/feed_models.dart';
import 'package:quirzy/features/feed/providers/feed_providers.dart';
import 'package:quirzy/features/feed/services/feed_stats_service.dart';
import 'package:quirzy/features/feed/services/mistakes_service.dart';
import 'package:quirzy/features/feed/services/streak_service.dart';
import 'package:quirzy/features/feed/services/xp_service.dart';
import 'package:quirzy/features/mocktest/models/mock_test.dart';
import 'package:quirzy/features/mocktest/screens/mock_test_screen.dart';
import 'package:quirzy/features/mocktest/services/mock_test_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/side_effect_fakes.dart';

PracticeQuestion _q(String topic, int n) => PracticeQuestion(
  id: '${topic}_$n',
  questionText: '$topic question $n',
  options: const ['A', 'B', 'C', 'D'],
  correctIndex: 0,
  explanation: 'A is right.',
  topic: topic,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  final pool = [
    for (var i = 0; i < 30; i++) _q('Physics', i),
    for (var i = 0; i < 30; i++) _q('History', i),
    for (var i = 0; i < 2; i++) _q('Art', i),
  ];

  group('MockTestService.build', () {
    test('spreads questions fairly across topics and never repeats one', () {
      final test = MockTestService(random: math.Random(3)).build(pool, length: 20);
      expect(test.total, 20);
      expect(test.questions.map((q) => q.engagementKey).toSet(), hasLength(20));
      int count(String t) => test.questions.where((q) => q.topicName == t).length;
      expect(count('Art'), 2);
      expect(count('Physics'), 9);
      expect(count('History'), 9);
      expect(test.limitSeconds, 20 * MockTestService.secondsPerQuestion);
    });

    test('only uses the chosen topics, and is shorter when they run out', () {
      final test = MockTestService(random: math.Random(1)).build(pool, topics: {'Art'}, length: 10);
      expect(test.total, 2);
      expect(test.questions.every((q) => q.topicName == 'Art'), isTrue);
      expect(test.limitSeconds, 2 * MockTestService.secondsPerQuestion);
    });
  });

  group('MockTestService.finish', () {
    test('scores per topic, counts as practice, and keeps a history', () async {
      final now = DateTime(2026, 10, 28, 10);
      final service = MockTestService(random: math.Random(2), clock: () => now);
      final test = service.build(pool.where((q) => q.topicName != 'Art').toList(), length: 10);
      // 6 right, 2 wrong, 2 left blank.
      final answers = <int, int>{};
      for (var i = 0; i < 8; i++) {
        answers[i] = i < 6 ? 0 : 1;
      }
      await service.saveInProgress(test);
      final result = await service.finish(test.copyWith(answers: answers, usedSeconds: 300));

      expect(result.correct, 6);
      expect(result.total, 10);
      expect(result.percent, 60);
      expect(result.usedSeconds, 300);
      expect(result.topics.fold(0, (s, t) => s + t.total), 10);

      final stats = await FeedStatsService().getTopicStats();
      expect(stats.values.fold(0, (s, t) => s + t.attempts), 8, reason: 'blanks are not attempts');
      expect((await MistakesService().all()), hasLength(2));
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getInt(StreakService.countKey(now)), 8);
      expect(await XpService().getXPTotal(), 6 * kFeedXpPerCorrect);

      expect(await service.loadInProgress(), isNull);
      final history = await service.history();
      expect(history.single.id, test.id);
    });

    test('a saved test comes back exactly as it was', () async {
      final service = MockTestService(random: math.Random(4));
      final test = service.build(pool, length: 10).copyWith(answers: {0: 1, 3: 0}, flagged: {3}, usedSeconds: 42, current: 3);
      await service.saveInProgress(test);
      final back = (await service.loadInProgress())!;
      expect(back.id, test.id);
      expect(back.answers, {0: 1, 3: 0});
      expect(back.flagged, {3});
      expect(back.usedSeconds, 42);
      expect(back.current, 3);
      expect(back.questions.map((q) => q.engagementKey), test.questions.map((q) => q.engagementKey));
    });

    test('the weakest topic is the lowest score', () {
      const result = MockResult(
        id: 'x',
        finishedMs: 0,
        correct: 5,
        total: 10,
        usedSeconds: 1,
        topics: [
          TopicScore(topic: 'A', correct: 4, total: 5),
          TopicScore(topic: 'B', correct: 1, total: 5),
        ],
      );
      expect(result.weakest!.topic, 'B');
    });
  });

  group('MockTestScreen', () {
    Future<void> pumpScreen(WidgetTester tester) async {
      GoogleFonts.config.allowRuntimeFetching = false;
      tester.view
        ..physicalSize = const Size(1080, 2400)
        ..devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [feedQuestionPoolProvider.overrideWith((ref) async => pool), ...sideEffectOverrides()],
          child: const MaterialApp(home: MockTestScreen()),
        ),
      );
      for (var i = 0; i < 5; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
    }

    Future<void> startTenQuestions(WidgetTester tester) async {
      await tester.tap(find.text('10 questions'));
      await tester.pump();
      await tester.ensureVisible(find.text('Start test'));
      await tester.tap(find.text('Start test'));
      for (var i = 0; i < 5; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
    }

    testWidgets('no right or wrong is shown during the test', (tester) async {
      await pumpScreen(tester);
      await startTenQuestions(tester);
      expect(find.text('Question 1 of 10'), findsOneWidget);
      expect(find.text('10:00'), findsOneWidget);

      await tester.tap(find.text('B').first);
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.byIcon(Icons.check_rounded), findsNothing);
      expect(find.byIcon(Icons.close_rounded), findsNothing);

      await tester.tap(find.text('Next'));
      for (var i = 0; i < 4; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(find.text('Question 2 of 10'), findsOneWidget);
    });

    testWidgets('running out of time submits the test', (tester) async {
      await pumpScreen(tester);
      await startTenQuestions(tester);
      await tester.tap(find.text('A').first);
      for (var s = 0; s < 601; s++) {
        await tester.pump(const Duration(seconds: 1));
      }
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.text('Your result'), findsOneWidget);
      expect(find.text('1 / 10'), findsOneWidget);
    });

    testWidgets('a test left part-way can be resumed', (tester) async {
      final service = MockTestService(random: math.Random(5));
      final test = service.build(pool, length: 10).copyWith(answers: {0: 0}, usedSeconds: 125, current: 2);
      SharedPreferences.setMockInitialValues({'mock_test_in_progress': jsonEncode(test.toJson())});
      await pumpScreen(tester);
      expect(find.text('You have a test in progress'), findsOneWidget);
      expect(find.textContaining('7:55 left'), findsOneWidget);

      await tester.tap(find.text('Resume'));
      for (var i = 0; i < 5; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(find.text('Question 3 of 10'), findsOneWidget);
    });
  });
}
