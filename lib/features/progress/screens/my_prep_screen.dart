import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../shared/providers/providers.dart';
import '../../../shared/theme/app_palette.dart';
import '../../../shared/widgets/app_widgets.dart';
import '../../feed/models/feed_models.dart';
import '../../feed/providers/feed_providers.dart';
import '../../profile/screens/leaderboard_screen.dart';
import '../providers/progress_providers.dart';
import '../services/share_card_service.dart';
import '../widgets/share_card.dart';

/// My Prep: the progress dashboard — streak, XP level, daily target, a
/// 7-day activity trend, and a per-topic accuracy breakdown, all sourced
/// from data the feed already tracks locally.
class MyPrepScreen extends ConsumerStatefulWidget {
  const MyPrepScreen({super.key});

  @override
  ConsumerState<MyPrepScreen> createState() => _MyPrepScreenState();
}

class _MyPrepScreenState extends ConsumerState<MyPrepScreen> {
  final _shareCardKey = GlobalKey();

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final statsAsync = ref.watch(myPrepStatsProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('My Prep')),
      body: statsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, st) => Center(child: Text('Could not load your progress.', style: text.bodyMedium)),
        data: (stats) => RefreshIndicator(
          onRefresh: () async => ref.invalidate(myPrepStatsProvider),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
            children: [
              _StreakCard(stats: stats),
              const SizedBox(height: 12),
              _LevelCard(stats: stats),
              const SizedBox(height: 12),
              _DailyTargetCard(stats: stats),
              const SizedBox(height: 12),
              _ActivityTrend(stats: stats),
              const SizedBox(height: 24),
              Text('Topic accuracy', style: text.titleMedium),
              const SizedBox(height: 10),
              _TopicBreakdown(stats: stats),
              const SizedBox(height: 24),
              Text('Keep going', style: text.titleMedium),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: _LaneCard(
                      icon: Icons.history_rounded,
                      label: 'Revision Vault',
                      count: stats.revisionDueCount,
                      lane: const FeedLane(type: FeedLaneType.revision, id: 'revision', label: 'Revision Vault'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _LaneCard(
                      icon: Icons.bookmark_rounded,
                      label: 'Saved',
                      count: stats.bookmarkCount,
                      lane: const FeedLane(type: FeedLaneType.bookmarks, id: 'bookmarks', label: 'Saved'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              AppButton.secondary(
                label: 'View leaderboard',
                icon: Icons.leaderboard_rounded,
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const LeaderboardScreen()),
                ),
              ),
              const SizedBox(height: 24),
              Text('Share your progress', style: text.titleMedium),
              const SizedBox(height: 12),
              Center(
                child: RepaintBoundary(
                  key: _shareCardKey,
                  child: ShareCard(stats: stats),
                ),
              ),
              const SizedBox(height: 16),
              AppButton(
                label: 'Share',
                icon: Icons.share_rounded,
                onPressed: () => ShareCardService.shareFromKey(_shareCardKey),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StreakCard extends StatelessWidget {
  final MyPrepStats stats;

  const _StreakCard({required this.stats});

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final text = Theme.of(context).textTheme;
    final hasStreak = stats.streak > 0;
    final status = !hasStreak
        ? 'Answer a question today to start your streak.'
        : stats.streakAtRisk
            ? 'Practise today to keep your streak alive.'
            : 'You practised today. See you tomorrow!';

    return AppCard(
      padding: const EdgeInsets.all(20),
      child: Row(
        children: [
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              color: hasStreak ? p.streakSoft : p.surfaceHigh,
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.local_fire_department_rounded,
              size: 36,
              color: hasStreak ? p.streak : p.textMuted,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.baseline,
                  textBaseline: TextBaseline.alphabetic,
                  children: [
                    Text('${stats.streak}', style: text.displaySmall),
                    const SizedBox(width: 6),
                    Text(stats.streak == 1 ? 'day streak' : 'day streak', style: text.titleSmall),
                  ],
                ),
                const SizedBox(height: 4),
                Text(status, style: text.bodySmall),
                if (stats.bestStreak > stats.streak) ...[
                  const SizedBox(height: 2),
                  Text('Best: ${stats.bestStreak} days', style: text.bodySmall),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _LevelCard extends StatelessWidget {
  final MyPrepStats stats;

  const _LevelCard({required this.stats});

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final text = Theme.of(context).textTheme;
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(color: p.accent, borderRadius: BorderRadius.circular(AppRadius.pill)),
                child: Text(
                  'Lv ${stats.level.level}',
                  style: text.labelMedium!.copyWith(color: p.onAccent, fontWeight: FontWeight.w800),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(child: Text(stats.level.title, style: text.titleMedium)),
              Text('${stats.xpToday} XP today', style: text.bodySmall),
            ],
          ),
          const SizedBox(height: 14),
          ClipRRect(
            borderRadius: BorderRadius.circular(AppRadius.pill),
            child: LinearProgressIndicator(value: stats.level.progress, minHeight: 8),
          ),
          const SizedBox(height: 6),
          Text(
            '${stats.level.xpIntoLevel} / ${stats.level.xpForNextLevel} XP to the next level',
            style: text.bodySmall,
          ),
        ],
      ),
    );
  }
}

class _DailyTargetCard extends StatelessWidget {
  final MyPrepStats stats;

  const _DailyTargetCard({required this.stats});

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final text = Theme.of(context).textTheme;
    final reached = stats.dailyTargetProgress >= 1;
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: Text('Daily goal', style: text.titleMedium)),
              if (reached) Icon(Icons.check_circle_rounded, color: p.success, size: 22),
            ],
          ),
          const SizedBox(height: 4),
          Text('${stats.todayAnswered} / $kFeedDailyTarget questions today', style: text.bodySmall),
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(AppRadius.pill),
            child: LinearProgressIndicator(
              value: stats.dailyTargetProgress,
              minHeight: 10,
              color: reached ? p.success : p.accentText,
            ),
          ),
        ],
      ),
    );
  }
}

class _ActivityTrend extends StatelessWidget {
  final MyPrepStats stats;

  const _ActivityTrend({required this.stats});

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final text = Theme.of(context).textTheme;
    final counts = stats.dailyAnsweredLast7;
    final maxCount = counts.fold<int>(1, (m, c) => c > m ? c : m);
    const names = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];
    final labels = List.generate(7, (i) {
      final date = DateTime.now().subtract(Duration(days: 6 - i));
      return names[date.weekday - 1];
    });

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Last 7 days', style: text.titleMedium),
          const SizedBox(height: 14),
          SizedBox(
            height: 76,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                for (var i = 0; i < counts.length; i++)
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          AnimatedContainer(
                            duration: const Duration(milliseconds: 250),
                            height: 48 * (counts[i] / maxCount).clamp(0.06, 1.0),
                            decoration: BoxDecoration(
                              color: counts[i] == 0
                                  ? p.surfaceHigh
                                  : (i == counts.length - 1 ? p.accentText : p.accentText.withValues(alpha: 0.45)),
                              borderRadius: BorderRadius.circular(6),
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(labels[i], style: text.bodySmall!.copyWith(fontSize: 10)),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _TopicBreakdown extends StatelessWidget {
  final MyPrepStats stats;

  const _TopicBreakdown({required this.stats});

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final text = Theme.of(context).textTheme;

    if (stats.topicStats.isEmpty) {
      return AppCard(
        child: Text(
          'Answer a few questions in the feed and your topic breakdown will show up here.',
          style: text.bodyMedium!.copyWith(color: p.textMuted),
        ),
      );
    }

    final entries = stats.topicStats.entries.toList()
      ..sort((a, b) => b.value.attempts.compareTo(a.value.attempts));

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final entry in entries)
          Builder(
            builder: (context) {
              final accuracy = entry.value.accuracy;
              final color = accuracy >= 70 ? p.success : (accuracy >= 55 ? p.streak : p.danger);
              return Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(AppRadius.chip),
                  border: Border.all(color: color.withValues(alpha: 0.35)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(entry.key, style: text.labelMedium),
                    Text(
                      '${accuracy.round()}% · ${entry.value.attempts} tries',
                      style: text.labelSmall!.copyWith(color: color, fontSize: 10),
                    ),
                  ],
                ),
              );
            },
          ),
      ],
    );
  }
}

class _LaneCard extends ConsumerWidget {
  final IconData icon;
  final String label;
  final int count;
  final FeedLane lane;

  const _LaneCard({
    required this.icon,
    required this.label,
    required this.count,
    required this.lane,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.palette;
    final text = Theme.of(context).textTheme;
    return AppCard(
      onTap: () {
        HapticFeedback.selectionClick();
        ref.read(feedControllerProvider.notifier).switchLane(lane, restorePosition: true);
        ref.read(tabIndexProvider.notifier).state = 0;
      },
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: p.accentText, size: 22),
          const SizedBox(height: 10),
          Text('$count', style: text.headlineMedium),
          Text(label, style: text.bodySmall),
        ],
      ),
    );
  }
}
