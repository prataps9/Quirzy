import 'dart:math' as math;

import '../models/feed_models.dart';
import 'feed_stats_service.dart' show TopicStat;

/// One card chosen by [FeedRanker], with the reason shown on it.
class RankedPick {
  final PracticeQuestion question;
  final String reason;

  /// Seen before and not due for revision, i.e. fresh questions ran out.
  final bool recycled;

  const RankedPick(this.question, this.reason, {this.recycled = false});
}

class RankedBatch {
  final List<RankedPick> picks;

  /// Unseen questions still available after this batch.
  final int unseenRemaining;

  const RankedBatch(this.picks, {required this.unseenRemaining});
}

/// The slow-changing inputs to ranking, gathered by the controller.
class RankerSnapshot {
  /// Eligible questions: reported ones and hidden topics already removed.
  final List<PracticeQuestion> pool;
  final Set<String> tooEasyIds;
  final Map<String, double> interest;
  final Map<String, TopicStat> topicStats;
  final Map<String, SeenRecord> seen;
  final Set<String> dueKeys;

  const RankerSnapshot({
    required this.pool,
    this.tooEasyIds = const {},
    this.interest = const {},
    this.topicStats = const {},
    this.seen = const {},
    this.dueKeys = const {},
  });
}

/// What the ranker remembers within one app session: what's been queued,
/// in which order, and the user's in-the-moment reactions per topic.
class RankerSession {
  static const _maxHistory = 500;

  final Set<String> _queued = {};
  final List<({String key, String topic})> _order = [];

  /// Consecutive quick swipe-pasts per topic; reset by any engagement.
  final Map<String, int> quickPassStreak = {};

  /// Likes given per topic this session.
  final Map<String, int> likes = {};

  bool isQueued(String engagementKey) => _queued.contains(engagementKey);

  void enqueue(PracticeQuestion question) {
    _queued.add(question.engagementKey);
    _order.add((key: question.engagementKey, topic: question.topicName));
    if (_order.length > _maxHistory) _order.removeAt(0);
  }

  /// Returns dropped, never-viewed cards to the candidate pool.
  void release(Iterable<String> engagementKeys) {
    for (final key in engagementKeys) {
      _queued.remove(key);
      final index = _order.lastIndexWhere((entry) => entry.key == key);
      if (index >= 0) _order.removeAt(index);
    }
  }

  /// Lets shown questions come back, except the [keepRecent] most recent.
  void recycle({required int keepRecent}) {
    final start = math.max(0, _order.length - keepRecent);
    _queued
      ..clear()
      ..addAll(_order.skip(start).map((entry) => entry.key));
  }

  void reset() {
    _queued.clear();
    _order.clear();
  }

  List<String> recentTopics(int count) => _order
      .skip(math.max(0, _order.length - count))
      .map((entry) => entry.topic)
      .toList();
}

/// Picks the next cards for the For You feed from what the user does.
///
/// Topics the user engages with (likes, saves, answers) get more slots;
/// topics they swipe straight past fade out within the session; weak
/// topics get a nudge; a share of slots explores less-seen topics and
/// due revision. Fresh questions come first, then the least recently
/// seen ones, so the feed can recycle forever without back-to-back
/// repeats.
class FeedRanker {
  FeedRanker({math.Random? random, DateTime Function()? clock})
    : _random = random ?? math.Random(),
      _clock = clock ?? DateTime.now;

  static const explorationRate = 0.15;
  static const repeatWindow = 20;
  static const _revisionSlotEvery = 5;
  static const _exposureWindow = Duration(days: 7);

  final math.Random _random;
  final DateTime Function() _clock;

  RankedBatch nextBatch(
    RankerSnapshot snapshot,
    RankerSession session, {
    int size = 8,
    bool allowRecycle = true,
  }) {
    final exposure = _topicExposure(snapshot);
    final picks = <RankedPick>[];
    var candidates = _candidates(snapshot, session);
    var recycled = false;

    for (var slot = 0; slot < size; slot++) {
      if (candidates.isEmpty) {
        if (!allowRecycle || recycled || snapshot.pool.length < 2) break;
        recycled = true;
        // Holding back half the pool (at least the last card) prevents
        // back-to-back repeats without replaying a small pool in a fixed
        // order every time.
        session.recycle(
          keepRecent: math.min(
            repeatWindow,
            math.max(1, snapshot.pool.length ~/ 2),
          ),
        );
        candidates = _candidates(snapshot, session);
        if (candidates.isEmpty) break;
      }
      final pick = _pickOne(snapshot, session, candidates, exposure, slot);
      picks.add(pick);
      session.enqueue(pick.question);
      final topicList = candidates[pick.question.topicName]!
        ..remove(pick.question);
      if (topicList.isEmpty) candidates.remove(pick.question.topicName);
    }

    final unseenRemaining = candidates.values
        .expand((list) => list)
        .where((q) => !snapshot.seen.containsKey(q.engagementKey))
        .length;
    return RankedBatch(picks, unseenRemaining: unseenRemaining);
  }

  Map<String, List<PracticeQuestion>> _candidates(
    RankerSnapshot snapshot,
    RankerSession session,
  ) {
    final available = snapshot.pool
        .where((q) => !session.isQueued(q.engagementKey))
        .toList();
    final preferred = available
        .where((q) => !snapshot.tooEasyIds.contains(q.id))
        .toList();
    final chosen = preferred.isNotEmpty ? preferred : available;
    final byTopic = <String, List<PracticeQuestion>>{};
    for (final question in chosen) {
      byTopic.putIfAbsent(question.topicName, () => []).add(question);
    }
    return byTopic;
  }

  Map<String, int> _topicExposure(RankerSnapshot snapshot) {
    final since = _clock().subtract(_exposureWindow).millisecondsSinceEpoch;
    final exposure = <String, int>{};
    for (final question in snapshot.pool) {
      final record = snapshot.seen[question.engagementKey];
      final count = record != null && record.lastSeenMs >= since
          ? record.count
          : 0;
      exposure.update(
        question.topicName,
        (value) => value + count,
        ifAbsent: () => count,
      );
    }
    return exposure;
  }

  RankedPick _pickOne(
    RankerSnapshot snapshot,
    RankerSession session,
    Map<String, List<PracticeQuestion>> candidates,
    Map<String, int> exposure,
    int slot,
  ) {
    if (slot % _revisionSlotEvery == 2) {
      final due = candidates.values
          .expand((list) => list)
          .where((q) => snapshot.dueKeys.contains(q.engagementKey))
          .toList();
      if (due.isNotEmpty) {
        return RankedPick(due[_random.nextInt(due.length)], 'Revision due');
      }
    }

    final topics = candidates.keys.toList();
    if (topics.length > 1 && _random.nextDouble() < explorationRate) {
      final topic = _leastExposed(topics, exposure);
      final question = _questionFrom(candidates[topic]!, snapshot);
      final reason = (exposure[topic] ?? 0) == 0
          ? 'New for you'
          : 'Something different';
      return _withRecycleReason(question, reason, snapshot);
    }

    final topic = _weightedChoice({
      for (final topic in topics)
        topic: _topicWeight(topic, snapshot, session, candidates[topic]!),
    });
    final question = _questionFrom(candidates[topic]!, snapshot);
    return _withRecycleReason(
      question,
      _reasonFor(topic, snapshot, session),
      snapshot,
    );
  }

  RankedPick _withRecycleReason(
    PracticeQuestion question,
    String reason,
    RankerSnapshot snapshot,
  ) {
    final key = question.engagementKey;
    if (snapshot.dueKeys.contains(key)) {
      return RankedPick(question, 'Revision due');
    }
    if (snapshot.seen.containsKey(key)) {
      return RankedPick(question, 'Worth another look', recycled: true);
    }
    return RankedPick(question, reason);
  }

  double _topicWeight(
    String topic,
    RankerSnapshot snapshot,
    RankerSession session,
    List<PracticeQuestion> candidates,
  ) {
    final interest = (snapshot.interest[topic] ?? 0).clamp(-6.0, 6.0);
    var weight = math.exp(0.35 * interest);
    if (_needsPractice(snapshot.topicStats[topic])) weight *= 1.5;
    final hasUnseen = candidates.any(
      (q) => !snapshot.seen.containsKey(q.engagementKey),
    );
    if (!hasUnseen) weight *= 0.5;
    weight *= math.pow(0.5, session.quickPassStreak[topic] ?? 0);
    weight *= math.min(2.5, math.pow(1.3, session.likes[topic] ?? 0));
    final recent = session.recentTopics(3);
    if (recent.length == 3 && recent.every((t) => t == topic)) weight *= 0.2;
    return weight;
  }

  bool _needsPractice(TopicStat? stat) =>
      stat != null && stat.attempts >= 5 && stat.accuracy < 60;

  String _reasonFor(
    String topic,
    RankerSnapshot snapshot,
    RankerSession session,
  ) {
    if ((session.likes[topic] ?? 0) > 0) return 'Because you liked $topic';
    if (_needsPractice(snapshot.topicStats[topic])) {
      return "Practice where you're weak";
    }
    return 'Suggested for you';
  }

  String _leastExposed(List<String> topics, Map<String, int> exposure) {
    final lowest = topics
        .map((topic) => exposure[topic] ?? 0)
        .reduce(math.min);
    final tied = topics.where((t) => (exposure[t] ?? 0) == lowest).toList();
    return tied[_random.nextInt(tied.length)];
  }

  PracticeQuestion _questionFrom(
    List<PracticeQuestion> candidates,
    RankerSnapshot snapshot,
  ) {
    final unseen = candidates
        .where((q) => !snapshot.seen.containsKey(q.engagementKey))
        .toList();
    if (unseen.isNotEmpty) return unseen[_random.nextInt(unseen.length)];
    return candidates.reduce(
      (a, b) =>
          snapshot.seen[a.engagementKey]!.lastSeenMs <=
              snapshot.seen[b.engagementKey]!.lastSeenMs
          ? a
          : b,
    );
  }

  String _weightedChoice(Map<String, double> weights) {
    final total = weights.values.fold<double>(0, (sum, w) => sum + w);
    var target = _random.nextDouble() * total;
    for (final entry in weights.entries) {
      target -= entry.value;
      if (target <= 0) return entry.key;
    }
    return weights.keys.last;
  }
}
