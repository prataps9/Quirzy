import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../shared/theme/app_palette.dart';
import '../../../shared/widgets/app_widgets.dart';
import '../models/feed_models.dart';
import '../models/topic_style.dart';

/// "Your session so far": answered, accuracy, XP, best combo and topics,
/// with a nudge to the weakest topic. In a long session it suggests a
/// break instead of popping up a dialog.
class RecapCard extends StatelessWidget {
  final FeedRecap recap;
  final VoidCallback onKeepGoing;
  final ValueChanged<String> onPracticeTopic;
  final VoidCallback onShare;
  final VoidCallback onTakeBreak;

  const RecapCard({
    super.key,
    required this.recap,
    required this.onKeepGoing,
    required this.onPracticeTopic,
    required this.onShare,
    required this.onTakeBreak,
  });

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final text = Theme.of(context).textTheme;
    return SafeArea(
      top: false,
      child: LayoutBuilder(
        builder: (context, constraints) => SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: constraints.maxHeight - 24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Icon(
                  recap.suggestBreak ? Icons.self_improvement_rounded : Icons.insights_rounded,
                  size: 44,
                  color: p.accentText,
                ),
                const SizedBox(height: 12),
                Text(
                  recap.suggestBreak ? 'Nice session — take 5?' : 'Your session so far',
                  textAlign: TextAlign.center,
                  style: text.headlineSmall,
                ),
                if (recap.suggestBreak) ...[
                  const SizedBox(height: 6),
                  Text(
                    'A short break helps it stick. Your streak is safe for today.',
                    textAlign: TextAlign.center,
                    style: text.bodyMedium!.copyWith(color: p.textMuted),
                  ),
                ],
                const SizedBox(height: 20),
                Row(
                  children: [
                    Expanded(child: _Stat(value: '${recap.answered}', label: 'answered')),
                    const SizedBox(width: 10),
                    Expanded(child: _Stat(value: '${recap.accuracyPercent}%', label: 'correct')),
                    const SizedBox(width: 10),
                    Expanded(child: _Stat(value: '+${recap.xp}', label: 'XP')),
                  ],
                ),
                if (recap.bestCombo >= 2) ...[
                  const SizedBox(height: 10),
                  Text(
                    'Best run: ${recap.bestCombo} in a row',
                    textAlign: TextAlign.center,
                    style: text.labelLarge!.copyWith(color: p.accentText),
                  ),
                ],
                if (recap.topTopics.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  Wrap(
                    alignment: WrapAlignment.center,
                    spacing: 8,
                    runSpacing: 8,
                    children: [for (final topic in recap.topTopics) _TopicChip(topic: topic)],
                  ),
                ],
                const SizedBox(height: 22),
                if (recap.suggestBreak) ...[
                  AppButton(label: 'Take a break', icon: Icons.self_improvement_rounded, onPressed: onTakeBreak),
                  const SizedBox(height: 10),
                  AppButton.secondary(label: 'Keep going', onPressed: onKeepGoing),
                ] else ...[
                  AppButton(label: 'Keep going', icon: Icons.keyboard_double_arrow_down_rounded, onPressed: onKeepGoing),
                  if (recap.weakTopic != null) ...[
                    const SizedBox(height: 10),
                    AppButton.secondary(
                      label: 'Practise ${recap.weakTopic}',
                      icon: Icons.track_changes_rounded,
                      onPressed: () => onPracticeTopic(recap.weakTopic!),
                    ),
                  ],
                ],
                const SizedBox(height: 4),
                TextButton.icon(
                  onPressed: () {
                    HapticFeedback.selectionClick();
                    onShare();
                  },
                  icon: const Icon(Icons.ios_share_rounded, size: 18),
                  label: const Text('Share my session'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// "You've seen everything new": offer to generate more of a topic (through
/// Home, so the daily limit applies) or keep reviewing.
class CaughtUpCard extends StatelessWidget {
  final String topic;
  final VoidCallback onGenerateMore;
  final VoidCallback onKeepReviewing;

  const CaughtUpCard({
    super.key,
    required this.topic,
    required this.onGenerateMore,
    required this.onKeepReviewing,
  });

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final text = Theme.of(context).textTheme;
    final style = TopicStyle.of(topic);
    return ColoredBox(
      color: style.tint(Theme.of(context).brightness),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Icon(Icons.task_alt_rounded, size: 52, color: p.accentText),
              const SizedBox(height: 14),
              Text("You've seen everything new", textAlign: TextAlign.center, style: text.headlineSmall),
              const SizedBox(height: 8),
              Text(
                'From here the feed mixes in questions worth another look. '
                'Want fresh ones in $topic?',
                textAlign: TextAlign.center,
                style: text.bodyMedium!.copyWith(color: p.textMuted),
              ),
              const SizedBox(height: 24),
              AppButton(label: 'Generate more $topic', icon: style.icon, onPressed: onGenerateMore),
              const SizedBox(height: 10),
              AppButton.secondary(label: 'Keep reviewing', onPressed: onKeepReviewing),
            ],
          ),
        ),
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  final String value;
  final String label;

  const _Stat({required this.value, required this.label});

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return AppCard(
      child: Column(
        children: [
          FittedBox(child: Text(value, style: text.headlineSmall)),
          const SizedBox(height: 2),
          Text(label, style: text.bodySmall),
        ],
      ),
    );
  }
}

class _TopicChip extends StatelessWidget {
  final String topic;

  const _TopicChip({required this.topic});

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final style = TopicStyle.of(topic);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: style.tint(Theme.of(context).brightness),
        borderRadius: BorderRadius.circular(AppRadius.pill),
        border: Border.all(color: p.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(style.icon, size: 16, color: p.accentText),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              topic,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.labelLarge,
            ),
          ),
        ],
      ),
    );
  }
}
