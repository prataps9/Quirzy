import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:quirzy/features/onboarding/screens/exam_selection_screen.dart';
import 'package:quirzy/shared/theme/app_theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<void> _open(WidgetTester tester) async {
  tester.view
    ..physicalSize = const Size(1080, 2400)
    ..devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(ProviderScope(
    child: MaterialApp(
      theme: AppTheme.dark,
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: TextButton(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const ExamSelectionScreen()),
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ),
  ));
  await tester.pump(const Duration(milliseconds: 100));
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}

void main() {
  setUp(() => GoogleFonts.config.allowRuntimeFetching = false);

  testWidgets('first run: back is blocked until an exam is chosen', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await _open(tester);
    expect(find.text('Which exam are you preparing for?'), findsOneWidget);
    expect(find.byType(BackButton), findsNothing);

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('Continue'), findsOneWidget, reason: 'still on the exam screen');

    await tester.tap(find.text('JEE'));
    await tester.pump();
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();
    expect(find.text('open'), findsOneWidget);
    expect((await SharedPreferences.getInstance()).getString('selected_exam'), 'jee');
  });

  testWidgets('changing later: back works and the current exam is pre-selected', (tester) async {
    SharedPreferences.setMockInitialValues({'selected_exam': 'neet'});
    await _open(tester);
    expect(find.text('Change exam'), findsOneWidget);
    expect(
      tester.getSemantics(find.text('NEET')).flagsCollection.isSelected.toBoolOrNull(),
      isTrue,
      reason: 'the current exam starts selected',
    );
    expect(tester.widget<FilledButton>(find.ancestor(of: find.text('Save'), matching: find.byType(FilledButton))).onPressed,
        isNull, reason: 'nothing to save yet');

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('open'), findsOneWidget);
  });
}
