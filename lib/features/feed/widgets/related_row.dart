import 'package:flutter/material.dart';

import '../../../shared/theme/app_palette.dart';
import '../models/feed_models.dart';
import '../services/related_questions.dart';

/// One related question: the text, its topic when it differs from the
/// current one, and whether it is new, missed or answered (word and icon,
/// never colour alone).
class RelatedRow extends StatelessWidget {
  final RelatedQuestion related;
  final bool showTopic;
  final VoidCallback onTap;

  const RelatedRow({super.key, required this.related, required this.showTopic, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final text = Theme.of(context).textTheme;
    final (icon, color) = switch (related.status) {
      RelatedStatus.fresh => (Icons.fiber_new_rounded, p.accentText),
      RelatedStatus.missed => (Icons.flag_rounded, p.danger),
      RelatedStatus.answered => (Icons.check_rounded, p.textMuted),
    };
    return Semantics(
      button: true,
      label: '${related.status.label}: ${related.question.questionText}. Tap to practise next',
      excludeSemantics: true,
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadius.control),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            border: Border.all(color: p.border),
            borderRadius: BorderRadius.circular(AppRadius.control),
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(icon, size: 14, color: color),
                        const SizedBox(width: 4),
                        Text(related.status.label, style: text.labelSmall!.copyWith(color: color)),
                        if (showTopic) ...[
                          Text('  ·  ', style: text.labelSmall),
                          Expanded(
                            child: Text(
                              related.question.topicName,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: text.labelSmall,
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      related.question.questionText,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: text.bodyMedium,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Icon(Icons.chevron_right_rounded, size: 20, color: p.accentText),
            ],
          ),
        ),
      ),
    );
  }
}
