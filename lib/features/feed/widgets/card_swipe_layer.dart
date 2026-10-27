import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../shared/theme/app_palette.dart';
import '../../../shared/theme/app_text.dart';

/// Makes a whole card swipeable sideways, like opening a panel: left for the
/// solution, right for the topic dial.
///
/// The card follows the finger a little and a hint appears on the edge the
/// panel is coming from. The swipe opens once the drag passes [openFraction]
/// of the width or flings faster than [flingVelocity]; otherwise the card
/// springs back. Taps and vertical drags go to the children untouched.
class CardSwipeLayer extends StatefulWidget {
  final Widget child;
  final bool enabled;
  final VoidCallback onSwipeLeft;
  final VoidCallback onSwipeRight;

  const CardSwipeLayer({
    super.key,
    required this.child,
    required this.onSwipeLeft,
    required this.onSwipeRight,
    this.enabled = true,
  });

  static const double openFraction = 0.35;
  static const double flingVelocity = 700;

  /// How far the card itself travels, as a fraction of the width.
  static const double followFraction = 0.18;

  @override
  State<CardSwipeLayer> createState() => _CardSwipeLayerState();
}

class _CardSwipeLayerState extends State<CardSwipeLayer> {
  double _drag = 0;
  bool _dragging = false;
  bool _armed = false;

  void _update(DragUpdateDetails details, double width) {
    final next = (_drag + details.delta.dx).clamp(-width, width);
    final armed = next.abs() >= width * CardSwipeLayer.openFraction;
    if (armed && !_armed) HapticFeedback.selectionClick();
    setState(() {
      _drag = next;
      _dragging = true;
      _armed = armed;
    });
  }

  void _end(DragEndDetails details, double width) {
    final velocity = details.primaryVelocity ?? 0;
    final distance = _drag;
    setState(() {
      _drag = 0;
      _dragging = false;
      _armed = false;
    });
    final left =
        distance <= -width * CardSwipeLayer.openFraction ||
        velocity <= -CardSwipeLayer.flingVelocity;
    final right =
        distance >= width * CardSwipeLayer.openFraction ||
        velocity >= CardSwipeLayer.flingVelocity;
    if (left && !right) {
      widget.onSwipeLeft();
    } else if (right && !left) {
      widget.onSwipeRight();
    }
  }

  void _cancel() {
    setState(() {
      _drag = 0;
      _dragging = false;
      _armed = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.enabled) return widget.child;
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final progress = (_drag.abs() / (width * CardSwipeLayer.openFraction))
            .clamp(0.0, 1.0);
        final follow = (_drag * 0.3).clamp(
          -width * CardSwipeLayer.followFraction,
          width * CardSwipeLayer.followFraction,
        );
        final duration = _dragging
            ? Duration.zero
            : const Duration(milliseconds: 180);
        return GestureDetector(
          behavior: HitTestBehavior.translucent,
          onHorizontalDragUpdate: (d) => _update(d, width),
          onHorizontalDragEnd: (d) => _end(d, width),
          onHorizontalDragCancel: _cancel,
          child: Stack(
            children: [
              if (_drag != 0)
                Positioned.fill(
                  child: IgnorePointer(
                    child: _EdgeHint(
                      towardsSolution: _drag < 0,
                      progress: progress,
                      armed: _armed,
                    ),
                  ),
                ),
              AnimatedContainer(
                duration: duration,
                curve: Curves.easeOut,
                transform: Matrix4.translationValues(follow, 0, 0),
                child: widget.child,
              ),
            ],
          ),
        );
      },
    );
  }
}

class _EdgeHint extends StatelessWidget {
  final bool towardsSolution;
  final double progress;
  final bool armed;

  const _EdgeHint({
    required this.towardsSolution,
    required this.progress,
    required this.armed,
  });

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final label = towardsSolution ? 'Solution' : 'Topics';
    final icon = towardsSolution
        ? Icons.lightbulb_outline_rounded
        : Icons.explore_rounded;
    return Align(
      alignment: towardsSolution ? Alignment.centerRight : Alignment.centerLeft,
      child: Opacity(
        opacity: progress,
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 8),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
          decoration: BoxDecoration(
            color: armed ? p.accent : p.surfaceHigh,
            borderRadius: BorderRadius.circular(AppRadius.control),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, color: armed ? p.onAccent : p.textMuted, size: 22),
              const SizedBox(height: 4),
              Text(
                label,
                style: Theme.of(context).textTheme.micro.copyWith(
                  color: armed ? p.onAccent : p.textMuted,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
