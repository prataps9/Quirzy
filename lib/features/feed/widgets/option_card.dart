import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../shared/theme/app_motion.dart';
import '../../../shared/theme/app_palette.dart';
import '../../../shared/theme/app_text.dart';

/// One answer choice. Before an answer it is a quiet outlined row; once
/// revealed the right option turns green and a wrong pick turns red, each
/// with an icon so colour is never the only signal. The colours fade, the
/// icon pops in, and the right answer gives a small bounce.
class OptionCard extends StatefulWidget {
  final String option;
  final String label;
  final bool isSelected;
  final bool? isCorrect; // null = not revealed yet
  final VoidCallback? onTap;

  const OptionCard({
    super.key,
    required this.option,
    required this.label,
    required this.isSelected,
    this.isCorrect,
    required this.onTap,
  });

  @override
  State<OptionCard> createState() => _OptionCardState();
}

class _OptionCardState extends State<OptionCard> with SingleTickerProviderStateMixin {
  // Settled at 1 so a card that is already revealed doesn't bounce on build.
  late final AnimationController _pop = AnimationController(vsync: this, duration: AppMotion.base, value: 1);

  @override
  void didUpdateWidget(OptionCard old) {
    super.didUpdateWidget(old);
    final wasRight = old.isSelected && old.isCorrect == true;
    final isRight = widget.isSelected && widget.isCorrect == true;
    if (isRight && !wasRight && !AppMotion.reduced(context)) _pop.forward(from: 0);
  }

  @override
  void dispose() {
    _pop.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final theme = Theme.of(context);
    final duration = AppMotion.of(context, AppMotion.fast);
    final isSelected = widget.isSelected;
    final isCorrect = widget.isCorrect;

    final Color accent;
    if (isSelected && isCorrect == true) {
      accent = p.success;
    } else if (isSelected && isCorrect == false) {
      accent = p.danger;
    } else if (isSelected) {
      accent = p.accentText;
    } else {
      accent = p.border;
    }

    final highlighted = isSelected;
    final fill = highlighted ? accent.withValues(alpha: 0.12) : p.surface;
    final badgeFill = highlighted ? accent : p.surfaceHigh;

    return Semantics(
      button: widget.onTap != null,
      selected: isSelected,
      label: 'Option ${widget.label}: ${widget.option}',
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedBuilder(
          animation: _pop,
          builder: (context, child) =>
              Transform.scale(scale: 1 + 0.03 * math.sin(_pop.value * math.pi), child: child),
          child: AnimatedContainer(
            duration: duration,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: fill,
              borderRadius: BorderRadius.circular(AppRadius.control),
              border: Border.all(color: accent, width: highlighted ? 2 : 1.5),
            ),
            child: Row(
              children: [
                AnimatedContainer(
                  duration: duration,
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(color: badgeFill, shape: BoxShape.circle),
                  child: Center(
                    child: AnimatedSwitcher(
                      duration: duration,
                      transitionBuilder: (child, animation) =>
                          ScaleTransition(scale: animation, child: FadeTransition(opacity: animation, child: child)),
                      child: isCorrect != null && isSelected
                          ? Icon(
                              isCorrect ? Icons.check_rounded : Icons.close_rounded,
                              key: ValueKey(isCorrect),
                              color: p.onFill(badgeFill),
                              size: 18,
                            )
                          : Text(
                              widget.label,
                              key: const ValueKey('label'),
                              style: theme.textTheme.labelMedium!.copyWith(
                                color: highlighted ? p.onFill(badgeFill) : p.textMuted,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    widget.option,
                    style: theme.textTheme.option.copyWith(
                      fontWeight: highlighted ? FontWeight.w700 : FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
