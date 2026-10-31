import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../shared/providers/providers.dart';
import '../../../shared/services/share_service.dart';
import '../../../shared/theme/app_motion.dart';
import '../../../shared/theme/app_palette.dart';
import '../../../shared/widgets/app_widgets.dart';
import '../../../shared/widgets/motion.dart';
import '../../feed/models/feed_models.dart';
import '../../feed/providers/feed_providers.dart';
import '../../feed/widgets/feed_share_cards.dart';
import '../../progress/services/share_card_service.dart';
import '../models/weekly_report.dart';
import '../providers/weekly_report_providers.dart';
import '../services/weekly_report_service.dart';
import '../widgets/week_bars.dart';

/// Your week, Monday to Sunday: how much, how well, which topics, when, and
/// how it compares with the week before. Earlier weeks are a tap away.
class WeeklyReportScreen extends ConsumerStatefulWidget {
  const WeeklyReportScreen({super.key});

  @override
  ConsumerState<WeeklyReportScreen> createState() => _WeeklyReportScreenState();
}

class _WeeklyReportScreenState extends ConsumerState<WeeklyReportScreen> {
  int _weeksAgo = 0;

  static const _months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

  String _weekLabel(DateTime start) {
    if (_weeksAgo == 0) return 'This week';
    if (_weeksAgo == 1) return 'Last week';
    final end = DateTime(start.year, start.month, start.day + 6);
    return '${start.day} ${_months[start.month - 1]} – ${end.day} ${_months[end.month - 1]}';
  }

  void _go(int weeksAgo) {
    HapticFeedback.selectionClick();
    setState(() => _weeksAgo = weeksAgo);
  }

  Future<void> _share(WeeklyReport report) async {
    final shared = await ShareCardService.shareWidget(
      context,
      WeeklyShareCard(report: report),
      text: 'My week on Quirzy #Quirzy',
      fileName: 'quirzy_week.png',
    );
    if (shared) return;
    await ShareService.shareWeek(answered: report.answered, accuracy: report.accuracy, daysActive: report.daysActive);
  }

  void _practise(String topic) {
    Navigator.of(context).popUntil((route) => route.isFirst);
    unawaited(
      ref
          .read(feedControllerProvider.notifier)
          .switchLane(FeedLane(type: FeedLaneType.topic, id: 'topic:$topic', label: topic)),
    );
    ref.read(tabIndexProvider.notifier).state = 0;
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final text = Theme.of(context).textTheme;
    final report = ref.watch(weeklyReportProvider(_weeksAgo));
    final value = report.value;
    final start = WeeklyReportService.weekStart(DateTime.now(), _weeksAgo);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Your week'),
        actions: [
          if (value != null && !value.isEmpty)
            IconButton(tooltip: 'Share', icon: const Icon(Icons.ios_share_rounded), onPressed: () => _share(value)),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpace.sm),
            child: Row(
              children: [
                IconButton(
                  tooltip: 'Earlier week',
                  onPressed: _weeksAgo < WeeklyReportService.maxWeeksBack ? () => _go(_weeksAgo + 1) : null,
                  icon: const Icon(Icons.chevron_left_rounded),
                ),
                Expanded(
                  child: AnimatedSwitcher(
                    duration: AppMotion.of(context, AppMotion.fast),
                    child: Text(
                      _weekLabel(start),
                      key: ValueKey(_weeksAgo),
                      textAlign: TextAlign.center,
                      style: text.titleMedium,
                    ),
                  ),
                ),
                IconButton(
                  tooltip: 'Later week',
                  onPressed: _weeksAgo > 0 ? () => _go(_weeksAgo - 1) : null,
                  icon: Icon(Icons.chevron_right_rounded, color: _weeksAgo > 0 ? null : p.border),
                ),
              ],
            ),
          ),
          Expanded(
            child: AnimatedSwitcher(
              duration: AppMotion.of(context, AppMotion.base),
              switchInCurve: AppMotion.enter,
              switchOutCurve: AppMotion.exit,
              child: KeyedSubtree(
                key: ValueKey('week:$_weeksAgo:${value == null}'),
                child: value == null
                    ? const SkeletonList(count: 4, itemHeight: 110)
                    : value.isEmpty
                    ? _Empty(thisWeek: _weeksAgo == 0)
                    : _Report(report: value, thisWeek: _weeksAgo == 0, onPractise: _practise),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Report extends StatelessWidget {
  final WeeklyReport report;
  final bool thisWeek;
  final void Function(String topic) onPractise;

  const _Report({required this.report, required this.thisWeek, required this.onPractise});

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final text = Theme.of(context).textTheme;
    final weakest = report.weakestTopic;
    final best = report.bestTopic;
    final bestTime = report.bestTime;
    final topics = report.topics.take(5).toList();
    final extras = [
      if (report.xp > 0) '+${report.xp} XP',
      if (report.mockTests > 0) '${report.mockTests} mock ${report.mockTests == 1 ? 'test' : 'tests'}',
      if (report.badges > 0) '${report.badges} ${report.badges == 1 ? 'badge' : 'badges'} earned',
    ];

    final sections = <Widget>[
      Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: _Stat(
              value: report.answered,
              label: 'questions',
              change: report.answeredChange,
              changeLabel: (c) => '${c.abs()}% on last week',
            ),
          ),
          const SizedBox(width: AppSpace.sm),
          Expanded(
            child: report.accuracy == null
                ? const _Stat(value: null, label: 'right')
                : _Stat(
                    value: report.accuracy,
                    format: (v) => '$v%',
                    label: 'right',
                    change: report.accuracyChange,
                    changeLabel: (c) => '${c.abs()} ${c.abs() == 1 ? 'point' : 'points'}',
                  ),
          ),
          const SizedBox(width: AppSpace.sm),
          Expanded(
            child: _Stat(value: report.daysActive, format: (v) => '$v/7', label: 'days practised'),
          ),
        ],
      ),
      if (extras.isNotEmpty) Text(extras.join(' · '), style: text.bodySmall),
      AppCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Questions each day', style: text.titleSmall),
            const SizedBox(height: AppSpace.md),
            WeekBars(values: report.answeredByDay, lastDay: thisWeek ? DateTime.now().weekday - 1 : null),
          ],
        ),
      ),
      if (topics.isNotEmpty)
        AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Topics', style: text.titleSmall),
              const SizedBox(height: AppSpace.sm),
              for (final t in topics)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: AppSpace.sm),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(t.topic, maxLines: 1, overflow: TextOverflow.ellipsis, style: text.bodyMedium),
                          ),
                          if (t.topic == best?.topic) _Badge('Best', p.success, Icons.star_rounded),
                          if (t.topic == weakest?.topic) _Badge('Needs work', p.danger, Icons.flag_rounded),
                          const SizedBox(width: AppSpace.sm),
                          Text('${t.answered} · ${t.accuracy}%', style: text.labelMedium!.copyWith(color: p.textMuted)),
                        ],
                      ),
                      const SizedBox(height: 6),
                      GrowBar(
                        value: t.answered / topics.first.answered,
                        color: p.accent,
                        backgroundColor: p.surfaceHigh,
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      if (bestTime != null)
        AppCard(
          child: Row(
            children: [
              Icon(_partIcon(bestTime), color: p.accentText, size: 28),
              const SizedBox(width: AppSpace.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('You practised most in the ${bestTime.label.toLowerCase()}', style: text.titleSmall),
                    const SizedBox(height: 2),
                    Text(bestTime.hours, style: text.bodySmall),
                  ],
                ),
              ),
            ],
          ),
        ),
      if (weakest != null)
        AppButton(
          label: 'Practise ${weakest.topic}',
          icon: Icons.play_arrow_rounded,
          onPressed: () => onPractise(weakest.topic),
        ),
    ];

    return ListView(
      padding: const EdgeInsets.fromLTRB(AppSpace.lg, AppSpace.sm, AppSpace.lg, AppSpace.xl),
      children: [
        for (final (i, s) in sections.indexed)
          Stagger(
            index: i,
            child: Padding(
              padding: const EdgeInsets.only(bottom: AppSpace.md),
              child: s,
            ),
          ),
      ],
    );
  }

  static IconData _partIcon(DayPart part) => switch (part) {
    DayPart.morning => Icons.wb_sunny_outlined,
    DayPart.afternoon => Icons.light_mode_rounded,
    DayPart.evening => Icons.wb_twilight_rounded,
    DayPart.night => Icons.nightlight_round,
  };
}

/// A headline number with its change on last week (arrow, word and colour,
/// never colour alone).
class _Stat extends StatelessWidget {
  final int? value;
  final String label;
  final String Function(int)? format;
  final int? change;
  final String Function(int change)? changeLabel;

  const _Stat({required this.value, required this.label, this.format, this.change, this.changeLabel});

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final text = Theme.of(context).textTheme;
    final c = change;
    return AppCard(
      padding: const EdgeInsets.all(AppSpace.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (value == null)
            Text('–', style: text.headlineSmall)
          else
            CountUp(value: value!, format: format, style: text.headlineSmall),
          Text(label, style: text.bodySmall),
          if (c != null && changeLabel != null) ...[
            const SizedBox(height: AppSpace.xs),
            Semantics(
              label: c == 0 ? 'Same as last week' : '${c > 0 ? 'Up' : 'Down'} ${changeLabel!(c)}',
              excludeSemantics: true,
              child: Row(
                children: [
                  Icon(
                    c > 0
                        ? Icons.arrow_upward_rounded
                        : c < 0
                        ? Icons.arrow_downward_rounded
                        : Icons.remove_rounded,
                    size: 14,
                    color: c > 0
                        ? p.success
                        : c < 0
                        ? p.danger
                        : p.textMuted,
                  ),
                  const SizedBox(width: 2),
                  Expanded(
                    child: Text(
                      c == 0 ? 'Same as last week' : changeLabel!(c),
                      maxLines: 2,
                      style: text.labelSmall!.copyWith(color: p.textMuted),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  final String label;
  final Color color;
  final IconData icon;

  const _Badge(this.label, this.color, this.icon);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: AppSpace.sm),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 2),
          Text(label, style: Theme.of(context).textTheme.labelSmall),
        ],
      ),
    );
  }
}

class _Empty extends ConsumerWidget {
  final bool thisWeek;

  const _Empty({required this.thisWeek});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.palette;
    final text = Theme.of(context).textTheme;
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(28),
        child: FadeRise(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.insights_rounded, size: 52, color: p.accentText),
              const SizedBox(height: 14),
              Text(
                thisWeek ? 'Nothing yet this week' : 'No practice that week',
                textAlign: TextAlign.center,
                style: text.titleLarge,
              ),
              const SizedBox(height: 8),
              Text(
                thisWeek
                    ? 'Answer a few questions and your week will show up here.'
                    : 'Try another week with the arrows above.',
                textAlign: TextAlign.center,
                style: text.bodyMedium!.copyWith(color: p.textMuted),
              ),
              if (thisWeek) ...[
                const SizedBox(height: 20),
                AppButton(
                  label: 'Start practising',
                  icon: Icons.play_arrow_rounded,
                  expanded: false,
                  onPressed: () {
                    Navigator.of(context).popUntil((route) => route.isFirst);
                    ref.read(tabIndexProvider.notifier).state = 0;
                  },
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
