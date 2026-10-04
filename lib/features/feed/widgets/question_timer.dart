import 'dart:async';
import 'package:flutter/material.dart';

/// Per-question count-up timer. Driven by its own [ValueNotifier] so only
/// this small widget rebuilds each second — never the question card
/// around it (a fresh instance is created per card by PageView.builder,
/// so the count always starts back at zero on a new question).
class QuestionTimer extends StatefulWidget {
  final bool paused;
  final Color color;

  const QuestionTimer({super.key, required this.paused, required this.color});

  @override
  State<QuestionTimer> createState() => _QuestionTimerState();
}

class _QuestionTimerState extends State<QuestionTimer> {
  final ValueNotifier<int> _seconds = ValueNotifier(0);
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!widget.paused) _seconds.value++;
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _seconds.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<int>(
      valueListenable: _seconds,
      builder: (context, value, _) {
        final minutes = (value ~/ 60).toString().padLeft(2, '0');
        final seconds = (value % 60).toString().padLeft(2, '0');
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              widget.paused ? Icons.timer_rounded : Icons.timer_outlined,
              size: 15,
              color: widget.color,
            ),
            const SizedBox(width: 4),
            Text(
              '$minutes:$seconds',
              style: Theme.of(context).textTheme.labelMedium!.copyWith(color: widget.color),
            ),
          ],
        );
      },
    );
  }
}
