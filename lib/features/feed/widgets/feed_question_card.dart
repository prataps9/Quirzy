import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../shared/theme/app_motion.dart';
import '../../../shared/theme/app_palette.dart';
import '../../../shared/theme/app_text.dart';
import '../../flashcards/services/srs_service.dart';
import '../models/feed_models.dart';
import '../models/topic_style.dart';
import 'card_swipe_layer.dart';
import 'feed_card_bodies.dart';
import 'option_card.dart';
import 'question_timer.dart';

const List<String> kWrongAnswerReasons = ['Silly mistake', "Didn't know", 'Ran out of time', 'Misread it'];

/// One full-screen card in the feed, laid out like an Instagram post, on
/// its topic's own background tint.
///
/// From top to bottom: a caption row (topic, why it was picked, timer),
/// the body for the card's [FeedCardKind] (question and options, True/
/// False, a "Remember this?" fact, or a flashcard), then an action bar.
/// Vertical swiping belongs to the enclosing PageView. A horizontal swipe
/// anywhere on the card opens the solution (left) or the topic dial
/// (right); the question box handles double-tap to like and long-press for
/// the menu, and answer controls sit outside it so answering stays instant.
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
  final ValueChanged<bool> onTrueFalse;
  final VoidCallback onFactDone;
  final VoidCallback onFlip;
  final ValueChanged<SrsRating> onRate;

  /// Read-aloud state for the speaker button.
  final bool soundOn;
  final VoidCallback onToggleSound;

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
    required this.onTrueFalse,
    required this.onFactDone,
    required this.onFlip,
    required this.onRate,
    required this.soundOn,
    required this.onToggleSound,
  });

  @override
  State<FeedQuestionCard> createState() => _FeedQuestionCardState();
}

class _FeedQuestionCardState extends State<FeedQuestionCard> with SingleTickerProviderStateMixin {
  bool _paused = false;
  DateTime? _pressStart;
  int _heartPops = 0;
  Timer? _peekTimer;

  /// Plays once, the first time this card is the one on screen, so content
  /// eases in instead of just being there.
  late final AnimationController _enter = AnimationController(vsync: this, duration: AppMotion.slow);
  bool _showPeek = false;
  String? _selectedReason;
  int _xpPops = 0;
  int _shakes = 0;

  @override
  void initState() {
    super.initState();
    if (widget.cardState.isResolved) {
      _enter.value = 1; // seen before: nothing to introduce
      _startPeek();
    } else if (widget.isActive) {
      _enter.forward();
    }
  }

  @override
  void dispose() {
    _peekTimer?.cancel();
    _enter.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant FeedQuestionCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!oldWidget.isActive && widget.isActive && _enter.value == 0) _enter.forward();
    final justResolved = !oldWidget.cardState.isResolved && widget.cardState.isResolved;
    if (!justResolved) return;
    _startPeek();
    final card = widget.cardState;
    if (card.skipped || !card.isQuiz) return;
    if (card.isCorrect) {
      _xpPops++;
      HapticFeedback.mediumImpact();
    } else {
      _shakes++;
      HapticFeedback.heavyImpact();
    }
  }

  void _startPeek() {
    setState(() => _showPeek = true);
    _peekTimer?.cancel();
    _peekTimer = Timer(const Duration(milliseconds: 2200), () {
      if (mounted) setState(() => _showPeek = false);
    });
  }

  void _handleDoubleTap() {
    HapticFeedback.mediumImpact();
    widget.onDoubleTapLike();
    // A new key each time, so every double-tap plays the pop from the start.
    setState(() => _heartPops++);
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

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final card = widget.cardState;
    final question = card.question;
    final resolved = card.isResolved;
    final style = TopicStyle.of(question.topicName);
    final isQuiz = card.isQuiz;

    final Widget answers = switch (card.kind) {
      FeedCardKind.question => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ..._buildOptions(question, card, resolved),
          Reveal(show: resolved && _showPeek, child: _buildPeek(p, question, card)),
          Reveal(show: resolved && !card.isCorrect && !card.skipped, child: _buildWrongReasons(p)),
        ],
      ),
      FeedCardKind.trueFalse => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TrueFalseBody(card: card, onAnswer: widget.onTrueFalse),
          const SizedBox(height: 8),
          Reveal(show: resolved && _showPeek, child: _buildPeek(p, question, card)),
        ],
      ),
      _ => const SizedBox.shrink(),
    };

    final Widget body = switch (card.kind) {
      FeedCardKind.fact => GestureDetector(
        behavior: HitTestBehavior.opaque,
        onDoubleTap: _handleDoubleTap,
        onLongPressStart: _handleLongPressStart,
        onLongPressEnd: _handleLongPressEnd,
        child: Stack(
          alignment: Alignment.center,
          children: [
            FactBody(card: card),
            _Heart(pops: _heartPops),
          ],
        ),
      ),
      FeedCardKind.flashcard => FlashcardBody(card: card, onFlip: widget.onFlip, onRate: widget.onRate),
      _ => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onDoubleTap: _handleDoubleTap,
            onLongPressStart: _handleLongPressStart,
            onLongPressEnd: _handleLongPressEnd,
            child: _QuestionBox(text: question.questionText, heartPops: _heartPops),
          ),
          if (widget.showGestureHint)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                'Double-tap to like · swipe left for the solution · swipe right for topics',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.labelSmall!.copyWith(color: context.palette.textMuted),
              ),
            ),
          const SizedBox(height: 12),
          _Shake(trigger: _shakes, child: answers),
        ],
      ),
    };

    return ColoredBox(
      color: style.tint(Theme.of(context).brightness),
      child: CardSwipeLayer(
        // A flashcard flips and rates with its own gestures.
        enabled: card.kind != FeedCardKind.flashcard,
        onSwipeLeft: widget.onExplain,
        onSwipeRight: widget.onOpenLaneSwitcher,
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _Caption(
                  topic: question.topicName,
                  icon: style.icon,
                  reason: card.reason,
                  onTopicTap: widget.onOpenTopic,
                  // A flashcard wraps a set, not a feed question: the menu's
                  // topic and difficulty actions don't apply to it.
                  onMore: card.kind == FeedCardKind.flashcard ? null : widget.onMore,
                  soundOn: widget.soundOn,
                  onToggleSound: widget.onToggleSound,
                  timer: isQuiz
                      ? QuestionTimer(paused: _paused || !widget.isActive || resolved, color: p.textMuted)
                      : null,
                ),
                if (card.kind == FeedCardKind.fact)
                  StoryBar(
                    key: ValueKey('story-${card.uid}'),
                    duration: factReadingTime(question),
                    running: widget.isActive && !_paused,
                    done: card.acknowledged,
                    onDone: widget.onFactDone,
                  )
                else if (widget.positionInLane != null)
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
                              children: [_Entrance(animation: _enter, child: body)],
                            ),
                          ),
                        ),
                      ),
                      if (_xpPops > 0)
                        Positioned(
                          top: 0,
                          left: 0,
                          right: 0,
                          child: IgnorePointer(
                            child: _XpPop(
                              key: ValueKey(_xpPops),
                              xp: card.kind == FeedCardKind.trueFalse ? kFeedXpPerTrueFalse : kFeedXpPerCorrect,
                            ),
                          ),
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
                  onFactDone: widget.onFactDone,
                  onToggleSave: widget.onToggleSave,
                ),
              ],
            ),
          ),
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
            isSelected: resolved ? (card.selectedOption == i || i == question.correctIndex) : card.selectedOption == i,
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
    return Container(
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
        style: Theme.of(context).textTheme.caption,
      ),
    );
  }

  Widget _buildWrongReasons(AppPalette p) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Wrap(
        spacing: 8,
        runSpacing: 4,
        children: [
          for (final reason in kWrongAnswerReasons)
            ChoiceChip(
              label: Text(reason),
              selected: _selectedReason == reason,
              showCheckmark: false,
              onSelected: _selectedReason == null
                  ? (_) {
                      HapticFeedback.selectionClick();
                      setState(() => _selectedReason = reason);
                      widget.onWrongReason(reason);
                    }
                  : null,
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
  final IconData icon;
  final String? reason;
  final VoidCallback? onTopicTap;
  final VoidCallback? onMore;
  final Widget? timer;
  final bool soundOn;
  final VoidCallback onToggleSound;

  const _Caption({
    required this.topic,
    required this.icon,
    required this.reason,
    required this.onTopicTap,
    required this.onMore,
    required this.soundOn,
    required this.onToggleSound,
    required this.timer,
  });

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final text = Theme.of(context).textTheme;
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
                    child: Icon(icon, size: 16, color: p.onAccent),
                  ),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text.rich(
                      TextSpan(
                        children: [
                          TextSpan(
                            text: topic,
                            style: const TextStyle(fontWeight: FontWeight.w800),
                          ),
                          if (reason != null)
                            TextSpan(
                              text: ' · $reason',
                              style: TextStyle(fontWeight: FontWeight.w500, color: p.textMuted),
                            ),
                        ],
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: text.caption,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 8),
          ?timer,
          IconButton(
            tooltip: soundOn ? 'Stop reading aloud' : 'Read aloud',
            visualDensity: VisualDensity.compact,
            onPressed: () {
              HapticFeedback.selectionClick();
              onToggleSound();
            },
            icon: Icon(
              soundOn ? Icons.volume_up_rounded : Icons.volume_off_rounded,
              size: 20,
              color: soundOn ? p.accentText : p.textMuted,
            ),
          ),
          if (onMore != null)
            IconButton(
              tooltip: 'More',
              visualDensity: VisualDensity.compact,
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
  final int heartPops;

  const _QuestionBox({required this.text, required this.heartPops});

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
          child: Text(text, textAlign: TextAlign.center, style: Theme.of(context).textTheme.question),
        ),
        _Heart(pops: heartPops),
      ],
    );
  }
}

/// The big heart that pops on double-tap: it grows past full size, settles,
/// then fades. Each double-tap ([pops] going up) plays it again.
class _Heart extends StatelessWidget {
  final int pops;

  const _Heart({required this.pops});

  @override
  Widget build(BuildContext context) {
    if (pops == 0) return const SizedBox.shrink();
    final reduced = AppMotion.reduced(context);
    return IgnorePointer(
      child: TweenAnimationBuilder<double>(
        key: ValueKey(pops),
        tween: Tween(begin: 0, end: 1),
        duration: AppMotion.of(context, const Duration(milliseconds: 700)),
        builder: (context, t, child) {
          final scale = reduced
              ? 1.0
              : t < 0.3
              ? 0.5 + 0.7 * Curves.easeOut.transform(t / 0.3)
              : t < 0.45
              ? 1.2 - 0.2 * ((t - 0.3) / 0.15)
              : 1.0;
          final opacity = t < 0.6 ? 1.0 : 1 - (t - 0.6) / 0.4;
          return Opacity(opacity: opacity.clamp(0.0, 1.0), child: Transform.scale(scale: scale, child: child));
        },
        child: Icon(Icons.favorite_rounded, color: context.palette.like, size: 84),
      ),
    );
  }
}

/// "+10 XP" floating up and fading out once, when an answer is correct.
class _XpPop extends StatelessWidget {
  final int xp;

  const _XpPop({super.key, required this.xp});

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
                  '+$xp XP',
                  style: Theme.of(
                    context,
                  ).textTheme.labelLarge!.copyWith(color: p.onAccent, fontWeight: FontWeight.w800),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

/// A short horizontal shake that plays each time [trigger] goes up (a wrong
/// answer). The child stays in the same place in the tree throughout, so the
/// colour fades on the options still play.
class _Shake extends StatefulWidget {
  final int trigger;
  final Widget child;

  const _Shake({required this.trigger, required this.child});

  @override
  State<_Shake> createState() => _ShakeState();
}

class _ShakeState extends State<_Shake> with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 380),
    value: 1,
  );

  @override
  void didUpdateWidget(_Shake old) {
    super.didUpdateWidget(old);
    if (widget.trigger != old.trigger && !AppMotion.reduced(context)) _controller.forward(from: 0);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      child: widget.child,
      builder: (context, child) {
        final t = _controller.value;
        return Transform.translate(offset: Offset(math.sin(t * math.pi * 6) * (1 - t) * 9, 0), child: child);
      },
    );
  }
}

/// Fades and lifts a card's content in as [animation] runs from 0 to 1.
class _Entrance extends StatelessWidget {
  final Animation<double> animation;
  final Widget child;

  const _Entrance({required this.animation, required this.child});

  @override
  Widget build(BuildContext context) {
    if (AppMotion.reduced(context)) return child;
    final curved = CurvedAnimation(parent: animation, curve: AppMotion.enter);
    return AnimatedBuilder(
      animation: curved,
      child: child,
      builder: (context, child) => Opacity(
        opacity: 0.45 + 0.55 * curved.value,
        child: Transform.translate(offset: Offset(0, 14 * (1 - curved.value)), child: child),
      ),
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
  final VoidCallback onFactDone;
  final VoidCallback onToggleSave;

  const _ActionBar({
    required this.card,
    required this.focusMode,
    required this.onToggleLike,
    required this.onExplain,
    required this.onShare,
    required this.onSkip,
    required this.onFactDone,
    required this.onToggleSave,
  });

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final isFlashcard = card.kind == FeedCardKind.flashcard;

    Widget? trailingAction() {
      if (card.isResolved) return null;
      if (card.isQuiz) {
        return TextButton(
          onPressed: () {
            HapticFeedback.lightImpact();
            onSkip();
          },
          child: Text(focusMode ? 'Skip' : 'Show answer', maxLines: 1, overflow: TextOverflow.ellipsis),
        );
      }
      if (card.kind == FeedCardKind.fact) {
        return TextButton(
          onPressed: () {
            HapticFeedback.lightImpact();
            onFactDone();
          },
          child: const Text('Got it', maxLines: 1),
        );
      }
      return null;
    }

    return SizedBox(
      height: 48,
      child: Row(
        children: [
          if (!isFlashcard) ...[
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
          ],
          Expanded(
            child: Align(alignment: Alignment.centerRight, child: trailingAction() ?? const SizedBox.shrink()),
          ),
          if (!isFlashcard)
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
