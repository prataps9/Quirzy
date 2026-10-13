import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../shared/theme/app_palette.dart';
import '../../flashcards/services/srs_service.dart';
import '../models/feed_models.dart';

/// "Is this the answer?" — the shown option and two big verdict buttons.
/// After answering, the verdict buttons turn green/red and the real answer
/// is shown if the shown one was wrong.
class TrueFalseBody extends StatelessWidget {
  final FeedCardState card;
  final ValueChanged<bool> onAnswer;

  const TrueFalseBody({super.key, required this.card, required this.onAnswer});

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final text = Theme.of(context).textTheme;
    final q = card.question;
    final shown = q.options[card.tfShownOption!];
    final resolved = card.isResolved;

    Widget verdict(bool value) {
      final label = value ? 'True' : 'False';
      final isRight = value == card.tfStatementTrue;
      final picked = card.tfChoice == value;
      Color fill = p.surface;
      Color border = p.border;
      Color fg = p.text;
      if (resolved && isRight) {
        fill = p.successSoft;
        border = p.success;
        fg = p.success;
      } else if (resolved && picked) {
        fill = p.dangerSoft;
        border = p.danger;
        fg = p.danger;
      }
      return Expanded(
        child: Semantics(
          button: true,
          label: label,
          child: Material(
            color: fill,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppRadius.card),
              side: BorderSide(color: border, width: resolved && (isRight || picked) ? 2 : 1),
            ),
            child: InkWell(
              borderRadius: BorderRadius.circular(AppRadius.card),
              onTap: resolved
                  ? null
                  : () {
                      HapticFeedback.selectionClick();
                      onAnswer(value);
                    },
              child: SizedBox(
                height: 64,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(value ? Icons.check_rounded : Icons.close_rounded, color: fg),
                    const SizedBox(width: 8),
                    Text(label, style: text.titleMedium!.copyWith(color: fg, fontWeight: FontWeight.w800)),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Is this the answer?', textAlign: TextAlign.center, style: text.labelLarge!.copyWith(color: p.textMuted)),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            color: p.surfaceHigh,
            borderRadius: BorderRadius.circular(AppRadius.chip),
            border: Border.all(color: p.border),
          ),
          child: Text(shown, textAlign: TextAlign.center, style: text.titleMedium),
        ),
        const SizedBox(height: 12),
        Row(children: [verdict(true), const SizedBox(width: 12), verdict(false)]),
        if (resolved && !card.tfStatementTrue) ...[
          const SizedBox(height: 12),
          _AnswerLine(answer: q.options[q.correctIndex]),
        ],
      ],
    );
  }
}

/// The correct answer, in green, used by True/False and fact cards.
class _AnswerLine extends StatelessWidget {
  final String answer;

  const _AnswerLine({required this.answer});

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final text = Theme.of(context).textTheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: p.successSoft,
        borderRadius: BorderRadius.circular(AppRadius.chip),
        border: Border.all(color: p.success),
      ),
      child: Row(
        children: [
          Icon(Icons.check_circle_rounded, color: p.success, size: 20),
          const SizedBox(width: 10),
          Expanded(child: Text(answer, style: text.titleSmall)),
        ],
      ),
    );
  }
}

/// How long a fact card stays up: about 4 words a second plus a beat,
/// between 4 and 12 seconds.
Duration factReadingTime(PracticeQuestion q) {
  final words = '${q.questionText} ${q.options[q.correctIndex]} ${q.explanation}'
      .split(RegExp(r'\s+'))
      .where((w) => w.isNotEmpty)
      .length;
  final ms = (words / 4 * 1000).round() + 2000;
  return Duration(milliseconds: ms.clamp(4000, 12000));
}

/// "Remember this?" — a question you missed, its answer and why, with a
/// story-style bar that fills while you read. Holding pauses it.
class FactBody extends StatelessWidget {
  final FeedCardState card;

  const FactBody({super.key, required this.card});

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final text = Theme.of(context).textTheme;
    final q = card.question;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.history_edu_rounded, size: 18, color: p.accentText),
            const SizedBox(width: 6),
            Text('Remember this?', style: text.labelLarge!.copyWith(color: p.accentText, fontWeight: FontWeight.w800)),
          ],
        ),
        const SizedBox(height: 10),
        Text(q.questionText, textAlign: TextAlign.center, style: text.titleMedium!.copyWith(fontSize: 18, height: 1.4)),
        const SizedBox(height: 14),
        _AnswerLine(answer: q.options[q.correctIndex]),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: p.surface,
            borderRadius: BorderRadius.circular(AppRadius.chip),
            border: Border.all(color: p.border),
          ),
          child: Text(q.explanation.trim(), style: text.bodyMedium!.copyWith(height: 1.45)),
        ),
      ],
    );
  }
}

/// The thin bar at the top of a fact card. Fills over [duration] while
/// [running], then calls [onDone] once.
class StoryBar extends StatefulWidget {
  final Duration duration;
  final bool running;
  final bool done;
  final VoidCallback onDone;

  const StoryBar({
    super.key,
    required this.duration,
    required this.running,
    required this.done,
    required this.onDone,
  });

  @override
  State<StoryBar> createState() => _StoryBarState();
}

class _StoryBarState extends State<StoryBar> with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(vsync: this, duration: widget.duration)
    ..addStatusListener((status) {
      if (status == AnimationStatus.completed) widget.onDone();
    });

  @override
  void initState() {
    super.initState();
    if (widget.done) {
      _controller.value = 1;
    } else if (widget.running) {
      _controller.forward();
    }
  }

  @override
  void didUpdateWidget(covariant StoryBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.done) {
      _controller.stop();
      _controller.value = 1;
    } else if (widget.running && !_controller.isAnimating) {
      _controller.forward();
    } else if (!widget.running && _controller.isAnimating) {
      _controller.stop();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return ClipRRect(
      borderRadius: BorderRadius.circular(AppRadius.pill),
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) => LinearProgressIndicator(
          value: _controller.value,
          minHeight: 3,
          backgroundColor: p.border,
          color: p.accentText,
        ),
      ),
    );
  }
}

/// A due flashcard: tap to flip, then rate it like in Cards.
class FlashcardBody extends StatelessWidget {
  final FeedCardState card;
  final VoidCallback onFlip;
  final ValueChanged<SrsRating> onRate;

  const FlashcardBody({super.key, required this.card, required this.onFlip, required this.onRate});

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final text = Theme.of(context).textTheme;
    final flashcard = card.flashcard!;
    final flipped = card.flipped;

    final face = Container(
      key: ValueKey(flipped),
      width: double.infinity,
      constraints: const BoxConstraints(minHeight: 220),
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 28),
      decoration: BoxDecoration(
        color: flipped ? p.surfaceHigh : p.surface,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: flipped ? p.accentText : p.border, width: flipped ? 1.5 : 1),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            flipped ? 'ANSWER' : 'FLASHCARD',
            style: text.labelSmall!.copyWith(letterSpacing: 1.2, color: flipped ? p.accentText : p.textMuted),
          ),
          const SizedBox(height: 14),
          Text(
            flipped ? flashcard.back : flashcard.front,
            textAlign: TextAlign.center,
            style: text.titleMedium!.copyWith(fontSize: 19, height: 1.4),
          ),
          if (!flipped) ...[
            const SizedBox(height: 18),
            Text('Tap to flip', style: text.bodySmall),
          ],
        ],
      ),
    );

    Widget rate(SrsRating rating, String label, IconData icon, {required bool primary}) {
      final onPressed = card.rated
          ? null
          : () {
              HapticFeedback.selectionClick();
              onRate(rating);
            };
      final child = Row(
        mainAxisAlignment: MainAxisAlignment.center,
        mainAxisSize: MainAxisSize.min,
        children: [Icon(icon, size: 20), const SizedBox(width: 8), Text(label)],
      );
      return Expanded(
        child: SizedBox(
          height: 52,
          child: primary
              ? FilledButton(onPressed: onPressed, child: child)
              : OutlinedButton(onPressed: onPressed, child: child),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        GestureDetector(
          onTap: flipped
              ? null
              : () {
                  HapticFeedback.lightImpact();
                  onFlip();
                },
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 220),
            transitionBuilder: (child, animation) => AnimatedBuilder(
              animation: animation,
              child: child,
              builder: (context, child) => Transform(
                alignment: Alignment.center,
                transform: Matrix4.diagonal3Values(math.max(animation.value, 0.01), 1, 1),
                child: child,
              ),
            ),
            child: face,
          ),
        ),
        const SizedBox(height: 14),
        if (flipped)
          card.rated
              ? Text(
                  'Saved to your review schedule',
                  textAlign: TextAlign.center,
                  style: text.bodySmall!.copyWith(color: p.success),
                )
              : Row(
                  children: [
                    rate(SrsRating.again, 'Again', Icons.replay_rounded, primary: false),
                    const SizedBox(width: 12),
                    rate(SrsRating.good, 'Got it', Icons.check_rounded, primary: true),
                  ],
                ),
      ],
    );
  }
}
