import 'package:flutter_test/flutter_test.dart';
import 'package:quirzy/features/feed/services/streak_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final now = DateTime(2026, 10, 4, 18, 30);
  final service = StreakService(clock: () => now);

  Future<void> practise(List<int> daysAgo) async {
    final values = <String, Object>{};
    for (final d in daysAgo) {
      values[StreakService.countKey(DateTime(now.year, now.month, now.day - d))] = 3;
    }
    SharedPreferences.setMockInitialValues(values);
  }

  test('no activity means no streak', () async {
    await practise([]);
    final info = await service.getStreak();
    expect(info.current, 0);
    expect(info.best, 0);
    expect(info.atRisk, isFalse);
  });

  test('practising today starts a streak of one', () async {
    await practise([0]);
    final info = await service.getStreak();
    expect(info.current, 1);
    expect(info.practisedToday, isTrue);
    expect(info.atRisk, isFalse);
  });

  test('consecutive days build the streak', () async {
    await practise([0, 1, 2, 3]);
    expect((await service.getStreak()).current, 4);
  });

  test('a streak stays alive until the end of today but is at risk', () async {
    await practise([1, 2]);
    final info = await service.getStreak();
    expect(info.current, 2);
    expect(info.practisedToday, isFalse);
    expect(info.atRisk, isTrue);
  });

  test('missing a whole day resets the streak', () async {
    await practise([2, 3, 4]);
    final info = await service.getStreak();
    expect(info.current, 0);
    expect(info.best, 3);
  });

  test('a gap ends the run and best remembers the longer one', () async {
    await practise([0, 1, 4, 5, 6, 7, 8]);
    final info = await service.getStreak();
    expect(info.current, 2);
    expect(info.best, 5);
  });

  test('works across a month boundary', () async {
    final earlyMonth = StreakService(clock: () => DateTime(2026, 3, 2, 9));
    SharedPreferences.setMockInitialValues({
      StreakService.countKey(DateTime(2026, 3, 2)): 1,
      StreakService.countKey(DateTime(2026, 3, 1)): 1,
      StreakService.countKey(DateTime(2026, 2, 28)): 1,
    });
    expect((await earlyMonth.getStreak()).current, 3);
  });

  test('keys match what the feed writes', () {
    final day = DateTime(2026, 1, 5);
    expect(
      StreakService.countKey(day),
      'feed_answered_count_${day.toIso8601String().split('T').first}',
    );
  });
}
