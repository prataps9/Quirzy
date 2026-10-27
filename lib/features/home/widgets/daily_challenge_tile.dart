import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../shared/providers/providers.dart';
import '../../../shared/theme/app_palette.dart';
import '../../../shared/widgets/app_widgets.dart';
import '../../feed/models/feed_models.dart';
import '../../feed/providers/feed_providers.dart';

/// One tap into today's Daily 5, with how far through it you are.
class DailyChallengeTile extends ConsumerWidget {
  const DailyChallengeTile({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final daily = ref.watch(dailyChallengeProvider).value;
    if (daily == null) return const SizedBox.shrink();
    final p = context.palette;
    final text = Theme.of(context).textTheme;

    final subtitle = daily.completed
        ? 'Done: ${daily.correct} of ${daily.total} right'
        : daily.answered > 0
        ? '${daily.answered} of ${daily.total} done. Finish for a bonus'
        : '${daily.total} questions, a fresh set every day';

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
      child: AppCard(
        onTap: () {
          ref
              .read(feedControllerProvider.notifier)
              .switchLane(
                FeedLane(type: FeedLaneType.daily, id: FeedLane.dailyId, label: 'Daily ${daily.total}', count: daily.total),
              );
          ref.read(tabIndexProvider.notifier).state = 0;
        },
        padding: const EdgeInsets.symmetric(horizontal: AppSpace.lg, vertical: AppSpace.md),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: daily.completed ? p.successSoft : p.accentSoft,
              ),
              child: Icon(
                daily.completed ? Icons.check_rounded : Icons.bolt_rounded,
                color: daily.completed ? p.success : p.accentText,
              ),
            ),
            const SizedBox(width: AppSpace.md),
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Daily ${daily.total}', style: text.titleSmall),
                  Text(subtitle, style: text.bodySmall!.copyWith(color: p.textMuted)),
                ],
              ),
            ),
            Icon(Icons.chevron_right_rounded, color: p.textMuted),
          ],
        ),
      ),
    );
  }
}
