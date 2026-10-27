import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';
import 'package:flutter/services.dart';

import '../../../shared/theme/app_motion.dart';
import '../../../shared/theme/app_palette.dart';
import '../../../shared/theme/app_text.dart';

/// Makes a whole card swipeable sideways, like opening a panel: left for the
/// solution, right for the topic dial.
///
/// The card follows the finger a little and a hint appears on the edge the
/// panel is coming from. The swipe opens once the drag passes [openFraction]
/// of the width or flings faster than [flingVelocity]; on release the card
/// springs back carrying the speed of the flick, while the panel slides in.
/// Taps and vertical drags go to the children untouched.
///
/// Dragging only moves a transform: the card itself is never rebuilt.
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

class _CardSwipeLayerState extends State<CardSwipeLayer> with SingleTickerProviderStateMixin {
  static final _spring = SpringDescription.withDampingRatio(mass: 1, stiffness: 320, ratio: 0.85);

  /// Raw finger travel in pixels (negative = left).
  final ValueNotifier<double> _offset = ValueNotifier(0);
  late final AnimationController _release;
  bool _armed = false;

  @override
  void initState() {
    super.initState();
    _release = AnimationController.unbounded(vsync: this)..addListener(() => _offset.value = _release.value);
  }

  @override
  void dispose() {
    _release.dispose();
    _offset.dispose();
    super.dispose();
  }

  void _start(DragStartDetails details) => _release.stop();

  void _update(DragUpdateDetails details, double width) {
    final next = (_offset.value + details.delta.dx).clamp(-width, width);
    final armed = next.abs() >= width * CardSwipeLayer.openFraction;
    if (armed && !_armed) HapticFeedback.selectionClick();
    _armed = armed;
    _offset.value = next;
  }

  void _end(DragEndDetails details, double width) {
    final velocity = details.primaryVelocity ?? 0;
    final distance = _offset.value;
    _armed = false;
    _springBack(velocity);

    final left = distance <= -width * CardSwipeLayer.openFraction || velocity <= -CardSwipeLayer.flingVelocity;
    final right = distance >= width * CardSwipeLayer.openFraction || velocity >= CardSwipeLayer.flingVelocity;
    if (left && !right) {
      widget.onSwipeLeft();
    } else if (right && !left) {
      widget.onSwipeRight();
    }
  }

  void _cancel() {
    _armed = false;
    _springBack(0);
  }

  void _springBack(double velocity) {
    if (AppMotion.reduced(context)) {
      _offset.value = 0;
      return;
    }
    _release.value = _offset.value;
    _release.animateWith(SpringSimulation(_spring, _offset.value, 0, velocity)).whenComplete(() {
      if (mounted && !_release.isAnimating) _offset.value = 0;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.enabled) return widget.child;
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final follow = width * CardSwipeLayer.followFraction;
        return GestureDetector(
          behavior: HitTestBehavior.translucent,
          onHorizontalDragStart: _start,
          onHorizontalDragUpdate: (d) => _update(d, width),
          onHorizontalDragEnd: (d) => _end(d, width),
          onHorizontalDragCancel: _cancel,
          // The same two children in the same order at all times, so the card
          // keeps its state when a drag begins or ends. The hint is drawn
          // last, over the card, so the sliding card never hides it.
          child: Stack(
            children: [
              ValueListenableBuilder<double>(
                valueListenable: _offset,
                child: widget.child,
                builder: (context, offset, child) =>
                    Transform.translate(offset: Offset((offset * 0.3).clamp(-follow, follow), 0), child: child),
              ),
              Positioned.fill(
                child: IgnorePointer(
                  child: ExcludeSemantics(
                    child: ValueListenableBuilder<double>(
                      valueListenable: _offset,
                      builder: (context, offset, _) =>
                          _EdgeHint(offset: offset, threshold: width * CardSwipeLayer.openFraction),
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// The chip on the screen edge saying what the swipe will open. It fades in
/// with the drag (by colour, not an opacity layer) and lights up once the
/// swipe is far enough to open.
class _EdgeHint extends StatelessWidget {
  final double offset;
  final double threshold;

  const _EdgeHint({required this.offset, required this.threshold});

  @override
  Widget build(BuildContext context) {
    // The spring only ever gets near zero, so treat a hair's breadth as rest.
    if (offset.abs() < 0.5) return const SizedBox.shrink();
    final p = context.palette;
    final progress = (offset.abs() / threshold).clamp(0.0, 1.0);
    final armed = progress >= 1;
    final towardsSolution = offset < 0;
    final fill = (armed ? p.accent : p.surfaceHigh).withValues(alpha: progress);
    final ink = (armed ? p.onAccent : p.textMuted).withValues(alpha: progress);
    return Align(
      alignment: towardsSolution ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 8),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
        decoration: BoxDecoration(color: fill, borderRadius: BorderRadius.circular(AppRadius.control)),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(towardsSolution ? Icons.lightbulb_outline_rounded : Icons.explore_rounded, color: ink, size: 22),
            const SizedBox(height: 4),
            Text(
              towardsSolution ? 'Solution' : 'Topics',
              style: Theme.of(context).textTheme.micro.copyWith(color: ink),
            ),
          ],
        ),
      ),
    );
  }
}
