import 'package:flutter/material.dart';

import '../../../shared/theme/app_palette.dart';

/// One answer choice. Before an answer it is a quiet outlined row; once
/// revealed the right option turns green and a wrong pick turns red, each
/// with an icon so colour is never the only signal.
class OptionCard extends StatelessWidget {
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
  Widget build(BuildContext context) {
    final p = context.palette;
    final theme = Theme.of(context);

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
      button: onTap != null,
      selected: isSelected,
      label: 'Option $label: $option',
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: fill,
            borderRadius: BorderRadius.circular(AppRadius.control),
            border: Border.all(color: accent, width: highlighted ? 2 : 1.5),
          ),
          child: Row(
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                width: 28,
                height: 28,
                decoration: BoxDecoration(color: badgeFill, shape: BoxShape.circle),
                child: Center(
                  child: isCorrect != null && isSelected
                      ? Icon(
                          isCorrect! ? Icons.check_rounded : Icons.close_rounded,
                          color: p.onFill(badgeFill),
                          size: 18,
                        )
                      : Text(
                          label,
                          style: theme.textTheme.labelMedium!.copyWith(
                            color: highlighted ? p.onFill(badgeFill) : p.textMuted,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  option,
                  style: theme.textTheme.bodyLarge!.copyWith(
                    fontSize: 15,
                    fontWeight: highlighted ? FontWeight.w700 : FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
