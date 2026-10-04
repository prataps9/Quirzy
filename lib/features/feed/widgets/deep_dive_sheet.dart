import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../shared/theme/app_palette.dart';
import '../models/feed_models.dart';
import '../providers/feed_providers.dart';

/// The solution drawer: the correct answer, its explanation, and a short
/// list of similar questions from the same topic.
class DeepDiveSheet extends ConsumerWidget {
  final PracticeQuestion question;
  final int cardIndex;

  const DeepDiveSheet({super.key, required this.question, required this.cardIndex});

  static Future<void> show(BuildContext context, PracticeQuestion question, int cardIndex) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (_) => DeepDiveSheet(question: question, cardIndex: cardIndex),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.palette;
    final text = Theme.of(context).textTheme;
    final controller = ref.read(feedControllerProvider.notifier);
    final similar = controller.similarTo(question);

    return DraggableScrollableSheet(
      initialChildSize: 0.75,
      minChildSize: 0.4,
      maxChildSize: 0.92,
      expand: false,
      builder: (context, scrollController) {
        return ListView(
          controller: scrollController,
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: p.border,
                  borderRadius: BorderRadius.circular(AppRadius.pill),
                ),
              ),
            ),
            const SizedBox(height: 18),
            Text('Solution', style: text.titleLarge),
            const SizedBox(height: 12),
            Text(question.questionText, style: text.bodyMedium!.copyWith(fontWeight: FontWeight.w600)),
            const SizedBox(height: 14),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: p.successSoft,
                borderRadius: BorderRadius.circular(AppRadius.control),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.check_circle_rounded, color: p.success, size: 20),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      question.options[question.correctIndex],
                      style: text.bodyMedium!.copyWith(fontWeight: FontWeight.w700),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            Text(
              question.explanation.trim().isEmpty
                  ? 'No solution notes for this question yet.'
                  : question.explanation,
              style: text.bodyMedium!.copyWith(height: 1.6, color: p.textMuted),
            ),
            if (similar.isNotEmpty) ...[
              const SizedBox(height: 26),
              Text('Similar questions', style: text.titleMedium),
              const SizedBox(height: 10),
              for (final q in similar)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(AppRadius.control),
                    onTap: () {
                      controller.insertNext(cardIndex, q);
                      Navigator.of(context).pop();
                    },
                    child: Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        border: Border.all(color: p.border),
                        borderRadius: BorderRadius.circular(AppRadius.control),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              q.questionText,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: text.bodyMedium,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Icon(Icons.chevron_right_rounded, size: 20, color: p.accentText),
                        ],
                      ),
                    ),
                  ),
                ),
            ],
          ],
        );
      },
    );
  }
}
