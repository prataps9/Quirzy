import 'package:flutter/material.dart';

/// Shared timing for every animation, so the app moves in one rhythm.
///
/// Always pass a duration through [of] so it collapses to zero when the
/// phone's "remove animations" setting is on.
class AppMotion {
  static const fast = Duration(milliseconds: 150);
  static const base = Duration(milliseconds: 250);
  static const slow = Duration(milliseconds: 380);

  /// Things arriving: quick start, soft landing.
  static const Curve enter = Curves.easeOutCubic;

  /// Things leaving.
  static const Curve exit = Curves.easeInCubic;

  /// Whether the user asked the system to cut animations.
  static bool reduced(BuildContext context) => MediaQuery.maybeDisableAnimationsOf(context) ?? false;

  /// [duration], or zero when animations are off.
  static Duration of(BuildContext context, Duration duration) => reduced(context) ? Duration.zero : duration;
}

/// Fades [child] in while lifting it a little, once, when it first appears.
/// For whole pages (empty and end-of-lane states).
class FadeRise extends StatelessWidget {
  final Widget child;
  final double rise;

  const FadeRise({super.key, required this.child, this.rise = 16});

  @override
  Widget build(BuildContext context) {
    if (AppMotion.reduced(context)) return child;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: AppMotion.slow,
      curve: AppMotion.enter,
      child: child,
      builder: (context, t, child) =>
          Opacity(opacity: t, child: Transform.translate(offset: Offset(0, rise * (1 - t)), child: child)),
    );
  }
}

/// Shows [child] with a fade and a smooth height change, and hides it the
/// same way, so extras that come and go don't make the layout jump. With
/// animations off it simply shows or hides (an [AnimatedSize] with a zero
/// duration is not allowed to lay out).
class Reveal extends StatelessWidget {
  final bool show;
  final Widget child;

  const Reveal({super.key, required this.show, required this.child});

  @override
  Widget build(BuildContext context) {
    if (AppMotion.reduced(context)) return show ? child : const SizedBox.shrink();
    return AnimatedSize(
      duration: AppMotion.base,
      curve: AppMotion.enter,
      alignment: Alignment.topCenter,
      child: AnimatedSwitcher(
        duration: AppMotion.base,
        switchInCurve: AppMotion.enter,
        switchOutCurve: AppMotion.exit,
        child: show
            ? KeyedSubtree(key: const ValueKey('shown'), child: child)
            : const SizedBox.shrink(key: ValueKey('hidden')),
      ),
    );
  }
}
