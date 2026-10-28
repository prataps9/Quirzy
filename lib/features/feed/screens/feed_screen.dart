import 'dart:async';
import 'dart:math' as math;

import 'package:confetti/confetti.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../shared/providers/providers.dart';
import '../../../shared/services/connectivity_service.dart';
import '../../../shared/services/share_service.dart';
import '../../../shared/theme/app_motion.dart';
import '../../../shared/theme/app_palette.dart';
import '../../../shared/theme/app_text.dart';
import '../../../shared/widgets/app_widgets.dart';
import '../../progress/models/badge.dart';
import '../../progress/services/share_card_service.dart';
import '../models/daily_challenge.dart';
import '../models/feed_models.dart';
import '../providers/feed_providers.dart';
import '../services/feed_audio.dart';
import '../services/streak_service.dart';
import '../widgets/deep_dive_sheet.dart';
import '../widgets/feed_question_card.dart';
import '../widgets/feed_session_cards.dart';
import '../widgets/feed_share_cards.dart';
import '../widgets/long_press_menu_sheet.dart';
import '../widgets/topic_dial.dart';

/// The Practice tab: one question per screen in an endless vertical feed.
///
/// A card counts as viewed once scrolling settles on it (not mid-swipe),
/// and view time only runs while this tab is visible and the app is in
/// the foreground — that's what the For You ranking learns from. The
/// header keeps the daily habit in view (streak, goal ring, combo), and
/// milestones are celebrated with confetti.
///
/// Like Reels, the feed moves on by itself after a correct answer, a fact
/// read to the end, or a rated flashcard (unless turned off in Profile);
/// any touch cancels a pending move. Read-aloud and answer sounds are
/// opt-in.
class FeedScreen extends ConsumerStatefulWidget {
  const FeedScreen({super.key});

  @override
  ConsumerState<FeedScreen> createState() => _FeedScreenState();
}

/// The parts of [FeedState] the page view itself depends on. Each page
/// watches its own card, and the header watches its own numbers, so
/// answering a card rebuilds that card only.
typedef _FeedView = ({
  FeedLane lane,
  int cardCount,
  int laneEpoch,
  int startIndex,
  bool loading,
  bool hasMore,
  bool showHints,
  bool focusMode,
  bool allTopicsHidden,
  bool failed,
});

_FeedView _viewOf(FeedState s) => (
  lane: s.lane,
  cardCount: s.cards.length,
  laneEpoch: s.laneEpoch,
  startIndex: s.startIndex,
  loading: s.loading,
  hasMore: s.hasMore,
  showHints: s.showHints,
  focusMode: s.focusMode,
  allTopicsHidden: s.allTopicsHidden,
  failed: s.error != null,
);

class _FeedScreenState extends ConsumerState<FeedScreen> {
  final PageController _pageController = PageController();
  final ConfettiController _confetti = ConfettiController(duration: const Duration(milliseconds: 900));
  late final AppLifecycleListener _lifecycle;
  Timer? _rewardTimer;
  Timer? _rewardDelay;

  /// The celebration banner shown at the top, and the last one shown, kept
  /// so the banner can slide out instead of vanishing.
  final ValueNotifier<FeedReward?> _bannerReward = ValueNotifier(null);
  FeedReward? _lastReward;
  Timer? _advanceTimer;
  int _currentIndex = 0;

  /// Bumped when the page changes. Pages listen to this instead of the whole
  /// screen rebuilding in the middle of a swipe.
  final ValueNotifier<int> _page = ValueNotifier(0);
  int _handledEpoch = 0;

  /// The feed is really in front of the user only when its tab is showing,
  /// the app is in the foreground and no other screen is pushed on top.
  bool _tabShown = true;
  bool _appResumed = true;
  bool _wasVisible = true;

  /// The card read aloud last, so a scroll that settles back on the same
  /// card doesn't start it again.
  int? _lastSpokenUid;

  /// How long to wait before moving on, so the green check (or the end of
  /// a fact) registers first.
  static const _advanceAfterCorrect = Duration(milliseconds: 1200);
  static const _advanceAfterRead = Duration(milliseconds: 500);

  /// How long the automatic move to the next card takes: about as long as a
  /// thumb flick settles, so it feels like the same gesture.
  static const _autoAdvanceTime = Duration(milliseconds: 340);

  FeedController get _controller => ref.read(feedControllerProvider.notifier);
  FeedAudio get _audio => ref.read(feedAudioProvider);
  List<FeedCardState> get _cards => ref.read(feedControllerProvider).cards;

  bool get _feedVisible => _tabShown && _appResumed && (ModalRoute.of(context)?.isCurrent ?? true);

  @override
  void initState() {
    super.initState();
    _controller.isScrollIdle = () => !_pageController.hasClients || !_pageController.position.isScrollingNotifier.value;
    _lifecycle = AppLifecycleListener(
      onStateChange: (lifecycleState) {
        final resumed = lifecycleState == AppLifecycleState.resumed;
        _controller.setAppResumed(resumed);
        if (mounted && resumed != _appResumed) setState(() => _appResumed = resumed);
      },
    );
  }

  @override
  void dispose() {
    _advanceTimer?.cancel();
    _rewardTimer?.cancel();
    _rewardDelay?.cancel();
    _confetti.dispose();
    _bannerReward.dispose();
    _page.dispose();
    _lifecycle.dispose();
    _pageController.dispose();
    super.dispose();
  }

  /// Lands on a freshly loaded lane's start card. Driven from build rather
  /// than a listener so a lane switched while this tab was hidden is still
  /// picked up the moment it shows.
  void _syncLaneStart(_FeedView view) {
    if (view.laneEpoch == _handledEpoch) return;
    _handledEpoch = view.laneEpoch;
    _currentIndex = view.startIndex;
    _advanceTimer?.cancel();
    _lastSpokenUid = null;
    final start = view.startIndex;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (_pageController.hasClients) _pageController.jumpToPage(start);
      _controller.activate(start);
      _readActive();
    });
  }

  /// Pauses everything that should only run while the feed is in front:
  /// speech, a pending auto-advance, and (via `isActive`) the fact bar and
  /// question timer.
  void _syncVisibility() {
    final visible = _feedVisible;
    if (visible == _wasVisible) return;
    _wasVisible = visible;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (visible) {
        _readActive();
      } else {
        _silence();
      }
    });
  }

  /// Stops speech and any pending auto-advance — the user is busy elsewhere.
  void _silence() {
    _advanceTimer?.cancel();
    _lastSpokenUid = null;
    _audio.stop();
  }

  /// Reads the card on screen aloud when read-aloud is on — once per card,
  /// unless [force]d (e.g. the back of a flipped flashcard).
  void _readActive({bool force = false}) {
    if (!mounted || !_feedVisible || !ref.read(settingsProvider).readAloud) return;
    final cards = _cards;
    if (_currentIndex >= cards.length) return;
    final card = cards[_currentIndex];
    if (!force && card.uid == _lastSpokenUid) return;
    if (card.kind == FeedCardKind.recap || card.kind == FeedCardKind.caughtUp) return;
    _lastSpokenUid = card.uid;
    _audio.speak(card);
  }

  void _toggleReadAloud() {
    final settings = ref.read(settingsProvider);
    settings.setReadAloud(!settings.readAloud);
    if (settings.readAloud) {
      _readActive(force: true);
    } else {
      _silence();
    }
  }

  /// Reacts to the card on screen resolving: plays the answer sound and,
  /// if auto-scroll is on, schedules the move to the next card.
  void _onActiveResolved(FeedCardState card) {
    final settings = ref.read(settingsProvider);
    if (card.isQuiz && !card.skipped && settings.soundEffects) {
      _audio.playAnswer(correct: card.isCorrect);
    }
    if (!settings.autoAdvance) return;
    final Duration? delay = switch (card.kind) {
      FeedCardKind.question || FeedCardKind.trueFalse => card.isCorrect ? _advanceAfterCorrect : null,
      FeedCardKind.fact || FeedCardKind.flashcard => _advanceAfterRead,
      // Their buttons move on themselves.
      FeedCardKind.recap || FeedCardKind.caughtUp => null,
    };
    if (delay == null) return;
    final from = _currentIndex;
    final uid = card.uid;
    final epoch = _handledEpoch;
    _advanceTimer?.cancel();
    _advanceTimer = Timer(delay, () {
      if (!mounted || !_feedVisible || !_pageController.hasClients) return;
      // Only move if the user is still on that exact card in that lane.
      final state = ref.read(feedControllerProvider);
      if (epoch != _handledEpoch || _currentIndex != from) return;
      if (from >= state.cards.length || state.cards[from].uid != uid) return;
      final itemCount = state.cards.length + (state.hasMore ? 0 : 1);
      if (from + 1 >= itemCount) return;
      _pageController.animateToPage(
        from + 1,
        duration: AppMotion.of(context, _autoAdvanceTime),
        curve: Curves.easeInOutCubic,
      );
    });
  }

  /// A card's own "Keep going" button: mark it done and go to the next.
  void _moveOn(int index) {
    _controller.acknowledgeCard(index);
    if (!_pageController.hasClients) return;
    _pageController.animateToPage(
      index + 1,
      duration: AppMotion.of(context, _autoAdvanceTime),
      curve: Curves.easeInOutCubic,
    );
  }

  void _handlePageChanged(int newIndex) {
    final feedState = ref.read(feedControllerProvider);
    if (feedState.focusMode && newIndex > _currentIndex) {
      final leavingIndex = _currentIndex;
      final stillBlocked = leavingIndex < feedState.cards.length && !feedState.cards[leavingIndex].isResolved;
      if (stillBlocked) {
        HapticFeedback.heavyImpact();
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (_pageController.hasClients) {
            _pageController.animateToPage(
              leavingIndex,
              duration: AppMotion.of(context, AppMotion.base),
              curve: AppMotion.enter,
            );
          }
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Focus mode: answer or skip this question to continue'),
            duration: Duration(milliseconds: 1400),
          ),
        );
        return;
      }
    }

    if (newIndex == _currentIndex) return;
    _silence();
    _currentIndex = newIndex;
    _page.value = newIndex;
    if (feedState.showHints) _controller.dismissHints();
    _controller.savePosition(newIndex);
  }

  bool _handleScrollEnd(ScrollEndNotification notification) {
    if (notification.depth == 0 && _pageController.hasClients) {
      final page = _pageController.page?.round();
      if (page != null) {
        _controller.activate(page);
        _readActive();
      }
    }
    return false;
  }

  /// Celebrates a milestone a beat after the answer, so the "+XP" pop on
  /// the card plays first instead of being covered by the banner.
  void _showReward(FeedReward reward) {
    _rewardDelay?.cancel();
    _rewardDelay = Timer(const Duration(milliseconds: 800), () {
      if (!mounted) return;
      HapticFeedback.mediumImpact();
      _confetti.play();
      _rewardTimer?.cancel();
      _lastReward = reward;
      _bannerReward.value = reward;
      _rewardTimer = Timer(const Duration(milliseconds: 3200), () {
        if (mounted) _bannerReward.value = null;
      });
    });
  }

  void _openDeepDive(PracticeQuestion question, int index) {
    _controller.recordExplanationOpened(question);
    DeepDiveSheet.show(context, question, index);
  }

  void _openLaneSwitcher() => TopicDial.show(context);

  void _openMenu(PracticeQuestion question) => LongPressMenuSheet.show(context, question);

  void _openMyPrep() => ref.read(tabIndexProvider.notifier).state = 2;

  /// Shares a question as an image card, falling back to text if the
  /// picture can't be made.
  Future<void> _share(PracticeQuestion question) async {
    final shared = await ShareCardService.shareWidget(
      context,
      QuestionShareCard(question: question),
      text: 'Can you get this ${question.topicName} question? Practise on Quirzy #Quirzy',
      fileName: 'quirzy_question.png',
    );
    if (shared) return;
    await ShareService.shareQuestion(
      topic: question.topicName,
      questionText: question.questionText,
      options: question.options,
    );
  }

  Future<void> _shareRecap(FeedRecap recap) async {
    final shared = await ShareCardService.shareWidget(
      context,
      RecapShareCard(recap: recap),
      text: 'My Quirzy practice session #Quirzy',
      fileName: 'quirzy_session.png',
    );
    if (shared) return;
    await ShareService.shareSession(answered: recap.answered, accuracy: recap.accuracyPercent, xp: recap.xp);
  }

  @override
  Widget build(BuildContext context) {
    final view = ref.watch(feedControllerProvider.select(_viewOf));
    final readAloud = ref.watch(settingsProvider.select((s) => s.readAloud));
    final p = context.palette;
    _syncLaneStart(view);
    _syncVisibility();

    ref.listen<int>(tabIndexProvider, (_, tab) {
      if (mounted && (tab == 0) != _tabShown) setState(() => _tabShown = tab == 0);
    });

    ref.listen<FeedState>(feedControllerProvider, (previous, next) {
      final i = _currentIndex;
      if (previous != null && i < next.cards.length && i < previous.cards.length) {
        final before = previous.cards[i];
        final now = next.cards[i];
        if (before.uid == now.uid && !before.isResolved && now.isResolved) _onActiveResolved(now);
        // Reading the back of a flipped flashcard aloud.
        if (before.uid == now.uid && !before.flipped && now.flipped && !now.rated) _readActive(force: true);
      }
      final reward = next.reward;
      if (reward != null && reward.id != previous?.reward?.id) _showReward(reward);
    });

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: Listener(
          // Any touch means the user is in control: drop a pending auto-advance.
          onPointerDown: (_) => _advanceTimer?.cancel(),
          child: Stack(
            children: [
              Column(
                children: [
                  _FeedHeaderBar(
                    onRefresh: () {
                      HapticFeedback.selectionClick();
                      _controller.refreshForYou();
                    },
                    onBack: () => _controller.switchLane(FeedLane.forYou),
                    onOpenLanes: _openLaneSwitcher,
                    onOpenMyPrep: _openMyPrep,
                  ),
                  Expanded(
                    child: _LaneFade(
                      epoch: view.laneEpoch,
                      child: _buildBody(view, readAloud: readAloud),
                    ),
                  ),
                ],
              ),
              Align(
                alignment: Alignment.topCenter,
                child: ConfettiWidget(
                  confettiController: _confetti,
                  blastDirection: math.pi / 2,
                  blastDirectionality: BlastDirectionality.explosive,
                  emissionFrequency: 0.05,
                  numberOfParticles: 18,
                  maxBlastForce: 22,
                  minBlastForce: 8,
                  gravity: 0.25,
                  colors: [p.accent, p.streak, p.like, p.text],
                ),
              ),
              Positioned(
                top: 56,
                left: 16,
                right: 16,
                child: ValueListenableBuilder<FeedReward?>(
                  valueListenable: _bannerReward,
                  builder: (context, reward, _) {
                    final shown = reward != null;
                    final banner = reward ?? _lastReward;
                    return IgnorePointer(
                      ignoring: !shown,
                      child: AnimatedSlide(
                        offset: shown ? Offset.zero : const Offset(0, -0.6),
                        duration: AppMotion.of(context, AppMotion.base),
                        curve: shown ? AppMotion.enter : AppMotion.exit,
                        child: AnimatedOpacity(
                          opacity: shown ? 1 : 0,
                          duration: AppMotion.of(context, AppMotion.base),
                          child: banner == null ? const SizedBox(height: 0) : _RewardBanner(reward: banner),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _dailyEnd(_FeedView view) => FadeRise(
    child: _DailyEnd(
      onShare: _shareDaily,
      onFinish: () => _controller.switchLane(view.lane),
      onForYou: () => _controller.switchLane(FeedLane.forYou),
      onAddTopic: () => ref.read(tabIndexProvider.notifier).state = 1,
    ),
  );

  Future<void> _shareDaily(DailyChallenge daily) =>
      ShareService.shareDailyChallenge(correct: daily.correct, total: daily.total);

  Widget _buildBody(_FeedView view, {required bool readAloud}) {
    if (view.loading && view.cardCount == 0) {
      return const Center(child: CircularProgressIndicator());
    }
    // Finished (or nothing to ask): the Daily 5 ends on its own result page.
    if (view.cardCount == 0 && view.lane.type == FeedLaneType.daily) return _dailyEnd(view);
    if (view.cardCount == 0) return FadeRise(child: _buildEmptyState(view));

    final visible = _feedVisible;
    final itemCount = view.cardCount + (view.hasMore ? 0 : 1);
    final pages = NotificationListener<ScrollEndNotification>(
      onNotification: _handleScrollEnd,
      child: PageView.builder(
        controller: _pageController,
        scrollDirection: Axis.vertical,
        physics: const _ReelsPhysics(),
        allowImplicitScrolling: true,
        itemCount: itemCount,
        onPageChanged: _handlePageChanged,
        itemBuilder: (context, index) => _buildPage(view, index, visible: visible, readAloud: readAloud),
      ),
    );

    return Stack(
      children: [
        pages,
        if (view.showHints)
          ValueListenableBuilder<int>(
            valueListenable: _page,
            builder: (context, _, _) => _currentIndex == 0
                ? const Positioned(left: 0, right: 0, bottom: 64, child: IgnorePointer(child: _SwipeUpHint()))
                : const SizedBox.shrink(),
          ),
      ],
    );
  }

  Widget _buildPage(_FeedView view, int index, {required bool visible, required bool readAloud}) {
    if (index >= view.cardCount) {
      if (view.lane.type == FeedLaneType.daily) return _dailyEnd(view);
      return FadeRise(
        child: _EndOfLane(
          lane: view.lane,
          cardCount: _cards.where((c) => c.isQuiz).length,
          onGoAgain: _controller.refreshForYou,
          onReplay: _controller.reshuffleCurrentLane,
          onForYou: () => _controller.switchLane(FeedLane.forYou),
          onAddTopic: () => ref.read(tabIndexProvider.notifier).state = 1,
          onBrowse: _openLaneSwitcher,
        ),
      );
    }
    // Each page watches only its own card, and re-reads which page is active
    // when the page changes, so a swipe never rebuilds the whole feed.
    return ValueListenableBuilder<int>(
      valueListenable: _page,
      builder: (context, _, _) => Consumer(
        builder: (context, ref, _) {
          final card = ref.watch(feedControllerProvider.select((s) => index < s.cards.length ? s.cards[index] : null));
          if (card == null) return const SizedBox.shrink();
          return _buildCard(card, index, view, isActive: index == _currentIndex && visible, readAloud: readAloud);
        },
      ),
    );
  }

  Widget _buildCard(FeedCardState card, int index, _FeedView view, {required bool isActive, required bool readAloud}) {
    final topic = card.question.topicName;
    if (card.kind == FeedCardKind.recap) {
      return RepaintBoundary(
        key: ValueKey('feed_card_${card.uid}'),
        child: RecapCard(
          recap: card.recap!,
          onKeepGoing: () => _moveOn(index),
          onPracticeTopic: (t) {
            _controller.acknowledgeCard(index);
            _controller.switchLane(FeedLane(type: FeedLaneType.topic, id: 'topic:$t', label: t));
          },
          onShare: () => _shareRecap(card.recap!),
          onTakeBreak: () {
            _controller.acknowledgeCard(index);
            ref.read(tabIndexProvider.notifier).state = 1;
          },
        ),
      );
    }
    if (card.kind == FeedCardKind.caughtUp) {
      return RepaintBoundary(
        key: ValueKey('feed_card_${card.uid}'),
        child: CaughtUpCard(
          topic: topic,
          onGenerateMore: () {
            _controller.acknowledgeCard(index);
            ref.read(homeTopicDraftProvider.notifier).state = topic;
            ref.read(tabIndexProvider.notifier).state = 1;
          },
          onKeepReviewing: () => _moveOn(index),
        ),
      );
    }
    // A flashcard's "topic" is its set title, not a feed topic.
    final canOpenTopic = view.lane.type != FeedLaneType.topic && card.kind != FeedCardKind.flashcard;
    return RepaintBoundary(
      key: ValueKey('feed_card_${card.uid}'),
      child: FeedQuestionCard(
        cardState: card,
        isActive: isActive,
        showGestureHint: view.showHints && index == 0,
        focusMode: view.focusMode,
        positionInLane: view.lane.isInfinite ? null : index + 1,
        laneLength: view.cardCount,
        onSelectOption: (opt) => _controller.selectOption(index, opt),
        onSkip: () => _controller.skipCurrent(index),
        onDoubleTapLike: () => _controller.like(index),
        onToggleLike: () => _controller.toggleLike(index),
        onToggleSave: () => _controller.toggleBookmark(index),
        onExplain: () => _openDeepDive(card.question, index),
        onShare: () => _share(card.question),
        onMore: () => _openMenu(card.question),
        onOpenLaneSwitcher: _openLaneSwitcher,
        onOpenTopic: canOpenTopic
            ? () => _controller.switchLane(FeedLane(type: FeedLaneType.topic, id: 'topic:$topic', label: topic))
            : null,
        onWrongReason: (reason) => _controller.recordWrongReason(index, reason),
        onTrueFalse: (saysTrue) => _controller.answerTrueFalse(index, saysTrue),
        onFactDone: () => _controller.acknowledgeFact(index),
        onFlip: () => _controller.flipFlashcard(index),
        onRate: (rating) => _controller.rateFlashcard(index, rating),
        soundOn: readAloud,
        onToggleSound: _toggleReadAloud,
      ),
    );
  }

  Widget _buildEmptyState(_FeedView view) {
    if (view.failed) {
      return _EmptyMessage(
        icon: Icons.cloud_off_rounded,
        title: "Couldn't load your feed",
        body: 'Something went wrong while loading your questions. Try again in a moment.',
        actionLabel: 'Try again',
        onAction: _controller.retry,
      );
    }
    if (view.allTopicsHidden) {
      return _EmptyMessage(
        icon: Icons.visibility_off_rounded,
        title: 'All your topics are hidden',
        body: 'Unhide them to bring your feed back.',
        actionLabel: 'Unhide all',
        onAction: _controller.unmuteAllTopics,
      );
    }
    if (view.lane.isInfinite) {
      return _EmptyMessage(
        icon: Icons.quiz_rounded,
        title: 'Your practice feed is empty',
        body: 'Add a topic from Home — its questions join this feed, and it learns what you like as you scroll.',
        actionLabel: 'Go to Home',
        onAction: () => ref.read(tabIndexProvider.notifier).state = 1,
      );
    }
    return _EmptyMessage(
      icon: Icons.inbox_rounded,
      title: 'Nothing here yet',
      body: 'This lane is empty right now.',
      actionLabel: 'Back to For You',
      onAction: () => _controller.switchLane(FeedLane.forYou),
    );
  }
}

/// The header, watching only what it shows (streak, today's count, combo,
/// lane, connectivity) so it doesn't rebuild the feed below it.
class _FeedHeaderBar extends ConsumerWidget {
  final VoidCallback onRefresh;
  final VoidCallback onBack;
  final VoidCallback onOpenLanes;
  final VoidCallback onOpenMyPrep;

  const _FeedHeaderBar({
    required this.onRefresh,
    required this.onBack,
    required this.onOpenLanes,
    required this.onOpenMyPrep,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final header = ref.watch(
      feedControllerProvider.select((s) => (lane: s.lane, today: s.todayAnswered, combo: s.combo)),
    );
    return _FeedHeader(
      lane: header.lane,
      isOnline: ref.watch(isOnlineProvider).value ?? true,
      streak: ref.watch(streakProvider).value ?? StreakInfo.none,
      todayAnswered: header.today,
      combo: header.combo,
      onRefresh: onRefresh,
      onBack: onBack,
      onOpenLanes: onOpenLanes,
      onOpenMyPrep: onOpenMyPrep,
    );
  }
}

class _FeedHeader extends StatelessWidget {
  final FeedLane lane;
  final bool isOnline;
  final StreakInfo streak;
  final int todayAnswered;
  final int combo;
  final VoidCallback onRefresh;
  final VoidCallback onBack;
  final VoidCallback onOpenLanes;
  final VoidCallback onOpenMyPrep;

  const _FeedHeader({
    required this.lane,
    required this.isOnline,
    required this.streak,
    required this.todayAnswered,
    required this.combo,
    required this.onRefresh,
    required this.onBack,
    required this.onOpenLanes,
    required this.onOpenMyPrep,
  });

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final text = Theme.of(context).textTheme;
    final flame = streak.practisedToday ? p.streak : p.textMuted;

    return SizedBox(
      height: 52,
      child: Row(
        children: [
          if (lane.isInfinite)
            const SizedBox(width: 16)
          else
            IconButton(tooltip: 'Back to For You', onPressed: onBack, icon: const Icon(Icons.arrow_back_rounded)),
          Flexible(
            child: GestureDetector(
              onTap: lane.isInfinite ? onRefresh : null,
              child: Text(lane.label, maxLines: 1, overflow: TextOverflow.ellipsis, style: text.headlineSmall),
            ),
          ),
          if (!isOnline)
            Padding(
              padding: const EdgeInsets.only(left: 8),
              child: Tooltip(
                message: 'Offline — practising your saved questions',
                child: Icon(Icons.cloud_off_rounded, size: 18, color: p.streak),
              ),
            ),
          const Spacer(),
          if (combo >= 2) ...[_ComboChip(combo: combo), const SizedBox(width: 6)],
          Semantics(
            button: true,
            label: streak.current == 0
                ? 'No streak yet. Answer a question to start one.'
                : '${streak.current} day streak${streak.atRisk ? '. Practise today to keep it.' : ''}',
            // Opaque padding makes the whole 48dp-tall area tappable, not just
            // the 30dp chip.
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: onOpenMyPrep,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 9),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: streak.practisedToday ? p.streakSoft : p.surfaceHigh,
                    borderRadius: BorderRadius.circular(AppRadius.pill),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.local_fire_department_rounded, size: 18, color: flame),
                      const SizedBox(width: 2),
                      Text(
                        '${streak.current}',
                        style: text.labelLarge!.copyWith(color: flame, fontWeight: FontWeight.w800),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 2),
          Semantics(
            button: true,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: onOpenMyPrep,
              child: Padding(
                padding: const EdgeInsets.all(6),
                child: _GoalRing(done: todayAnswered),
              ),
            ),
          ),
          IconButton(tooltip: 'Topics', onPressed: onOpenLanes, icon: const Icon(Icons.explore_rounded)),
        ],
      ),
    );
  }
}

class _ComboChip extends StatelessWidget {
  final int combo;

  const _ComboChip({required this.combo});

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    // A quick "bump" each time the combo grows (keyed on the value, so it
    // replays for every new count).
    return TweenAnimationBuilder<double>(
      key: ValueKey(combo),
      tween: Tween(begin: 1.3, end: 1),
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOutBack,
      builder: (context, scale, child) => Transform.scale(scale: scale, child: child),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(color: p.accent, borderRadius: BorderRadius.circular(AppRadius.pill)),
        child: Text(
          '×$combo',
          style: Theme.of(context).textTheme.labelLarge!.copyWith(color: p.onAccent, fontWeight: FontWeight.w800),
        ),
      ),
    );
  }
}

/// Progress towards today's question goal; turns into a check when met.
class _GoalRing extends StatelessWidget {
  final int done;

  const _GoalRing({required this.done});

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final reached = done >= kFeedDailyTarget;
    final progress = (done / kFeedDailyTarget).clamp(0.0, 1.0);
    return Semantics(
      label: 'Daily goal: $done of $kFeedDailyTarget questions',
      child: SizedBox(
        width: 36,
        height: 36,
        child: Stack(
          alignment: Alignment.center,
          children: [
            SizedBox(
              width: 34,
              height: 34,
              // Fills smoothly from the old value to the new one.
              child: TweenAnimationBuilder<double>(
                tween: Tween(end: progress),
                duration: const Duration(milliseconds: 400),
                curve: Curves.easeOutCubic,
                builder: (context, value, _) => CircularProgressIndicator(
                  value: value,
                  strokeWidth: 3.5,
                  backgroundColor: p.border,
                  color: reached ? p.success : p.accentText,
                ),
              ),
            ),
            if (reached)
              Icon(Icons.check_rounded, size: 18, color: p.success)
            else
              Text('$done', style: Theme.of(context).textTheme.micro),
          ],
        ),
      ),
    );
  }
}

class _RewardBanner extends StatelessWidget {
  final FeedReward reward;

  const _RewardBanner({required this.reward});

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final text = Theme.of(context).textTheme;

    final (IconData icon, Color color, String title, String? subtitle) = switch (reward.kind) {
      FeedRewardKind.streak => (
        Icons.local_fire_department_rounded,
        p.streak,
        reward.value <= 1 ? 'Streak started!' : '${reward.value}-day streak!',
        reward.value <= 1 ? 'Come back tomorrow to keep it going.' : 'You practised today — keep it alive.',
      ),
      FeedRewardKind.comboMilestone => (
        Icons.bolt_rounded,
        p.accentText,
        '${reward.value} in a row!',
        '+$kFeedComboBonusXp bonus XP',
      ),
      FeedRewardKind.dailyGoal => (
        Icons.emoji_events_rounded,
        p.success,
        'Daily goal hit!',
        '${reward.value} questions today. Nice work.',
      ),
      FeedRewardKind.levelUp => (Icons.military_tech_rounded, p.accentText, 'Level ${reward.value} reached!', null),
      FeedRewardKind.freezeUsed => (
        Icons.ac_unit_rounded,
        p.accentText,
        'Streak freeze used',
        'It kept your ${reward.value}-day streak going. You get a new one next week.',
      ),
      FeedRewardKind.badge => () {
        final badge = BadgeDef.catalog[reward.value.clamp(0, BadgeDef.catalog.length - 1)];
        return (badge.icon, p.accentText, 'New badge: ${badge.title}', badge.description);
      }(),
    };

    return Material(
      color: p.surfaceHigh,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.card),
        side: BorderSide(color: color.withValues(alpha: 0.5), width: 1.5),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(
          children: [
            Icon(icon, color: color, size: 28),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(title, style: text.titleSmall!.copyWith(fontWeight: FontWeight.w800)),
                  if (subtitle != null) Text(subtitle, style: text.bodySmall),
                ],
              ),
            ),
            if (reward.kind == FeedRewardKind.streak && reward.value >= 2 || reward.kind == FeedRewardKind.dailyGoal)
              TextButton(
                onPressed: () => reward.kind == FeedRewardKind.dailyGoal
                    ? ShareService.shareDailyGoal(questions: reward.value)
                    : ShareService.shareStreak(days: math.max(reward.value, 1)),
                child: const Text('Share'),
              ),
          ],
        ),
      ),
    );
  }
}

class _EndOfLane extends StatelessWidget {
  final FeedLane lane;
  final int cardCount;
  final VoidCallback onGoAgain;
  final VoidCallback onReplay;
  final VoidCallback onForYou;
  final VoidCallback onAddTopic;
  final VoidCallback onBrowse;

  const _EndOfLane({
    required this.lane,
    required this.cardCount,
    required this.onGoAgain,
    required this.onReplay,
    required this.onForYou,
    required this.onAddTopic,
    required this.onBrowse,
  });

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final text = Theme.of(context).textTheme;
    final forYou = lane.isInfinite;
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.emoji_events_rounded, size: 56, color: p.accentText),
            const SizedBox(height: 18),
            Text(
              forYou
                  ? "You've practised all $cardCount ${cardCount == 1 ? 'question' : 'questions'}"
                  : "You're all caught up",
              textAlign: TextAlign.center,
              style: text.titleLarge,
            ),
            const SizedBox(height: 8),
            Text(
              forYou
                  ? 'Add another topic to keep your feed going, or run through these again.'
                  : 'You finished every question in "${lane.label}" for now.',
              textAlign: TextAlign.center,
              style: text.bodyMedium!.copyWith(color: p.textMuted),
            ),
            const SizedBox(height: 22),
            AppButton(label: forYou ? 'Add a topic' : 'Continue in For You', onPressed: forYou ? onAddTopic : onForYou),
            const SizedBox(height: 10),
            AppButton.secondary(
              label: forYou ? 'Go again' : 'Replay this lane',
              onPressed: forYou ? onGoAgain : onReplay,
            ),
            if (!forYou) TextButton(onPressed: onBrowse, child: const Text('Browse another lane')),
          ],
        ),
      ),
    );
  }
}

/// The last page of the Daily 5: the score and bonus when it's finished,
/// or a nudge to finish the rest.
class _DailyEnd extends ConsumerWidget {
  final Future<void> Function(DailyChallenge daily) onShare;
  final VoidCallback onFinish;
  final VoidCallback onForYou;
  final VoidCallback onAddTopic;

  const _DailyEnd({required this.onShare, required this.onFinish, required this.onForYou, required this.onAddTopic});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.palette;
    final text = Theme.of(context).textTheme;
    final daily = ref.watch(feedControllerProvider.select((s) => s.daily));

    final String title;
    final String body;
    final List<Widget> actions;
    if (daily == null) {
      title = 'No Daily 5 yet';
      body = 'Add a topic and a fresh set of five will be waiting here every day.';
      actions = [AppButton(label: 'Add a topic', onPressed: onAddTopic)];
    } else if (daily.completed) {
      title = 'Daily 5 done: ${daily.correct} of ${daily.total} right';
      final xp = daily.bonusXp;
      body = '${xp == null ? '' : '+$xp XP earned. '}Come back tomorrow for a fresh set.';
      actions = [
        AppButton(label: 'Share result', icon: Icons.ios_share_rounded, onPressed: () => onShare(daily)),
        const SizedBox(height: 10),
        AppButton.secondary(label: 'Continue in For You', onPressed: onForYou),
      ];
    } else {
      title = 'Almost there';
      body = "You've answered ${daily.answered} of ${daily.total} today. Finish the rest to earn your bonus.";
      actions = [
        AppButton(label: 'Finish the rest', onPressed: onFinish),
        const SizedBox(height: 10),
        AppButton.secondary(label: 'Continue in For You', onPressed: onForYou),
      ];
    }

    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              daily?.completed == true ? Icons.emoji_events_rounded : Icons.bolt_rounded,
              size: 56,
              color: p.accentText,
            ),
            const SizedBox(height: 18),
            Text(title, textAlign: TextAlign.center, style: text.titleLarge),
            const SizedBox(height: 8),
            Text(
              body,
              textAlign: TextAlign.center,
              style: text.bodyMedium!.copyWith(color: p.textMuted),
            ),
            const SizedBox(height: 22),
            ...actions,
          ],
        ),
      ),
    );
  }
}

class _EmptyMessage extends StatelessWidget {
  final IconData icon;
  final String title;
  final String body;
  final String actionLabel;
  final VoidCallback onAction;

  const _EmptyMessage({
    required this.icon,
    required this.title,
    required this.body,
    required this.actionLabel,
    required this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final text = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.all(28),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 64, color: p.textMuted),
          const SizedBox(height: 20),
          Text(title, textAlign: TextAlign.center, style: text.titleLarge),
          const SizedBox(height: 10),
          Text(
            body,
            textAlign: TextAlign.center,
            style: text.bodyMedium!.copyWith(color: p.textMuted),
          ),
          const SizedBox(height: 24),
          AppButton(label: actionLabel, onPressed: onAction),
        ],
      ),
    );
  }
}

/// A gently bouncing "swipe up" cue on the very first card, until the user
/// swipes once.
class _SwipeUpHint extends StatefulWidget {
  const _SwipeUpHint();

  @override
  State<_SwipeUpHint> createState() => _SwipeUpHintState();
}

class _SwipeUpHintState extends State<_SwipeUpHint> with SingleTickerProviderStateMixin {
  late final AnimationController _bounce = AnimationController(vsync: this, duration: const Duration(milliseconds: 900))
    ..repeat(reverse: true);

  @override
  void dispose() {
    _bounce.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return AnimatedBuilder(
      animation: _bounce,
      builder: (context, child) =>
          Transform.translate(offset: Offset(0, -8 * Curves.easeInOut.transform(_bounce.value)), child: child),
      child: Center(
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 24),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(color: p.accent, borderRadius: BorderRadius.circular(AppRadius.pill)),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.keyboard_double_arrow_up_rounded, size: 18, color: p.onAccent),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  'Swipe up for the next one',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(
                    context,
                  ).textTheme.labelLarge!.copyWith(color: p.onAccent, fontWeight: FontWeight.w700),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The Reels page feel: the page follows the finger one-to-one, a flick of
/// any strength turns exactly one page (even a hard throw never skips two),
/// and it settles quickly on a critically damped spring that keeps the
/// speed of the flick, so there is no overshoot or wobble.
class _ReelsPhysics extends PageScrollPhysics {
  const _ReelsPhysics({super.parent});

  /// A flick faster than this (px/s) always turns the page, however short
  /// the drag. Slower releases snap to whichever page is nearer.
  static const _flick = 120.0;

  static final _snap = SpringDescription.withDampingRatio(mass: 1, stiffness: 360, ratio: 1);

  @override
  _ReelsPhysics applyTo(ScrollPhysics? ancestor) => _ReelsPhysics(parent: buildParent(ancestor));

  @override
  SpringDescription get spring => _snap;

  @override
  Simulation? createBallisticSimulation(ScrollMetrics position, double velocity) {
    // Past the first or last page: leave it to the usual edge handling.
    if ((velocity <= 0 && position.pixels <= position.minScrollExtent) ||
        (velocity >= 0 && position.pixels >= position.maxScrollExtent)) {
      return super.createBallisticSimulation(position, velocity);
    }
    final page = position.pixels / position.viewportDimension;
    final targetPage = velocity > _flick
        ? page.ceilToDouble()
        : velocity < -_flick
        ? page.floorToDouble()
        : page.roundToDouble();
    final target = (targetPage * position.viewportDimension).clamp(position.minScrollExtent, position.maxScrollExtent);
    if (target == position.pixels) return null;
    return ScrollSpringSimulation(spring, position.pixels, target, velocity, tolerance: toleranceFor(position));
  }
}

/// Fades a lane in when it (re)loads, so switching lanes doesn't pop.
class _LaneFade extends StatefulWidget {
  final int epoch;
  final Widget child;

  const _LaneFade({required this.epoch, required this.child});

  @override
  State<_LaneFade> createState() => _LaneFadeState();
}

class _LaneFadeState extends State<_LaneFade> with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(vsync: this, duration: AppMotion.base, value: 1);
  late final Animation<double> _opacity = Tween<double>(
    begin: 0.2,
    end: 1,
  ).animate(CurvedAnimation(parent: _controller, curve: AppMotion.enter));

  @override
  void didUpdateWidget(_LaneFade old) {
    super.didUpdateWidget(old);
    if (old.epoch != widget.epoch && !AppMotion.reduced(context)) _controller.forward(from: 0);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => FadeTransition(opacity: _opacity, child: widget.child);
}
