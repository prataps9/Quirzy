import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:quirzy/features/flashcards/providers/flashcard_providers.dart';
import 'package:quirzy/features/flashcards/screens/flashcards_screen.dart';
import 'package:quirzy/features/flashcards/services/flashcard_service.dart';
import 'package:quirzy/features/l10n/app_localizations.dart';
import 'package:quirzy/shared/theme/app_theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// A flashcard service whose library load fails until [failing] is false.
class _FakeFlashcardService implements FlashcardService {
  bool failing = true;
  int loads = 0;

  @override
  Future<List<Map<String, dynamic>>> getMyFlashcardSets() async {
    loads++;
    if (failing) throw Exception('Failed host lookup: cloud.appwrite.io');
    return [
      {'id': 'set1', 'title': 'Photosynthesis', 'cardCount': 1},
    ];
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Future<void> _pumpScreen(WidgetTester tester, _FakeFlashcardService service) async {
  tester.view
    ..physicalSize = const Size(1080, 2400)
    ..devicePixelRatio = 3;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [flashcardServiceProvider.overrideWithValue(service)],
      child: MaterialApp(
        theme: AppTheme.dark,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: const [Locale('en')],
        home: const FlashcardsScreen(),
      ),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 100));
}

Future<void> _openLibrary(WidgetTester tester) async {
  final chip = find.widgetWithText(ChoiceChip, 'My Library');
  await tester.ensureVisible(chip);
  await tester.pump();
  await tester.tap(chip);
  await tester.pump();
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
    GoogleFonts.config.allowRuntimeFetching = false;
  });

  testWidgets('a failed library load shows an error with Retry, not "No flashcards yet"', (tester) async {
    final service = _FakeFlashcardService();
    await _pumpScreen(tester, service);
    await _openLibrary(tester);

    await tester.dragUntilVisible(
      find.text('Retry'),
      find.byType(CustomScrollView),
      const Offset(0, -300),
    );
    expect(
      find.text("Couldn't load your flashcards. Check your connection and try again."),
      findsOneWidget,
    );
    expect(find.text('No flashcards yet'), findsNothing);
    expect(find.textContaining('Exception'), findsNothing);

    service.failing = false;
    await tester.tap(find.text('Retry'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(service.loads, 2);
    expect(find.text('Photosynthesis'), findsOneWidget);
    expect(find.text('1 card'), findsOneWidget);
    expect(find.text('Retry'), findsNothing);
  });

  testWidgets('library tabs are full-size chips, not shrunk to fit', (tester) async {
    await _pumpScreen(tester, _FakeFlashcardService()..failing = false);
    for (final label in ['Recommended', 'My Library', 'Recent', 'Favourites']) {
      expect(find.widgetWithText(ChoiceChip, label), findsOneWidget);
    }
    expect(find.byType(FittedBox), findsNothing);
  });
}
