import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../shared/theme/app_palette.dart';
import '../../../shared/widgets/app_widgets.dart';
import '../providers/weekly_report_providers.dart';
import '../screens/weekly_report_screen.dart';

/// My Prep's way into the weekly report: this week's headline numbers.
class YourWeekCard extends ConsumerWidget {
  const YourWeekCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.palette;
    final text = Theme.of(context).textTheme;
    final report = ref.watch(weeklyReportProvider(0)).value;
    final String line;
    if (report == null || report.isEmpty) {
      line = 'Your questions, topics and best time of day';
    } else {
      final right = report.accuracy == null ? '' : ' · ${report.accuracy}% right';
      line =
          '${report.answered} ${report.answered == 1 ? 'question' : 'questions'}$right · ${report.daysActive}/7 days';
    }
    return AppCard(
      onTap: () {
        HapticFeedback.selectionClick();
        Navigator.of(context).push(MaterialPageRoute(builder: (_) => const WeeklyReportScreen()));
      },
      child: Row(
        children: [
          Icon(Icons.insights_rounded, color: p.accentText, size: 22),
          const SizedBox(width: AppSpace.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Your week', style: text.titleMedium),
                const SizedBox(height: 2),
                Text(line, style: text.bodySmall),
              ],
            ),
          ),
          Icon(Icons.chevron_right_rounded, color: p.textMuted),
        ],
      ),
    );
  }
}
