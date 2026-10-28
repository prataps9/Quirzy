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

  test('missing one day is forgiven by the weekly streak freeze', () async {
    await practise([2, 3, 4]);
    final info = await service.getStreak();
    expect(info.current, 4, reason: 'yesterday is frozen and counts');
    expect(info.atRisk, isTrue);
    expect(info.freezeReady, isFalse, reason: 'used this week');
    expect(await service.takeFreezeAnnouncement(), 4);
    expect(await service.takeFreezeAnnouncement(), isNull, reason: 'announced once');
  });

  test('missing two days in a row still resets the streak', () async {
    await practise([3, 4, 5]);
    final info = await service.getStreak();
    expect(info.current, 0);
    expect(info.best, 3);
    expect(info.freezeReady, isTrue);
  });

  test('only one freeze a week: a second miss that week resets the streak', () async {
    // Wednesday 7 Oct, missed Tuesday 6 Oct. The freeze used on 30 Sep was
    // last week, so this week's freeze saves the streak.
    final later = StreakService(clock: () => DateTime(2026, 10, 7, 9));
    SharedPreferences.setMockInitialValues({
      StreakService.countKey(DateTime(2026, 10, 5)): 1,
      StreakService.countKey(DateTime(2026, 10, 4)): 1,
      'streak_frozen_days': ['2026-09-30'],
    });
    expect((await later.getStreak()).current, 3);

    // Same week, already frozen on Monday 5 Oct: missing Tuesday breaks it.
    SharedPreferences.setMockInitialValues({
      StreakService.countKey(DateTime(2026, 10, 4)): 1,
      StreakService.countKey(DateTime(2026, 10, 3)): 1,
      'streak_frozen_days': ['2026-10-05'],
    });
    expect((await later.getStreak()).current, 0);
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

  test('a day with only flashcard reviews keeps the streak alive', () async {
    SharedPreferences.setMockInitialValues({
      StreakService.countKey(DateTime(now.year, now.month, now.day - 1)): 2,
    });
    await service.recordFlashcardReview();
    final streak = await service.getStreak();
    expect(streak.current, 2);
    expect(streak.practisedToday, isTrue);
  });

  test('flashcardsReviewed sums the last week only', () async {
    SharedPreferences.setMockInitialValues({
      StreakService.flashcardKey(DateTime(now.year, now.month, now.day - 2)): 4,
      StreakService.flashcardKey(DateTime(now.year, now.month, now.day - 9)): 50,
    });
    await service.recordFlashcardReview();
    expect(await service.flashcardsReviewed(), 5);
  });
}
