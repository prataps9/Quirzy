import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../auth/providers/auth_provider.dart';
import '../../../shared/theme/app_motion.dart';
import '../../../shared/theme/app_palette.dart';
import '../../../shared/theme/app_text.dart';
import '../../../shared/widgets/app_widgets.dart';
import '../../../shared/widgets/motion.dart';
import '../../feed/models/feed_models.dart';
import '../../feed/providers/feed_providers.dart';
import '../../feed/services/streak_service.dart';
import '../../feed/widgets/option_card.dart';
import '../models/challenge.dart';

/// The user's first name, for "Beat my 4/5" from them.
String? firstNameOf(WidgetRef ref) {
  final name = ref.read(authProvider).value?.name.trim() ?? '';
  return name.isEmpty ? null : name.split(RegExp(r'\s+')).first;
}

/// Sends [challenge] (questions and, optionally, a score) to another app.
Future<void> shareChallenge(Challenge challenge) =>
    SharePlus.instance.share(ShareParams(text: ChallengeCodec.shareText(challenge), subject: 'A Quirzy challenge'));

/// Plays a challenge someone sent: the questions one by one, no answers
/// until the end, then your score against theirs.
class ChallengeScreen extends ConsumerStatefulWidget {
  final Challenge challenge;

  const ChallengeScreen({super.key, required this.challenge});

  @override
  ConsumerState<ChallengeScreen> createState() => _ChallengeScreenState();
}

class _ChallengeScreenState extends ConsumerState<ChallengeScreen> {
  final _pages = PageController();
  final Map<int, int> _answers = {};
  int _current = 0;
  bool _done = false;

  Challenge get _c => widget.challenge;

  int get _score =>
      [for (var i = 0; i < _c.total; i++) i].where((i) => _answers[i] == _c.questions[i].correctIndex).length;

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  void _go(int index) =>
      _pages.animateToPage(index, duration: AppMotion.of(context, AppMotion.base), curve: AppMotion.enter);

  Future<void> _finish() async {
    if (_done) return;
    HapticFeedback.mediumImpact();
    setState(() => _done = true);
    // Counts as practice: topic stats, the Mistakes notebook and today.
    final stats = ref.read(feedStatsServiceProvider);
    final mistakes = ref.read(mistakesServiceProvider);
    for (final e in _answers.entries) {
      final q = _c.questions[e.key];
      final right = e.value == q.correctIndex;
      await stats.recordAttempt(q.topic, right);
      await mistakes.recordAnswer(q, correct: right, pick: right ? null : e.value);
    }
    if (_answers.isNotEmpty) {
      final prefs = await SharedPreferences.getInstance();
      final key = StreakService.countKey(DateTime.now());
      await prefs.setInt(key, (prefs.getInt(key) ?? 0) + _answers.length);
    }
    if (!mounted) return;
    ref
      ..invalidate(streakProvider)
      ..invalidate(mistakeInsightProvider);
  }

  @override
  Widget build(BuildContext context) {
    final from = _c.from ?? 'Your friend';
    return Scaffold(
      appBar: AppBar(title: Text(_done ? 'Challenge result' : 'Challenge from $from')),
      body: AnimatedSwitcher(
        duration: AppMotion.of(context, AppMotion.base),
        child: _done ? _result(context) : _questions(context),
      ),
    );
  }

  Widget _questions(BuildContext context) {
    final p = context.palette;
    final text = Theme.of(context).textTheme;
    final last = _current == _c.total - 1;
    const labels = ['A', 'B', 'C', 'D', 'E', 'F'];
    return Column(
      key: const ValueKey('questions'),
      children: [
        LinearProgressIndicator(value: (_current + 1) / _c.total, minHeight: 3),
        if (_c.score != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
            child: Text(
              '${_c.from ?? 'They'} got ${_c.score}/${_c.total}. Can you beat it?',
              style: text.labelLarge!.copyWith(color: p.accentText),
            ),
          ),
        Expanded(
          child: PageView.builder(
            controller: _pages,
            itemCount: _c.total,
            onPageChanged: (i) => setState(() => _current = i),
            itemBuilder: (context, i) {
              final q = _c.questions[i];
              return ListView(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
                children: [
                  Text('QUESTION ${i + 1} OF ${_c.total}', style: text.micro.copyWith(color: p.textMuted)),
                  const SizedBox(height: 8),
                  Text(q.questionText, style: text.question),
                  const SizedBox(height: 20),
                  for (var o = 0; o < q.options.length; o++)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: OptionCard(
                        option: q.options[o],
                        label: labels[o],
                        isSelected: _answers[i] == o,
                        onTap: () {
                          HapticFeedback.selectionClick();
                          setState(() => _answers[i] = o);
                        },
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
                  child: AppButton.secondary(label: 'Back', onPressed: _current == 0 ? null : () => _go(_current - 1)),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: last
                      ? AppButton(label: 'Finish', onPressed: _answers.isEmpty ? null : () => unawaited(_finish()))
                      : AppButton(label: 'Next', onPressed: () => _go(_current + 1)),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _result(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final mine = _score;
    final theirs = _c.score;
    final name = _c.from ?? 'Your friend';
    final verdict = theirs == null
        ? 'You got $mine of ${_c.total}.'
        : mine > theirs
        ? 'You beat $name!'
        : mine == theirs
        ? "It's a tie."
        : '$name wins this one.';

    return Stack(
      key: const ValueKey('result'),
      children: [
        ListView(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
          children: [
            FadeRise(
              child: AppCard(
                child: Column(
                  children: [
                    Text(verdict, textAlign: TextAlign.center, style: text.titleLarge),
                    const SizedBox(height: 14),
                    Row(
                      children: [
                        Expanded(
                          child: _ScoreBlock(label: 'You', score: mine, total: _c.total, lead: true),
                        ),
                        if (theirs != null)
                          Expanded(
                            child: _ScoreBlock(label: name, score: theirs, total: _c.total, lead: false),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            AppButton(
              label: 'Share your score',
              icon: Icons.ios_share_rounded,
              onPressed: () => shareChallenge(_c.copyWith(from: firstNameOf(ref) ?? 'A friend', score: mine)),
            ),
            const SizedBox(height: 10),
            AppButton.secondary(label: 'Done', onPressed: () => Navigator.of(context).pop()),
            const SizedBox(height: 24),
            Text('Answers', style: text.titleMedium),
            const SizedBox(height: 10),
            for (var i = 0; i < _c.total; i++) _AnswerTile(number: i + 1, question: _c.questions[i], pick: _answers[i]),
          ],
        ),
        Positioned.fill(child: Celebration(play: theirs != null && mine > theirs)),
      ],
    );
  }
}

class _ScoreBlock extends StatelessWidget {
  final String label;
  final int score;
  final int total;
  final bool lead;

  const _ScoreBlock({required this.label, required this.score, required this.total, required this.lead});

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final text = Theme.of(context).textTheme;
    return Column(
      children: [
        CountUp(
          value: score,
          format: (v) => '$v/$total',
          style: text.displaySmall!.copyWith(color: lead ? p.accentText : p.text),
        ),
        Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: text.bodySmall!.copyWith(color: p.textMuted),
        ),
      ],
    );
  }
}

class _AnswerTile extends StatelessWidget {
  final int number;
  final PracticeQuestion question;
  final int? pick;

  const _AnswerTile({required this.number, required this.question, required this.pick});

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final text = Theme.of(context).textTheme;
    final picked = pick;
    final right = picked == question.correctIndex;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: AppCard(
        padding: const EdgeInsets.all(AppSpace.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  right ? Icons.check_circle_rounded : Icons.cancel_rounded,
                  size: 18,
                  color: right ? p.success : p.danger,
                ),
                const SizedBox(width: 6),
                Text('Q$number', style: text.micro.copyWith(color: p.textMuted)),
              ],
            ),
            const SizedBox(height: 6),
            Text(question.questionText, style: text.titleSmall),
            const SizedBox(height: 6),
            if (!right)
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
