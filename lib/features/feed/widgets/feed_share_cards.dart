import 'package:flutter/material.dart';

import '../../report/models/weekly_report.dart';
import '../../../shared/theme/app_palette.dart';
import '../../../shared/theme/app_text.dart';
import '../models/feed_models.dart';
import '../models/topic_style.dart';

/// A question as a story-sized image: topic, question and options, never
/// the answer — "can you get it?". Always dark so every shared picture
/// looks the same whatever theme the sender uses.
class QuestionShareCard extends StatelessWidget {
  final PracticeQuestion question;

  const QuestionShareCard({super.key, required this.question});

  @override
  Widget build(BuildContext context) {
    const p = AppPalette.dark;
    final text = Theme.of(context).textTheme;
    final style = TopicStyle.of(question.topicName);
    const labels = ['A', 'B', 'C', 'D', 'E', 'F'];
    final long = question.questionText.length > 160 || question.options.any((o) => o.length > 60);

    return _StoryFrame(
      tint: style.tint(Brightness.dark),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _Brand(),
          const SizedBox(height: 18),
          Row(
            children: [
              Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(color: p.accent, shape: BoxShape.circle),
                child: Icon(style.icon, size: 16, color: p.onAccent),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  question.topicName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: text.titleSmall!.copyWith(color: p.text),
                ),
              ),
            ],
          ),
          const Spacer(),
          Text(
            question.questionText,
            maxLines: 7,
            overflow: TextOverflow.ellipsis,
            style: text.shareQuestion(long: long).copyWith(color: p.text),
          ),
          const SizedBox(height: 18),
          for (var i = 0; i < question.options.length && i < labels.length; i++)
            Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: p.surface,
                borderRadius: BorderRadius.circular(AppRadius.chip),
                border: Border.all(color: p.border),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('${labels[i]}  ', style: text.labelLarge!.copyWith(color: p.accentText)),
                  Expanded(
                    child: Text(
                      question.options[i],
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: text.bodyMedium!.copyWith(color: p.text),
                    ),
                  ),
                ],
              ),
            ),
          const Spacer(),
          Text('Can you get it?', style: text.titleMedium!.copyWith(color: p.accentText)),
          const SizedBox(height: 2),
          Text('Practise on Quirzy', style: text.bodySmall!.copyWith(color: p.textMuted)),
        ],
      ),
    );
  }
}

/// A practice session as a story-sized image.
class RecapShareCard extends StatelessWidget {
  final FeedRecap recap;

  const RecapShareCard({super.key, required this.recap});

  @override
  Widget build(BuildContext context) {
    const p = AppPalette.dark;
    final text = Theme.of(context).textTheme;

    Widget stat(String value, String label) => Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(value, style: text.displaySmall!.copyWith(color: p.text, fontWeight: FontWeight.w800)),
        Text(label, style: text.bodyMedium!.copyWith(color: p.textMuted)),
      ],
    );

    return _StoryFrame(
      tint: p.bg,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _Brand(),
          const Spacer(),
          Text('Practice session', style: text.titleMedium!.copyWith(color: p.accentText)),
          const SizedBox(height: 16),
          stat('${recap.answered}', 'questions answered'),
          const SizedBox(height: 14),
          stat('${recap.accuracyPercent}%', 'right'),
          const SizedBox(height: 14),
          stat('+${recap.xp}', 'XP earned'),
          if (recap.bestCombo >= 2) ...[
            const SizedBox(height: 14),
            stat('${recap.bestCombo}', 'in a row, best run'),
          ],
          if (recap.topTopics.isNotEmpty) ...[
            const SizedBox(height: 20),
            Text(
              recap.topTopics.join(' · '),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: text.bodyMedium!.copyWith(color: p.text),
            ),
          ],
          const Spacer(),
          Text('Your turn? Practise on Quirzy', style: text.bodySmall!.copyWith(color: p.textMuted)),
        ],
      ),
    );
  }
}

/// The weekly report as a story-sized image.
class WeeklyShareCard extends StatelessWidget {
  final WeeklyReport report;

  const WeeklyShareCard({super.key, required this.report});

  @override
  Widget build(BuildContext context) {
    const p = AppPalette.dark;
    final text = Theme.of(context).textTheme;
    final max = report.answeredByDay.fold(0, (a, b) => b > a ? b : a);

    Widget stat(String value, String label) => Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(value, style: text.displaySmall!.copyWith(color: p.text, fontWeight: FontWeight.w800)),
        Text(label, style: text.bodyMedium!.copyWith(color: p.textMuted)),
      ],
    );

    return _StoryFrame(
      tint: p.bg,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _Brand(),
          const Spacer(),
          Text('My week', style: text.titleMedium!.copyWith(color: p.accentText)),
          const SizedBox(height: 16),
          stat('${report.answered}', 'questions answered'),
          if (report.accuracy != null) ...[const SizedBox(height: 14), stat('${report.accuracy}%', 'right')],
          const SizedBox(height: 14),
          stat('${report.daysActive}/7', 'days practised'),
          const SizedBox(height: 22),
          SizedBox(
            height: 64,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                for (final n in report.answeredByDay)
                  Expanded(
                    child: Align(
                      alignment: Alignment.bottomCenter,
                      child: Container(
                        width: 18,
                        height: max == 0 ? 0 : 64 * n / max,
                        decoration: BoxDecoration(
                          color: p.accent,
                          borderRadius: const BorderRadius.vertical(top: Radius.circular(4)),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          Container(height: 1, color: p.border),
          if (report.mostPractised != null) ...[
            const SizedBox(height: 16),
            Text(
              'Most practised: ${report.mostPractised!.topic}',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: text.bodyMedium!.copyWith(color: p.text),
            ),
          ],
          const Spacer(),
          Text('Your turn? Practise on Quirzy', style: text.bodySmall!.copyWith(color: p.textMuted)),
        ],
      ),
    );
  }
}

/// The 9:16 frame both share cards use (same size as My Prep's card).
class _StoryFrame extends StatelessWidget {
  final Color tint;
  final Widget child;

  const _StoryFrame({required this.tint, required this.child});

  @override
  Widget build(BuildContext context) {
    const p = AppPalette.dark;
    return Container(
      width: 320,
      height: 568,
      padding: const EdgeInsets.all(28),
      decoration: BoxDecoration(
        color: tint,
        borderRadius: BorderRadius.circular(AppRadius.sheet),
        border: Border.all(color: p.border),
      ),
      child: child,
    );
  }
}

class _Brand extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    const p = AppPalette.dark;
    return Row(
      children: [
        Icon(Icons.bolt_rounded, color: p.accent, size: 24),
        const SizedBox(width: 6),
        Text('Quirzy', style: Theme.of(context).textTheme.titleMedium!.copyWith(color: p.text)),
      ],
    );
  }
}
