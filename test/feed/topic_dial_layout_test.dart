import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:quirzy/features/feed/models/topic_mastery.dart';
import 'package:quirzy/features/feed/services/feed_stats_service.dart';
import 'package:quirzy/features/feed/widgets/topic_dial_layout.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  const layout = DialLayout(size: Size(320, 560));

  group('DialLayout', () {
    test('the focused node bulges out further than its neighbours', () {
      final focus = layout.positionAt(0);
      expect(layout.positionAt(1).dx, lessThan(focus.dx));
      expect(layout.positionAt(-1).dx, lessThan(focus.dx));
      expect(focus.dy, closeTo(layout.size.height / 2, 0.001));
    });

    test('nodes above and below the focus are mirrored', () {
      final up = layout.positionAt(-2);
      final down = layout.positionAt(2);
      expect(up.dx, closeTo(down.dx, 0.001));
      expect(layout.size.height / 2 - up.dy, closeTo(down.dy - layout.size.height / 2, 0.001));
    });

    test('only nodes within the visible steps are drawn, shrinking and fading outwards', () {
      final nodes = layout.nodes(20, 10);
      expect(nodes.map((n) => n.index), [for (var i = 7; i <= 13; i++) i]);
      final focus = nodes.firstWhere((n) => n.index == 10);
      final edge = nodes.firstWhere((n) => n.index == 13);
      expect(focus.scale, 1);
      expect(focus.opacity, 1);
      expect(edge.scale, lessThan(focus.scale));
      expect(edge.opacity, lessThan(focus.opacity));
    });

    test('nodes never go past the first or last lane', () {
      expect(layout.nodes(3, 0).map((n) => n.index), [0, 1, 2]);
      expect(layout.nodes(1, 0).map((n) => n.index), [0]);
    });

    test('dragging up brings later lanes to the middle, clamped to the ends', () {
      final up = layout.focusAfterDrag(2, -layout.pixelsPerStep, 10);
      expect(up, closeTo(3, 0.001));
      expect(layout.focusAfterDrag(0, 500, 10), 0);
      expect(layout.focusAfterDrag(9, -500, 10), 9);
    });

    test('a fling settles on a whole lane in the direction of the fling', () {
      expect(layout.settleIndex(4.2, 0, 10), 4);
      expect(layout.settleIndex(4, -2000, 10), greaterThan(4));
      expect(layout.settleIndex(4, 2000, 10), lessThan(4));
      expect(layout.settleIndex(0, 5000, 10), 0);
    });
  });

  group('TopicMastery', () {
    TopicMastery of(int attempts, double accuracy) =>
        TopicMastery(topic: 'T', attempts: attempts, accuracy: accuracy);

    test('levels follow attempts and accuracy', () {
      expect(of(2, 100).level, MasteryLevel.fresh);
      expect(of(8, 40).level, MasteryLevel.learning);
      expect(of(12, 40).level, MasteryLevel.weak);
      expect(of(12, 75).level, MasteryLevel.solid);
      expect(of(30, 90).level, MasteryLevel.mastered);
      expect(of(12, 90).level, MasteryLevel.solid);
    });

    test('weak matches the My Weak Topics rule', () async {
      SharedPreferences.setMockInitialValues({});
      final stats = FeedStatsService();
      for (var i = 0; i < 12; i++) {
        await stats.recordAttempt('Art', i < 5);
      }
      final weak = await stats.getWeakTopics();
      final stat = (await stats.getTopicStats())['Art']!;
      final mastery = TopicMastery(topic: 'Art', attempts: stat.attempts, accuracy: stat.accuracy);
      expect(weak.contains('Art'), mastery.level == MasteryLevel.weak);
    });

    test('last practised reads naturally', () {
      final now = DateTime(2026, 10, 27, 15);
      String label(DateTime? at) => TopicMastery(topic: 'T', lastPracticed: at).lastPractisedLabel(now);
      expect(label(null), 'Not yet');
      expect(label(DateTime(2026, 10, 27, 1)), 'Today');
      expect(label(DateTime(2026, 10, 26, 23)), 'Yesterday');
      expect(label(DateTime(2026, 10, 24)), '3 days ago');
      expect(label(DateTime(2026, 10, 1)), '3 weeks ago');
    });
  });

  group('FeedStatsService', () {
    test('records when a topic was last answered and keeps older saves readable', () async {
      SharedPreferences.setMockInitialValues({
        'feed_topic_stats': '{"Old":{"attempts":4,"correct":3}}',
      });
      final stats = FeedStatsService();
      expect((await stats.getTopicStats())['Old']!.lastPracticed, isNull);

      final when = DateTime(2026, 10, 27, 9, 30);
      await stats.recordAttempt('Art', true, now: when);
      await stats.recordAttempt('Old', false, now: when);
      final all = await stats.getTopicStats();
      expect(all['Art']!.lastPracticed, when);
      expect(all['Old']!.attempts, 5);
      expect(all['Old']!.correct, 3);
      expect(all['Old']!.lastPracticed, when);
    });
  });
}
