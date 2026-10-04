import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../shared/theme/practice_theme.dart';
import '../models/feed_models.dart';
import '../providers/feed_providers.dart';
import '../services/practice_content_service.dart';

IconData _iconForLane(FeedLaneType type) {
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

/// Swipe-right drawer: pick a lane, unhide topics, toggle Focus Mode.
class LaneSwitcherSheet extends ConsumerWidget {
  const LaneSwitcherSheet({super.key});

  static Future<void> show(BuildContext context) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const LaneSwitcherSheet(),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final lanesAsync = ref.watch(feedLanesProvider);
    final hidden = ref.watch(hiddenTopicsProvider).value ?? const <String>[];
    final feedState = ref.watch(feedControllerProvider);
    final controller = ref.read(feedControllerProvider.notifier);
    final mutedText = isDark ? Colors.white38 : Colors.black38;

    return SafeArea(
      child: Container(
        constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.75),
        decoration: BoxDecoration(
          color: isDark ? PracticeTheme.surfaceDark : PracticeTheme.surfaceLight,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        ),
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: isDark ? Colors.white24 : Colors.black12,
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'Switch lane',
              style: GoogleFonts.plusJakartaSans(
                fontSize: 18,
                fontWeight: FontWeight.w800,
                color: isDark ? Colors.white : Colors.black87,
              ),
            ),
            const SizedBox(height: 12),
            Flexible(
              child: lanesAsync.when(
                loading: () => const Padding(
                  padding: EdgeInsets.symmetric(vertical: 24),
                  child: Center(child: CircularProgressIndicator()),
                ),
                error: (err, st) => Padding(
                  padding: const EdgeInsets.symmetric(vertical: 24),
                  child: Text('Could not load lanes.', style: GoogleFonts.plusJakartaSans()),
                ),
                data: (lanes) => ListView(
                  shrinkWrap: true,
                  children: [
                    for (final lane in lanes)
                      _LaneTile(
                        lane: lane,
                        selected: lane.id == feedState.lane.id,
                        isDark: isDark,
                        onTap: () {
                          HapticFeedback.selectionClick();
                          controller.switchLane(lane, restorePosition: true);
                          Navigator.of(context).pop();
                        },
                        onToggleDownload: () async {
                          HapticFeedback.selectionClick();
                          await ref
                              .read(practiceContentServiceProvider)
                              .setDownloaded(lane.label, !lane.downloaded);
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
                          title: Text(
                            topic,
                            style: GoogleFonts.plusJakartaSans(fontSize: 14, fontWeight: FontWeight.w600),
                          ),
                          trailing: TextButton(
                            onPressed: () => controller.unmuteTopic(topic),
                            child: const Text('Unhide'),
                          ),
                        ),
                    ],
                  ],
                ),
              ),
            ),
            const Divider(height: 20),
            SwitchListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 12),
              value: feedState.focusMode,
              onChanged: controller.setFocusMode,
              title: Text(
                'Focus mode',
                style: GoogleFonts.plusJakartaSans(fontSize: 14, fontWeight: FontWeight.w700),
              ),
              subtitle: Text(
                'Answer or skip before scrolling on',
                style: GoogleFonts.plusJakartaSans(fontSize: 12, color: mutedText),
              ),
            ),
          ],
        ),
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
        style: GoogleFonts.plusJakartaSans(
          fontSize: 11,
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
  final bool isDark;
  final VoidCallback onTap;
  final VoidCallback onToggleDownload;

  const _LaneTile({
    required this.lane,
    required this.selected,
    required this.isDark,
    required this.onTap,
    required this.onToggleDownload,
  });

  @override
  Widget build(BuildContext context) {
    final muted = isDark ? Colors.white38 : Colors.black38;
    final count = Text(
      '${lane.count}',
      style: GoogleFonts.plusJakartaSans(fontSize: 12, fontWeight: FontWeight.w600, color: muted),
    );

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
              color: lane.downloaded ? PracticeTheme.primary : muted,
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
          tileColor: selected ? PracticeTheme.primary.withOpacity(0.08) : null,
          leading: Icon(
            _iconForLane(lane.type),
            color: selected ? PracticeTheme.primary : (isDark ? Colors.white54 : Colors.black45),
          ),
          title: Text(
            lane.label,
            style: GoogleFonts.plusJakartaSans(
              fontSize: 14,
              fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
              color: selected ? PracticeTheme.primary : (isDark ? Colors.white : Colors.black87),
            ),
          ),
          subtitle: lane.isInfinite
              ? Text(
                  'Adapts to what you like and skip',
                  style: GoogleFonts.plusJakartaSans(fontSize: 12, color: muted),
                )
              : null,
          trailing: trailing,
        ),
      ),
    );
  }
}
