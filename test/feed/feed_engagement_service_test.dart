import 'package:flutter_test/flutter_test.dart';
import 'package:quirzy/features/feed/services/feed_engagement_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late DateTime now;
  FeedEngagementService service() => FeedEngagementService(clock: () => now);

  setUp(() {
    now = DateTime(2026, 10, 4, 12);
    SharedPreferences.setMockInitialValues({});
  });

  test('signals add their weights and clamp at the limits', () async {
    final engagement = service();
    await engagement.load();
    engagement
      ..record('Physics', EngagementSignal.like)
      ..record('Physics', EngagementSignal.save);
    expect(engagement.interestOf('Physics'), closeTo(2.5, 1e-9));

    for (var i = 0; i < 10; i++) {
      engagement.record('Physics', EngagementSignal.save);
      engagement.record('Math', EngagementSignal.showLess);
    }
    expect(engagement.interestOf('Physics'), FeedEngagementService.maxInterest);
    expect(engagement.interestOf('Math'), -FeedEngagementService.maxInterest);
    await engagement.flush();
  });

  test('interest decays by 10% per day', () async {
    final engagement = service();
    await engagement.load();
    engagement.record('History', EngagementSignal.showLess);
    now = now.add(const Duration(days: 1));
    expect(engagement.interestOf('History'), closeTo(-2.7, 1e-9));
    now = now.add(const Duration(days: 1));
    expect(engagement.interestOf('History'), closeTo(-2.43, 1e-9));
    await engagement.flush();
  });

  test('flush persists interest, likes and seen log', () async {
    final first = service();
    await first.load();
    first
      ..record('Bio', EngagementSignal.like)
      ..setLiked('Bio|q1', true)
      ..markSeen('Bio|q1')
      ..markSeen('Bio|q1');
    await first.flush();

    final second = service();
    await second.load();
    expect(second.interestOf('Bio'), closeTo(1.0, 1e-9));
    expect(second.isLiked('Bio|q1'), isTrue);
    expect(second.seen['Bio|q1']?.count, 2);
    expect(second.seen['Bio|q1']?.lastSeenMs, now.millisecondsSinceEpoch);
  });

  test('seen entries for questions no longer in the pool are pruned', () async {
    final first = service();
    await first.load();
    first
      ..markSeen('Geo|kept')
      ..markSeen('Geo|gone');
    await first.flush();

    final second = service();
    await second.load(liveKeys: {'Geo|kept'});
    expect(second.seen.keys, ['Geo|kept']);
    await second.flush();
  });

  test('unliking removes the like', () async {
    final engagement = service();
    await engagement.load();
    engagement.setLiked('Chem|q', true);
    engagement.setLiked('Chem|q', false);
    expect(engagement.isLiked('Chem|q'), isFalse);
    await engagement.flush();
  });
}
