import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:quirzy/features/feed/models/feed_models.dart';
import 'package:quirzy/features/feed/providers/feed_providers.dart';
import 'package:quirzy/features/feed/services/feed_ranker.dart';
import 'package:quirzy/features/home/screens/main_screen.dart';
import 'package:quirzy/features/mocktest/screens/mock_test_screen.dart';
import 'package:quirzy/features/progress/screens/mistakes_screen.dart';
import 'package:quirzy/shared/providers/app_action_provider.dart';
import 'package:quirzy/shared/providers/providers.dart';
import 'package:quirzy/shared/services/connectivity_service.dart';
import 'package:quirzy/shared/services/home_widget_sync.dart';
import 'package:quirzy/shared/theme/app_theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/side_effect_fakes.dart';

PracticeQuestion _q(int n) => PracticeQuestion(
  id: 'q$n',
  questionText: 'Question $n?',
  options: const ['A', 'B', 'C'],
  correctIndex: 0,
  topic: 'Physics',
);

void main() {
  final pool = [for (var i = 0; i < 20; i++) _q(i)];

  group('app shortcuts', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({'selected_exam': 'jee', 'notif_permission_asked': true});
      GoogleFonts.config.allowRuntimeFetching = false;
    });

    Future<ProviderContainer> pumpShell(WidgetTester tester) async {
      tester.view
        ..physicalSize = const Size(1080, 2400)
        ..devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            feedQuestionPoolProvider.overrideWith((ref) async => pool),
            ...sideEffectOverrides(),
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

    Future<void> settle(WidgetTester tester) async {
      for (var i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
    }

    Future<void> tearDownShell(WidgetTester tester) async {
      await tester.pump(const Duration(seconds: 6));
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 6));
    }

    testWidgets('Mock test and Mistakes open their screens', (tester) async {
      final container = await pumpShell(tester);
      container.read(pendingAppActionProvider.notifier).state = AppAction.mockTest;
      await settle(tester);
      expect(find.byType(MockTestScreen), findsOneWidget);
      expect(container.read(pendingAppActionProvider), isNull);

      container.read(pendingAppActionProvider.notifier).state = AppAction.mistakes;
      await settle(tester);
      expect(find.byType(MistakesScreen), findsOneWidget);
      expect(find.byType(MockTestScreen), findsNothing, reason: 'opens from the shell, not on top of another screen');
      await tearDownShell(tester);
    });

    testWidgets('Daily 5 opens Practice on the Daily 5', (tester) async {
      final container = await pumpShell(tester);
      container.read(tabIndexProvider.notifier).state = 2;
      container.read(pendingAppActionProvider.notifier).state = AppAction.daily;
      await settle(tester);
      expect(container.read(tabIndexProvider), 0);
      expect(container.read(feedControllerProvider).lane.type, FeedLaneType.daily);
      await tearDownShell(tester);
    });

    testWidgets('a shortcut used before sign-in opens once the app shell is up', (tester) async {
      tester.view
        ..physicalSize = const Size(1080, 2400)
        ..devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      final container = ProviderContainer(
        overrides: [
          feedQuestionPoolProvider.overrideWith((ref) async => pool),
          ...sideEffectOverrides(),
          isOnlineProvider.overrideWith((ref) => Stream.value(true)),
        ],
      );
      addTearDown(container.dispose);
      container.read(pendingAppActionProvider.notifier).state = AppAction.mistakes;
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(theme: AppTheme.dark, home: const MainScreen()),
        ),
      );
      await settle(tester);
      expect(find.byType(MistakesScreen), findsOneWidget);
      await tearDownShell(tester);
    });
  });

  group('home-screen widget', () {
    test('an answer updates the numbers the widget shows', () async {
      SharedPreferences.setMockInitialValues({});
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
      final controller = container.read(feedControllerProvider.notifier);
      controller.activate(0);
      await controller.selectOption(0, 0);
      await controller.syncHomeWidget();

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getInt(HomeWidgetSync.todayKey), 1);
      expect(prefs.getInt(HomeWidgetSync.streakKey), 1);
      expect(prefs.getInt(HomeWidgetSync.goalKey), kFeedDailyTarget);
    });
  });
}
