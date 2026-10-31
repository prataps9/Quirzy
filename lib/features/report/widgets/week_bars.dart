import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../shared/theme/app_motion.dart';
import '../../../shared/theme/app_palette.dart';

/// Questions per day as seven columns, Monday first. One series, so no
/// legend: the card's title names it. Bars grow from a hairline baseline
/// one after another; only the busiest day carries its number, and tapping
/// a bar shows that day's instead. Each bar reads out its day and value.
class WeekBars extends StatefulWidget {
  final List<int> values;

  /// Days after this index (Monday = 0) haven't happened yet; null when the
  /// whole week is past.
  final int? lastDay;

  const WeekBars({super.key, required this.values, this.lastDay});

  static const days = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];
  static const height = 150.0;
  static const maxBarWidth = 24.0;

  @override
  State<WeekBars> createState() => _WeekBarsState();
}

class _WeekBarsState extends State<WeekBars> {
  int? _selected;

  @override
  void didUpdateWidget(WeekBars old) {
    super.didUpdateWidget(old);
    if (old.values != widget.values) _selected = null;
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final text = Theme.of(context).textTheme;
    final values = widget.values;
    final max = values.fold(0, (a, b) => b > a ? b : a);
    var best = 0;
    for (var i = 1; i < values.length; i++) {
      if (values[i] > values[best]) best = i;
    }
    final labelled = _selected ?? (max > 0 ? best : null);
    const labelSpace = 22.0;
    const barSpace = WeekBars.height - labelSpace;

    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: AppMotion.of(context, const Duration(milliseconds: 900)),
      builder: (context, t, _) => Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          for (var i = 0; i < 7; i++)
            Expanded(
              child: Semantics(
                button: true,
                selected: _selected == i,
                label: widget.lastDay != null && i > widget.lastDay!
                    ? '${WeekBars.days[i]}, still to come'
                    : '${WeekBars.days[i]}, ${values[i]} ${values[i] == 1 ? 'question' : 'questions'}',
                excludeSemantics: true,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () {
                    HapticFeedback.selectionClick();
                    setState(() => _selected = _selected == i ? null : i);
                  },
                  child: Column(
                    children: [
                      SizedBox(
                        height: WeekBars.height,
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            SizedBox(
                              height: labelSpace,
                              child: AnimatedOpacity(
                                opacity: labelled == i && t > 0.6 ? 1 : 0,
                                duration: AppMotion.of(context, AppMotion.fast),
                                child: Text(
                                  '${values[i]}',
                                  style: text.labelMedium!.copyWith(color: p.text, fontWeight: FontWeight.w700),
                                ),
                              ),
                            ),
                            Container(
                              width: WeekBars.maxBarWidth,
                              height: max == 0 ? 0 : barSpace * (values[i] / max) * _grow(t, i),
                              decoration: BoxDecoration(
                                color: _selected == null || _selected == i ? p.accent : p.surfaceHigh,
                                borderRadius: const BorderRadius.vertical(top: Radius.circular(4)),
                              ),
                            ),
                          ],
                        ),
                      ),
                      Container(height: 1, color: p.border),
                      const SizedBox(height: 6),
                      Text(
                        WeekBars.days[i][0],
                        style: text.labelMedium!.copyWith(
                          color: _selected == i ? p.text : p.textMuted,
                          fontWeight: _selected == i ? FontWeight.w700 : null,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  /// Each bar starts a little after the one before.
  static double _grow(double t, int i) {
    final start = i * 0.06;
    final local = ((t - start) / (1 - 0.36)).clamp(0.0, 1.0);
    return Curves.easeOutCubic.transform(local);
  }
}
