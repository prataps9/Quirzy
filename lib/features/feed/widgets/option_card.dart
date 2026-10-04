import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../shared/theme/practice_theme.dart';

class OptionCard extends StatelessWidget {
  final String option;
  final String label;
  final bool isSelected;
  final bool? isCorrect; // null = not revealed yet
  final VoidCallback? onTap;
  final bool isDark;

  const OptionCard({
    super.key,
    required this.option,
    required this.label,
    required this.isSelected,
    this.isCorrect,
    required this.onTap,
    required this.isDark,
  });

  Color _getBorderColor() {
    if (isCorrect == true && isSelected) return PracticeTheme.success;
    if (isCorrect == false && isSelected) return PracticeTheme.error;
    if (isSelected) return PracticeTheme.primary;
    return isDark ? Colors.white10 : Colors.black12;
  }

  Color _getBackgroundColor() {
    if (isCorrect == true && isSelected)
      return PracticeTheme.success.withOpacity(0.1);
    if (isCorrect == false && isSelected)
      return PracticeTheme.error.withOpacity(0.1);
    if (isSelected) return PracticeTheme.primary.withOpacity(0.1);
    return isDark ? PracticeTheme.surfaceDark : PracticeTheme.surfaceLight;
  }

  @override
  Widget build(BuildContext context) {
    final borderColor = _getBorderColor();
    final backgroundColor = _getBackgroundColor();

    return GestureDetector(
      onTap: onTap,
      child:
          AnimatedContainer(
                duration: 200.ms,
                decoration: BoxDecoration(
                  color: backgroundColor,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: borderColor,
                    width: isSelected ? 2 : 1.5,
                  ),
                  boxShadow: isSelected
                      ? [
                          BoxShadow(
                            color: borderColor.withOpacity(0.2),
                            blurRadius: 12,
                            offset: const Offset(0, 4),
                          ),
                        ]
                      : [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.05),
                            blurRadius: 4,
                            offset: const Offset(0, 2),
                          ),
                        ],
                ),
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 12,
                ),
                child: Row(
                  children: [
                    AnimatedContainer(
                      duration: 200.ms,
                      width: 28,
                      height: 28,
                      decoration: BoxDecoration(
                        color: isSelected
                            ? borderColor
                            : (isDark
                                  ? Colors.white10
                                  : Colors.black.withOpacity(0.05)),
                        shape: BoxShape.circle,
                      ),
                      child: Center(
                        child: isCorrect != null && isSelected
                            ? Icon(
                                isCorrect!
                                    ? Icons.check_rounded
                                    : Icons.close_rounded,
                                color: Colors.white,
                                size: 16,
                              )
                            : Text(
                                label,
                                style: GoogleFonts.plusJakartaSans(
                                  fontSize: 13,
                                  fontWeight: FontWeight.bold,
                                  color: isSelected
                                      ? Colors.white
                                      : (isDark
                                            ? Colors.white70
                                            : Colors.black54),
                                ),
                              ),
                      ),
                    ),

                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        option,
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 15,
                          fontWeight: isSelected
                              ? FontWeight.w600
                              : FontWeight.normal,
                          color: isDark ? Colors.white : Colors.black87,
                        ),
                      ),
                    ),
                  ],
                ),
              )
              .animate(target: isSelected ? 1 : 0)
              .scale(
                begin: const Offset(1, 1),
                end: const Offset(1.02, 1.02),
                duration: 100.ms,
              ),
    );
  }
}
