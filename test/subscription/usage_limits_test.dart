import 'package:flutter_test/flutter_test.dart';
import 'package:quirzy/features/subscription/services/pro_status.dart';
import 'package:quirzy/features/subscription/services/usage_limits.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  var now = DateTime(2026, 10, 4, 10);
  DateTime clock() => now;

  setUp(() {
    now = DateTime(2026, 10, 4, 10);
    SharedPreferences.setMockInitialValues({});
  });

  group('UsageLimitsService', () {
    test('free users hit each daily cap independently', () async {
      final service = UsageLimitsService(clock: clock);
      await service.record(UsageKind.topic);
      await service.record(UsageKind.topic);
      final state = await service.load();
      expect(state.canUse(UsageKind.topic), isFalse);
      expect(state.remaining(UsageKind.topic), 0);
      expect(state.canUse(UsageKind.studySet), isTrue);
      expect(state.remaining(UsageKind.flashcardSet), 3);
    });

    test('counters reset on a new day', () async {
      final service = UsageLimitsService(clock: clock);
      await service.record(UsageKind.studySet);
      expect((await service.load()).canUse(UsageKind.studySet), isFalse);
      now = DateTime(2026, 10, 5, 0, 1);
      expect((await service.load()).canUse(UsageKind.studySet), isTrue);
    });

    test('reads the legacy topic counter keys', () async {
      SharedPreferences.setMockInitialValues({
        'last_quiz_generation_date': '2026-10-04',
        'daily_quiz_generation_count': 2,
      });
      final state = await UsageLimitsService(clock: clock).load();
      expect(state.canUse(UsageKind.topic), isFalse);
    });

    test('Pro is unlimited', () async {
      await ProStatusStore(clock: clock).activate(ProPlan.monthly);
      final service = UsageLimitsService(clock: clock);
      for (var i = 0; i < 5; i++) {
        await service.record(UsageKind.topic);
      }
      final state = await service.load();
      expect(state.canUse(UsageKind.topic), isTrue);
      expect(state.remaining(UsageKind.topic), isNull);
    });
  });

  group('ProStatusStore', () {
    test('a plan expires after its period', () async {
      final store = ProStatusStore(clock: clock);
      final status = await store.activate(ProPlan.monthly, paymentId: 'pay_1');
      expect(status.isPro, isTrue);
      expect(status.expiresAt, now.add(const Duration(days: 31)));

      now = now.add(const Duration(days: 30));
      expect((await store.load()).isPro, isTrue);
      now = now.add(const Duration(days: 1));
      expect((await store.load()).isPro, isFalse);
    });

    test('buying again while Pro stacks onto the current expiry', () async {
      final store = ProStatusStore(clock: clock);
      await store.activate(ProPlan.monthly);
      now = now.add(const Duration(days: 10));
      final status = await store.activate(ProPlan.yearly);
      expect(status.expiresAt, DateTime(2026, 10, 4, 10).add(const Duration(days: 31 + 366)));
      expect(status.plan, ProPlan.yearly);
    });

    test('Pro only applies to the account that bought it', () async {
      var user = 'alice';
      final store = ProStatusStore(clock: clock, currentUserId: () async => user);
      await store.activate(ProPlan.monthly);
      expect((await store.load()).isPro, isTrue);
      user = 'bob';
      expect((await store.load()).isPro, isFalse);
      user = 'alice';
      expect((await store.load()).isPro, isTrue);
    });

    test('legacy is_pro without a date is not Pro', () async {
      SharedPreferences.setMockInitialValues({'is_pro': true});
      expect((await ProStatusStore(clock: clock).load()).isPro, isFalse);
    });
  });
}
