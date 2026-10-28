import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../shared/providers/providers.dart';
import '../../../shared/theme/app_motion.dart';
import '../../../shared/theme/app_palette.dart';
import '../../../shared/theme/app_text.dart';
import '../../../shared/widgets/app_widgets.dart';
import '../../../shared/widgets/motion.dart';
import '../../feed/models/feed_models.dart';
import '../../feed/providers/feed_providers.dart';
import '../../feed/widgets/option_card.dart';
import '../../progress/models/badge.dart';
import '../../progress/providers/badge_providers.dart';
import '../models/mock_test.dart';
import '../providers/mock_test_providers.dart';
import '../services/mock_test_service.dart';

/// "m:ss", e.g. 9:05.
String formatClock(int seconds) {
  final s = seconds.clamp(0, 359999);
  return '${s ~/ 60}:${(s % 60).toString().padLeft(2, '0')}';
}

enum _Phase { setup, running, result }

/// A timed, exam-style test: pick topics and a length, answer against the
/// clock with no hints, then see the score per topic and review mistakes.
/// A test left part-way is saved and can be resumed.
class MockTestScreen extends ConsumerStatefulWidget {
  const MockTestScreen({super.key});

  @override
  ConsumerState<MockTestScreen> createState() => _MockTestScreenState();
}

class _MockTestScreenState extends ConsumerState<MockTestScreen> {
  _Phase _phase = _Phase.setup;
  MockTest? _test;
  MockResult? _result;
  List<BadgeId> _newBadges = const [];
  bool _submitting = false;

  MockTestService get _service => ref.read(mockTestServiceProvider);

  void _start(MockTest test) {
    HapticFeedback.mediumImpact();
    setState(() {
      _test = test;
      _phase = _Phase.running;
    });
    unawaited(_service.saveInProgress(test));
  }

  Future<void> _submit(MockTest test) async {
    if (_submitting) return;
    _submitting = true;
    final result = await _service.finish(test);
    final badges = await ref.read(badgeServiceProvider).check();
    if (!mounted) return;
    refreshAfterMockTest(ref);
    ref.invalidate(badgeStatusesProvider);
    HapticFeedback.mediumImpact();
    setState(() {
      _result = result;
      _newBadges = badges;
      _test = test;
      _phase = _Phase.result;
      _submitting = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return switch (_phase) {
      _Phase.setup => _SetupView(onStart: _start),
      _Phase.running => _RunnerView(
        key: ValueKey(_test!.id),
        initial: _test!,
        onSave: _service.saveInProgress,
        onSubmit: _submit,
      ),
      _Phase.result => _ResultView(test: _test!, result: _result!, newBadges: _newBadges),
    };
  }
}

// ---------------------------------------------------------------------------
// Setup

class _SetupView extends ConsumerStatefulWidget {
  final ValueChanged<MockTest> onStart;

  const _SetupView({required this.onStart});

  @override
  ConsumerState<_SetupView> createState() => _SetupViewState();
}

class _SetupViewState extends ConsumerState<_SetupView> {
  /// Topics left out of the test (everything is in by default).
  final Set<String> _excluded = {};
  int _length = 20;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final text = Theme.of(context).textTheme;
    final pool = ref.watch(feedQuestionPoolProvider).value;
    final inProgress = ref.watch(mockInProgressProvider).value;

    final counts = <String, int>{};
    for (final q in pool ?? const <PracticeQuestion>[]) {
      counts[q.topicName] = (counts[q.topicName] ?? 0) + 1;
    }
    final topics = counts.keys.toList()..sort();
    final chosen = {
      for (final t in topics)
        if (!_excluded.contains(t)) t,
    };
    final available = chosen.fold(0, (sum, t) => sum + counts[t]!);
    final length = available == 0 ? 0 : (available < _length ? available : _length);

    return Scaffold(
      appBar: AppBar(title: const Text('Mock test')),
      body: pool == null
          ? const SkeletonList(count: 4, itemHeight: 70)
          : topics.isEmpty
          ? const _Message(
              icon: Icons.timer_outlined,
              title: 'Add a topic first',
              body: 'A mock test is built from your topics. Add one from Home, then come back.',
            )
          : FadeRise(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
                children: [
                  if (inProgress != null) ...[
                    AppCard(
                      color: p.accentSoft,
                      borderColor: p.accentText,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('You have a test in progress', style: text.titleSmall),
                          const SizedBox(height: 4),
                          Text(
                            '${inProgress.answeredCount} of ${inProgress.total} answered · '
                            '${formatClock(inProgress.remainingSeconds)} left',
                            style: text.bodySmall,
                          ),
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              Expanded(
                                child: AppButton(label: 'Resume', onPressed: () => widget.onStart(inProgress)),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: AppButton.secondary(
                                  label: 'Discard',
                                  onPressed: () async {
                                    await ref.read(mockTestServiceProvider).discardInProgress();
                                    ref.invalidate(mockInProgressProvider);
                                  },
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 24),
                  ],
                  Text('Exam conditions', style: text.titleLarge),
                  const SizedBox(height: 6),
                  Text(
                    'One minute a question, no hints or answers until you finish. '
                    'Your score is broken down by topic at the end.',
                    style: text.bodyMedium!.copyWith(color: p.textMuted),
                  ),
                  const SizedBox(height: 24),
                  Text('Topics', style: text.titleMedium),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final t in topics)
                        FilterChip(
                          label: Text('$t (${counts[t]})'),
                          selected: chosen.contains(t),
                          onSelected: (on) => setState(() => on ? _excluded.remove(t) : _excluded.add(t)),
                        ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  Text('Length', style: text.titleMedium),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    children: [
                      for (final n in MockTestService.lengths)
                        ChoiceChip(
                          label: Text('$n questions'),
                          selected: _length == n,
                          showCheckmark: false,
                          onSelected: (_) => setState(() => _length = n),
                        ),
                    ],
                  ),
                  const SizedBox(height: 28),
                  Text(
                    length == 0
                        ? 'Pick at least one topic.'
                        : '$length questions · ${length * MockTestService.secondsPerQuestion ~/ 60} minutes',
                    textAlign: TextAlign.center,
                    style: text.titleSmall,
                  ),
                  if (length > 0 && length < _length)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(
                        'Only $length questions in these topics.',
                        textAlign: TextAlign.center,
                        style: text.bodySmall!.copyWith(color: p.textMuted),
                      ),
                    ),
                  const SizedBox(height: 12),
                  AppButton(
                    label: 'Start test',
                    icon: Icons.timer_outlined,
                    onPressed: length == 0
                        ? null
                        : () => widget.onStart(
                            ref.read(mockTestServiceProvider).build(pool, topics: chosen, length: _length),
                          ),
                  ),
                ],
              ),
            ),
    );
  }
}

// ---------------------------------------------------------------------------
// Running

class _RunnerView extends StatefulWidget {
  final MockTest initial;
  final Future<void> Function(MockTest) onSave;
  final Future<void> Function(MockTest) onSubmit;

  const _RunnerView({super.key, required this.initial, required this.onSave, required this.onSubmit});

  @override
  State<_RunnerView> createState() => _RunnerViewState();
}

class _RunnerViewState extends State<_RunnerView> {
  late MockTest _test = widget.initial;
  late final PageController _pages = PageController(initialPage: widget.initial.current);
  late final AppLifecycleListener _lifecycle;
  Timer? _clock;
  bool _done = false;

  @override
  void initState() {
    super.initState();
    _lifecycle = AppLifecycleListener(
      onStateChange: (state) {
        // The clock only runs while the test is in front of the user.
        if (state == AppLifecycleState.resumed) {
          _startClock();
        } else {
          _stopClock();
          unawaited(widget.onSave(_test));
        }
      },
    );
    _startClock();
    if (_test.timeUp) WidgetsBinding.instance.addPostFrameCallback((_) => _finish());
  }

  @override
  void dispose() {
    _stopClock();
    _lifecycle.dispose();
    _pages.dispose();
    super.dispose();
  }

  void _startClock() {
    _clock?.cancel();
    _clock = Timer.periodic(const Duration(seconds: 1), (_) => _tick());
  }

  void _stopClock() {
    _clock?.cancel();
    _clock = null;
  }

  void _tick() {
    if (_done || !mounted) return;
    setState(() => _test = _test.copyWith(usedSeconds: _test.usedSeconds + 1));
    if (_test.remainingSeconds == 60) HapticFeedback.heavyImpact();
    if (_test.timeUp) {
      _finish();
    } else if (_test.usedSeconds % 5 == 0) {
      unawaited(widget.onSave(_test));
    }
  }

  void _pick(int question, int option) {
    HapticFeedback.selectionClick();
    setState(() => _test = _test.copyWith(answers: {..._test.answers, question: option}));
    unawaited(widget.onSave(_test));
  }

  void _toggleFlag() {
    final i = _test.current;
    final flagged = {..._test.flagged};
    flagged.contains(i) ? flagged.remove(i) : flagged.add(i);
    setState(() => _test = _test.copyWith(flagged: flagged));
  }

  void _goTo(int index) {
    if (index < 0 || index >= _test.total) return;
    _pages.animateToPage(index, duration: AppMotion.of(context, AppMotion.base), curve: AppMotion.enter);
  }

  void _finish() {
    if (_done) return;
    _done = true;
    _stopClock();
    widget.onSubmit(_test);
  }

  Future<void> _confirmSubmit() async {
    final left = _test.unanswered;
    if (left == 0) return _finish();
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Submit now?'),
        content: Text("$left ${left == 1 ? 'question is' : 'questions are'} unanswered and will count as wrong."),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Keep going')),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Submit')),
        ],
      ),
    );
    if (ok == true) _finish();
  }

  Future<void> _confirmLeave() async {
    _stopClock();
    final leave = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Leave the test?'),
        content: const Text('Your answers and time are saved. You can pick up where you left off from My Prep.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Stay')),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Leave')),
        ],
      ),
    );
    if (!mounted) return;
    if (leave == true) {
      await widget.onSave(_test);
      if (mounted) Navigator.of(context).pop();
    } else {
      _startClock();
    }
  }

  void _openGrid() {
    showModalBottomSheet<void>(
      context: context,
      builder: (context) => _QuestionGrid(
        test: _test,
        onPick: (i) {
          Navigator.pop(context);
          _goTo(i);
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final text = Theme.of(context).textTheme;
    final remaining = _test.remainingSeconds;
    final last = _test.current == _test.total - 1;
    final flagged = _test.flagged.contains(_test.current);

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _confirmLeave();
      },
      child: Scaffold(
        appBar: AppBar(
          // Short, so it fits beside the timer and buttons on a small phone.
          title: Text('${_test.current + 1} of ${_test.total}'),
          actions: [
            Center(
              child: Semantics(
                label: '${formatClock(remaining)} left',
                child: AnimatedContainer(
                  duration: AppMotion.of(context, AppMotion.base),
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: remaining <= 60 ? p.dangerSoft : p.surfaceHigh,
                    borderRadius: BorderRadius.circular(AppRadius.pill),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.timer_outlined, size: 16, color: remaining <= 60 ? p.danger : p.textMuted),
                      const SizedBox(width: 4),
                      // In the last minute each second gives a small beat.
                      TweenAnimationBuilder<double>(
                        key: ValueKey(remaining <= 60 ? remaining : -1),
                        tween: Tween(begin: remaining <= 60 && !AppMotion.reduced(context) ? 1.18 : 1, end: 1),
                        duration: AppMotion.base,
                        curve: Curves.easeOut,
                        builder: (context, scale, child) => Transform.scale(scale: scale, child: child),
                        child: Text(
                          formatClock(remaining),
                          style: text.labelLarge!.copyWith(
                            color: remaining <= 60 ? p.danger : p.text,
                            fontFeatures: const [FontFeature.tabularFigures()],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            IconButton(
              tooltip: flagged ? 'Unflag' : 'Flag for review',
              onPressed: _toggleFlag,
              icon: Icon(
                flagged ? Icons.flag_rounded : Icons.outlined_flag_rounded,
                color: flagged ? p.accentText : null,
              ),
            ),
            IconButton(tooltip: 'All questions', onPressed: _openGrid, icon: const Icon(Icons.grid_view_rounded)),
          ],
        ),
        body: Column(
          children: [
            TweenAnimationBuilder<double>(
              tween: Tween(end: _test.answeredCount / _test.total),
              duration: AppMotion.of(context, AppMotion.base),
              builder: (context, value, _) => LinearProgressIndicator(value: value, minHeight: 3),
            ),
            Expanded(
              child: PageView.builder(
                controller: _pages,
                itemCount: _test.total,
                onPageChanged: (i) => setState(() => _test = _test.copyWith(current: i)),
                itemBuilder: (context, i) {
                  final q = _test.questions[i];
                  const labels = ['A', 'B', 'C', 'D', 'E', 'F'];
                  return ListView(
                    padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
                    children: [
                      Text(q.topicName.toUpperCase(), style: text.micro.copyWith(color: p.textMuted)),
                      const SizedBox(height: 8),
                      Text(q.questionText, style: text.question),
                      const SizedBox(height: 20),
                      for (var o = 0; o < q.options.length; o++)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: OptionCard(
                            option: q.options[o],
                            label: labels[o % labels.length],
                            isSelected: _test.answers[i] == o,
                            onTap: () => _pick(i, o),
                          ),
                        ),
                    ],
                  );
                },
              ),
            ),
            SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                child: Row(
                  children: [
                    Expanded(
                      child: AppButton.secondary(
                        label: 'Back',
                        onPressed: _test.current == 0 ? null : () => _goTo(_test.current - 1),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: last
                          ? AppButton(label: 'Submit', onPressed: _confirmSubmit)
                          : AppButton(label: 'Next', onPressed: () => _goTo(_test.current + 1)),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _QuestionGrid extends StatelessWidget {
  final MockTest test;
  final ValueChanged<int> onPick;

  const _QuestionGrid({required this.test, required this.onPick});

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final text = Theme.of(context).textTheme;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('${test.answeredCount} of ${test.total} answered', style: text.titleMedium),
            if (test.flagged.isNotEmpty)
              Text('${test.flagged.length} flagged for review', style: text.bodySmall!.copyWith(color: p.textMuted)),
            const SizedBox(height: 16),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                for (var i = 0; i < test.total; i++)
                  Semantics(
                    button: true,
                    label:
                        'Question ${i + 1}${test.answers.containsKey(i) ? ', answered' : ''}'
                        '${test.flagged.contains(i) ? ', flagged' : ''}',
                    child: InkWell(
                      customBorder: const CircleBorder(),
                      onTap: () => onPick(i),
                      child: Container(
                        width: 44,
                        height: 44,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: test.answers.containsKey(i) ? p.accent : p.surfaceHigh,
                          border: Border.all(
                            color: test.flagged.contains(i)
                                ? p.danger
                                : i == test.current
                                ? p.accentText
                                : p.border,
                            width: test.flagged.contains(i) || i == test.current ? 2 : 1,
                          ),
                        ),
                        child: ExcludeSemantics(
                          child: Text(
                            '${i + 1}',
                            style: text.labelLarge!.copyWith(color: test.answers.containsKey(i) ? p.onAccent : p.text),
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Result

class _ResultView extends ConsumerWidget {
  final MockTest test;
  final MockResult result;
  final List<BadgeId> newBadges;

  const _ResultView({required this.test, required this.result, this.newBadges = const []});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.palette;
    final text = Theme.of(context).textTheme;
    final weakest = result.weakest;
    final toReview = [
      for (var i = 0; i < test.total; i++)
        if (!test.isRight(i)) i,
    ];

    void practise(String topic) {
      ref
          .read(feedControllerProvider.notifier)
          .switchLane(FeedLane(type: FeedLaneType.topic, id: 'topic:$topic', label: topic));
      ref.read(tabIndexProvider.notifier).state = 0;
      Navigator.of(context).popUntil((route) => route.isFirst);
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Your result'), automaticallyImplyLeading: false),
      body: Stack(
        children: [
          FadeRise(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
              children: [
                AppCard(
                  child: Column(
                    children: [
                      CountUp(value: result.correct, format: (v) => '$v / ${result.total}', style: text.displaySmall),
                      const SizedBox(height: 4),
                      Text(
                        '${result.percent}% · ${formatClock(result.usedSeconds)} used',
                        style: text.bodyMedium!.copyWith(color: p.textMuted),
                      ),
                    ],
                  ),
                ),
                for (final id in newBadges) ...[
                  const SizedBox(height: 12),
                  AppCard(
                    color: p.accentSoft,
                    borderColor: p.accentText,
                    child: Row(
                      children: [
                        Icon(BadgeDef.of(id).icon, color: p.accentText),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('New badge: ${BadgeDef.of(id).title}', style: text.titleSmall),
                              Text(BadgeDef.of(id).description, style: text.bodySmall),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: 20),
                Text('By topic', style: text.titleMedium),
                const SizedBox(height: 10),
                for (final t in result.topics)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(t.topic, style: text.bodyMedium, overflow: TextOverflow.ellipsis),
                            ),
                            Text('${t.correct}/${t.total}', style: text.labelLarge),
                          ],
                        ),
                        const SizedBox(height: 6),
                        GrowBar(
                          value: t.share,
                          color: t.share >= 0.7 ? p.success : (t.share < 0.5 ? p.danger : p.accentText),
                        ),
                      ],
                    ),
                  ),
                if (weakest != null) ...[
                  const SizedBox(height: 8),
                  AppButton(
                    label: 'Practise ${weakest.topic}',
                    icon: Icons.bolt_rounded,
                    onPressed: () => practise(weakest.topic),
                  ),
                ],
                const SizedBox(height: 10),
                AppButton.secondary(label: 'Done', onPressed: () => Navigator.of(context).pop()),
                if (toReview.isNotEmpty) ...[
                  const SizedBox(height: 28),
                  Text('Review (${toReview.length})', style: text.titleMedium),
                  const SizedBox(height: 4),
                  Text('These are in your Mistakes notebook too.', style: text.bodySmall!.copyWith(color: p.textMuted)),
                  const SizedBox(height: 10),
                  for (final i in toReview)
                    _ReviewTile(number: i + 1, question: test.questions[i], pick: test.answers[i]),
                ],
              ],
            ),
          ),
          // A burst of confetti for a strong result.
          Positioned.fill(child: Celebration(play: result.percent >= 80)),
        ],
      ),
    );
  }
}

class _ReviewTile extends StatelessWidget {
  final int number;
  final PracticeQuestion question;
  final int? pick;

  const _ReviewTile({required this.number, required this.question, required this.pick});

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final text = Theme.of(context).textTheme;
    final picked = pick;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: AppCard(
        padding: const EdgeInsets.all(AppSpace.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Q$number · ${question.topicName}', style: text.micro.copyWith(color: p.textMuted)),
            const SizedBox(height: 6),
            Text(question.questionText, style: text.titleSmall),
            const SizedBox(height: 8),
            Text(
              picked == null ? 'Not answered' : 'You picked: ${question.options[picked]}',
              style: text.bodyMedium!.copyWith(color: p.danger),
            ),
            Text(
              'Answer: ${question.options[question.correctIndex]}',
              style: text.bodyMedium!.copyWith(color: p.success),
            ),
            if (question.explanation.trim().isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(question.explanation.trim(), style: text.caption.copyWith(color: p.textMuted)),
            ],
          ],
        ),
      ),
    );
  }
}

class _Message extends StatelessWidget {
  final IconData icon;
  final String title;
  final String body;

  const _Message({required this.icon, required this.title, required this.body});

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final text = Theme.of(context).textTheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 52, color: p.accentText),
            const SizedBox(height: 14),
            Text(title, textAlign: TextAlign.center, style: text.titleLarge),
            const SizedBox(height: 8),
            Text(
              body,
              textAlign: TextAlign.center,
              style: text.bodyMedium!.copyWith(color: p.textMuted),
            ),
          ],
        ),
      ),
    );
  }
}
