import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:quirzy/features/feed/models/feed_models.dart';
import 'package:quirzy/features/feed/providers/feed_providers.dart';
import 'package:quirzy/features/feed/services/activity_log.dart';
import 'package:quirzy/features/report/models/weekly_report.dart';
import 'package:quirzy/features/report/providers/weekly_report_providers.dart';
import 'package:quirzy/features/report/screens/weekly_report_screen.dart';
import 'package:quirzy/features/report/services/weekly_report_service.dart';
import 'package:quirzy/features/report/widgets/week_bars.dart';
import 'package:quirzy/shared/services/smart_notification_service.dart';
import 'package:quirzy/shared/theme/app_theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/side_effect_fakes.dart';

/// Wednesday.
final _now = DateTime(2026, 6, 10, 20);

Future<void> _answer(String topic, int right, int wrong, DateTime at) async {
  final log = ActivityLog();
  for (var i = 0; i < right; i++) {
    await log.record(topic, true, at: at);
  }
  for (var i = 0; i < wrong; i++) {
    await log.record(topic, false, at: at);
  }
}

String _key(DateTime d) => ActivityLog.dateKey(d);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('Weeks', () {
    test('run Monday to Sunday', () {
      expect(WeeklyReportService.weekStart(DateTime(2026, 6, 8, 1)), DateTime(2026, 6, 8));
      expect(WeeklyReportService.weekStart(DateTime(2026, 6, 14, 23, 59)), DateTime(2026, 6, 8));
      expect(WeeklyReportService.weekStart(DateTime(2026, 6, 15)), DateTime(2026, 6, 15));
      expect(WeeklyReportService.weekStart(_now, 2), DateTime(2026, 5, 25));
      // Across a month and a year.
      expect(WeeklyReportService.weekStart(DateTime(2027, 1, 1)), DateTime(2026, 12, 28));
    });

    test('parts of the day', () {
      expect([5, 11, 12, 16, 17, 20, 21, 4].map((h) => DayPart.of(h)), [
        DayPart.morning,
        DayPart.morning,
        DayPart.afternoon,
        DayPart.afternoon,
        DayPart.evening,
        DayPart.evening,
        DayPart.night,
        DayPart.night,
      ]);
    });
  });

  group('WeeklyReportService', () {
    test('adds up the week from the log, counters and XP, and compares with the week before', () async {
      // This week: Monday and Wednesday.
      await _answer('Polity', 8, 2, DateTime(2026, 6, 8, 7));
      await _answer('History', 3, 7, DateTime(2026, 6, 10, 19));
      await _answer('Polity', 5, 5, DateTime(2026, 6, 10, 20));
      // Sunday at 23:30 is still this week; next Monday is not.
      await _answer('Art', 1, 0, DateTime(2026, 6, 14, 23, 30));
      await _answer('Art', 1, 0, DateTime(2026, 6, 15, 0, 10));
      // The week before: 20 answers, half right.
      await _answer('Polity', 10, 10, DateTime(2026, 6, 3, 9));

      final prefs = await SharedPreferences.getInstance();
      // The feed's counter can be ahead of the log (older answers).
      await prefs.setInt('feed_answered_count_${_key(DateTime(2026, 6, 8))}', 15);
      await prefs.setInt('xp_today_${_key(DateTime(2026, 6, 8))}', 120);
      await prefs.setInt('xp_today_${_key(DateTime(2026, 6, 10))}', 80);
      await prefs.setInt('xp_today_${_key(DateTime(2026, 6, 15))}', 999);
      await prefs.setString('badges_v1', jsonEncode({'firstAnswer': DateTime(2026, 6, 9).millisecondsSinceEpoch}));

      final report = await WeeklyReportService(clock: () => _now).week();
      expect(report.start, DateTime(2026, 6, 8));
      expect(report.answeredByDay, [15, 0, 20, 0, 0, 0, 1]);
      expect(report.answered, 36);
      expect(report.daysActive, 3);
      expect(report.graded, 31);
      expect(report.accuracy, 55); // 17 of 31
      expect(report.xp, 200);
      expect(report.badges, 1);
      expect(report.answeredChange, 80); // 36 against 20
      expect(report.previousAccuracy, 50);
      expect(report.accuracyChange, 5);
      expect(report.bestDay, 2);
      expect([for (final t in report.topics) t.topic], ['Polity', 'History', 'Art']);
      expect(report.mostPractised!.answered, 20);
      expect(report.bestTopic!.topic, 'Polity');
      expect(report.weakestTopic!.topic, 'History');
      expect(report.bestTime, DayPart.evening);

      final before = await WeeklyReportService(clock: () => _now).week(1);
      expect(before.answeredByDay, [0, 0, 20, 0, 0, 0, 0]);
      expect(before.answeredChange, isNull, reason: 'nothing the week before that');
    });

    test('names best and weakest topics only with enough answers', () {
      final few = WeeklyReport(
        start: DateTime(2026),
        answeredByDay: const [9, 0, 0, 0, 0, 0, 0],
        topics: const [TopicWeek('A', 9, 9)],
        parts: const {DayPart.morning: 9},
      );
      expect(few.bestTopic, isNull);
      expect(few.weakestTopic, isNull);
      expect(few.bestTime, isNull);

      final one = WeeklyReport(
        start: DateTime(2026),
        answeredByDay: const [30, 0, 0, 0, 0, 0, 0],
        topics: const [TopicWeek('A', 20, 10), TopicWeek('B', 10, 5)],
      );
      expect(one.bestTopic, isNotNull);
      expect(one.weakestTopic, isNull, reason: 'equal scores: nothing is weaker');
    });

    test('the last seven days for the Sunday notification', () async {
      await _answer('Polity', 6, 4, DateTime(2026, 6, 9, 9));
      await _answer('Polity', 4, 4, DateTime(2026, 6, 1, 9));
      final (answered, accuracy, change) = await WeeklyReportService(clock: () => _now).lastSevenDays();
      expect((answered, accuracy, change), (10, 60, 25));
    });
  });

  group('Weekly notification', () {
    test('gives the numbers and the change', () {
      expect(
        SmartNotificationService.weeklyDigestBody(questions: 212, accuracy: 78, changePercent: 9),
        '212 questions · 78% right · up 9% on last week. Tap to see your week.',
      );
      expect(
        SmartNotificationService.weeklyDigestBody(questions: 1, changePercent: -40),
        '1 question · down 40% on last week. Tap to see your week.',
      );
      expect(
        SmartNotificationService.weeklyDigestBody(questions: 30, accuracy: 70, flashcards: 12, bestStreak: 4),
        '30 questions · 70% right · 12 cards · 4-day best streak. Tap to see your week.',
      );
      expect(SmartNotificationService.weeklyDigestBody(questions: 0), startsWith('A quiet week'));
    });
  });

  group('WeeklyReportScreen', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({'selected_exam': 'jee'});
      GoogleFonts.config.allowRuntimeFetching = false;
    });

    WeeklyReport report(int weeksAgo) => switch (weeksAgo) {
      0 => WeeklyReport(
        start: WeeklyReportService.weekStart(DateTime.now()),
        answeredByDay: const [12, 30, 0, 8, 0, 0, 0],
        graded: 50,
        correct: 40,
        xp: 300,
        topics: const [TopicWeek('Polity', 30, 27), TopicWeek('History', 20, 8)],
        parts: const {DayPart.evening: 40, DayPart.morning: 10},
        mockTests: 1,
        previousAnswered: 40,
        previousAccuracy: 70,
      ),
      _ => WeeklyReport(
        start: WeeklyReportService.weekStart(DateTime.now(), weeksAgo),
        answeredByDay: List.filled(7, 0),
      ),
    };

    Future<ProviderContainer> pumpReport(WidgetTester tester) async {
      tester.view
        ..physicalSize = const Size(1080, 2400)
        ..devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      final pool = [
        for (var i = 0; i < 10; i++)
          PracticeQuestion(
            id: 'q$i',
            questionText: 'Q$i?',
            options: const ['A', 'B'],
            correctIndex: 0,
            topic: 'History',
          ),
      ];
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            feedQuestionPoolProvider.overrideWith((ref) async => pool),
            ...sideEffectOverrides(),
            weeklyReportProvider.overrideWith((ref, weeksAgo) async => report(weeksAgo)),
          ],
          child: MaterialApp(
            theme: AppTheme.dark,
            home: Builder(
              builder: (context) => TextButton(
                onPressed: () =>
                    Navigator.of(context).push(MaterialPageRoute(builder: (_) => const WeeklyReportScreen())),
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      );
      final container = ProviderScope.containerOf(tester.element(find.text('Open')));
      container.listen(feedControllerProvider, (_, _) {});
      for (var i = 0; i < 20 && container.read(feedControllerProvider).loading; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      await tester.tap(find.text('Open'));
      await frames(tester, 12);
      return container;
    }

    testWidgets('shows the week, switches weeks and practises the weakest topic', (tester) async {
      final container = await pumpReport(tester);
      expect(find.text('This week'), findsOneWidget);
      expect(find.text('50'), findsOneWidget);
      expect(find.text('80%'), findsOneWidget);
      expect(find.text('3/7'), findsOneWidget);
      expect(find.text('25% on last week'), findsOneWidget);
      expect(find.text('10 points'), findsOneWidget);
      expect(find.byIcon(Icons.arrow_upward_rounded), findsNWidgets(2));
      expect(find.text('+300 XP · 1 mock test'), findsOneWidget);
      expect(find.text('You practised most in the evening'), findsOneWidget);
      expect(find.text('Best'), findsOneWidget);
      expect(find.text('Needs work'), findsOneWidget);
      expect(find.bySemanticsLabel('Tuesday, 30 questions'), findsOneWidget);
      // Only the busiest day is labelled; a tapped bar shows its own.
      final bars = find.byType(WeekBars);
      expect(find.descendant(of: bars, matching: find.text('30')), findsOneWidget);
      await tester.tap(find.bySemanticsLabel('Monday, 12 questions'));
      await frames(tester, 3);
      final visible = tester
          .widgetList<AnimatedOpacity>(find.descendant(of: bars, matching: find.byType(AnimatedOpacity)))
          .where((o) => o.opacity == 1)
          .length;
      expect(visible, 1);

      await tester.tap(find.byTooltip('Earlier week'));
      await frames(tester, 6);
      expect(find.text('Last week'), findsOneWidget);
      expect(find.text('No practice that week'), findsOneWidget);
      await tester.tap(find.byTooltip('Later week'));
      await frames(tester, 6);
      expect(find.text('This week'), findsOneWidget);

      await tester.scrollUntilVisible(find.text('Practise History'), 200);
      await tester.tap(find.text('Practise History'));
      await frames(tester, 6);
      expect(find.byType(WeeklyReportScreen), findsNothing);
      expect(container.read(feedControllerProvider).lane.label, 'History');
      await tester.pump(const Duration(seconds: 6));
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 6));
    });
  });
}

Future<void> frames(WidgetTester tester, int n) async {
  for (var i = 0; i < n; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}
