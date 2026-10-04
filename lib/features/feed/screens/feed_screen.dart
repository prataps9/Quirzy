import 'dart:async';
import 'dart:math' as math;

import 'package:confetti/confetti.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../shared/providers/providers.dart';
import '../../../shared/services/connectivity_service.dart';
import '../../../shared/services/share_service.dart';
import '../../../shared/theme/app_palette.dart';
import '../models/feed_models.dart';
import '../providers/feed_providers.dart';
import '../services/streak_service.dart';
import '../widgets/deep_dive_sheet.dart';
import '../widgets/feed_question_card.dart';
import '../widgets/lane_switcher_sheet.dart';
import '../widgets/long_press_menu_sheet.dart';

/// The Practice tab: one question per screen in an endless vertical feed.
///
/// A card counts as viewed once scrolling settles on it (not mid-swipe),
/// and view time only runs while this tab is visible and the app is in
/// the foreground — that's what the For You ranking learns from. The
/// header keeps the daily habit in view (streak, goal ring, combo), and
/// milestones are celebrated with confetti.
class FeedScreen extends ConsumerStatefulWidget {
  const FeedScreen({super.key});

  @override
  ConsumerState<FeedScreen> createState() => _FeedScreenState();
}

class _FeedScreenState extends ConsumerState<FeedScreen> {
  final PageController _pageController = PageController();
  final ConfettiController _confetti = ConfettiController(duration: const Duration(milliseconds: 900));
  late final AppLifecycleListener _lifecycle;
  Timer? _rewardTimer;
  Timer? _rewardDelay;
  FeedReward? _bannerReward;
  int _currentIndex = 0;
  int _handledEpoch = 0;

  FeedController get _controller => ref.read(feedControllerProvider.notifier);

  @override
  void initState() {
    super.initState();
    _controller.isScrollIdle = () =>
        !_pageController.hasClients || !_pageController.position.isScrollingNotifier.value;
    _lifecycle = AppLifecycleListener(
      onStateChange: (lifecycleState) =>
          _controller.setAppResumed(lifecycleState == AppLifecycleState.resumed),
    );
  }

  @override
  void dispose() {
    _rewardTimer?.cancel();
    _rewardDelay?.cancel();
    _confetti.dispose();
    _lifecycle.dispose();
    _pageController.dispose();
    super.dispose();
  }

  /// Lands on a freshly loaded lane's start card. Driven from build rather
  /// than a listener so a lane switched while this tab was hidden is still
  /// picked up the moment it shows.
  void _syncLaneStart(FeedState feedState) {
    if (feedState.laneEpoch == _handledEpoch) return;
    _handledEpoch = feedState.laneEpoch;
    _currentIndex = feedState.startIndex;
    final start = feedState.startIndex;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (_pageController.hasClients) _pageController.jumpToPage(start);
      _controller.activate(start);
    });
  }

  void _handlePageChanged(int newIndex, FeedState feedState) {
    if (feedState.focusMode && newIndex > _currentIndex) {
      final leavingIndex = _currentIndex;
      final stillBlocked = leavingIndex < feedState.cards.length && !feedState.cards[leavingIndex].isResolved;
      if (stillBlocked) {
        HapticFeedback.heavyImpact();
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (_pageController.hasClients) {
            _pageController.animateToPage(
              leavingIndex,
              duration: const Duration(milliseconds: 260),
              curve: Curves.easeOutCubic,
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
    setState(() => _currentIndex = newIndex);
    if (feedState.showHints) _controller.dismissHints();
    _controller.savePosition(newIndex);
  }

  bool _handleScrollEnd(ScrollEndNotification notification) {
    if (notification.depth == 0 && _pageController.hasClients) {
      final page = _pageController.page?.round();
      if (page != null) _controller.activate(page);
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
      setState(() => _bannerReward = reward);
      _rewardTimer = Timer(const Duration(milliseconds: 3200), () {
        if (mounted) setState(() => _bannerReward = null);
      });
    });
  }

  void _openDeepDive(PracticeQuestion question, int index) {
    _controller.recordExplanationOpened(question);
    DeepDiveSheet.show(context, question, index);
  }

  void _openLaneSwitcher() => LaneSwitcherSheet.show(context);

  void _openMenu(PracticeQuestion question) => LongPressMenuSheet.show(context, question);

  void _openMyPrep() => ref.read(tabIndexProvider.notifier).state = 2;

  void _share(PracticeQuestion question) {
    ShareService.shareQuestion(
      topic: question.topicName,
      questionText: question.questionText,
      options: question.options,
    );
  }

  void _showBreakNudge(FeedState feedState) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Take 5?'),
        content: Text("You've done ${feedState.sessionAnswered} questions this session."),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('5 more min'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.of(context).pop();
              ref.read(tabIndexProvider.notifier).state = 1; // Home tab
            },
            child: const Text('Take a break'),
          ),
        ],
      ),
    ).then((_) => _controller.acknowledgeBreakNudge());
  }

  @override
  Widget build(BuildContext context) {
    final feedState = ref.watch(feedControllerProvider);
    final streak = ref.watch(streakProvider).value ?? StreakInfo.none;
    final isOnline = ref.watch(isOnlineProvider).value ?? true;
    final p = context.palette;
    _syncLaneStart(feedState);

    ref.listen<FeedState>(feedControllerProvider, (previous, next) {
      if (next.pendingBreakNudge && !(previous?.pendingBreakNudge ?? false)) {
        _showBreakNudge(next);
      }
      final reward = next.reward;
      if (reward != null && reward.id != previous?.reward?.id) _showReward(reward);
      if (next.pendingCaughtUpNotice && !(previous?.pendingCaughtUpNotice ?? false)) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("You're all caught up — now mixing in questions worth another look")),
        );
        _controller.acknowledgeCaughtUpNotice();
      }
    });

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: Stack(
          children: [
            Column(
              children: [
                _FeedHeader(
                  lane: feedState.lane,
                  isOnline: isOnline,
                  streak: streak,
                  todayAnswered: feedState.todayAnswered,
                  combo: feedState.combo,
                  onRefresh: () {
                    HapticFeedback.selectionClick();
                    _controller.refreshForYou();
                  },
                  onBack: () => _controller.switchLane(FeedLane.forYou),
                  onOpenLanes: _openLaneSwitcher,
                  onOpenMyPrep: _openMyPrep,
                ),
                Expanded(child: _buildBody(feedState)),
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
              child: IgnorePointer(
                ignoring: _bannerReward == null,
                child: AnimatedSlide(
                  offset: _bannerReward == null ? const Offset(0, -0.6) : Offset.zero,
                  duration: const Duration(milliseconds: 220),
                  curve: Curves.easeOutCubic,
                  child: AnimatedOpacity(
                    opacity: _bannerReward == null ? 0 : 1,
                    duration: const Duration(milliseconds: 180),
                    child: _bannerReward == null ? const SizedBox(height: 0) : _RewardBanner(reward: _bannerReward!),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBody(FeedState feedState) {
    if (feedState.loading && feedState.cards.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (feedState.cards.isEmpty) return _buildEmptyState(feedState);

    final itemCount = feedState.cards.length + (feedState.hasMore ? 0 : 1);
    return NotificationListener<ScrollEndNotification>(
      onNotification: _handleScrollEnd,
      child: PageView.builder(
        controller: _pageController,
        scrollDirection: Axis.vertical,
        allowImplicitScrolling: true,
        itemCount: itemCount,
        onPageChanged: (i) => _handlePageChanged(i, feedState),
        itemBuilder: (context, index) {
          if (index >= feedState.cards.length) {
            return _EndOfLane(
              lane: feedState.lane,
              cardCount: feedState.cards.length,
              onGoAgain: _controller.refreshForYou,
              onReplay: _controller.reshuffleCurrentLane,
              onForYou: () => _controller.switchLane(FeedLane.forYou),
              onAddTopic: () => ref.read(tabIndexProvider.notifier).state = 1,
              onBrowse: _openLaneSwitcher,
            );
          }
          final card = feedState.cards[index];
          final topic = card.question.topicName;
          final inTopicLane = feedState.lane.type == FeedLaneType.topic;
          return RepaintBoundary(
            key: ValueKey('feed_card_${card.uid}'),
            child: FeedQuestionCard(
              cardState: card,
              isActive: index == _currentIndex,
              showGestureHint: feedState.showHints && index == 0,
              focusMode: feedState.focusMode,
              positionInLane: feedState.lane.isInfinite ? null : index + 1,
              laneLength: feedState.cards.length,
              onSelectOption: (opt) => _controller.selectOption(index, opt),
              onSkip: () => _controller.skipCurrent(index),
              onDoubleTapLike: () => _controller.like(index),
              onToggleLike: () => _controller.toggleLike(index),
              onToggleSave: () => _controller.toggleBookmark(index),
              onExplain: () => _openDeepDive(card.question, index),
              onShare: () => _share(card.question),
              onMore: () => _openMenu(card.question),
              onOpenLaneSwitcher: _openLaneSwitcher,
              onOpenTopic: inTopicLane
                  ? null
                  : () => _controller.switchLane(
                        FeedLane(type: FeedLaneType.topic, id: 'topic:$topic', label: topic),
                      ),
              onWrongReason: _controller.recordWrongReason,
            ),
          );
        },
      ),
    );
  }

  Widget _buildEmptyState(FeedState feedState) {
    if (feedState.allTopicsHidden) {
      return _EmptyMessage(
        icon: Icons.visibility_off_rounded,
        title: 'All your topics are hidden',
        body: 'Unhide them to bring your feed back.',
        actionLabel: 'Unhide all',
        onAction: _controller.unmuteAllTopics,
      );
    }
    if (feedState.lane.isInfinite) {
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
            IconButton(
              tooltip: 'Back to For You',
              onPressed: onBack,
              icon: const Icon(Icons.arrow_back_rounded),
            ),
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
          if (combo >= 2) ...[
            _ComboChip(combo: combo),
            const SizedBox(width: 6),
          ],
          Semantics(
            button: true,
            label: streak.current == 0
                ? 'No streak yet. Answer a question to start one.'
                : '${streak.current} day streak${streak.atRisk ? '. Practise today to keep it.' : ''}',
            child: GestureDetector(
              onTap: onOpenMyPrep,
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
                    Text('${streak.current}', style: text.labelLarge!.copyWith(color: flame, fontWeight: FontWeight.w800)),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(width: 6),
          GestureDetector(onTap: onOpenMyPrep, child: _GoalRing(done: todayAnswered)),
          IconButton(
            tooltip: 'Lanes',
            onPressed: onOpenLanes,
            icon: const Icon(Icons.layers_rounded),
          ),
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
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(color: p.accent, borderRadius: BorderRadius.circular(AppRadius.pill)),
      child: Text(
        '×$combo',
        style: Theme.of(context).textTheme.labelLarge!.copyWith(color: p.onAccent, fontWeight: FontWeight.w800),
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
              child: CircularProgressIndicator(
                value: progress,
                strokeWidth: 3.5,
                backgroundColor: p.border,
                color: reached ? p.success : p.accentText,
              ),
            ),
            if (reached)
              Icon(Icons.check_rounded, size: 18, color: p.success)
            else
              Text(
                '$done',
                style: Theme.of(context).textTheme.labelSmall!.copyWith(fontSize: 10, fontWeight: FontWeight.w800),
              ),
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
      FeedRewardKind.levelUp => (
          Icons.military_tech_rounded,
          p.accentText,
          'Level ${reward.value} reached!',
          null,
        ),
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
            if (reward.kind == FeedRewardKind.streak && reward.value >= 2 ||
                reward.kind == FeedRewardKind.dailyGoal)
              TextButton(
                onPressed: () => ShareService.shareStreak(days: math.max(reward.value, 1)),
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
              forYou ? "You've practiced all $cardCount" : "You're all caught up",
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
            FilledButton(
              onPressed: forYou ? onAddTopic : onForYou,
              child: Text(forYou ? 'Add a topic' : 'Continue in For You'),
            ),
            const SizedBox(height: 10),
            OutlinedButton(
              onPressed: forYou ? onGoAgain : onReplay,
              child: Text(forYou ? 'Go again' : 'Replay this lane'),
            ),
            if (!forYou) TextButton(onPressed: onBrowse, child: const Text('Browse another lane')),
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
          Text(body, textAlign: TextAlign.center, style: text.bodyMedium!.copyWith(color: p.textMuted)),
          const SizedBox(height: 24),
          FilledButton(onPressed: onAction, child: Text(actionLabel)),
        ],
      ),
    );
  }
}
