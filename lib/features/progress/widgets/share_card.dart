import 'package:flutter/material.dart';

import '../../../shared/theme/app_palette.dart';
import '../providers/progress_providers.dart';

/// A vertical, Instagram-Story-proportioned card summarizing progress,
/// captured and shared as an image. It always uses the dark palette so the
/// shared picture looks the same whatever theme the sender uses.
class ShareCard extends StatelessWidget {
  final MyPrepStats stats;

  const ShareCard({super.key, required this.stats});

  @override
  Widget build(BuildContext context) {
    const p = AppPalette.dark;
    final text = Theme.of(context).textTheme;

    return Container(
      width: 320,
      height: 568,
      padding: const EdgeInsets.all(28),
      decoration: BoxDecoration(
        color: p.bg,
        borderRadius: BorderRadius.circular(AppRadius.sheet),
        border: Border.all(color: p.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.bolt_rounded, color: p.accent, size: 24),
              const SizedBox(width: 6),
              Text('Quirzy', style: text.titleMedium!.copyWith(color: p.text)),
            ],
          ),
          const Spacer(),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                '${stats.streak}',
                style: text.displayLarge!.copyWith(color: p.accent, fontSize: 88, height: 1),
              ),
              const SizedBox(width: 8),
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Icon(Icons.local_fire_department_rounded, color: p.streak, size: 44),
              ),
            ],
          ),
          Text('day streak', style: text.titleMedium!.copyWith(color: p.textMuted)),
          const SizedBox(height: 28),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 14),
            decoration: BoxDecoration(
              color: p.surface,
              borderRadius: BorderRadius.circular(AppRadius.control),
              border: Border.all(color: p.border),
            ),
            child: Center(
              child: Text(
                'Level ${stats.level.level} · ${stats.level.title}',
                style: text.titleMedium!.copyWith(color: p.text),
              ),
            ),
          ),
          const SizedBox(height: 14),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _stat(text, p, '${stats.dailyAnsweredLast7.fold<int>(0, (a, b) => a + b)}', 'this week'),
              _stat(text, p, '${stats.topicStats.length}', 'topics'),
            ],
          ),
          const Spacer(),
          Text(
            'Practice a little every day →',
            style: text.bodySmall!.copyWith(color: p.textMuted),
          ),
        ],
      ),
    );
  }

  Widget _stat(TextTheme text, AppPalette p, String value, String label) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(value, style: text.headlineMedium!.copyWith(color: p.text)),
        Text(label, style: text.bodySmall!.copyWith(color: p.textMuted)),
      ],
    );
  }
}
