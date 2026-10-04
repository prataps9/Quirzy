import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../shared/theme/practice_theme.dart';
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
/// share, more, save). Vertical swiping belongs to the enclosing
/// PageView. The question box handles double-tap to like, long-press for
/// the menu, and horizontal swipes for the solution or lane switcher.
/// Options sit outside that region so answering stays instant.
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

  @override
  void initState() {
    super.initState();
    if (widget.cardState.isResolved) _startPeek();
  }

  @override
  void didUpdateWidget(covariant FeedQuestionCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!oldWidget.cardState.isResolved && widget.cardState.isResolved) {
      _startPeek();
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
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final card = widget.cardState;
    final question = card.question;
    final resolved = card.isResolved;
    final muted = isDark ? Colors.white60 : Colors.black54;

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
              mutedColor: muted,
              onTopicTap: widget.onOpenTopic,
              onMore: widget.onMore,
              timer: QuestionTimer(
                paused: _paused || !widget.isActive || resolved,
                color: muted,
              ),
            ),
            if (widget.positionInLane != null)
              _LaneProgress(
                position: widget.positionInLane!,
                length: widget.laneLength,
                isDark: isDark,
              ),
            const SizedBox(height: 8),
            Expanded(
              child: LayoutBuilder(
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
                          child: _QuestionBox(
                            text: question.questionText,
                            isDark: isDark,
                            showHeart: _showHeart,
                          ),
                        ),
                        if (widget.showGestureHint)
                          Padding(
                            padding: const EdgeInsets.only(top: 6),
                            child: Text(
                              'double-tap to like · swipe left for solution · swipe right for lanes',
                              textAlign: TextAlign.center,
                              style: GoogleFonts.plusJakartaSans(
                                fontSize: 11,
                                fontWeight: FontWeight.w500,
                                color: muted.withOpacity(0.6),
                              ),
                            ),
                          ),
                        const SizedBox(height: 12),
                        ..._buildOptions(isDark, question, card, resolved),
                        if (resolved && _showPeek) _buildPeek(isDark, question, card),
                        if (resolved && !card.isCorrect && !card.skipped) _buildWrongReasons(isDark),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            _ActionBar(
              card: card,
              focusMode: widget.focusMode,
              mutedColor: muted,
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

  List<Widget> _buildOptions(
    bool isDark,
    PracticeQuestion question,
    FeedCardState card,
    bool resolved,
  ) {
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
            isDark: isDark,
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

  Widget _buildPeek(bool isDark, PracticeQuestion question, FeedCardState card) {
    final explanation = question.explanation.trim();
    if (explanation.isEmpty) return const SizedBox.shrink();
    return AnimatedOpacity(
      opacity: _showPeek ? 1 : 0,
      duration: const Duration(milliseconds: 250),
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: (card.isCorrect ? PracticeTheme.success : PracticeTheme.error).withOpacity(0.08),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Text(
          explanation,
          maxLines: 3,
          overflow: TextOverflow.ellipsis,
          style: GoogleFonts.plusJakartaSans(
            fontSize: 13,
            fontWeight: FontWeight.w500,
            color: isDark ? Colors.white70 : Colors.black87,
          ),
        ),
      ),
    );
  }

  Widget _buildWrongReasons(bool isDark) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: kWrongAnswerReasons.map((reason) {
          final selected = _selectedReason == reason;
          return GestureDetector(
            onTap: _selectedReason == null
                ? () {
                    setState(() => _selectedReason = reason);
                    widget.onWrongReason(reason);
                  }
                : null,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: selected
                    ? PracticeTheme.primary.withOpacity(0.12)
                    : (isDark ? Colors.white10 : Colors.black.withOpacity(0.04)),
                borderRadius: BorderRadius.circular(999),
                border: Border.all(color: selected ? PracticeTheme.primary : Colors.transparent),
              ),
              child: Text(
                reason,
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: selected ? PracticeTheme.primary : (isDark ? Colors.white60 : Colors.black54),
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}

/// Topic "avatar", topic name, why this card was picked, timer and the
/// "more" menu — the author line of an Instagram post.
class _Caption extends StatelessWidget {
  final String topic;
  final String? reason;
  final Color mutedColor;
  final VoidCallback? onTopicTap;
  final VoidCallback onMore;
  final Widget timer;

  const _Caption({
    required this.topic,
    required this.reason,
    required this.mutedColor,
    required this.onTopicTap,
    required this.onMore,
    required this.timer,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
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
                    decoration: BoxDecoration(
                      color: PracticeTheme.primary.withOpacity(0.12),
                      shape: BoxShape.circle,
                    ),
                    child: Text(
                      initial,
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                        color: PracticeTheme.primary,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text.rich(
                      TextSpan(
                        children: [
                          TextSpan(
                            text: topic,
                            style: GoogleFonts.plusJakartaSans(
                              fontWeight: FontWeight.w800,
                              color: isDark ? Colors.white : Colors.black87,
                            ),
                          ),
                          if (reason != null)
                            TextSpan(
                              text: ' · $reason',
                              style: GoogleFonts.plusJakartaSans(
                                fontWeight: FontWeight.w500,
                                color: mutedColor,
                              ),
                            ),
                        ],
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 13),
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
            icon: Icon(Icons.more_horiz_rounded, color: mutedColor),
          ),
        ],
      ),
    );
  }
}

class _LaneProgress extends StatelessWidget {
  final int position;
  final int length;
  final bool isDark;

  const _LaneProgress({required this.position, required this.length, required this.isDark});

  @override
  Widget build(BuildContext context) {
    final total = length == 0 ? 1 : length;
    return Row(
      children: [
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              value: (position / total).clamp(0.0, 1.0),
              minHeight: 3,
              backgroundColor: isDark ? Colors.white12 : Colors.black12,
              valueColor: const AlwaysStoppedAnimation(PracticeTheme.primary),
            ),
          ),
        ),
        const SizedBox(width: 10),
        Text(
          '$position/$length',
          style: GoogleFonts.plusJakartaSans(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: isDark ? Colors.white38 : Colors.black38,
          ),
        ),
      ],
    );
  }
}

class _QuestionBox extends StatelessWidget {
  final String text;
  final bool isDark;
  final bool showHeart;

  const _QuestionBox({required this.text, required this.isDark, required this.showHeart});

  @override
  Widget build(BuildContext context) {
    return Stack(
      alignment: Alignment.center,
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 22),
          decoration: PracticeTheme.cardDecoration(isDark: isDark),
          child: Text(
            text,
            textAlign: TextAlign.center,
            style: GoogleFonts.plusJakartaSans(
              fontSize: 18,
              height: 1.4,
              fontWeight: FontWeight.w600,
              color: isDark ? Colors.white : const Color(0xFF1A1A2E),
            ),
          ),
        ),
        IgnorePointer(
          child: AnimatedOpacity(
            opacity: showHeart ? 1 : 0,
            duration: const Duration(milliseconds: 200),
            child: AnimatedScale(
              scale: showHeart ? 1.0 : 0.6,
              duration: const Duration(milliseconds: 200),
              child: const Icon(Icons.favorite_rounded, color: PracticeTheme.accent, size: 84),
            ),
          ),
        ),
      ],
    );
  }
}

class _ActionBar extends StatelessWidget {
  final FeedCardState card;
  final bool focusMode;
  final Color mutedColor;
  final VoidCallback onToggleLike;
  final VoidCallback onExplain;
  final VoidCallback onShare;
  final VoidCallback onSkip;
  final VoidCallback onToggleSave;

  const _ActionBar({
    required this.card,
    required this.focusMode,
    required this.mutedColor,
    required this.onToggleLike,
    required this.onExplain,
    required this.onShare,
    required this.onSkip,
    required this.onToggleSave,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final iconColor = isDark ? Colors.white : Colors.black87;
    return SizedBox(
      height: 48,
      child: Row(
        children: [
          _ActionIcon(
            icon: card.liked ? Icons.favorite_rounded : Icons.favorite_border_rounded,
            color: card.liked ? PracticeTheme.accent : iconColor,
            tooltip: card.liked ? 'Unlike' : 'Like',
            onPressed: () {
              HapticFeedback.lightImpact();
              onToggleLike();
            },
          ),
          _ActionIcon(icon: Icons.mode_comment_outlined, color: iconColor, tooltip: 'Explanation', onPressed: onExplain),
          _ActionIcon(icon: Icons.send_rounded, color: iconColor, tooltip: 'Share', onPressed: onShare),
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
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        visualDensity: VisualDensity.compact,
                      ),
                      child: Text(
                        focusMode ? 'Skip ›' : 'Show answer',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: PracticeTheme.primary,
                        ),
                      ),
                    ),
                  ),
          ),
          _ActionIcon(
            icon: card.bookmarked ? Icons.bookmark_rounded : Icons.bookmark_border_rounded,
            color: card.bookmarked ? PracticeTheme.primary : iconColor,
            tooltip: card.bookmarked ? 'Remove from saved' : 'Save',
            onPressed: onToggleSave,
          ),
        ],
      ),
    );
  }
}

class _ActionIcon extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String tooltip;
  final VoidCallback onPressed;

  const _ActionIcon({
    required this.icon,
    required this.color,
    required this.tooltip,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: tooltip,
      onPressed: onPressed,
      icon: Icon(icon, size: 24, color: color),
    );
  }
}
