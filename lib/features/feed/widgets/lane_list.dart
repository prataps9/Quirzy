import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../shared/theme/app_palette.dart';
import '../models/feed_models.dart';
import '../providers/feed_providers.dart';
import '../services/practice_content_service.dart';

IconData iconForLane(FeedLaneType type) {
  switch (type) {
    case FeedLaneType.forYou:
      return Icons.explore_rounded;
    case FeedLaneType.topic:
      return Icons.layers_rounded;
    case FeedLaneType.weakTopics:
      return Icons.trending_up_rounded;
    case FeedLaneType.revision:
      return Icons.history_rounded;
    case FeedLaneType.bookmarks:
      return Icons.bookmark_rounded;
  }
}

/// The lanes as a plain list, with the Hidden topics section: the fallback
/// view of the topic dial. [onPick] runs after the controller has switched.
class LaneList extends ConsumerWidget {
  final VoidCallback onPick;

  const LaneList({super.key, required this.onPick});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.palette;
    final text = Theme.of(context).textTheme;
    final lanesAsync = ref.watch(feedLanesProvider);
    final hidden = ref.watch(hiddenTopicsProvider).value ?? const <String>[];
    final currentId = ref.watch(feedControllerProvider.select((s) => s.lane.id));
    final controller = ref.read(feedControllerProvider.notifier);
    final mutedText = p.textMuted;

    return lanesAsync.when(
      loading: () => const Padding(
        padding: EdgeInsets.symmetric(vertical: 24),
        child: Center(child: CircularProgressIndicator()),
      ),
      error: (err, st) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              "Couldn't load your topics. Check your connection and try again.",
              style: text.bodyMedium!.copyWith(color: mutedText),
            ),
            const SizedBox(height: AppSpace.sm),
            TextButton.icon(
              onPressed: () => ref.invalidate(feedLanesProvider),
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('Retry'),
            ),
          ],
        ),
      ),
      data: (lanes) => ListView(
        shrinkWrap: true,
        children: [
          for (final lane in lanes)
            _LaneTile(
              lane: lane,
              selected: lane.id == currentId,
              onTap: () {
                HapticFeedback.selectionClick();
                controller.switchLane(lane, restorePosition: true);
                onPick();
              },
              onToggleDownload: () async {
                HapticFeedback.selectionClick();
                await ref.read(practiceContentServiceProvider).setDownloaded(lane.label, !lane.downloaded);
                ref.invalidate(feedLanesProvider);
              },
            ),
          if (hidden.isNotEmpty) ...[
            const SizedBox(height: 12),
            _SectionLabel('Hidden topics', color: mutedText),
            for (final topic in hidden)
              ListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 12),
                leading: Icon(Icons.visibility_off_rounded, color: mutedText),
                title: Text(topic, style: text.titleSmall),
                trailing: TextButton(
                  onPressed: () => controller.unmuteTopic(topic),
                  child: const Text('Unhide'),
                ),
              ),
          ],
        ],
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  final String text;
  final Color color;

  const _SectionLabel(this.text, {required this.color});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 4),
      child: Text(
        text.toUpperCase(),
        style: Theme.of(context).textTheme.labelSmall!.copyWith(
          fontWeight: FontWeight.w800,
          letterSpacing: 0.6,
          color: color,
        ),
      ),
    );
  }
}

class _LaneTile extends StatelessWidget {
  final FeedLane lane;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback onToggleDownload;

  const _LaneTile({
    required this.lane,
    required this.selected,
    required this.onTap,
    required this.onToggleDownload,
  });

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final text = Theme.of(context).textTheme;
    final muted = p.textMuted;
    final count = Text('${lane.count}', style: text.labelMedium!.copyWith(color: muted));

    Widget? trailing;
    if (lane.type == FeedLaneType.topic) {
      trailing = Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          count,
          const SizedBox(width: 4),
          IconButton(
            visualDensity: VisualDensity.compact,
            tooltip: lane.downloaded ? 'Downloaded — won\'t be removed' : 'Keep offline',
            onPressed: onToggleDownload,
            icon: Icon(
              lane.downloaded ? Icons.check_circle_rounded : Icons.download_rounded,
              size: 20,
              color: lane.downloaded ? p.accentText : muted,
            ),
          ),
        ],
      );
    } else if (!lane.isInfinite) {
      trailing = count;
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Material(
        color: Colors.transparent,
        child: ListTile(
          onTap: onTap,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          tileColor: selected ? p.accentSoft : null,
          leading: Icon(
            iconForLane(lane.type),
            color: selected ? p.accentText : muted,
          ),
          title: Text(
            lane.label,
            style: text.titleSmall!.copyWith(
              fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
              color: selected ? p.accentText : p.text,
            ),
          ),
          subtitle: lane.isInfinite ? Text('Adapts to what you like and skip', style: text.bodySmall) : null,
          trailing: trailing,
        ),
      ),
    );
  }
}
