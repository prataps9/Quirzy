import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../shared/providers/providers.dart';
import '../../../shared/theme/app_motion.dart';
import '../../../shared/theme/app_palette.dart';
import '../../../shared/widgets/app_widgets.dart';
import '../../../shared/widgets/motion.dart';
import '../../feed/models/feed_models.dart';
import '../../feed/providers/feed_providers.dart';
import '../../progress/providers/badge_providers.dart';
import '../../progress/widgets/exam_date_card.dart';
import '../models/study_plan.dart';
import '../providers/study_plan_providers.dart';

/// Home's "Today's plan": a short checklist worked out from the exam date,
/// weak topics, mistakes and pace. Each row opens what it asks for, rows
/// tick off as you go, and finishing them all is celebrated (and counted).
class TodayPlanCard extends ConsumerStatefulWidget {
  const TodayPlanCard({super.key});

  @override
  ConsumerState<TodayPlanCard> createState() => _TodayPlanCardState();
}

class _TodayPlanCardState extends ConsumerState<TodayPlanCard> {
  bool _celebrate = false;

  Future<void> _onComplete() async {
    final first = await ref.read(studyPlanServiceProvider).markComplete();
    if (!first || !mounted) return;
    HapticFeedback.mediumImpact();
    setState(() => _celebrate = true);
    await ref.read(badgeServiceProvider).check();
    if (mounted) ref.invalidate(badgeStatusesProvider);
  }

  void _open(PlanTask task) {
    HapticFeedback.selectionClick();
    final feed = ref.read(feedControllerProvider.notifier);
    switch (task.kind) {
      case PlanTaskKind.daily:
        final daily = ref.read(dailyChallengeProvider).value;
        if (daily != null) {
          unawaited(
            feed.switchLane(
              FeedLane(
                type: FeedLaneType.daily,
                id: FeedLane.dailyId,
                label: 'Daily ${daily.total}',
                count: daily.total,
              ),
            ),
          );
        }
      case PlanTaskKind.mistakes:
        unawaited(feed.switchLane(FeedLane.mistakes));
      case PlanTaskKind.revision:
        unawaited(
          feed.switchLane(const FeedLane(type: FeedLaneType.revision, id: 'revision', label: 'Revision Vault')),
        );
      case PlanTaskKind.focusTopic:
        final topic = task.topic!;
        unawaited(feed.switchLane(FeedLane(type: FeedLaneType.topic, id: 'topic:$topic', label: topic)));
      case PlanTaskKind.goal:
        break;
    }
    ref.read(tabIndexProvider.notifier).state = 0;
  }

  @override
  Widget build(BuildContext context) {
    final plan = ref.watch(studyPlanProvider).value;
    if (plan == null || plan.tasks.isEmpty) return const SizedBox.shrink();
    if (plan.complete && !_celebrate) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _onComplete());
    }
    final p = context.palette;
    final text = Theme.of(context).textTheme;
    final paceColor = switch (plan.pace) {
      PlanPace.onTrack => p.success,
      PlanPace.behind => p.danger,
      _ => p.textMuted,
    };

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
      child: Stack(
        children: [
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Icon(Icons.checklist_rounded, color: p.accentText),
                    const SizedBox(width: 10),
                    Expanded(child: Text("Today's plan", style: text.titleMedium)),
                    CountUp(
                      value: plan.completeCount,
                      format: (v) => '$v/${plan.tasks.length}',
                      style: text.labelLarge!.copyWith(color: plan.complete ? p.success : p.textMuted),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                InkWell(
                  borderRadius: BorderRadius.circular(AppRadius.chip),
                  onTap: plan.pace == PlanPace.noDate || plan.pace == PlanPace.examDay
                      ? () => pickExamDate(context, ref)
                      : null,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 2),
                    child: Text(plan.paceLine, style: text.bodySmall!.copyWith(color: paceColor)),
                  ),
                ),
                const SizedBox(height: 8),
                for (final (i, task) in plan.tasks.indexed)
                  Stagger(
                    index: i,
                    child: _TaskRow(task: task, onTap: () => _open(task)),
                  ),
                Reveal(
                  show: plan.complete,
                  child: Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text('All done for today. Great work!', style: text.titleSmall!.copyWith(color: p.success)),
                  ),
                ),
              ],
            ),
          ),
          Positioned.fill(child: Celebration(play: _celebrate)),
        ],
      ),
    );
  }
}

class _TaskRow extends StatelessWidget {
  final PlanTask task;
  final VoidCallback onTap;

  const _TaskRow({required this.task, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final text = Theme.of(context).textTheme;
    final duration = AppMotion.of(context, AppMotion.base);
    return Semantics(
      button: true,
      label: '${task.title}, ${task.done} of ${task.target}${task.complete ? ', done' : ''}',
      excludeSemantics: true,
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadius.chip),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Row(
            children: [
              SizedBox(
                width: 24,
                height: 24,
                child: AnimatedSwitcher(
                  duration: duration,
                  transitionBuilder: (child, animation) => ScaleTransition(scale: animation, child: child),
                  child: task.complete
                      ? Icon(Icons.check_circle_rounded, key: const ValueKey('done'), color: p.success, size: 24)
                      : TweenAnimationBuilder<double>(
                          key: const ValueKey('ring'),
                          tween: Tween(begin: 0, end: task.progress),
                          duration: AppMotion.of(context, AppMotion.slow),
                          builder: (context, v, _) => CircularProgressIndicator(
                            value: v,
                            strokeWidth: 3,
                            color: p.accentText,
                            backgroundColor: p.surfaceHigh,
                          ),
                        ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: AnimatedDefaultTextStyle(
                  duration: duration,
                  style: text.bodyMedium!.copyWith(color: task.complete ? p.textMuted : p.text),
                  child: Text(task.title, maxLines: 1, overflow: TextOverflow.ellipsis),
                ),
              ),
              const SizedBox(width: 8),
              Text('${task.done}/${task.target}', style: text.labelMedium!.copyWith(color: p.textMuted)),
              Icon(Icons.chevron_right_rounded, size: 18, color: p.textMuted),
            ],
          ),
        ),
      ),
    );
  }
}
