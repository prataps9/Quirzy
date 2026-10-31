import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../shared/providers/exam_provider.dart';
import '../../../shared/theme/app_palette.dart';
import '../../../shared/widgets/app_widgets.dart';
import '../../plan/models/study_plan.dart';
import '../../plan/providers/study_plan_providers.dart';

/// Lets the user pick their exam date (today or later) and saves it, which
/// also reschedules the exam countdown notification. Returns true if a
/// date was saved.
Future<bool> pickExamDate(BuildContext context, WidgetRef ref) async {
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final current = ref.read(examDateProvider).value;
  final picked = await showDatePicker(
    context: context,
    initialDate: current != null && !current.isBefore(today) ? current : today.add(const Duration(days: 30)),
    firstDate: today,
    lastDate: DateTime(today.year + 5, today.month, today.day),
    helpText: 'When is your exam?',
  );
  if (picked == null) return false;
  await ref.read(examDateProvider.notifier).setDate(picked);
  return true;
}

/// Compact My Prep card: asks for the exam date, or counts down to it.
class ExamDateCard extends ConsumerWidget {
  const ExamDateCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.palette;
    final text = Theme.of(context).textTheme;
    final date = ref.watch(examDateProvider).value;
    final examName = examDisplayName(ref.watch(examProvider));

    final String title;
    final String subtitle;
    if (date == null) {
      title = 'When is your exam?';
      subtitle = 'Add the date to see a countdown here.';
    } else {
      final days = daysUntilExam(date);
      final label = MaterialLocalizations.of(context).formatMediumDate(date);
      if (days > 0) {
        title = days == 1 ? '1 day to $examName' : '$days days to $examName';
      } else if (days == 0) {
        title = '$examName is today';
      } else {
        title = '$examName has passed';
      }
      subtitle = days < 0 ? 'Set your next exam date.' : label;
    }
    // How the last week's pace compares with what's needed (from the plan).
    final plan = date == null ? null : ref.watch(studyPlanProvider).value;
    final (String, Color)? pace = switch (plan?.pace) {
      PlanPace.onTrack => ('On track · you average ${plan!.averagePerDay} a day', p.success),
      PlanPace.behind => ('Aim for ${plan!.neededPerDay} a day · you average ${plan.averagePerDay}', p.danger),
      _ => null,
    };

    return AppCard(
      onTap: () {
        HapticFeedback.selectionClick();
        pickExamDate(context, ref);
      },
      child: Row(
        children: [
          Icon(Icons.event_rounded, color: p.accentText, size: 22),
          const SizedBox(width: AppSpace.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: text.titleMedium),
                const SizedBox(height: 2),
                Text(subtitle, style: text.bodySmall),
                if (pace != null) ...[
                  const SizedBox(height: 2),
                  Text(pace.$1, style: text.bodySmall!.copyWith(color: pace.$2, fontWeight: FontWeight.w600)),
                ],
              ],
            ),
          ),
          const SizedBox(width: AppSpace.sm),
          Text(
            date == null ? 'Set date' : 'Edit',
            style: text.labelLarge!.copyWith(color: p.accentText, fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
  }
}
