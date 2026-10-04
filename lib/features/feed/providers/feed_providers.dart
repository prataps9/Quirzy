import 'dart:async';
import 'dart:math' as math;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../home/providers/home_stats_provider.dart';
import '../models/feed_models.dart';
import '../services/feed_bookmark_service.dart';
import '../services/feed_engagement_service.dart';
import '../services/feed_ranker.dart';
import '../services/feed_revision_service.dart';
import '../services/feed_stats_service.dart';
import '../services/practice_content_service.dart';
import '../services/streak_service.dart';
import '../services/xp_service.dart';

const int kFeedDailyTarget = 50;
const int kFeedBreakNudgeMinutes = 25;

/// Below this many eligible questions For You plays through once instead
/// of recycling, so a tiny pool never loops on the same few cards.
const int kMinInfinitePool = 12;

/// Leaving an unanswered card faster than this counts as a quick pass.
const Duration kQuickPass = Duration(seconds: 2);

const int _batchSize = 8;
const int _appendThreshold = 3;

final feedStatsServiceProvider = Provider<FeedStatsService>((ref) => FeedStatsService());
final feedBookmarkServiceProvider = Provider<FeedBookmarkService>((ref) => FeedBookmarkService());
final feedRevisionServiceProvider = Provider<FeedRevisionService>((ref) => FeedRevisionService());
final feedRankerProvider = Provider<FeedRanker>((ref) => FeedRanker());

/// The full local question pool the feed draws from — see
/// PracticeContentService.
final feedQuestionPoolProvider = FutureProvider<List<PracticeQuestion>>((ref) async {
  final service = ref.watch(practiceContentServiceProvider);
  return service.getQuestionPool();
});

/// Lanes available in the Lane Switcher, derived from per-topic storage +
/// local stats/bookmarks/revision state.
final feedLanesProvider = FutureProvider<List<FeedLane>>((ref) async {
  final contentService = ref.watch(practiceContentServiceProvider);
  final stats = ref.watch(feedStatsServiceProvider);
  final bookmarks = ref.watch(feedBookmarkServiceProvider);
  final revision = ref.watch(feedRevisionServiceProvider);

  final topicSummaries = await contentService.getTopicSummaries();
  final muted = await stats.getMutedTopics();

  final topicLanes = topicSummaries
      .where((t) => t.count > 0 && !muted.contains(t.topic))
      .map((t) => FeedLane(
            type: FeedLaneType.topic,
            id: 'topic:${t.topic}',
            label: t.topic,
            count: t.count,
            downloaded: t.downloaded,
          ))
      .toList()
    ..sort((a, b) => b.count.compareTo(a.count));

  final weakTopics = await stats.getWeakTopics();
  final dueCount = await revision.getDueCount();
  final bookmarkCount = await bookmarks.getCount();

  return [
    FeedLane.forYou,
    if (dueCount > 0)
      FeedLane(type: FeedLaneType.revision, id: 'revision', label: 'Revision Vault', count: dueCount),
    if (weakTopics.isNotEmpty)
      FeedLane(type: FeedLaneType.weakTopics, id: 'weak', label: 'My Weak Topics', count: weakTopics.length),
    if (bookmarkCount > 0)
      FeedLane(type: FeedLaneType.bookmarks, id: 'bookmarks', label: 'Saved', count: bookmarkCount),
    ...topicLanes,
  ];
});

/// Topics hidden from the feed, for the lane switcher's Unhide list.
final hiddenTopicsProvider = FutureProvider<List<String>>((ref) async {
  final muted = await ref.watch(feedStatsServiceProvider).getMutedTopics();
  return muted.toList()..sort();
});

/// One circle in Home's "Your topics" row.
class TopicStory {
  final String topic;
  final int count;
  final bool hasUnseen;

  const TopicStory({
    required this.topic,
    required this.count,
    required this.hasUnseen,
  });
}

/// Your topics, ones with unseen questions first (they get a ring).
final topicStoriesProvider = FutureProvider<List<TopicStory>>((ref) async {
  final lanes = await ref.watch(feedLanesProvider.future);
  final pool = await ref.watch(feedQuestionPoolProvider.future);
  final engagement = ref.watch(feedEngagementServiceProvider);
  await engagement.load();
  final seen = engagement.seen;
  final topicsWithUnseen = pool
      .where((q) => !seen.containsKey(q.engagementKey))
      .map((q) => q.topicName)
      .toSet();
  return lanes
      .where((lane) => lane.type == FeedLaneType.topic)
      .map((lane) => TopicStory(
            topic: lane.label,
            count: lane.count,
            hasUnseen: topicsWithUnseen.contains(lane.label),
          ))
      .toList()
    ..sort((a, b) {
      if (a.hasUnseen != b.hasUnseen) return a.hasUnseen ? -1 : 1;
      return b.count.compareTo(a.count);
    });
});

final feedControllerProvider = NotifierProvider<FeedController, FeedState>(FeedController.new);

/// Drives the practice feed.
///
/// For You is an endless, ranked feed that adapts within the session:
/// liking a card, asking for less of a topic, or swiping quickly past
/// two cards of one topic re-ranks everything after the current card,
/// so the very next swipe reflects it. Other lanes are finite lists.
/// Answers also feed the existing stats, revision vault and XP.
class FeedController extends Notifier<FeedState> {
  List<PracticeQuestion> _fullPool = [];
  final RankerSession _session = RankerSession();
  final Stopwatch _dwell = Stopwatch();

  List<PracticeQuestion> _eligible = [];
  Set<String> _muted = {};
  Set<String> _tooEasy = {};
  Set<String> _bookmarkedIds = {};
  Set<String> _dueKeys = {};
  Map<String, TopicStat> _topicStats = {};

  int _nextUid = 0;
  int _rewardId = 0;
  int? _activeIndex;
  bool _tabVisible = true;
  bool _appResumed = true;
  bool _visible = true;
  bool _refillPending = false;
  bool _caughtUpNotified = false;

  /// Set by the feed screen so re-ranking waits until scrolling settles.
  bool Function() isScrollIdle = () => true;

  FeedEngagementService get _engagement => ref.read(feedEngagementServiceProvider);
  FeedRanker get _ranker => ref.read(feedRankerProvider);
  FeedStatsService get _stats => ref.read(feedStatsServiceProvider);
  bool get _tinyPool => _eligible.length < kMinInfinitePool;

  @override
  FeedState build() {
    Future.microtask(_init);
    return FeedState.initial();
  }

  Future<void> _init() async {
    try {
      _fullPool = await ref.read(feedQuestionPoolProvider.future);
      await _engagement.load(
        liveKeys: _fullPool.map((q) => q.engagementKey).toSet(),
      );

      final prefs = await SharedPreferences.getInstance();
      final focusMode = prefs.getBool('feed_focus_mode') ?? false;
      final showHints = !(prefs.getBool('feed_hint_dismissed') ?? false);
      final todayAnswered = await _stats.getTodayAnsweredCount();
      state = state.copyWith(
        focusMode: focusMode,
        showHints: showHints,
        todayAnswered: todayAnswered,
        dailyTargetCelebrated: todayAnswered >= kFeedDailyTarget,
      );

      final lane = _restoredLane(prefs);
      await switchLane(lane, restorePosition: true);
      if (state.cards.isEmpty && !lane.isInfinite) {
        await switchLane(FeedLane.forYou);
      }
    } catch (e) {
      state = state.copyWith(loading: false, error: e.toString());
    }
  }

  FeedLane _restoredLane(SharedPreferences prefs) {
    final typeName = prefs.getString('feed_last_lane_type');
    final type = FeedLaneType.values.firstWhere(
      (t) => t.name == typeName,
      orElse: () => FeedLaneType.forYou,
    );
    if (type == FeedLaneType.forYou) return FeedLane.forYou;
    return FeedLane(
      type: type,
      id: prefs.getString('feed_last_lane_id') ?? FeedLane.forYou.id,
      label: prefs.getString('feed_last_lane_label') ?? FeedLane.forYou.label,
    );
  }

  Future<void> _refreshInputs() async {
    final reported = await _stats.getReportedQuestions();
    _muted = await _stats.getMutedTopics();
    _tooEasy = await _stats.getDeprioritizedQuestions();
    _topicStats = await _stats.getTopicStats();
    _bookmarkedIds = await ref.read(feedBookmarkServiceProvider).getBookmarkedIds();
    final due = await ref.read(feedRevisionServiceProvider).getDueQuestions();
    _dueKeys = due.map((q) => q.engagementKey).toSet();
    _eligible = _fullPool
        .where((q) => !reported.contains(q.id) && !_muted.contains(q.topicName))
        .toList();
  }

  RankerSnapshot _snapshot() => RankerSnapshot(
        pool: _eligible,
        tooEasyIds: _tooEasy,
        interest: _engagement.interestSnapshot(),
        topicStats: _topicStats,
        seen: _engagement.seen,
        dueKeys: _dueKeys,
      );

  FeedCardState _card(PracticeQuestion question, {String? reason, bool pinned = false}) {
    return FeedCardState(
      uid: _nextUid++,
      question: question,
      bookmarked: _bookmarkedIds.contains(question.id),
      liked: _engagement.isLiked(question.engagementKey),
      reason: reason,
      pinned: pinned,
    );
  }

  List<FeedCardState> _cardsFrom(RankedBatch batch) =>
      batch.picks.map((p) => _card(p.question, reason: p.reason)).toList();

  /// True the first time this session that fresh questions have run out.
  bool _caughtUpNow(RankedBatch batch) {
    if (_caughtUpNotified) return false;
    if (batch.unseenRemaining > 0 || !batch.picks.any((p) => p.recycled)) return false;
    _caughtUpNotified = true;
    return true;
  }

  Future<List<PracticeQuestion>> _questionsForLane(FeedLane lane) async {
    switch (lane.type) {
      case FeedLaneType.forYou:
        return const [];
      case FeedLaneType.topic:
        return _freshFirst(_eligible.where((q) => q.topicName == lane.label));
      case FeedLaneType.weakTopics:
        final weak = await _stats.getWeakTopics();
        return _freshFirst(_eligible.where((q) => weak.contains(q.topicName)));
      case FeedLaneType.revision:
        return ref.read(feedRevisionServiceProvider).getDueQuestions();
      case FeedLaneType.bookmarks:
        return ref.read(feedBookmarkServiceProvider).getBookmarks();
    }
  }

  /// Unseen questions (shuffled) first, then the least recently seen.
  List<PracticeQuestion> _freshFirst(Iterable<PracticeQuestion> questions) {
    final seen = _engagement.seen;
    final unseen = questions.where((q) => !seen.containsKey(q.engagementKey)).toList()..shuffle();
    final seenBefore = questions.where((q) => seen.containsKey(q.engagementKey)).toList()
      ..sort((a, b) => seen[a.engagementKey]!.lastSeenMs.compareTo(seen[b.engagementKey]!.lastSeenMs));
    return [...unseen, ...seenBefore];
  }

  Future<void> switchLane(FeedLane lane, {bool restorePosition = false}) async {
    _closeActive();
    if (state.lane.isInfinite) _releaseAfter(_activeIndex ?? -1);
    _activeIndex = null;
    _refillPending = false;
    unawaited(_engagement.flush());

    final target = lane.isInfinite ? FeedLane.forYou : lane;
    state = state.copyWith(loading: true, lane: target);
    await _refreshInputs();

    var cards = <FeedCardState>[];
    var hasMore = false;
    var caughtUp = false;
    if (target.isInfinite) {
      if (_tinyPool) _session.reset();
      final batch = _ranker.nextBatch(
        _snapshot(),
        _session,
        size: _tinyPool ? _eligible.length : _batchSize,
        allowRecycle: !_tinyPool,
      );
      cards = _cardsFrom(batch);
      hasMore = !_tinyPool && batch.picks.isNotEmpty;
      caughtUp = _caughtUpNow(batch);
    } else {
      cards = (await _questionsForLane(target)).map((q) => _card(q)).toList();
    }

    final prefs = await SharedPreferences.getInstance();
    var startIndex = 0;
    if (restorePosition && !target.isInfinite) {
      final ts = prefs.getInt('feed_lane_ts_${target.id}');
      if (ts != null && DateTime.now().millisecondsSinceEpoch - ts < const Duration(hours: 24).inMilliseconds) {
        final saved = prefs.getInt('feed_lane_pos_${target.id}') ?? 0;
        startIndex = cards.isEmpty ? 0 : saved.clamp(0, cards.length - 1);
      }
    }

    await prefs.setString('feed_last_lane_id', target.id);
    await prefs.setString('feed_last_lane_label', target.label);
    await prefs.setString('feed_last_lane_type', target.type.name);

    state = state.copyWith(
      lane: target,
      cards: cards,
      loading: false,
      startIndex: startIndex,
      laneEpoch: state.laneEpoch + 1,
      hasMore: hasMore,
      allTopicsHidden: _fullPool.isNotEmpty && _muted.isNotEmpty && _eligible.isEmpty,
      pendingCaughtUpNotice: caughtUp ? true : null,
    );
    ref.invalidate(topicStoriesProvider);
  }

  /// Fresh ranking for For You (tapping its title, or "Go again").
  Future<void> refreshForYou() => switchLane(FeedLane.forYou);

  Future<void> reshuffleCurrentLane() => switchLane(state.lane);

  /// Refreshes the pool from storage (picking up questions just added
  /// elsewhere, e.g. a freshly generated/added topic) and switches straight
  /// to a lane for [topic].
  Future<void> switchToTopic(String topic) async {
    _fullPool = await ref.refresh(feedQuestionPoolProvider.future);
    ref.invalidate(feedLanesProvider);
    await switchLane(FeedLane(type: FeedLaneType.topic, id: 'topic:$topic', label: topic));
  }

  /// Called when scrolling settles on [index]: closes the previous card's
  /// dwell, marks this one seen, and tops up or re-ranks the feed.
  void activate(int index) {
    if (index == _activeIndex) return;
    _closeActive();
    _activeIndex = index;
    if (index < 0 || index >= state.cards.length) return;

    _engagement.markSeen(state.cards[index].question.engagementKey);
    _dwell.reset();
    if (_visible) _dwell.start();
    if (_refillPending) {
      _refillPending = false;
      _refillAfter(index);
    }
    _maybeAppend(index);
  }

  /// Whether the Practice tab is the one on screen.
  void setTabVisible(bool visible) {
    _tabVisible = visible;
    _syncDwell();
  }

  /// Whether the app is in the foreground.
  void setAppResumed(bool resumed) {
    _appResumed = resumed;
    _syncDwell();
  }

  /// Dwell only counts while the feed is actually on screen; leaving it
  /// also saves pending signals.
  void _syncDwell() {
    final visible = _tabVisible && _appResumed;
    if (visible == _visible) return;
    _visible = visible;
    if (visible && _activeIndex != null) {
      _dwell.start();
    } else {
      _dwell.stop();
      unawaited(_engagement.flush());
    }
  }

  void _closeActive() {
    _dwell.stop();
    final index = _activeIndex;
    if (index == null || index < 0 || index >= state.cards.length) return;
    final card = state.cards[index];
    if (card.isResolved || card.liked) return;

    final topic = card.question.topicName;
    if (_dwell.elapsed < kQuickPass) {
      _engagement.record(topic, EngagementSignal.quickPass);
      final streak = (_session.quickPassStreak[topic] ?? 0) + 1;
      _session.quickPassStreak[topic] = streak;
      if (streak >= 2 && state.lane.isInfinite) _refillPending = true;
    } else {
      _session.quickPassStreak[topic] = 0;
    }
  }

  void _releaseAfter(int index) {
    _session.release(
      state.cards.skip(index + 1).map((c) => c.question.engagementKey),
    );
  }

  void _maybeAppend(int index) {
    if (!state.lane.isInfinite || !state.hasMore) return;
    if (index < state.cards.length - _appendThreshold) return;
    final batch = _ranker.nextBatch(_snapshot(), _session, size: _batchSize);
    final caughtUp = _caughtUpNow(batch);
    state = state.copyWith(
      cards: [...state.cards, ..._cardsFrom(batch)],
      hasMore: batch.picks.isNotEmpty,
      pendingCaughtUpNotice: caughtUp ? true : null,
    );
  }

  /// Re-ranks every card after [index], keeping pinned ones, so the next
  /// swipe reflects what the user just did. Waits for scrolling to stop.
  void _refillAfter(int index) {
    if (!state.lane.isInfinite || index < 0) return;
    if (!isScrollIdle()) {
      _refillPending = true;
      return;
    }
    final kept = state.cards.take(index + 1).toList();
    final tail = state.cards.skip(index + 1);
    final pinned = tail.takeWhile((c) => c.pinned).toList();
    _session.release(
      tail.skip(pinned.length).map((c) => c.question.engagementKey),
    );
    final batch = _ranker.nextBatch(
      _snapshot(),
      _session,
      size: _tinyPool ? _eligible.length : _batchSize,
      allowRecycle: !_tinyPool,
    );
    final caughtUp = _caughtUpNow(batch);
    state = state.copyWith(
      cards: [...kept, ...pinned, ..._cardsFrom(batch)],
      hasMore: !_tinyPool && batch.picks.isNotEmpty,
      pendingCaughtUpNotice: caughtUp ? true : null,
    );
  }

  void _refillAfterActive() {
    final index = _activeIndex;
    if (index != null) _refillAfter(index);
  }

  Future<void> savePosition(int index) async {
    if (state.lane.isInfinite) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('feed_lane_pos_${state.lane.id}', index);
    await prefs.setInt('feed_lane_ts_${state.lane.id}', DateTime.now().millisecondsSinceEpoch);
  }

  Future<void> setFocusMode(bool value) async {
    state = state.copyWith(focusMode: value);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('feed_focus_mode', value);
  }

  Future<void> dismissHints() async {
    if (!state.showHints) return;
    state = state.copyWith(showHints: false);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('feed_hint_dismissed', true);
  }

  Future<void> selectOption(int index, int optionIndex) async {
    if (index < 0 || index >= state.cards.length) return;
    final card = state.cards[index];
    if (card.isResolved) return;

    final correct = optionIndex == card.question.correctIndex;
    final combo = correct ? state.combo + 1 : 0;
    final cards = List<FeedCardState>.from(state.cards);
    cards[index] = card.copyWith(selectedOption: optionIndex);
    state = state.copyWith(
      cards: cards,
      combo: combo,
      sessionAnswered: state.sessionAnswered + 1,
      sessionCorrect: state.sessionCorrect + (correct ? 1 : 0),
    );

    final topic = card.question.topicName;
    _engagement.record(topic, EngagementSignal.answered);
    _session.quickPassStreak[topic] = 0;
    final stat = _topicStats[topic] ?? const TopicStat();
    _topicStats[topic] = TopicStat(
      attempts: stat.attempts + 1,
      correct: stat.correct + (correct ? 1 : 0),
    );

    await ref.read(feedStatsServiceProvider).recordAttempt(card.question.topic, correct);
    await ref.read(feedRevisionServiceProvider).recordOutcome(card.question, correct);

    var leveledUpTo = 0;
    final milestone = correct && combo % kFeedComboMilestone == 0;
    if (correct) {
      final xp = ref.read(xpServiceProvider);
      final levelBefore = (await xp.getLevel()).level;
      await xp.addXPToday(kFeedXpPerCorrect + (milestone ? kFeedComboBonusXp : 0));
      final levelAfter = (await xp.getLevel()).level;
      if (levelAfter > levelBefore) leveledUpTo = levelAfter;
    }

    final attempt = await _afterAttempt();
    await _emitBestReward(
      leveledUpTo: leveledUpTo,
      goalReached: attempt.goalReached,
      comboMilestone: milestone ? combo : 0,
      firstOfDay: attempt.firstOfDay,
    );
  }

  /// Reveals the answer without answering ("Skip" / "Show answer").
  Future<void> skipCurrent(int index) async {
    if (index < 0 || index >= state.cards.length) return;
    final card = state.cards[index];
    if (card.isResolved) return;

    final cards = List<FeedCardState>.from(state.cards);
    cards[index] = card.copyWith(skipped: true);
    state = state.copyWith(cards: cards, sessionAnswered: state.sessionAnswered + 1);
    _session.quickPassStreak[card.question.topicName] = 0;

    final attempt = await _afterAttempt();
    await _emitBestReward(
      leveledUpTo: 0,
      goalReached: attempt.goalReached,
      comboMilestone: 0,
      firstOfDay: attempt.firstOfDay,
    );
  }

  /// Counts the attempt towards today and refreshes everything that shows
  /// the streak, XP or daily goal.
  Future<({bool firstOfDay, bool goalReached})> _afterAttempt() async {
    final prefs = await SharedPreferences.getInstance();
    final key = StreakService.countKey(DateTime.now());
    final before = prefs.getInt(key) ?? 0;
    final count = before + 1;
    await prefs.setInt(key, count);

    final goalReached =
        before < kFeedDailyTarget && count >= kFeedDailyTarget && !state.dailyTargetCelebrated;
    state = state.copyWith(
      todayAnswered: count,
      dailyTargetCelebrated: goalReached ? true : null,
    );

    final elapsedMinutes = DateTime.now().difference(state.sessionStart).inMinutes;
    if (elapsedMinutes >= kFeedBreakNudgeMinutes && !state.breakNudgeShown) {
      state = state.copyWith(breakNudgeShown: true, pendingBreakNudge: true);
    }

    ref.invalidate(streakProvider);
    ref.invalidate(homeStatsProvider);
    ref.invalidate(xpTotalProvider);
    return (firstOfDay: before == 0, goalReached: goalReached);
  }

  /// Shows at most one celebration per answer, most special first.
  Future<void> _emitBestReward({
    required int leveledUpTo,
    required bool goalReached,
    required int comboMilestone,
    required bool firstOfDay,
  }) async {
    if (leveledUpTo > 0) {
      _emitReward(FeedRewardKind.levelUp, leveledUpTo);
    } else if (goalReached) {
      _emitReward(FeedRewardKind.dailyGoal, kFeedDailyTarget);
    } else if (comboMilestone > 0) {
      _emitReward(FeedRewardKind.comboMilestone, comboMilestone);
    } else if (firstOfDay) {
      final streak = await ref.read(streakServiceProvider).getStreak();
      _emitReward(FeedRewardKind.streak, streak.current);
    }
  }

  void _emitReward(FeedRewardKind kind, int value) {
    state = state.copyWith(
      reward: FeedReward(id: ++_rewardId, kind: kind, value: value),
    );
  }

  void acknowledgeBreakNudge() {
    state = state.copyWith(pendingBreakNudge: false);
  }

  void acknowledgeCaughtUpNotice() {
    state = state.copyWith(pendingCaughtUpNotice: false);
  }

  /// Double-tap: like only, never unlike.
  void like(int index) {
    if (index < 0 || index >= state.cards.length) return;
    if (!state.cards[index].liked) _setLiked(index, true);
  }

  void toggleLike(int index) {
    if (index < 0 || index >= state.cards.length) return;
    _setLiked(index, !state.cards[index].liked);
  }

  void _setLiked(int index, bool liked) {
    final card = state.cards[index];
    final topic = card.question.topicName;
    final cards = List<FeedCardState>.from(state.cards);
    cards[index] = card.copyWith(liked: liked);
    state = state.copyWith(cards: cards);

    _engagement
      ..setLiked(card.question.engagementKey, liked)
      ..record(topic, liked ? EngagementSignal.like : EngagementSignal.unlike);
    if (liked) {
      _session.likes.update(topic, (n) => n + 1, ifAbsent: () => 1);
      _session.quickPassStreak[topic] = 0;
      _refillAfterActive();
    } else {
      _session.likes.update(topic, (n) => math.max(0, n - 1), ifAbsent: () => 0);
    }
  }

  Future<void> toggleBookmark(int index) async {
    if (index < 0 || index >= state.cards.length) return;
    final card = state.cards[index];
    final newValue = !card.bookmarked;

    final cards = List<FeedCardState>.from(state.cards);
    cards[index] = card.copyWith(bookmarked: newValue);
    state = state.copyWith(cards: cards);

    final bookmarks = ref.read(feedBookmarkServiceProvider);
    if (newValue) {
      _bookmarkedIds.add(card.question.id);
      _engagement.record(card.question.topicName, EngagementSignal.save);
      await bookmarks.addBookmark(card.question);
    } else {
      _bookmarkedIds.remove(card.question.id);
      await bookmarks.removeBookmark(card.question.id);
    }
    ref.invalidate(feedLanesProvider);
  }

  void recordExplanationOpened(PracticeQuestion question) {
    _engagement.record(question.topicName, EngagementSignal.explanationOpened);
    _session.quickPassStreak[question.topicName] = 0;
  }

  /// Soft negative: the topic still appears, just much less.
  void showLessOf(String topic) {
    _engagement.record(topic, EngagementSignal.showLess);
    _session.likes.remove(topic);
    _session.quickPassStreak[topic] = math.max(2, _session.quickPassStreak[topic] ?? 0);
    _refillAfterActive();
  }

  void undoShowLess(String topic) {
    _engagement.record(topic, EngagementSignal.undoShowLess);
    _session.quickPassStreak[topic] = 0;
    _refillAfterActive();
  }

  /// Hides [topic] from every lane until unhidden.
  Future<void> muteTopic(String topic) async {
    await _stats.muteTopic(topic);
    await _refreshInputs();
    _refillAfterActive();
    ref.invalidate(feedLanesProvider);
    ref.invalidate(hiddenTopicsProvider);
  }

  Future<void> unmuteTopic(String topic) async {
    await _stats.unmuteTopic(topic);
    await _refreshInputs();
    ref.invalidate(feedLanesProvider);
    ref.invalidate(hiddenTopicsProvider);
    if (state.cards.isEmpty) {
      await switchLane(FeedLane.forYou);
    } else {
      _refillAfterActive();
    }
  }

  Future<void> unmuteAllTopics() async {
    for (final topic in await _stats.getMutedTopics()) {
      await _stats.unmuteTopic(topic);
    }
    ref.invalidate(feedLanesProvider);
    ref.invalidate(hiddenTopicsProvider);
    await switchLane(FeedLane.forYou);
  }

  Future<void> reportQuestion(String questionId) async {
    await ref.read(feedStatsServiceProvider).reportQuestion(questionId);
    await _refreshInputs();
    ref.invalidate(feedLanesProvider);
  }

  Future<void> markTooEasy(PracticeQuestion question) async {
    _tooEasy.add(question.id);
    await ref.read(feedStatsServiceProvider).deprioritizeQuestion(question.id);
  }

  Future<void> markTooHard(PracticeQuestion question) async {
    // Surfaces the question again soon, same as a wrong answer would.
    await ref.read(feedRevisionServiceProvider).recordOutcome(question, false);
  }

  Future<void> recordWrongReason(String reason) async {
    await ref.read(feedStatsServiceProvider).recordWrongReason(reason);
  }

  List<PracticeQuestion> similarTo(PracticeQuestion question, {int limit = 3}) {
    final topic = question.topic;
    if (topic == null || topic.trim().isEmpty) return const [];
    return _fullPool
        .where((q) => q.id != question.id && q.topic == topic)
        .take(limit)
        .toList();
  }

  /// Inserts [question] right after [afterIndex] (or jumps to it if it's
  /// already coming up) — used when tapping a "Similar" question in the
  /// Deep Dive drawer. Returns the index to scroll to.
  int insertNext(int afterIndex, PracticeQuestion question) {
    final cards = List<FeedCardState>.from(state.cards);
    final existing = cards.indexWhere(
      (c) => c.question.engagementKey == question.engagementKey,
      afterIndex + 1,
    );
    if (existing != -1) return existing;

    final insertAt = (afterIndex + 1).clamp(0, cards.length);
    cards.insert(insertAt, _card(question, reason: 'Similar question', pinned: true));
    if (state.lane.isInfinite) _session.enqueue(question);
    state = state.copyWith(cards: cards);
    return insertAt;
  }
}
