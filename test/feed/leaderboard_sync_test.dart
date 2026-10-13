import 'package:flutter_test/flutter_test.dart';
import 'package:quirzy/features/feed/services/leaderboard_sync.dart';
import 'package:quirzy/features/feed/services/streak_service.dart';
import 'package:quirzy/shared/appwrite/leaderboard/leaderboard_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Update {
  final String userId;
  final String userName;
  final int totalXP;
  final int currentStreak;
  final String rank;

  _Update(this.userId, this.userName, this.totalXP, this.currentStreak, this.rank);
}

class _FakeLeaderboardService implements LeaderboardService {
  final updates = <_Update>[];
  bool fail = false;

  @override
  Future<void> updateLeaderboard({
    required String userId,
    required String userName,
    required int totalXP,
    required int quizzesCompleted,
    required int currentStreak,
    required String rank,
  }) async {
    if (fail) throw Exception('offline');
    updates.add(_Update(userId, userName, totalXP, currentStreak, rank));
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const debounce = Duration(milliseconds: 50);
  final today = DateTime.now();

  late _FakeLeaderboardService service;
  late Map<String, String> secure;

  LeaderboardSync build() => LeaderboardSync(
        service: service,
        readSecure: (key) async => secure[key],
        debounce: debounce,
      );

  setUp(() {
    service = _FakeLeaderboardService();
    secure = {'user_id': 'u1', 'user_name': 'Asha'};
    SharedPreferences.setMockInitialValues({
      'xp_total': 250,
      StreakService.countKey(today): 4,
    });
  });

  test('a burst of schedule() calls results in a single sync', () async {
    final sync = build();
    for (var i = 0; i < 5; i++) {
      sync.schedule();
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    expect(service.updates, isEmpty);

    await Future<void>.delayed(debounce * 3);
    expect(service.updates, hasLength(1));
    final u = service.updates.single;
    expect(u.userId, 'u1');
    expect(u.userName, 'Asha');
    expect(u.totalXP, 250);
    expect(u.currentStreak, 1);
    expect(u.rank, 'Bronze');
    sync.dispose();
  });

  test('syncNow uploads immediately and cancels a pending schedule', () async {
    final sync = build();
    sync.schedule();
    await sync.syncNow();
    expect(service.updates, hasLength(1));

    await Future<void>.delayed(debounce * 3);
    expect(service.updates, hasLength(1));
  });

  test('signed-out users are not synced', () async {
    secure = {};
    await build().syncNow();
    expect(service.updates, isEmpty);
  });

  test('failures are swallowed', () async {
    service.fail = true;
    await expectLater(build().syncNow(), completes);
  });
}
