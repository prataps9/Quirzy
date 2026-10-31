import 'dart:convert';
import 'dart:io' show gzip;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:quirzy/features/report/screens/weekly_report_screen.dart';
import 'package:quirzy/features/challenge/models/challenge.dart';
import 'package:quirzy/features/challenge/providers/challenge_providers.dart';
import 'package:quirzy/features/challenge/screens/challenge_screen.dart';
import 'package:quirzy/features/feed/models/feed_models.dart';
import 'package:quirzy/features/feed/providers/feed_providers.dart';
import 'package:quirzy/features/feed/services/mistakes_service.dart';
import 'package:quirzy/features/home/screens/main_screen.dart';
import 'package:quirzy/shared/providers/providers.dart';
import 'package:quirzy/shared/services/connectivity_service.dart';
import 'package:quirzy/shared/services/smart_notification_service.dart';
import 'package:quirzy/shared/theme/app_theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/side_effect_fakes.dart';

PracticeQuestion _q(int n, {String topic = 'Physics'}) => PracticeQuestion(
  id: 'q$n',
  questionText: 'Question $n: which is right?',
  options: const ['Right', 'Wrong one', 'Wrong two'],
  correctIndex: 0,
  explanation: 'Because the first one is right.',
  topic: topic,
);

Uri _rawLink(Object json) => Uri(
  scheme: 'quirzy',
  host: 'challenge',
  queryParameters: {'d': base64Url.encode(gzip.encode(utf8.encode(jsonEncode(json)))).replaceAll('=', '')},
);

void main() {
  group('ChallengeCodec', () {
    test('a challenge survives the round trip through a link', () {
      final challenge = Challenge(from: 'Asha', score: 2, questions: [_q(1), _q(2, topic: 'History'), _q(3)]);
      final link = ChallengeCodec.encode(challenge);
      expect(link.scheme, 'quirzy');
      expect(link.host, 'challenge');

      final back = ChallengeCodec.decode(link);
      expect(back.from, 'Asha');
      expect(back.score, 2);
      expect(back.total, 3);
      expect(back.questions[1].questionText, 'Question 2: which is right?');
      expect(back.questions[1].options, ['Right', 'Wrong one', 'Wrong two']);
      expect(back.questions[1].correctIndex, 0);
      expect(back.questions[1].topic, 'History');
      expect(back.questions[1].explanation, 'Because the first one is right.');
    });

    test('keeps non-English text intact', () {
      const q = PracticeQuestion(
        id: 'h',
        questionText: 'भारत की राजधानी क्या है?',
        options: ['नई दिल्ली', 'मुंबई'],
        correctIndex: 0,
      );
      final back = ChallengeCodec.decode(ChallengeCodec.encode(const Challenge(questions: [q])));
      expect(back.questions.single.questionText, 'भारत की राजधानी क्या है?');
      expect(back.from, isNull);
      expect(back.score, isNull);
    });

    test('long text is trimmed so the link stays small, and extra questions are dropped', () {
      final long = PracticeQuestion(
        id: 'l',
        questionText: 'x' * 2000,
        options: ['y' * 900, 'z'],
        correctIndex: 1,
        explanation: 'e' * 900,
      );
      final back = ChallengeCodec.decode(
        ChallengeCodec.encode(Challenge(questions: [for (var i = 0; i < 15; i++) long])),
      );
      expect(back.total, ChallengeCodec.maxQuestions);
      expect(back.questions.first.questionText.length, ChallengeCodec.maxQuestionLength);
      expect(back.questions.first.options.first.length, ChallengeCodec.maxOptionLength);
      expect(back.questions.first.explanation.length, ChallengeCodec.maxExplanationLength);
    });

    test('finds the link inside a pasted message', () {
      final text = ChallengeCodec.shareText(Challenge(score: 1, questions: [_q(1)]));
      expect(text, startsWith('Beat my 1/1 on Quirzy!'));
      final found = ChallengeCodec.findIn('Hey, try this:\n$text\nthanks');
      expect(ChallengeCodec.decode(found!).total, 1);
      expect(ChallengeCodec.findIn('nothing here'), isNull);
    });

    test('rejects broken, tampered and oversized links', () {
      void rejects(Uri uri) => expect(() => ChallengeCodec.decode(uri), throwsFormatException);
      final good = {
        'v': 1,
        'q': [
          {
            't': 'Q?',
            'o': ['a', 'b'],
            'c': 0,
          },
        ],
      };
      expect(ChallengeCodec.decode(_rawLink(good)).total, 1);

      rejects(Uri.parse('quirzy://practice'));
      rejects(Uri.parse('quirzy://challenge'));
      rejects(Uri.parse('quirzy://challenge?d=not-base64-at-all!!'));
      rejects(Uri.parse('quirzy://challenge?d=${base64Url.encode(utf8.encode('plain, not gzipped'))}'));
      rejects(Uri.parse('quirzy://challenge?d=${'A' * 20000}'));
      rejects(_rawLink({...good, 'v': 2}));
      rejects(_rawLink({'v': 1, 'q': []}));
      rejects(_rawLink({
        'v': 1,
        'q': [for (var i = 0; i < 11; i++) good['q']! as List].expand((e) => e).toList(),
      }));
      rejects(_rawLink({
        'v': 1,
        'q': [
          {
            't': 'Q?',
            'o': ['a', 'b'],
            'c': 5,
          },
        ],
      }));
      rejects(_rawLink({
        'v': 1,
        'q': [
          {
            't': 'Q?',
            'o': ['only one'],
            'c': 0,
          },
        ],
      }));
      rejects(_rawLink({...good, 's': 9}));
      rejects(_rawLink({...good, 'f': 'n' * 100}));
      rejects(_rawLink(['not', 'a', 'map']));
    });
  });

  group('ChallengeScreen', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
      GoogleFonts.config.allowRuntimeFetching = false;
    });

    testWidgets('play it, then see your score against theirs', (tester) async {
      tester.view
        ..physicalSize = const Size(1080, 2400)
        ..devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      final challenge = Challenge(from: 'Asha', score: 1, questions: [_q(1), _q(2), _q(3)]);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [...sideEffectOverrides()],
          child: MaterialApp(home: ChallengeScreen(challenge: challenge)),
        ),
      );
      await tester.pump();
      expect(find.text('Challenge from Asha'), findsOneWidget);
      expect(find.text('Asha got 1/3. Can you beat it?'), findsOneWidget);

      Future<void> pick(String option) async {
        await tester.tap(find.text(option).first);
        await tester.pump(const Duration(milliseconds: 100));
      }

      Future<void> next(String label) async {
        await tester.tap(find.text(label));
        for (var i = 0; i < 5; i++) {
          await tester.pump(const Duration(milliseconds: 100));
        }
      }

      await pick('Right');
      // No right or wrong shown while playing.
      expect(find.byIcon(Icons.check_rounded), findsNothing);
      await next('Next');
      await pick('Right');
      await next('Next');
      await pick('Wrong one');
      await next('Finish');

      expect(find.text('You beat Asha!'), findsOneWidget);
      expect(find.text('2/3'), findsOneWidget);
      expect(find.text('1/3'), findsOneWidget);
      expect(find.text('Share your score'), findsOneWidget);

      final mistakes = await tester.runAsync(() => MistakesService().all());
      expect(mistakes!.single.question.questionText, 'Question 3: which is right?');
    });
  });

  group('the app shell', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({'selected_exam': 'jee', 'notif_permission_asked': true});
      GoogleFonts.config.allowRuntimeFetching = false;
    });

    Future<ProviderContainer> pumpShell(WidgetTester tester, FakeNotificationScheduler scheduler) async {
      tester.view
        ..physicalSize = const Size(1080, 2400)
        ..devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      final pool = [for (var i = 0; i < 20; i++) _q(i)];
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            feedQuestionPoolProvider.overrideWith((ref) async => pool),
            ...sideEffectOverrides(scheduler: scheduler),
            isOnlineProvider.overrideWith((ref) => Stream.value(true)),
          ],
          child: MaterialApp(theme: AppTheme.dark, home: const MainScreen()),
        ),
      );
      for (var i = 0; i < 5; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      return ProviderScope.containerOf(tester.element(find.byType(MainScreen)));
    }

    Future<void> tearDownShell(WidgetTester tester) async {
      await tester.pump(const Duration(seconds: 6));
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 6));
    }

    testWidgets('a challenge link opens the challenge; a broken one says so', (tester) async {
      final container = await pumpShell(tester, FakeNotificationScheduler());
      container.read(pendingChallengeProvider.notifier).state = IncomingChallenge.ok(
        Challenge(from: 'Ravi', questions: [_q(1)]),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 600));
      expect(find.text('Challenge from Ravi'), findsOneWidget);
      expect(container.read(pendingChallengeProvider), isNull);

      Navigator.of(tester.element(find.byType(ChallengeScreen))).pop();
      for (var i = 0; i < 20; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(find.byType(ChallengeScreen), findsNothing);
      container.read(pendingChallengeProvider.notifier).state = const IncomingChallenge.broken();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.textContaining("That challenge link doesn't work"), findsOneWidget);
      await tearDownShell(tester);
    });

    testWidgets('tapping a notification opens the right place', (tester) async {
      final scheduler = FakeNotificationScheduler();
      final container = await pumpShell(tester, scheduler);

      scheduler.tapController.add(NotificationRoute.exam);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(container.read(tabIndexProvider), 2);

      scheduler.tapController.add(NotificationRoute.revision);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(container.read(tabIndexProvider), 0);
      expect(container.read(feedControllerProvider).lane.type, FeedLaneType.revision);
      await tearDownShell(tester);
    });

    testWidgets('a notification that launched the app is followed once it opens', (tester) async {
      final scheduler = FakeNotificationScheduler()..launchPayload = NotificationRoute.digest;
      final container = await pumpShell(tester, scheduler);
      await tester.pump(const Duration(milliseconds: 300));
      expect(container.read(tabIndexProvider), 2);
      for (var i = 0; i < 6; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(find.byType(WeeklyReportScreen), findsOneWidget, reason: 'the weekly notification opens the report');
      await tearDownShell(tester);
    });
  });
}
