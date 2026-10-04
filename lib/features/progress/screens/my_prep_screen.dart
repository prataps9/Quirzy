import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../shared/providers/providers.dart';
import '../../../shared/theme/practice_theme.dart';
import '../../feed/models/feed_models.dart';
import '../../feed/providers/feed_providers.dart';
import '../../profile/screens/leaderboard_screen.dart';
import '../providers/progress_providers.dart';
import '../services/share_card_service.dart';
import '../widgets/share_card.dart';

/// My Prep: the feed's progress dashboard (PRD §F7) — streak, XP level,
/// daily target, a 7-day activity trend, and a per-topic accuracy
/// heatmap, all sourced from data the feed already tracks locally.
class MyPrepScreen extends ConsumerStatefulWidget {
  const MyPrepScreen({super.key});

  @override
  ConsumerState<MyPrepScreen> createState() => _MyPrepScreenState();
}

class _MyPrepScreenState extends ConsumerState<MyPrepScreen> {
  final _shareCardKey = GlobalKey();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final statsAsync = ref.watch(myPrepStatsProvider);

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        title: Text('My Prep', style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.bold)),
        backgroundColor: theme.scaffoldBackgroundColor,
        elevation: 0,
      ),
      body: statsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, st) => Center(
          child: Text('Could not load your progress.', style: GoogleFonts.plusJakartaSans()),
        ),
        data: (stats) => RefreshIndicator(
          onRefresh: () async => ref.invalidate(myPrepStatsProvider),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
            children: [
              _buildStreakAndLevelCard(context, isDark, stats),
              const SizedBox(height: 16),
              _buildDailyTargetCard(context, isDark, stats),
              const SizedBox(height: 16),
              _buildActivityTrend(context, isDark, stats),
              const SizedBox(height: 24),
              _buildSectionTitle(isDark, 'Topic accuracy'),
              const SizedBox(height: 10),
              _buildTopicHeatmap(context, isDark, stats),
              const SizedBox(height: 24),
              _buildSectionTitle(isDark, 'Keep going'),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: _buildLaneCard(
                      context,
                      ref,
                      isDark,
                      icon: Icons.history_rounded,
                      label: 'Revision Vault',
                      count: stats.revisionDueCount,
                      lane: const FeedLane(type: FeedLaneType.revision, id: 'revision', label: 'Revision Vault'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _buildLaneCard(
                      context,
                      ref,
                      isDark,
                      icon: Icons.bookmark_rounded,
                      label: 'Saved',
                      count: stats.bookmarkCount,
                      lane: const FeedLane(type: FeedLaneType.bookmarks, id: 'bookmarks', label: 'Saved'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              OutlinedButton.icon(
                onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const LeaderboardScreen())),
                icon: const Icon(Icons.leaderboard_rounded, color: PracticeTheme.primary),
                label: Text(
                  'View Leaderboard',
                  style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w700, color: PracticeTheme.primary),
                ),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  side: const BorderSide(color: PracticeTheme.primary),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
              ),
              const SizedBox(height: 24),
              _buildSectionTitle(isDark, 'Share your progress'),
              const SizedBox(height: 12),
              Center(
                child: RepaintBoundary(
                  key: _shareCardKey,
                  child: ShareCard(stats: stats),
                ),
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: () => ShareCardService.shareFromKey(_shareCardKey),
                icon: const Icon(Icons.share_rounded, color: Colors.white),
                label: Text(
                  'Share',
                  style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w700, color: Colors.white),
                ),
                style: FilledButton.styleFrom(
                  backgroundColor: PracticeTheme.primary,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSectionTitle(bool isDark, String text) {
    return Text(
      text,
      style: GoogleFonts.plusJakartaSans(
        fontSize: 15,
        fontWeight: FontWeight.w800,
        color: isDark ? Colors.white : Colors.black87,
      ),
    );
  }

  Widget _buildStreakAndLevelCard(BuildContext context, bool isDark, MyPrepStats stats) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: PracticeTheme.cardDecoration(isDark: isDark),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.local_fire_department_rounded, color: Color(0xFFF59E0B), size: 20),
                    const SizedBox(width: 6),
                    Text(
                      '${stats.streak} day streak',
                      style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w700, fontSize: 15, color: isDark ? Colors.white : Colors.black87),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  '${stats.xpToday} XP today',
                  style: GoogleFonts.plusJakartaSans(fontSize: 12, color: isDark ? Colors.white60 : Colors.black54),
                ),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: PracticeTheme.primary.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  'Lv ${stats.level.level} · ${stats.level.title}',
                  style: GoogleFonts.plusJakartaSans(fontSize: 12, fontWeight: FontWeight.w800, color: PracticeTheme.primary),
                ),
              ),
              const SizedBox(height: 6),
              SizedBox(
                width: 120,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(999),
                  child: LinearProgressIndicator(
                    value: stats.level.progress,
                    minHeight: 5,
                    backgroundColor: isDark ? Colors.white12 : Colors.black12,
                    valueColor: const AlwaysStoppedAnimation(PracticeTheme.primary),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildDailyTargetCard(BuildContext context, bool isDark, MyPrepStats stats) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: PracticeTheme.cardDecoration(isDark: isDark),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Daily target',
                  style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w700, fontSize: 14, color: isDark ? Colors.white : Colors.black87),
                ),
                const SizedBox(height: 6),
                Text(
                  '${stats.todayAnswered} / $kFeedDailyTarget questions today',
                  style: GoogleFonts.plusJakartaSans(fontSize: 12, color: isDark ? Colors.white60 : Colors.black54),
                ),
                const SizedBox(height: 10),
                ClipRRect(
                  borderRadius: BorderRadius.circular(999),
                  child: LinearProgressIndicator(
                    value: stats.dailyTargetProgress,
                    minHeight: 8,
                    backgroundColor: isDark ? Colors.white12 : Colors.black12,
                    valueColor: AlwaysStoppedAnimation(
                      stats.dailyTargetProgress >= 1 ? PracticeTheme.success : PracticeTheme.primary,
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

  Widget _buildActivityTrend(BuildContext context, bool isDark, MyPrepStats stats) {
    final counts = stats.dailyAnsweredLast7;
    final maxCount = counts.fold<int>(1, (m, c) => c > m ? c : m);
    final labels = List.generate(7, (i) {
      final date = DateTime.now().subtract(Duration(days: 6 - i));
      const names = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];
      return names[date.weekday - 1];
    });

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: PracticeTheme.cardDecoration(isDark: isDark),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Last 7 days',
            style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w700, fontSize: 14, color: isDark ? Colors.white : Colors.black87),
          ),
          const SizedBox(height: 14),
          SizedBox(
            height: 70,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: List.generate(counts.length, (i) {
                final heightFraction = counts[i] / maxCount;
                return Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        AnimatedContainer(
                          duration: const Duration(milliseconds: 300),
                          height: 44 * heightFraction.clamp(0.04, 1.0),
                          decoration: BoxDecoration(
                            color: i == counts.length - 1
                                ? PracticeTheme.primary
                                : PracticeTheme.primary.withOpacity(0.3),
                            borderRadius: BorderRadius.circular(4),
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          labels[i],
                          style: GoogleFonts.plusJakartaSans(fontSize: 10, color: isDark ? Colors.white38 : Colors.black38),
                        ),
                      ],
                    ),
                  ),
                );
              }),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTopicHeatmap(BuildContext context, bool isDark, MyPrepStats stats) {
    if (stats.topicStats.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(18),
        decoration: PracticeTheme.cardDecoration(isDark: isDark),
        child: Text(
          'Answer a few questions in the feed and your topic breakdown will show up here.',
          style: GoogleFonts.plusJakartaSans(fontSize: 13, color: isDark ? Colors.white60 : Colors.black54),
        ),
      );
    }

    final entries = stats.topicStats.entries.toList()
      ..sort((a, b) => b.value.attempts.compareTo(a.value.attempts));

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: entries.map((entry) {
        final accuracy = entry.value.accuracy;
        final color = accuracy >= 70
            ? PracticeTheme.success
            : accuracy >= 55
                ? PracticeTheme.warning
                : PracticeTheme.error;
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: color.withOpacity(0.12),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: color.withOpacity(0.3)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                entry.key,
                style: GoogleFonts.plusJakartaSans(fontSize: 12, fontWeight: FontWeight.w700, color: isDark ? Colors.white : Colors.black87),
              ),
              Text(
                '${accuracy.round()}% · ${entry.value.attempts} tries',
                style: GoogleFonts.plusJakartaSans(fontSize: 10, color: color),
              ),
            ],
          ),
        );
      }).toList(),
    );
  }

  Widget _buildLaneCard(
    BuildContext context,
    WidgetRef ref,
    bool isDark, {
    required IconData icon,
    required String label,
    required int count,
    required FeedLane lane,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () {
          HapticFeedback.selectionClick();
          ref.read(feedControllerProvider.notifier).switchLane(lane, restorePosition: true);
          ref.read(tabIndexProvider.notifier).state = 0; // Practice tab
        },
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: PracticeTheme.cardDecoration(isDark: isDark),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, color: PracticeTheme.primary, size: 22),
              const SizedBox(height: 10),
              Text(
                '$count',
                style: GoogleFonts.plusJakartaSans(fontSize: 20, fontWeight: FontWeight.w800, color: isDark ? Colors.white : Colors.black87),
              ),
              Text(
                label,
                style: GoogleFonts.plusJakartaSans(fontSize: 12, color: isDark ? Colors.white60 : Colors.black54),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
