import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:quirzy/features/feed/models/feed_models.dart';
import 'package:quirzy/features/feed/providers/feed_providers.dart';
import 'package:quirzy/features/home/screens/main_screen.dart';
import 'package:quirzy/shared/providers/providers.dart';
import 'package:quirzy/shared/services/connectivity_service.dart';
import 'package:quirzy/shared/theme/app_theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/side_effect_fakes.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({'selected_exam': 'jee', 'notif_permission_asked': true});
    GoogleFonts.config.allowRuntimeFetching = false;
  });

  testWidgets('back returns to Practice from another tab, then needs a second press to exit', (tester) async {
    tester.view
      ..physicalSize = const Size(1080, 2400)
      ..devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    final exits = <MethodCall>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'SystemNavigator.pop') exits.add(call);
      return null;
    });

    final pool = [
      for (var i = 0; i < 20; i++)
        PracticeQuestion(id: 'q$i', questionText: 'Q$i?', options: const ['A', 'B'], correctIndex: 0, topic: 'Math'),
    ];
    await tester.pumpWidget(ProviderScope(
      overrides: [
        feedQuestionPoolProvider.overrideWith((ref) async => pool),
        ...sideEffectOverrides(),
        isOnlineProvider.overrideWith((ref) => Stream.value(true)),
      ],
      child: MaterialApp(theme: AppTheme.dark, home: const MainScreen()),
    ));
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    final container = ProviderScope.containerOf(tester.element(find.byType(MainScreen)));

    // On another tab, back goes to Practice instead of leaving the app.
    container.read(tabIndexProvider.notifier).state = 2;
    await tester.pump();
    await tester.binding.handlePopRoute();
    await tester.pump();
    expect(container.read(tabIndexProvider), 0);
    expect(exits, isEmpty);

    // On Practice, the first back only warns…
    await tester.binding.handlePopRoute();
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('Press back again to exit'), findsOneWidget);
    expect(exits, isEmpty);

    // …and a second one within two seconds leaves.
    await tester.binding.handlePopRoute();
    await tester.pump();
    expect(exits, hasLength(1));

    // Let debounced saves and the snackbar finish before tearing down.
    await tester.pump(const Duration(seconds: 6));
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 6));
  });
}
