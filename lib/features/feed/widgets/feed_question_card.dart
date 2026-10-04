import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../shared/theme/app_palette.dart';
import '../models/feed_models.dart';
import 'option_card.dart';
import 'question_timer.dart';

const List<String> kWrongAnswerReasons = [
  'Silly mistake',
  "Didn't know",
  'Ran out of time',
  'Misread it',
];

/// One full-screen question in the feed, laid out like an Instagram post.
///
/// From top to bottom: a caption row (topic, why it was picked, timer),
/// the question and options, then an action bar (like, explanation,
/// share, save). Vertical swiping belongs to the enclosing PageView. The
/// question box handles double-tap to like, long-press for the menu, and
/// horizontal swipes for the solution or lane switcher. Options sit
/// outside that region so answering stays instant.
class FeedQuestionCard extends StatefulWidget {
  final FeedCardState cardState;
  final bool isActive;
  final bool showGestureHint;
  final bool focusMode;

  /// 1-based position for finite lanes; null hides the progress bar.
  final int? positionInLane;
  final int laneLength;
  final ValueChanged<int> onSelectOption;
  final VoidCallback onSkip;
  final VoidCallback onDoubleTapLike;
  final VoidCallback onToggleLike;
  final VoidCallback onToggleSave;
  final VoidCallback onExplain;
  final VoidCallback onShare;
  final VoidCallback onMore;
  final VoidCallback onOpenLaneSwitcher;

  /// Opens this card's topic as its own lane; null when already in it.
  final VoidCallback? onOpenTopic;
  final ValueChanged<String> onWrongReason;

  const FeedQuestionCard({
    super.key,
    required this.cardState,
    required this.isActive,
    required this.showGestureHint,
    required this.focusMode,
    required this.positionInLane,
    required this.laneLength,
    required this.onSelectOption,
    required this.onSkip,
    required this.onDoubleTapLike,
    required this.onToggleLike,
    required this.onToggleSave,
    required this.onExplain,
    required this.onShare,
    required this.onMore,
    required this.onOpenLaneSwitcher,
    required this.onOpenTopic,
    required this.onWrongReason,
  });

  @override
  State<FeedQuestionCard> createState() => _FeedQuestionCardState();
}

class _FeedQuestionCardState extends State<FeedQuestionCard> {
  bool _paused = false;
  DateTime? _pressStart;
  bool _showHeart = false;
  bool _showPeek = false;
  String? _selectedReason;
  int _xpPops = 0;
  int _shakes = 0;

  @override
  void initState() {
    super.initState();
    if (widget.cardState.isResolved) _startPeek();
  }

  @override
  void didUpdateWidget(covariant FeedQuestionCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    final justResolved = !oldWidget.cardState.isResolved && widget.cardState.isResolved;
    if (!justResolved) return;
    _startPeek();
    final card = widget.cardState;
    if (card.skipped) return;
    if (card.isCorrect) {
      _xpPops++;
    } else {
      _shakes++;
      HapticFeedback.heavyImpact();
    }
  }

  void _startPeek() {
    setState(() => _showPeek = true);
    Future.delayed(const Duration(milliseconds: 2200), () {
      if (mounted) setState(() => _showPeek = false);
    });
  }

  void _handleDoubleTap() {
    HapticFeedback.mediumImpact();
    widget.onDoubleTapLike();
    setState(() => _showHeart = true);
    Future.delayed(const Duration(milliseconds: 650), () {
      if (mounted) setState(() => _showHeart = false);
    });
  }

  void _handleLongPressStart(LongPressStartDetails details) {
    _pressStart = DateTime.now();
    setState(() => _paused = true);
  }

  void _handleLongPressEnd(LongPressEndDetails details) {
    setState(() => _paused = false);
    final start = _pressStart;
    _pressStart = null;
    if (start != null && DateTime.now().difference(start).inMilliseconds >= 1200) {
      widget.onMore();
    }
  }

  void _handleHorizontalDragEnd(DragEndDetails details) {
    final velocity = details.primaryVelocity ?? 0;
    if (velocity < -250) {
      widget.onExplain();
    } else if (velocity > 250) {
      widget.onOpenLaneSwitcher();
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final card = widget.cardState;
    final question = card.question;
    final resolved = card.isResolved;

    final options = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ..._buildOptions(question, card, resolved),
        if (resolved && _showPeek) _buildPeek(p, question, card),
        if (resolved && !card.isCorrect && !card.skipped) _buildWrongReasons(p),
      ],
    );

    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _Caption(
              topic: question.topicName,
              reason: card.reason,
              onTopicTap: widget.onOpenTopic,
              onMore: widget.onMore,
              timer: QuestionTimer(
                paused: _paused || !widget.isActive || resolved,
                color: p.textMuted,
              ),
            ),
            if (widget.positionInLane != null)
              _LaneProgress(position: widget.positionInLane!, length: widget.laneLength),
            const SizedBox(height: 8),
            Expanded(
              child: Stack(
                children: [
                  LayoutBuilder(
                    builder: (context, constraints) => SingleChildScrollView(
                      child: ConstrainedBox(
                        constraints: BoxConstraints(minHeight: constraints.maxHeight),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            GestureDetector(
                              behavior: HitTestBehavior.opaque,
                              onDoubleTap: _handleDoubleTap,
                              onLongPressStart: _handleLongPressStart,
                              onLongPressEnd: _handleLongPressEnd,
                              onHorizontalDragEnd: _handleHorizontalDragEnd,
                              child: _QuestionBox(text: question.questionText, showHeart: _showHeart),
                            ),
                            if (widget.showGestureHint)
                              Padding(
                                padding: const EdgeInsets.only(top: 6),
                                child: Text(
                                  'double-tap to like · swipe left for solution · swipe right for lanes',
                                  textAlign: TextAlign.center,
                                  style: Theme.of(context).textTheme.bodySmall!.copyWith(fontSize: 11),
                                ),
                              ),
                            const SizedBox(height: 12),
                            _shakes == 0 ? options : _Shake(key: ValueKey(_shakes), child: options),
                          ],
                        ),
                      ),
                    ),
                  ),
                  if (_xpPops > 0)
                    Positioned(
                      top: 0,
                      left: 0,
                      right: 0,
                      child: IgnorePointer(child: _XpPop(key: ValueKey(_xpPops))),
                    ),
                ],
              ),
            ),
            _ActionBar(
              card: card,
              focusMode: widget.focusMode,
              onToggleLike: widget.onToggleLike,
              onExplain: widget.onExplain,
              onShare: widget.onShare,
              onSkip: widget.onSkip,
              onToggleSave: widget.onToggleSave,
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> _buildOptions(PracticeQuestion question, FeedCardState card, bool resolved) {
    const labels = ['A', 'B', 'C', 'D', 'E', 'F'];
    return [
      for (var i = 0; i < question.options.length; i++)
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: OptionCard(
            option: question.options[i],
            label: labels[i % labels.length],
            isSelected: resolved
                ? (card.selectedOption == i || i == question.correctIndex)
                : card.selectedOption == i,
            isCorrect: resolved ? i == question.correctIndex : null,
            onTap: resolved
                ? null
                : () {
                    HapticFeedback.selectionClick();
                    widget.onSelectOption(i);
                  },
          ),
        ),
    ];
  }

  Widget _buildPeek(AppPalette p, PracticeQuestion question, FeedCardState card) {
    final explanation = question.explanation.trim();
    if (explanation.isEmpty) return const SizedBox.shrink();
    return AnimatedOpacity(
      opacity: _showPeek ? 1 : 0,
      duration: const Duration(milliseconds: 250),
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: card.isCorrect ? p.successSoft : p.dangerSoft,
          borderRadius: BorderRadius.circular(AppRadius.chip),
        ),
        child: Text(
          explanation,
          maxLines: 3,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(context).textTheme.bodyMedium!.copyWith(fontSize: 13),
        ),
      ),
    );
  }

  Widget _buildWrongReasons(AppPalette p) {
    final label = Theme.of(context).textTheme.labelSmall!;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final reason in kWrongAnswerReasons)
            GestureDetector(
              onTap: _selectedReason == null
                  ? () {
                      setState(() => _selectedReason = reason);
                      widget.onWrongReason(reason);
                    }
                  : null,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: _selectedReason == reason ? p.accentSoft : p.surfaceHigh,
                  borderRadius: BorderRadius.circular(AppRadius.pill),
                  border: Border.all(
                    color: _selectedReason == reason ? p.accentText : Colors.transparent,
                  ),
                ),
                child: Text(
                  reason,
                  style: label.copyWith(
                    color: _selectedReason == reason ? p.accentText : p.textMuted,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Topic "avatar", topic name, why this card was picked, timer and the
/// "more" menu — the author line of an Instagram post.
class _Caption extends StatelessWidget {
  final String topic;
  final String? reason;
  final VoidCallback? onTopicTap;
  final VoidCallback onMore;
  final Widget timer;

  const _Caption({
    required this.topic,
    required this.reason,
    required this.onTopicTap,
    required this.onMore,
    required this.timer,
  });

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final text = Theme.of(context).textTheme;
    final initial = topic.trim().isEmpty ? '?' : topic.trim()[0].toUpperCase();
    return SizedBox(
      height: 40,
      child: Row(
        children: [
          Expanded(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: onTopicTap,
              child: Row(
                children: [
                  Container(
                    width: 28,
                    height: 28,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(color: p.accent, shape: BoxShape.circle),
                    child: Text(
                      initial,
                      style: text.labelMedium!.copyWith(color: p.onAccent, fontWeight: FontWeight.w800),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text.rich(
                      TextSpan(
                        children: [
                          TextSpan(text: topic, style: const TextStyle(fontWeight: FontWeight.w800)),
                          if (reason != null)
                            TextSpan(
                              text: ' · $reason',
                              style: TextStyle(fontWeight: FontWeight.w500, color: p.textMuted),
                            ),
                        ],
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: text.bodyMedium!.copyWith(fontSize: 13),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 8),
          timer,
          IconButton(
            tooltip: 'More',
            onPressed: onMore,
            icon: Icon(Icons.more_horiz_rounded, color: p.textMuted),
          ),
        ],
      ),
    );
  }
}

class _LaneProgress extends StatelessWidget {
  final int position;
  final int length;

  const _LaneProgress({required this.position, required this.length});

  @override
  Widget build(BuildContext context) {
    final total = length == 0 ? 1 : length;
    return Row(
      children: [
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(AppRadius.pill),
            child: LinearProgressIndicator(value: (position / total).clamp(0.0, 1.0), minHeight: 3),
          ),
        ),
        const SizedBox(width: 10),
        Text('$position/$length', style: Theme.of(context).textTheme.bodySmall),
      ],
    );
  }
}

class _QuestionBox extends StatelessWidget {
  final String text;
  final bool showHeart;

  const _QuestionBox({required this.text, required this.showHeart});

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Stack(
      alignment: Alignment.center,
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 24),
          decoration: BoxDecoration(
            color: p.surface,
            borderRadius: BorderRadius.circular(AppRadius.card),
            border: Border.all(color: p.border),
          ),
          child: Text(
            text,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.titleMedium!.copyWith(fontSize: 19, height: 1.4),
          ),
        ),
        IgnorePointer(
          child: AnimatedOpacity(
            opacity: showHeart ? 1 : 0,
            duration: const Duration(milliseconds: 200),
            child: AnimatedScale(
              scale: showHeart ? 1.0 : 0.6,
              duration: const Duration(milliseconds: 200),
              child: Icon(Icons.favorite_rounded, color: p.like, size: 84),
            ),
          ),
        ),
      ],
    );
  }
}

/// "+10 XP" floating up and fading out once, when an answer is correct.
class _XpPop extends StatelessWidget {
  const _XpPop({super.key});

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 1100),
      curve: Curves.easeOut,
      builder: (context, t, _) {
        final opacity = t < 0.2 ? t / 0.2 : (t > 0.7 ? (1 - t) / 0.3 : 1.0);
        return Opacity(
          opacity: opacity.clamp(0.0, 1.0),
          child: Transform.translate(
            offset: Offset(0, 10 - 36 * t),
            child: Center(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                decoration: BoxDecoration(color: p.accent, borderRadius: BorderRadius.circular(AppRadius.pill)),
                child: Text(
                  '+$kFeedXpPerCorrect XP',
                  style: Theme.of(context).textTheme.labelLarge!.copyWith(
                    color: p.onAccent,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

/// A short horizontal shake, played once when mounted, for a wrong answer.
class _Shake extends StatelessWidget {
  final Widget child;

  const _Shake({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 380),
      builder: (context, t, child) => Transform.translate(
        offset: Offset(math.sin(t * math.pi * 6) * (1 - t) * 9, 0),
        child: child,
      ),
      child: child,
    );
  }
}

class _ActionBar extends StatelessWidget {
  final FeedCardState card;
  final bool focusMode;
  final VoidCallback onToggleLike;
  final VoidCallback onExplain;
  final VoidCallback onShare;
  final VoidCallback onSkip;
  final VoidCallback onToggleSave;

  const _ActionBar({
    required this.card,
    required this.focusMode,
    required this.onToggleLike,
    required this.onExplain,
    required this.onShare,
    required this.onSkip,
    required this.onToggleSave,
  });

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return SizedBox(
      height: 48,
      child: Row(
        children: [
          IconButton(
            tooltip: card.liked ? 'Unlike' : 'Like',
            onPressed: () {
              HapticFeedback.lightImpact();
              onToggleLike();
            },
            icon: Icon(
              card.liked ? Icons.favorite_rounded : Icons.favorite_border_rounded,
              color: card.liked ? p.like : p.text,
            ),
          ),
          IconButton(tooltip: 'Explanation', onPressed: onExplain, icon: const Icon(Icons.mode_comment_outlined)),
          IconButton(tooltip: 'Share', onPressed: onShare, icon: const Icon(Icons.send_rounded)),
          Expanded(
            child: card.isResolved
                ? const SizedBox.shrink()
                : Align(
                    alignment: Alignment.centerRight,
                    child: TextButton(
                      onPressed: () {
                        HapticFeedback.lightImpact();
                        onSkip();
                      },
                      child: Text(focusMode ? 'Skip ›' : 'Show answer', maxLines: 1, overflow: TextOverflow.ellipsis),
                    ),
                  ),
          ),
          IconButton(
            tooltip: card.bookmarked ? 'Remove from saved' : 'Save',
            onPressed: onToggleSave,
            icon: Icon(
              card.bookmarked ? Icons.bookmark_rounded : Icons.bookmark_border_rounded,
              color: card.bookmarked ? p.accentText : p.text,
            ),
          ),
        ],
      ),
    );
  }
}
