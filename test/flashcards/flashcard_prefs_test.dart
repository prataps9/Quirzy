import 'package:flutter_test/flutter_test.dart';
import 'package:quirzy/features/flashcards/services/flashcard_prefs.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  var now = DateTime(2026, 10, 4, 10);
  DateTime clock() => now;

  setUp(() {
    now = DateTime(2026, 10, 4, 10);
    SharedPreferences.setMockInitialValues({});
  });

  test('favourite toggle persists across service instances', () async {
    final service = FlashcardPrefsService(clock: clock);
    expect(await service.toggleFavourite('a'), isTrue);
    expect((await FlashcardPrefsService().load()).isFavourite('a'), isTrue);

    expect(await service.toggleFavourite('a'), isFalse);
    expect((await FlashcardPrefsService().load()).isFavourite('a'), isFalse);
  });

  test('recent is ordered by last studied and skips unstudied sets', () async {
    final service = FlashcardPrefsService(clock: clock);
    await service.markStudied('a');
    now = now.add(const Duration(hours: 1));
    await service.markStudied('b');
    now = now.add(const Duration(hours: 1));
    await service.markStudied('c');
    now = now.add(const Duration(hours: 1));
    await service.markStudied('a');

    final state = await service.load();
    expect(state.recentIds, ['a', 'c', 'b']);
    expect(state.recentIds, isNot(contains('never')));
    expect(state.lastStudied['a'], DateTime(2026, 10, 4, 13));
  });

  test('remove drops a set from favourites and recent', () async {
    final service = FlashcardPrefsService(clock: clock);
    await service.toggleFavourite('a');
    await service.toggleFavourite('b');
    await service.markStudied('a');
    await service.markStudied('b');

    await service.remove('a');

    final state = await service.load();
    expect(state.favourites, {'b'});
    expect(state.recentIds, ['b']);
  });

  test('corrupt last-studied data is ignored', () async {
    SharedPreferences.setMockInitialValues({
      FlashcardPrefsService.lastStudiedKey: 'not json',
    });
    final state = await FlashcardPrefsService().load();
    expect(state.recentIds, isEmpty);
  });
}
