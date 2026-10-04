import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../shared/providers/providers.dart';
import '../../../shared/services/connectivity_service.dart';
import '../../../shared/services/share_service.dart';
import '../../../shared/theme/practice_theme.dart';
import '../models/feed_models.dart';
import '../providers/feed_providers.dart';
import '../widgets/deep_dive_sheet.dart';
import '../widgets/feed_question_card.dart';
import '../widgets/lane_switcher_sheet.dart';
import '../widgets/long_press_menu_sheet.dart';

/// The Practice tab: one question per screen in an endless vertical feed.
///
/// A card counts as viewed once scrolling settles on it (not mid-swipe),
/// and view time only runs while this tab is visible and the app is in
/// the foreground — that's what the For You ranking learns from.
class FeedScreen extends ConsumerStatefulWidget {
  const FeedScreen({super.key});

  @override
  ConsumerState<FeedScreen> createState() => _FeedScreenState();
}

class _FeedScreenState extends ConsumerState<FeedScreen> {
  final PageController _pageController = PageController();
  late final AppLifecycleListener _lifecycle;
  int _currentIndex = 0;
  int _handledEpoch = 0;

  FeedController get _controller => ref.read(feedControllerProvider.notifier);

  @override
  void initState() {
    super.initState();
    _controller.isScrollIdle = () =>
        !_pageController.hasClients ||
        !_pageController.position.isScrollingNotifier.value;
    _lifecycle = AppLifecycleListener(
      onStateChange: (lifecycleState) => _controller.setAppResumed(
        lifecycleState == AppLifecycleState.resumed,
      ),
    );
  }

  @override
  void dispose() {
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

  void _openDeepDive(PracticeQuestion question, int index) {
    _controller.recordExplanationOpened(question);
    DeepDiveSheet.show(context, question, index);
  }

  void _openLaneSwitcher() => LaneSwitcherSheet.show(context);

  void _openMenu(PracticeQuestion question) => LongPressMenuSheet.show(context, question);

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

  void _showSnack(String message, {Color? color}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: color,
        duration: const Duration(seconds: 3),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final feedState = ref.watch(feedControllerProvider);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isOnline = ref.watch(isOnlineProvider).value ?? true;
    _syncLaneStart(feedState);

    ref.listen<FeedState>(feedControllerProvider, (previous, next) {
      if (next.pendingBreakNudge && !(previous?.pendingBreakNudge ?? false)) {
        _showBreakNudge(next);
      }
      if (next.pendingTargetBanner && !(previous?.pendingTargetBanner ?? false)) {
        _showSnack('🎯 Daily target reached — $kFeedDailyTarget questions today!', color: PracticeTheme.success);
        _controller.acknowledgeTargetBanner();
      }
      if (next.pendingCaughtUpNotice && !(previous?.pendingCaughtUpNotice ?? false)) {
        _showSnack("You're all caught up — now mixing in questions worth another look");
        _controller.acknowledgeCaughtUpNotice();
      }
    });

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            _FeedHeader(
              lane: feedState.lane,
              isOnline: isOnline,
              isDark: isDark,
              onRefresh: () {
                HapticFeedback.selectionClick();
                _controller.refreshForYou();
              },
              onBack: () => _controller.switchLane(FeedLane.forYou),
              onOpenLanes: _openLaneSwitcher,
            ),
            Expanded(child: _buildBody(feedState, isDark)),
          ],
        ),
      ),
    );
  }

  Widget _buildBody(FeedState feedState, bool isDark) {
    if (feedState.loading && feedState.cards.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (feedState.cards.isEmpty) return _buildEmptyState(feedState, isDark);

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
              isDark: isDark,
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

  Widget _buildEmptyState(FeedState feedState, bool isDark) {
    if (feedState.allTopicsHidden) {
      return _EmptyMessage(
        icon: Icons.visibility_off_rounded,
        title: 'All your topics are hidden',
        body: 'Unhide them to bring your feed back.',
        actionLabel: 'Unhide all',
        onAction: _controller.unmuteAllTopics,
        isDark: isDark,
      );
    }
    if (feedState.lane.isInfinite) {
      return _EmptyMessage(
        icon: Icons.quiz_rounded,
        title: 'Your practice feed is empty',
        body: 'Add a topic from Home — its questions join this feed, and it learns what you like as you scroll.',
        actionLabel: 'Go to Home',
        onAction: () => ref.read(tabIndexProvider.notifier).state = 1,
        isDark: isDark,
      );
    }
    return _EmptyMessage(
      icon: Icons.inbox_rounded,
      title: 'Nothing here yet',
      body: 'This lane is empty right now.',
      actionLabel: 'Back to For You',
      onAction: () => _controller.switchLane(FeedLane.forYou),
      isDark: isDark,
    );
  }
}

class _FeedHeader extends StatelessWidget {
  final FeedLane lane;
  final bool isOnline;
  final bool isDark;
  final VoidCallback onRefresh;
  final VoidCallback onBack;
  final VoidCallback onOpenLanes;

  const _FeedHeader({
    required this.lane,
    required this.isOnline,
    required this.isDark,
    required this.onRefresh,
    required this.onBack,
    required this.onOpenLanes,
  });

  @override
  Widget build(BuildContext context) {
    final textColor = isDark ? Colors.white : Colors.black87;
    return SizedBox(
      height: 44,
      child: Row(
        children: [
          if (lane.isInfinite)
            const SizedBox(width: 16)
          else
            IconButton(
              tooltip: 'Back to For You',
              onPressed: onBack,
              icon: Icon(Icons.arrow_back_rounded, color: textColor),
            ),
          Flexible(
            child: GestureDetector(
              onTap: lane.isInfinite ? onRefresh : null,
              child: Text(
                lane.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                  color: textColor,
                ),
              ),
            ),
          ),
          const Spacer(),
          if (!isOnline)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: PracticeTheme.warning,
                borderRadius: BorderRadius.circular(999),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.cloud_off_rounded, size: 14, color: Colors.black87),
                  const SizedBox(width: 4),
                  Text(
                    'Offline',
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: Colors.black87,
                    ),
                  ),
                ],
              ),
            ),
          IconButton(
            tooltip: 'Lanes',
            onPressed: onOpenLanes,
            icon: Icon(Icons.layers_rounded, color: textColor),
          ),
        ],
      ),
    );
  }
}

class _EndOfLane extends StatelessWidget {
  final FeedLane lane;
  final int cardCount;
  final bool isDark;
  final VoidCallback onGoAgain;
  final VoidCallback onReplay;
  final VoidCallback onForYou;
  final VoidCallback onAddTopic;
  final VoidCallback onBrowse;

  const _EndOfLane({
    required this.lane,
    required this.cardCount,
    required this.isDark,
    required this.onGoAgain,
    required this.onReplay,
    required this.onForYou,
    required this.onAddTopic,
    required this.onBrowse,
  });

  @override
  Widget build(BuildContext context) {
    final forYou = lane.isInfinite;
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.emoji_events_rounded, size: 56, color: PracticeTheme.primary),
            const SizedBox(height: 18),
            Text(
              forYou ? "You've practiced all $cardCount" : "You're all caught up",
              textAlign: TextAlign.center,
              style: GoogleFonts.plusJakartaSans(
                fontSize: 19,
                fontWeight: FontWeight.w800,
                color: isDark ? Colors.white : Colors.black87,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              forYou
                  ? 'Add another topic to keep your feed going, or run through these again.'
                  : 'You finished every question in "${lane.label}" for now.',
              textAlign: TextAlign.center,
              style: GoogleFonts.plusJakartaSans(fontSize: 14, color: isDark ? Colors.white60 : Colors.black54),
            ),
            const SizedBox(height: 22),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: PracticeTheme.primary),
              onPressed: forYou ? onAddTopic : onForYou,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                child: Text(forYou ? 'Add a topic' : 'Continue in For You'),
              ),
            ),
            const SizedBox(height: 10),
            OutlinedButton(
              onPressed: forYou ? onGoAgain : onReplay,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                child: Text(forYou ? 'Go again' : 'Replay this lane'),
              ),
            ),
            if (!forYou)
              TextButton(onPressed: onBrowse, child: const Text('Browse another lane')),
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
  final bool isDark;

  const _EmptyMessage({
    required this.icon,
    required this.title,
    required this.body,
    required this.actionLabel,
    required this.onAction,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(28),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 64, color: isDark ? Colors.white24 : Colors.black26),
          const SizedBox(height: 20),
          Text(
            title,
            textAlign: TextAlign.center,
            style: GoogleFonts.plusJakartaSans(
              fontSize: 19,
              fontWeight: FontWeight.w800,
              color: isDark ? Colors.white : Colors.black87,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            body,
            textAlign: TextAlign.center,
            style: GoogleFonts.plusJakartaSans(
              fontSize: 14,
              height: 1.5,
              color: isDark ? Colors.white60 : Colors.black54,
            ),
          ),
          const SizedBox(height: 24),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: PracticeTheme.primary),
            onPressed: onAction,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
              child: Text(actionLabel),
            ),
          ),
        ],
      ),
    );
  }
}
