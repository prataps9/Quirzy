import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../shared/providers/providers.dart';
import '../../../shared/theme/app_palette.dart';
import '../../../shared/theme/app_text.dart';
import '../../../shared/widgets/app_widgets.dart';
import '../../../shared/widgets/motion.dart';
import '../../../shared/widgets/tab_header.dart';
import '../../feed/models/feed_models.dart';
import '../../feed/providers/feed_providers.dart';
import '../../profile/screens/leaderboard_screen.dart';
import '../providers/progress_providers.dart';
import '../../mocktest/providers/mock_test_providers.dart';
import '../../mocktest/screens/mock_test_screen.dart';
import '../../feed/services/streak_service.dart';
import '../models/badge.dart';
import '../providers/badge_providers.dart';
import 'mistakes_screen.dart';
import '../services/share_card_service.dart';
import '../widgets/exam_date_card.dart';
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
    final statsAsync = ref.watch(myPrepStatsProvider);

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const TabHeader(title: 'My Prep', subtitle: 'Your streak, progress and exam countdown'),
            Expanded(child: _buildBody(statsAsync)),
          ],
        ),
      ),
    );
  }

  Widget _buildBody(AsyncValue<MyPrepStats> statsAsync) {
    final text = Theme.of(context).textTheme;
    return statsAsync.when(
        loading: () => const SkeletonList(count: 5, itemHeight: 110),
        error: (err, st) => Center(
          child: Padding(
            padding: const EdgeInsets.all(AppSpace.xl),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  "Couldn't load your progress. Check your connection and try again.",
                  textAlign: TextAlign.center,
                  style: text.bodyMedium,
                ),
                const SizedBox(height: AppSpace.lg),
                AppButton.secondary(
                  label: 'Retry',
                  icon: Icons.refresh_rounded,
                  expanded: false,
                  onPressed: () => ref.invalidate(myPrepStatsProvider),
                ),
              ],
            ),
          ),
        ),
        data: (stats) => RefreshIndicator(
          onRefresh: () async => ref.invalidate(myPrepStatsProvider),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
            children: staggered([
              _StreakCard(stats: stats),
              const SizedBox(height: 12),
              const ExamDateCard(),
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
              const SizedBox(height: 12),
              const _MistakesCard(),
              const SizedBox(height: 12),
              const _MockTestCard(),
              const SizedBox(height: 24),
              const _BadgesSection(),
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
                // Shown at a comfortable preview size; the boundary inside
                // still captures the full-size card for sharing.
                child: SizedBox(
                  height: 340,
                  child: FittedBox(
                    child: RepaintBoundary(
                      key: _shareCardKey,
                      child: ShareCard(stats: stats),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              AppButton(
                label: 'Share',
                icon: Icons.share_rounded,
                onPressed: () => ShareCardService.shareFromKey(_shareCardKey),
              ),
            ]),
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
                    CountUp(value: stats.streak, style: text.displaySmall),
                    const SizedBox(width: 6),
                    Text('day streak', style: text.titleSmall),
                  ],
                ),
                const SizedBox(height: 4),
                Text(status, style: text.bodySmall),
                Consumer(
                  builder: (context, ref, _) {
                    final ready = ref.watch(streakProvider).value?.freezeReady;
                    if (ready == null) return const SizedBox.shrink();
                    return Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Row(
                        children: [
                          Icon(Icons.ac_unit_rounded, size: 14, color: ready ? p.accentText : p.textMuted),
                          const SizedBox(width: 4),
                          Flexible(
                            child: Text(
                              ready ? 'Streak freeze ready: one missed day is forgiven' : 'Streak freeze used this week',
                              style: text.bodySmall!.copyWith(color: ready ? p.accentText : p.textMuted),
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
                if (stats.bestStreak > stats.streak) ...[
                  const SizedBox(height: 2),
                  Text(stats.bestStreak == 1 ? 'Best: 1 day' : 'Best: ${stats.bestStreak} days', style: text.bodySmall),
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
          GrowBar(value: stats.level.progress, minHeight: 8),
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
          GrowBar(value: stats.dailyTargetProgress, minHeight: 10, color: reached ? p.success : p.accentText),
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
                          Text(labels[i], style: text.micro.copyWith(fontWeight: FontWeight.w500)),
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
                      style: text.micro.copyWith(color: color),
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

/// The Mistakes notebook in one line: how many are left to fix and the slip
/// the user makes most. Hidden until there is a first mistake.
class _MistakesCard extends ConsumerWidget {
  const _MistakesCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final insight = ref.watch(mistakeInsightProvider).value;
    if (insight == null || insight.total == 0) return const SizedBox.shrink();
    final p = context.palette;
    final text = Theme.of(context).textTheme;

    final title = insight.open == 0
        ? 'All ${insight.total} mistakes fixed'
        : '${insight.open} ${insight.open == 1 ? 'mistake' : 'mistakes'} to fix';
    final detail = insight.topReason != null
        ? 'Most common slip: ${insight.topReason} (${insight.topReasonPercent}%)'
        : insight.topTopic != null
        ? 'Most of them in ${insight.topTopic}'
        : 'Open your notebook to see what to work on';

    return AppCard(
      onTap: () {
        HapticFeedback.selectionClick();
        Navigator.push(context, MaterialPageRoute(builder: (_) => const MistakesScreen()));
      },
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: insight.open == 0 ? p.successSoft : p.dangerSoft,
            ),
            child: Icon(Icons.rule_rounded, color: insight.open == 0 ? p.success : p.danger),
          ),
          const SizedBox(width: AppSpace.md),
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: text.titleSmall),
                Text(detail, style: text.bodySmall!.copyWith(color: p.textMuted)),
              ],
            ),
          ),
          Icon(Icons.chevron_right_rounded, color: p.textMuted),
        ],
      ),
    );
  }
}

/// Mock tests: the last score and a short history, or an invitation to take
/// the first one, and a way back into a test left part-way.
class _MockTestCard extends ConsumerWidget {
  const _MockTestCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.palette;
    final text = Theme.of(context).textTheme;
    final history = ref.watch(mockHistoryProvider).value ?? const [];
    final inProgress = ref.watch(mockInProgressProvider).value;
    final last = history.isEmpty ? null : history.first;
    final recent = history.take(6).toList().reversed.toList();

    void open() {
      HapticFeedback.selectionClick();
      Navigator.push(context, MaterialPageRoute(builder: (_) => const MockTestScreen()));
    }

    return AppCard(
      onTap: open,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(Icons.timer_outlined, color: p.accentText),
              const SizedBox(width: 10),
              Expanded(child: Text('Mock tests', style: text.titleMedium)),
              if (last != null) Text('Last: ${last.correct}/${last.total}', style: text.labelLarge),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            inProgress != null
                ? 'You have a test in progress: ${inProgress.answeredCount} of ${inProgress.total} answered.'
                : last == null
                ? 'Test yourself under exam conditions: one minute a question, answers at the end.'
                : 'Your last ${recent.length} ${recent.length == 1 ? 'score' : 'scores'}',
            style: text.bodySmall!.copyWith(color: p.textMuted),
          ),
          if (recent.length > 1 && inProgress == null) ...[
            const SizedBox(height: 10),
            SizedBox(
              height: 44,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  for (final r in recent)
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 3),
                        child: Semantics(
                          label: '${r.percent}%',
                          child: FractionallySizedBox(
                            heightFactor: (r.percent / 100).clamp(0.08, 1.0),
                            child: DecoratedBox(
                              decoration: BoxDecoration(
                                color: r == last ? p.accent : p.surfaceHigh,
                                borderRadius: BorderRadius.circular(AppRadius.chip / 2),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 12),
          AppButton(
            label: inProgress != null ? 'Resume test' : 'Take a mock test',
            icon: Icons.timer_outlined,
            onPressed: open,
          ),
        ],
      ),
    );
  }
}

/// Badges: earned ones in colour, the rest greyed with how far along you
/// are. Tap one for what it takes.
class _BadgesSection extends ConsumerWidget {
  const _BadgesSection();

  void _details(BuildContext context, BadgeStatus badge) {
    final p = context.palette;
    final text = Theme.of(context).textTheme;
    final at = badge.earnedAt;
    showModalBottomSheet<void>(
      context: context,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _BadgeIcon(badge: badge, size: 72),
              const SizedBox(height: 14),
              Text(badge.def.title, style: text.titleLarge),
              const SizedBox(height: 6),
              Text(badge.def.description, textAlign: TextAlign.center, style: text.bodyMedium),
              const SizedBox(height: 14),
              if (at != null)
                Text('Earned ${at.day}/${at.month}/${at.year}', style: text.bodySmall!.copyWith(color: p.accentText))
              else ...[
                ClipRRect(
                  borderRadius: BorderRadius.circular(AppRadius.pill),
                  child: LinearProgressIndicator(value: badge.progress / badge.def.target, minHeight: 6),
                ),
                const SizedBox(height: 6),
                Text('${badge.progress} / ${badge.def.target}', style: text.bodySmall),
              ],
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.palette;
    final text = Theme.of(context).textTheme;
    final badges = ref.watch(badgeStatusesProvider).value;
    if (badges == null) return const SizedBox.shrink();
    final earned = badges.where((b) => b.earned).length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(child: Text('Badges', style: text.titleMedium)),
            Text('$earned of ${badges.length}', style: text.labelLarge!.copyWith(color: p.textMuted)),
          ],
        ),
        const SizedBox(height: 12),
        LayoutBuilder(
          builder: (context, constraints) {
            const perRow = 4;
            const gap = 10.0;
            final width = (constraints.maxWidth - gap * (perRow - 1)) / perRow;
            return Wrap(
              spacing: gap,
              runSpacing: 14,
              children: [
                for (final (i, badge) in badges.indexed)
                  Stagger(
                    index: i,
                    child: SizedBox(
                    width: width,
                    child: Semantics(
                      button: true,
                      label:
                          '${badge.def.title}, ${badge.earned ? 'earned' : '${badge.progress} of ${badge.def.target}'}',
                      excludeSemantics: true,
                      child: InkWell(
                        borderRadius: BorderRadius.circular(AppRadius.control),
                        onTap: () => _details(context, badge),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 4),
                          child: Column(
                            children: [
                              _BadgeIcon(badge: badge, size: 52),
                              const SizedBox(height: 6),
                              Text(
                                badge.def.title,
                                textAlign: TextAlign.center,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: text.labelSmall!.copyWith(color: badge.earned ? p.text : p.textMuted),
                              ),
                              if (!badge.earned && badge.def.target > 1)
                                Text(
                                  '${badge.progress}/${badge.def.target}',
                                  style: text.micro.copyWith(color: p.textMuted),
                                ),
                              if (badge.earnedAt != null &&
                                  DateTime.now().difference(badge.earnedAt!) < const Duration(days: 3))
                                Text('New', style: text.micro.copyWith(color: p.accentText)),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                  ),
              ],
            );
          },
        ),
      ],
    );
  }
}

class _BadgeIcon extends StatelessWidget {
  final BadgeStatus badge;
  final double size;

  const _BadgeIcon({required this.badge, required this.size});

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: badge.earned ? p.accent : p.surfaceHigh,
        border: Border.all(color: badge.earned ? p.accent : p.border),
      ),
      child: Icon(badge.def.icon, size: size * 0.48, color: badge.earned ? p.onAccent : p.textMuted),
    );
  }
}
