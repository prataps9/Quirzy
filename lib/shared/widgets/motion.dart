import 'dart:async';

import 'package:confetti/confetti.dart';
import 'package:flutter/material.dart';

import '../theme/app_motion.dart';
import '../theme/app_palette.dart';

/// List items that fade and rise in one after another, the first time they
/// are shown. Only the first [maxStaggered] items wait their turn; later
/// ones (usually off screen) simply appear.
class Stagger extends StatefulWidget {
  final int index;
  final Widget child;

  const Stagger({super.key, required this.index, required this.child});

  static const step = Duration(milliseconds: 45);
  static const maxStaggered = 8;

  @override
  State<Stagger> createState() => _StaggerState();
}

class _StaggerState extends State<Stagger> with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _curve;
  Timer? _delay;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: AppMotion.slow);
    _curve = CurvedAnimation(parent: _controller, curve: AppMotion.enter);
    if (widget.index >= Stagger.maxStaggered) {
      _controller.value = 1;
    } else if (widget.index == 0) {
      _controller.forward();
    } else {
      _delay = Timer(Stagger.step * widget.index, () {
        if (mounted) _controller.forward();
      });
    }
  }

  @override
  void dispose() {
    _delay?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (AppMotion.reduced(context)) return widget.child;
    return AnimatedBuilder(
      animation: _curve,
      child: widget.child,
      builder: (context, child) => Opacity(
        opacity: _curve.value,
        child: Transform.translate(offset: Offset(0, 18 * (1 - _curve.value)), child: child),
      ),
    );
  }
}

/// A number that rolls up to [value] the first time it shows, and from the
/// old value to the new one when it changes.
class CountUp extends StatelessWidget {
  final int value;
  final TextStyle? style;
  final String Function(int value)? format;
  final TextAlign? textAlign;

  const CountUp({super.key, required this.value, this.style, this.format, this.textAlign});

  static const duration = Duration(milliseconds: 650);

  @override
  Widget build(BuildContext context) {
    final show = format ?? (v) => '$v';
    if (AppMotion.reduced(context)) return Text(show(value), style: style, textAlign: textAlign);
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: value.toDouble()),
      duration: duration,
      curve: Curves.easeOutCubic,
      builder: (context, v, _) => Semantics(
        // Screen readers hear the real number, not the rolling one.
        label: show(value),
        excludeSemantics: true,
        child: Text(show(v.round()), style: style, textAlign: textAlign),
      ),
    );
  }
}

/// A progress bar that fills from empty the first time it shows.
class GrowBar extends StatelessWidget {
  final double value;
  final double minHeight;
  final Color? color;
  final Color? backgroundColor;

  const GrowBar({super.key, required this.value, this.minHeight = 6, this.color, this.backgroundColor});

  @override
  Widget build(BuildContext context) {
    final target = value.clamp(0.0, 1.0);
    return ClipRRect(
      borderRadius: BorderRadius.circular(AppRadius.pill),
      child: AppMotion.reduced(context)
          ? LinearProgressIndicator(
              value: target,
              minHeight: minHeight,
              color: color,
              backgroundColor: backgroundColor,
            )
          : TweenAnimationBuilder<double>(
              tween: Tween(begin: 0, end: target),
              duration: const Duration(milliseconds: 700),
              curve: Curves.easeOutCubic,
              builder: (context, v, _) => LinearProgressIndicator(
                value: v,
                minHeight: minHeight,
                color: color,
                backgroundColor: backgroundColor,
              ),
            ),
    );
  }
}

/// Shrinks its child a touch while a finger is down on it, so cards and
/// buttons feel pressed. Purely visual: taps go straight to the child.
class PressScale extends StatefulWidget {
  final Widget child;
  final bool enabled;
  final double pressedScale;

  const PressScale({super.key, required this.child, this.enabled = true, this.pressedScale = 0.97});

  @override
  State<PressScale> createState() => _PressScaleState();
}

class _PressScaleState extends State<PressScale> {
  bool _down = false;

  void _set(bool down) {
    if (_down != down) setState(() => _down = down);
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.enabled || AppMotion.reduced(context)) return widget.child;
    return Listener(
      onPointerDown: (_) => _set(true),
      onPointerUp: (_) => _set(false),
      onPointerCancel: (_) => _set(false),
      child: AnimatedScale(
        scale: _down ? widget.pressedScale : 1,
        duration: _down ? AppMotion.fast : AppMotion.base,
        curve: _down ? Curves.easeOut : Curves.easeOutBack,
        child: widget.child,
      ),
    );
  }
}

/// A grey block shaped like content that is still loading.
class SkeletonBox extends StatelessWidget {
  final double? width;
  final double height;
  final double radius;

  const SkeletonBox({super.key, this.width, required this.height, this.radius = AppRadius.chip});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: context.palette.surfaceHigh,
        borderRadius: BorderRadius.circular(radius),
      ),
    );
  }
}

/// Placeholder cards that gently pulse while a screen loads, instead of a
/// spinner. One pulse drives every block, and it stops with reduced motion.
class SkeletonList extends StatefulWidget {
  final int count;
  final double itemHeight;
  final EdgeInsetsGeometry padding;

  const SkeletonList({
    super.key,
    this.count = 4,
    this.itemHeight = 96,
    this.padding = const EdgeInsets.fromLTRB(20, 8, 20, 20),
  });

  @override
  State<SkeletonList> createState() => _SkeletonListState();
}

class _SkeletonListState extends State<SkeletonList> with SingleTickerProviderStateMixin {
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
    lowerBound: 0.45,
    upperBound: 1,
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (AppMotion.reduced(context)) {
      _pulse.stop();
      _pulse.value = 1;
    } else if (!_pulse.isAnimating) {
      _pulse.repeat(reverse: true);
    }
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Semantics(
      label: 'Loading',
      child: FadeTransition(
        opacity: _pulse,
        child: ListView.separated(
          physics: const NeverScrollableScrollPhysics(),
          padding: widget.padding,
          itemCount: widget.count,
          separatorBuilder: (_, _) => const SizedBox(height: 12),
          itemBuilder: (context, i) => Container(
            height: widget.itemHeight,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: p.surface,
              borderRadius: BorderRadius.circular(AppRadius.card),
              border: Border.all(color: p.border),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                SkeletonBox(width: 90 + (i % 3) * 30.0, height: 12),
                const SizedBox(height: 10),
                const SkeletonBox(height: 14),
                if (widget.itemHeight > 80) ...[
                  const SizedBox(height: 8),
                  SkeletonBox(width: 140 + (i % 2) * 40.0, height: 14),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// A burst of confetti from the top of the screen, once, when [play] is
/// true. Place it in a Stack above the content. Silent with reduced motion.
class Celebration extends StatefulWidget {
  final bool play;

  const Celebration({super.key, required this.play});

  @override
  State<Celebration> createState() => _CelebrationState();
}

class _CelebrationState extends State<Celebration> {
  final _confetti = ConfettiController(duration: const Duration(milliseconds: 900));
  bool _played = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _maybePlay();
  }

  @override
  void didUpdateWidget(Celebration old) {
    super.didUpdateWidget(old);
    _maybePlay();
  }

  void _maybePlay() {
    if (_played || !widget.play || AppMotion.reduced(context)) return;
    _played = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _confetti.play();
    });
  }

  @override
  void dispose() {
    _confetti.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return IgnorePointer(
      child: Align(
        alignment: Alignment.topCenter,
        child: ConfettiWidget(
          confettiController: _confetti,
          blastDirectionality: BlastDirectionality.explosive,
          emissionFrequency: 0.06,
          numberOfParticles: 22,
          maxBlastForce: 24,
          minBlastForce: 9,
          gravity: 0.25,
          colors: [p.accent, p.streak, p.like, p.success, p.text],
        ),
      ),
    );
  }
}

/// Wraps each child (skipping plain spacers) in a [Stagger], in order, so a
/// page's sections arrive one after another.
List<Widget> staggered(List<Widget> children) {
  var index = 0;
  return [
    for (final child in children) child is SizedBox && child.child == null ? child : Stagger(index: index++, child: child),
  ];
}
