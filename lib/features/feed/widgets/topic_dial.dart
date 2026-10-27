import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../shared/theme/app_palette.dart';
import '../../../shared/theme/app_text.dart';
import '../../../shared/widgets/app_widgets.dart';
import '../models/feed_models.dart';
import '../models/topic_mastery.dart';
import '../models/topic_style.dart';
import '../providers/feed_providers.dart';
import '../services/practice_content_service.dart';
import 'lane_list.dart';
import 'topic_dial_layout.dart';

const double _nodeSize = 56;

String masteryLabel(MasteryLevel level) => switch (level) {
  MasteryLevel.fresh => 'New',
  MasteryLevel.learning => 'Learning',
  MasteryLevel.weak => 'Needs work',
  MasteryLevel.solid => 'Solid',
  MasteryLevel.mastered => 'Mastered',
};

/// The topic chooser: lanes sit on a curved arc along the left edge. Drag up
/// or down to turn it, and the lane in the middle shows its progress. Tap a
/// lane (or Open) to jump to it. A list view is one tap away.
class TopicDial extends ConsumerStatefulWidget {
  const TopicDial({super.key});

  static Future<void> show(BuildContext context) {
    return showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Close topics',
      barrierColor: Colors.black54,
      transitionDuration: const Duration(milliseconds: 260),
      pageBuilder: (context, animation, secondary) => const TopicDial(),
      transitionBuilder: (context, animation, secondary, child) => SlideTransition(
        position: Tween(
          begin: const Offset(-1, 0),
          end: Offset.zero,
        ).animate(CurvedAnimation(parent: animation, curve: Curves.easeOutCubic, reverseCurve: Curves.easeInCubic)),
        child: child,
      ),
    );
  }

  @override
  ConsumerState<TopicDial> createState() => _TopicDialState();
}

class _TopicDialState extends ConsumerState<TopicDial> with SingleTickerProviderStateMixin {
  late final AnimationController _settle;

  double _focus = 0;
  double _from = 0;
  double _to = 0;
  int _lastTick = 0;
  bool _positioned = false;
  bool _listMode = false;
  int _laneCount = 0;

  @override
  void initState() {
    super.initState();
    _settle = AnimationController(vsync: this, duration: const Duration(milliseconds: 260))..addListener(_onSettleTick);
  }

  @override
  void dispose() {
    _settle.dispose();
    super.dispose();
  }

  void _onSettleTick() {
    final t = Curves.easeOutCubic.transform(_settle.value);
    _setFocus(_from + (_to - _from) * t);
  }

  void _setFocus(double value) {
    final rounded = value.round();
    if (rounded != _lastTick) {
      _lastTick = rounded;
      HapticFeedback.selectionClick();
    }
    setState(() => _focus = value);
  }

  void _animateTo(int index) {
    _from = _focus;
    _to = index.toDouble();
    _settle.forward(from: 0);
  }

  void _close() => Navigator.of(context).pop();

  void _open(FeedLane lane) {
    HapticFeedback.selectionClick();
    ref.read(feedControllerProvider.notifier).switchLane(lane, restorePosition: true);
    _close();
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final text = Theme.of(context).textTheme;
    final lanesAsync = ref.watch(feedLanesProvider);
    final mastery = ref.watch(topicMasteryProvider).value ?? const <String, TopicMastery>{};
    final focusMode = ref.watch(feedControllerProvider.select((s) => s.focusMode));
    final currentId = ref.watch(feedControllerProvider.select((s) => s.lane.id));
    final width = math.min(MediaQuery.sizeOf(context).width * 0.88, 380.0);

    lanesAsync.whenData((lanes) {
      _laneCount = lanes.length;
      if (!_positioned) {
        _positioned = true;
        final at = lanes.indexWhere((l) => l.id == currentId);
        _focus = _from = _to = math.max(0, at).toDouble();
        _lastTick = _focus.round();
      }
    });

    return Align(
      alignment: Alignment.centerLeft,
      child: SizedBox(
        width: width,
        child: Material(
          color: p.surface,
          shape: RoundedRectangleBorder(
            borderRadius: const BorderRadius.horizontal(right: Radius.circular(AppRadius.sheet)),
            side: BorderSide(color: p.border),
          ),
          clipBehavior: Clip.antiAlias,
          child: SafeArea(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 12, 8, 0),
                  child: Row(
                    children: [
                      Expanded(child: Text('Topics', style: text.titleLarge)),
                      IconButton(
                        tooltip: _listMode ? 'Show as dial' : 'Show as list',
                        onPressed: () => setState(() => _listMode = !_listMode),
                        icon: Icon(_listMode ? Icons.explore_rounded : Icons.view_list_rounded),
                      ),
                      IconButton(tooltip: 'Close', onPressed: _close, icon: const Icon(Icons.close_rounded)),
                    ],
                  ),
                ),
                Expanded(
                  child: _listMode
                      ? Padding(
                          padding: const EdgeInsets.fromLTRB(12, 4, 12, 0),
                          child: LaneList(onPick: _close),
                        )
                      : lanesAsync.when(
                          loading: () => const Center(child: CircularProgressIndicator()),
                          error: (e, st) => Center(
                            child: TextButton.icon(
                              onPressed: () => ref.invalidate(feedLanesProvider),
                              icon: const Icon(Icons.refresh_rounded),
                              label: const Text("Couldn't load topics. Retry"),
                            ),
                          ),
                          data: (lanes) => _buildDial(context, lanes, mastery, currentId),
                        ),
                ),
                const Divider(height: 1),
                SwitchListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 20),
                  value: focusMode,
                  onChanged: ref.read(feedControllerProvider.notifier).setFocusMode,
                  title: Text('Focus mode', style: text.titleSmall),
                  subtitle: Text('Answer or skip before scrolling on', style: text.bodySmall),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildDial(BuildContext context, List<FeedLane> lanes, Map<String, TopicMastery> mastery, String currentId) {
    final p = context.palette;
    final focusIndex = _focus.round().clamp(0, lanes.length - 1);
    final focusLane = lanes[focusIndex];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final layout = DialLayout(size: constraints.biggest);
              return GestureDetector(
                behavior: HitTestBehavior.opaque,
                onVerticalDragStart: (_) => _settle.stop(),
                onVerticalDragUpdate: (d) => _setFocus(layout.focusAfterDrag(_focus, d.delta.dy, _laneCount)),
                onVerticalDragEnd: (d) => _animateTo(layout.settleIndex(_focus, d.primaryVelocity ?? 0, _laneCount)),
                child: Stack(
                  clipBehavior: Clip.hardEdge,
                  children: [
                    Positioned.fill(
                      child: CustomPaint(
                        painter: _TrackPainter(layout: layout, color: p.border),
                      ),
                    ),
                    for (final node in layout.nodes(lanes.length, _focus))
                      _positionedNode(
                        context,
                        layout,
                        node,
                        lanes[node.index],
                        mastery,
                        currentId,
                        node.index == focusIndex,
                      ),
                  ],
                ),
              );
            },
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
          child: _FocusDetail(
            lane: focusLane,
            mastery: focusLane.type == FeedLaneType.topic ? mastery[focusLane.label] : null,
            onOpen: () => _open(focusLane),
          ),
        ),
      ],
    );
  }

  Widget _positionedNode(
    BuildContext context,
    DialLayout layout,
    DialNode node,
    FeedLane lane,
    Map<String, TopicMastery> mastery,
    String currentId,
    bool focused,
  ) {
    final width = layout.size.width;
    final left = node.center.dx - _nodeSize / 2;
    final top = node.center.dy - _nodeSize / 2;
    final topicMastery = lane.type == FeedLaneType.topic ? mastery[lane.label] : null;
    return Positioned(
      left: left,
      top: top,
      width: math.max(0, width - left),
      height: _nodeSize,
      child: Semantics(
        button: true,
        label: '${lane.label}${topicMastery == null ? '' : ', ${masteryLabel(topicMastery.level)}'}',
        excludeSemantics: true,
        onTap: () => _open(lane),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => _open(lane),
          child: Opacity(
            opacity: node.opacity,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Transform.scale(
                  scale: node.scale,
                  child: _NodeBubble(
                    lane: lane,
                    mastery: topicMastery,
                    focused: focused,
                    current: lane.id == currentId,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    lane.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: focused
                        ? Theme.of(context).textTheme.titleSmall
                        : Theme.of(context).textTheme.labelLarge!.copyWith(color: context.palette.textMuted),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _NodeBubble extends StatelessWidget {
  final FeedLane lane;
  final TopicMastery? mastery;
  final bool focused;
  final bool current;

  const _NodeBubble({required this.lane, required this.mastery, required this.focused, required this.current});

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final level = mastery?.level ?? MasteryLevel.fresh;
    final ringColor = switch (level) {
      MasteryLevel.weak => p.danger,
      MasteryLevel.mastered => p.success,
      _ => p.accentText,
    };
    final icon = lane.type == FeedLaneType.topic ? TopicStyle.of(lane.label).icon : iconForLane(lane.type);
    final filled = focused || current;
    return SizedBox(
      width: _nodeSize,
      height: _nodeSize,
      child: CustomPaint(
        painter: _RingPainter(
          progress: mastery == null ? 0 : mastery!.accuracy / 100,
          color: ringColor,
          track: p.border,
          dashed: lane.type == FeedLaneType.topic && level == MasteryLevel.fresh,
          filled: level == MasteryLevel.mastered,
        ),
        child: Padding(
          padding: const EdgeInsets.all(6),
          child: DecoratedBox(
            decoration: BoxDecoration(shape: BoxShape.circle, color: filled ? p.accent : p.surfaceHigh),
            child: Icon(
              level == MasteryLevel.mastered && !filled ? Icons.check_rounded : icon,
              size: 22,
              color: filled ? p.onAccent : p.text,
            ),
          ),
        ),
      ),
    );
  }
}

/// The detail shown beside the focused lane.
class _FocusDetail extends ConsumerWidget {
  final FeedLane lane;
  final TopicMastery? mastery;
  final VoidCallback onOpen;

  const _FocusDetail({required this.lane, required this.mastery, required this.onOpen});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.palette;
    final text = Theme.of(context).textTheme;
    final lines = <String>[
      switch (lane.type) {
        FeedLaneType.forYou => 'Adapts to what you like and skip',
        FeedLaneType.revision => '${lane.count} due for revision',
        FeedLaneType.weakTopics => '${lane.count} ${lane.count == 1 ? 'topic' : 'topics'} to work on',
        FeedLaneType.bookmarks => '${lane.count} saved',
        FeedLaneType.topic => '${lane.count} questions',
      },
      if (mastery != null && mastery!.attempts > 0) ...[
        '${masteryLabel(mastery!.level)} · ${mastery!.accuracy.round()}% correct',
        'Last practised ${mastery!.lastPractisedLabel(DateTime.now()).toLowerCase()}',
        if (mastery!.dueCount > 0) '${mastery!.dueCount} due for revision',
      ],
    ];
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: p.surfaceHigh,
        borderRadius: BorderRadius.circular(AppRadius.control),
        border: Border.all(color: p.border),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final line in lines) Text(line, style: text.caption.copyWith(color: p.textMuted)),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: AppButton(label: 'Open', onPressed: onOpen),
              ),
              if (lane.type == FeedLaneType.topic)
                IconButton(
                  tooltip: lane.downloaded ? "Downloaded — won't be removed" : 'Keep offline',
                  onPressed: () async {
                    HapticFeedback.selectionClick();
                    await ref.read(practiceContentServiceProvider).setDownloaded(lane.label, !lane.downloaded);
                    ref.invalidate(feedLanesProvider);
                  },
                  icon: Icon(
                    lane.downloaded ? Icons.check_circle_rounded : Icons.download_rounded,
                    color: lane.downloaded ? p.accentText : p.textMuted,
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _TrackPainter extends CustomPainter {
  final DialLayout layout;
  final Color color;

  _TrackPainter({required this.layout, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final span = layout.stepAngle * layout.visibleSteps;
    canvas.drawArc(
      Rect.fromCircle(center: layout.arcCenter, radius: layout.radius),
      -span,
      span * 2,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = color,
    );
  }

  @override
  bool shouldRepaint(_TrackPainter old) => old.layout.size != layout.size || old.color != color;
}

class _RingPainter extends CustomPainter {
  final double progress;
  final Color color;
  final Color track;
  final bool dashed;
  final bool filled;

  _RingPainter({
    required this.progress,
    required this.color,
    required this.track,
    required this.dashed,
    required this.filled,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final rect = (Offset.zero & size).deflate(2);
    final stroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round;
    if (dashed) {
      const dashes = 14;
      for (var i = 0; i < dashes; i++) {
        canvas.drawArc(rect, i * 2 * math.pi / dashes, math.pi / dashes, false, stroke..color = track);
      }
      return;
    }
    canvas.drawArc(rect, 0, 2 * math.pi, false, stroke..color = track);
    canvas.drawArc(
      rect,
      -math.pi / 2,
      2 * math.pi * (filled ? 1 : progress.clamp(0.0, 1.0)),
      false,
      stroke..color = color,
    );
  }

  @override
  bool shouldRepaint(_RingPainter old) =>
      old.progress != progress ||
      old.color != color ||
      old.track != track ||
      old.dashed != dashed ||
      old.filled != filled;
}
