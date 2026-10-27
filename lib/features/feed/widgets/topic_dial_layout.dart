import 'dart:math' as math;
import 'dart:ui';

/// Where one lane's node sits on the dial.
class DialNode {
  final int index;
  final Offset center;

  /// 1 at the focus, shrinking towards the ends of the visible arc.
  final double scale;
  final double opacity;

  /// Steps from the focus (negative above it).
  final double delta;

  const DialNode({
    required this.index,
    required this.center,
    required this.scale,
    required this.opacity,
    required this.delta,
  });
}

/// The curved topic dial's geometry, kept apart from the widget so it can be
/// tested: the nodes sit on an arc whose centre is off-screen to the left, so
/// the focused node bulges out towards the middle of the screen and the rest
/// curve back towards the edge.
class DialLayout {
  final Size size;

  /// The least distance, along the arc, between neighbouring nodes.
  final double minNodeGap;

  /// How many steps either side of the focus are drawn.
  final double visibleSteps;

  const DialLayout({required this.size, this.minNodeGap = 64, this.visibleSteps = 3});

  double get radius => math.min(size.height * 0.42, 340);

  /// Angle between neighbouring nodes, in radians: at least 0.3, and wide
  /// enough on a short screen that nodes never touch.
  double get stepAngle => math.max(0.3, minNodeGap / radius);

  Offset get arcCenter => Offset(-radius * 0.55, size.height / 2);

  /// Vertical distance, in pixels, the finger travels to move one node.
  double get pixelsPerStep => radius * stepAngle;

  /// Position of the node [delta] steps from the focus.
  Offset positionAt(double delta) {
    final angle = delta * stepAngle;
    return arcCenter + Offset(math.cos(angle), math.sin(angle)) * radius;
  }

  /// The visible nodes for [count] lanes with [focus] (a lane index, may be
  /// fractional while dragging) in the middle.
  List<DialNode> nodes(int count, double focus) {
    final first = math.max(0, (focus - visibleSteps).floor());
    final last = math.min(count - 1, (focus + visibleSteps).ceil());
    return [
      for (var i = first; i <= last; i++)
        if ((i - focus).abs() <= visibleSteps)
          () {
            final delta = i - focus;
            final t = (delta.abs() / visibleSteps).clamp(0.0, 1.0);
            return DialNode(
              index: i,
              center: positionAt(delta),
              scale: 1 - 0.4 * t,
              opacity: 1 - 0.75 * t * t,
              delta: delta,
            );
          }(),
    ];
  }

  double clampFocus(double focus, int count) => focus.clamp(0, math.max(0, count - 1)).toDouble();

  /// A finger moving up by [dy] pixels (negative) brings later lanes up.
  double focusAfterDrag(double focus, double dy, int count) => clampFocus(focus - dy / pixelsPerStep, count);

  /// Where a fling of [velocityY] px/s should settle, as a whole lane index.
  int settleIndex(double focus, double velocityY, int count) {
    final target = focus - (velocityY * 0.12) / pixelsPerStep;
    return clampFocus(target, count).round();
  }
}
