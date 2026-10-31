import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:quirzy/features/feed/models/daily_challenge.dart';
import 'package:quirzy/features/feed/models/feed_models.dart';
import 'package:quirzy/features/feed/models/topic_mastery.dart';
import 'package:quirzy/features/feed/providers/feed_providers.dart';
import 'package:quirzy/features/feed/services/activity_log.dart';
import 'package:quirzy/features/feed/services/feed_stats_service.dart';
import 'package:quirzy/features/feed/services/mistakes_service.dart';
import 'package:quirzy/features/plan/models/study_plan.dart';
import 'package:quirzy/features/plan/providers/study_plan_providers.dart';
import 'package:quirzy/features/plan/services/study_plan_service.dart';
import 'package:quirzy/features/plan/widgets/today_plan_card.dart';
import 'package:quirzy/features/progress/models/badge.dart';
import 'package:quirzy/features/progress/services/badge_service.dart';
import 'package:quirzy/shared/providers/providers.dart';
import 'package:quirzy/shared/theme/app_theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/side_effect_fakes.dart';

PracticeQuestion _q(String topic, int n) => PracticeQuestion(
  id: '${topic}_$n',
  questionText: '$topic question $n',
  options: const ['A', 'B', 'C', 'D'],
  correctIndex: 0,
  topic: topic,
);

TopicMastery _m(String topic, int attempts, double accuracy) =>
    TopicMastery(topic: topic, attempts: attempts, accuracy: accuracy);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('ActivityLog', () {
    test('keeps answers per topic and per hour for each day', () async {
      final log = ActivityLog();
      final morning = DateTime(2026, 3, 10, 8, 15);
      await log.record('Polity', true, at: morning);
      await log.record('Polity', false, at: morning);
      await log.record('History', true, at: DateTime(2026, 3, 10, 21, 5));
      await log.record('History', true, at: DateTime(2026, 3, 11, 9));

      final day = await log.day(DateTime(2026, 3, 10));
      expect(day.answered, 3);
      expect(day.correct, 2);
      expect(day.topics['Polity'], (2, 1));
      expect(day.answeredIn('History'), 1);
      expect(day.atHour(8), 2);
      expect(day.atHour(21), 1);
      expect(day.atHour(12), 0);

      final range = await log.range(DateTime(2026, 3, 9), DateTime(2026, 3, 11));
      expect([for (final d in range) d.answered], [0, 3, 1]);
      expect(range.first.day, DateTime(2026, 3, 9));
    });

    test('drops days older than ten weeks when a new day starts', () async {
      final log = ActivityLog();
      final start = DateTime(2026, 1, 1, 10);
      await log.record('Art', true, at: start);
      await log.record('Art', true, at: DateTime(2026, 2, 1, 10));
      // 70 days after the first day: still kept.
      await log.record('Art', true, at: DateTime(2026, 3, 12, 10));
      expect((await log.day(start)).answered, 1);
      // 71 days after: the first day goes, the second stays.
      await log.record('Art', true, at: DateTime(2026, 3, 13, 10));
      expect((await log.day(start)).answered, 0);
      expect((await log.day(DateTime(2026, 2, 1))).answered, 1);
    });

    test('every recorded attempt is logged, wherever it came from', () async {
      final now = DateTime(2026, 5, 4, 14);
      await FeedStatsService().recordAttempt('Economy', false, now: now);
      await FeedStatsService().recordAttempt(null, true, now: now);
      final day = await ActivityLog().day(now);
      expect(day.topics, {'Economy': (1, 0), 'General': (1, 1)});
      expect(day.atHour(14), 2);
    });

    test('a damaged record reads as an empty day', () async {
      SharedPreferences.setMockInitialValues({ActivityLog.keyFor(DateTime(2026, 1, 2)): 'not json'});
      expect((await ActivityLog().day(DateTime(2026, 1, 2))).answered, 0);
    });
  });

  group('Practice counters', () {
    test('mistakes answered again count towards today', () async {
      final mistakes = MistakesService();
      await mistakes.recordAnswer(_q('Art', 1), correct: false);
      expect(await mistakes.reviewedOn(), 0, reason: 'a new mistake is not a review');
      await mistakes.recordAnswer(_q('Art', 1), correct: true);
      await mistakes.recordAnswer(_q('Art', 1), correct: false);
      expect(await mistakes.reviewedOn(), 2);
      // Questions that were never mistakes do not count.
      await mistakes.recordAnswer(_q('Art', 2), correct: true);
      expect(await mistakes.reviewedOn(), 2);
    });
  });

  group('StudyPlanService.focusTopic', () {
    test('picks a weak topic, then the lowest accuracy, then the least practised new one', () {
      final pool = {'A': 10, 'B': 10, 'C': 10, 'D': 10};
      expect(
        StudyPlanService.focusTopic(pool, {
          'A': _m('A', 30, 50), // weak
          'B': _m('B', 30, 60), // learning
          'C': _m('C', 30, 95), // mastered
        }),
        'A',
      );
      expect(
        StudyPlanService.focusTopic(pool, {
          'A': _m('A', 30, 65),
          'B': _m('B', 30, 60),
          'C': _m('C', 30, 95),
          'D': _m('D', 30, 90),
        }),
        'B',
      );
      expect(
        StudyPlanService.focusTopic(pool, {
          'A': _m('A', 30, 80),
          'B': _m('B', 3, 0),
          'C': _m('C', 30, 95),
          'D': _m('D', 1, 0),
        }),
        'D',
      );
    });

    test('only topics with questions in the pool', () {
      expect(StudyPlanService.focusTopic({'A': 0}, {'A': _m('A', 30, 10)}), isNull);
      expect(StudyPlanService.focusTopic({'A': 0, 'B': 4}, {'A': _m('A', 30, 10)}), 'B');
    });
  });

  group('StudyPlanService.build', () {
    final now = DateTime(2026, 6, 1, 9);

    test('lists only what there is to do, with today\'s progress', () {
      final plan = StudyPlanService.build(
        StudyPlanInputs(
          now: now,
          poolTopics: const {'Polity': 40, 'Art': 8},
          mastery: {'Polity': _m('Polity', 20, 40)},
          daily: const DailyChallenge(date: 'd', keys: ['a', 'b', 'c', 'd', 'e'], results: {'a': true, 'b': false}),
          mistakesOpen: 14,
          mistakesReviewedToday: 3,
          revisionDue: 2,
          revisionReviewedToday: 1,
          todayByTopic: const {'Polity': 7},
          todayAnswered: 31,
        ),
      );
      expect([for (final t in plan.tasks) t.kind], PlanTaskKind.values);
      final byKind = {for (final t in plan.tasks) t.kind: t};
      expect(byKind[PlanTaskKind.daily]!.title, 'Play the Daily 5');
      expect((byKind[PlanTaskKind.daily]!.done, byKind[PlanTaskKind.daily]!.target), (2, 5));
      expect(byKind[PlanTaskKind.mistakes]!.title, 'Fix 10 mistakes');
      expect(byKind[PlanTaskKind.mistakes]!.done, 3);
      expect(byKind[PlanTaskKind.revision]!.title, 'Revise 3 due questions');
      expect(byKind[PlanTaskKind.revision]!.done, 1);
      expect(byKind[PlanTaskKind.focusTopic]!.title, 'Practise 20 in Polity');
      expect(byKind[PlanTaskKind.focusTopic]!.topic, 'Polity');
      expect(byKind[PlanTaskKind.focusTopic]!.done, 7);
      expect(byKind[PlanTaskKind.goal]!.title, 'Answer 50 questions');
      expect(byKind[PlanTaskKind.goal]!.done, 31);
      expect(plan.complete, isFalse);
      expect(plan.completeCount, 0);
    });

    test('leaves out empty lists and caps the focus target at the pool size', () {
      final plan = StudyPlanService.build(
        StudyPlanInputs(now: now, poolTopics: const {'Art': 8}, todayByTopic: const {'Art': 12}, todayAnswered: 60),
      );
      expect([for (final t in plan.tasks) t.kind], [PlanTaskKind.focusTopic, PlanTaskKind.goal]);
      expect(plan.tasks.first.title, 'Practise 8 in Art');
      expect(plan.tasks.first.done, 8);
      expect(plan.complete, isTrue);
      expect(plan.completeCount, 2);
    });

    test('a finished Daily stays on the list, ticked', () {
      final plan = StudyPlanService.build(
        StudyPlanInputs(
          now: now,
          daily: const DailyChallenge(date: 'd', keys: ['a'], results: {'a': true}),
        ),
      );
      expect(plan.tasks.first.kind, PlanTaskKind.daily);
      expect(plan.tasks.first.complete, isTrue);
    });

    test('without an exam date the goal is the default and the plan asks for one', () {
      final plan = StudyPlanService.build(StudyPlanInputs(now: now, unseenQuestions: 5000));
      expect(plan.pace, PlanPace.noDate);
      expect(plan.tasks.single.target, StudyPlanService.defaultGoal);
      expect(plan.paceLine, 'Set your exam date to plan towards it');
    });

    test('the goal rises as the exam gets closer, within its bounds', () {
      int goalFor(int daysLeft, int unseen) => StudyPlanService.build(
        StudyPlanInputs(
          now: now,
          examDate: now.add(Duration(days: daysLeft)),
          unseenQuestions: unseen,
        ),
      ).tasks.last.target;

      expect(goalFor(100, 1000), 50, reason: '10 a day needed: never below the default');
      expect(goalFor(10, 700), 70);
      expect(goalFor(5, 5000), StudyPlanService.maxGoal);
    });

    test('compares the last week\'s average with what the exam needs', () {
      final exam = DateTime(2026, 6, 21);
      final behind = StudyPlanService.build(
        StudyPlanInputs(now: now, examDate: exam, unseenQuestions: 1400, lastWeek: const [30, 40, 50, 60, 20, 0, 10]),
      );
      expect(behind.daysLeft, 20);
      expect(behind.neededPerDay, 70);
      expect(behind.averagePerDay, 30);
      expect(behind.pace, PlanPace.behind);
      expect(behind.paceLine, 'Exam in 20 days · Aim for 70 a day');

      final onTrack = StudyPlanService.build(
        StudyPlanInputs(now: now, examDate: exam, unseenQuestions: 200, lastWeek: const [30, 30, 30, 30, 30, 30, 30]),
      );
      expect(onTrack.neededPerDay, StudyPlanService.minGoal);
      expect(onTrack.pace, PlanPace.onTrack);
      expect(onTrack.paceLine, 'Exam in 20 days · On track');

      final tomorrow = StudyPlanService.build(
        StudyPlanInputs(now: now, examDate: DateTime(2026, 6, 2), lastWeek: const [100]),
      );
      expect(tomorrow.paceLine, 'Exam in 1 day · On track');
    });

    test('on and after exam day', () {
      final today = StudyPlanService.build(StudyPlanInputs(now: now, examDate: DateTime(2026, 6, 1, 18)));
      expect(today.pace, PlanPace.examDay);
      expect(today.paceLine, 'Exam day. Good luck!');
      final past = StudyPlanService.build(StudyPlanInputs(now: now, examDate: DateTime(2026, 5, 20)));
      expect(past.paceLine, 'Your exam date has passed');
      expect(past.tasks.last.target, StudyPlanService.defaultGoal);
    });
  });

  group('Plan days', () {
    test('each finished day counts once, and five earn "On plan"', () async {
      final service = StudyPlanService();
      expect(await service.markComplete(now: DateTime(2026, 6, 1, 9)), isTrue);
      expect(await service.markComplete(now: DateTime(2026, 6, 1, 22)), isFalse);
      for (var d = 2; d <= 5; d++) {
        await service.markComplete(now: DateTime(2026, 6, d));
      }
      expect(await service.completedDays(), 5);

      final metrics = await BadgeService().metrics();
      expect(metrics.planDays, 5);
      expect(await BadgeService().check(metrics: BadgeMetrics(planDays: metrics.planDays)), contains(BadgeId.onPlan));
    });

    test('a damaged record starts again from zero', () async {
      SharedPreferences.setMockInitialValues({
        'plan_days_done': jsonEncode({'x': 1}),
      });
      expect(await StudyPlanService().completedDays(), 0);
    });
  });

  group('TodayPlanCard', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({'selected_exam': 'jee'});
      GoogleFonts.config.allowRuntimeFetching = false;
    });

    Future<ProviderContainer> pumpCard(WidgetTester tester, StudyPlan plan) async {
      tester.view
        ..physicalSize = const Size(1080, 2400)
        ..devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      final pool = [for (var i = 0; i < 12; i++) _q(i.isEven ? 'Polity' : 'Art', i)];
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            feedQuestionPoolProvider.overrideWith((ref) async => pool),
            ...sideEffectOverrides(),
            studyPlanProvider.overrideWith((ref) async => plan),
          ],
          child: MaterialApp(
            theme: AppTheme.dark,
            home: const Scaffold(body: SingleChildScrollView(child: TodayPlanCard())),
          ),
        ),
      );
      for (var i = 0; i < 5; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      final container = ProviderScope.containerOf(tester.element(find.byType(TodayPlanCard)));
      // In the app the feed is already running behind Home; load it here too.
      container.listen(feedControllerProvider, (_, _) {});
      for (var i = 0; i < 20 && container.read(feedControllerProvider).loading; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      return container;
    }

    Future<void> settle(WidgetTester tester) async {
      await tester.pump(const Duration(seconds: 6));
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 6));
    }

    testWidgets('shows the tasks and opens the focus topic in Practice', (tester) async {
      final container = await pumpCard(
        tester,
        const StudyPlan(
          pace: PlanPace.behind,
          daysLeft: 12,
          neededPerDay: 80,
          tasks: [
            PlanTask(kind: PlanTaskKind.focusTopic, title: 'Practise 6 in Polity', done: 2, target: 6, topic: 'Polity'),
            PlanTask(kind: PlanTaskKind.goal, title: 'Answer 80 questions', done: 80, target: 80),
          ],
        ),
      );
      container.read(tabIndexProvider.notifier).state = 3;

      expect(find.text("Today's plan"), findsOneWidget);
      expect(find.text('1/2'), findsOneWidget);
      expect(find.text('Exam in 12 days · Aim for 80 a day'), findsOneWidget);
      expect(find.bySemanticsLabel('Answer 80 questions, 80 of 80, done'), findsOneWidget);

      await tester.tap(find.text('Practise 6 in Polity'));
      for (var i = 0; i < 5; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      final feed = container.read(feedControllerProvider);
      expect(feed.lane.type, FeedLaneType.topic);
      expect(feed.lane.label, 'Polity');
      expect(container.read(tabIndexProvider), 0);
      await settle(tester);
    });

    testWidgets('the mistakes row opens the Mistakes lane', (tester) async {
      final container = await pumpCard(
        tester,
        const StudyPlan(
          pace: PlanPace.noDate,
          tasks: [PlanTask(kind: PlanTaskKind.mistakes, title: 'Fix 3 mistakes', done: 0, target: 3)],
        ),
      );
      expect(find.text('Set your exam date to plan towards it'), findsOneWidget);
      await tester.tap(find.text('Fix 3 mistakes'));
      for (var i = 0; i < 5; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(container.read(feedControllerProvider).lane.id, FeedLane.mistakes.id);
      await settle(tester);
    });

    testWidgets('a finished plan is celebrated and counted once', (tester) async {
      await pumpCard(
        tester,
        const StudyPlan(
          pace: PlanPace.noDate,
          tasks: [PlanTask(kind: PlanTaskKind.goal, title: 'Answer 50 questions', done: 50, target: 50)],
        ),
      );
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.text('All done for today. Great work!'), findsOneWidget);
      expect(await StudyPlanService().completedDays(), 1);
      await settle(tester);
    });
  });
}
