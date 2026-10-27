import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../shared/theme/app_motion.dart';
import '../../../shared/theme/app_palette.dart';
import '../../../shared/theme/app_text.dart';
import '../../../shared/widgets/app_widgets.dart';
import '../models/daily_challenge.dart';
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
      transitionDuration: AppMotion.of(context, AppMotion.base),
      pageBuilder: (context, animation, secondary) => const TopicDial(),
      transitionBuilder: (context, animation, secondary, child) {
        final curved = CurvedAnimation(parent: animation, curve: AppMotion.enter, reverseCurve: AppMotion.exit);
        return FadeTransition(
          opacity: Tween<double>(begin: 0.4, end: 1).animate(curved),
          child: SlideTransition(
            position: Tween(begin: const Offset(-1, 0), end: Offset.zero).animate(curved),
            child: child,
          ),
        );
      },
    );
  }

  @override
  ConsumerState<TopicDial> createState() => _TopicDialState();
}

class _TopicDialState extends ConsumerState<TopicDial> with SingleTickerProviderStateMixin {
  static final _spring = SpringDescription.withDampingRatio(mass: 1, stiffness: 240, ratio: 0.9);

  /// Which lane is in the middle, as a (fractional while moving) lane index.
  /// Only the arc and its nodes listen to this, so turning the dial never
  /// rebuilds the panel around it.
  final ValueNotifier<double> _focus = ValueNotifier(0);

  /// The whole lane index in the middle, for the detail card below.
  final ValueNotifier<int> _focusIndex = ValueNotifier(0);
  late final AnimationController _settle;

  bool _positioned = false;
  bool _listMode = false;
  int _laneCount = 0;

  @override
  void initState() {
    super.initState();
    _settle = AnimationController.unbounded(vsync: this)..addListener(() => _setFocus(_settle.value));
  }

  @override
  void dispose() {
    _settle.dispose();
    _focus.dispose();
    _focusIndex.dispose();
    super.dispose();
  }

  void _setFocus(double value) {
    _focus.value = value;
    final rounded = value.round();
    if (rounded != _focusIndex.value) {
      _focusIndex.value = rounded;
      HapticFeedback.selectionClick();
    }
  }

  /// Glides to lane [index], carrying the speed the finger let go at
  /// ([velocity], in lanes per second).
  void _animateTo(int index, {double velocity = 0}) {
    if (AppMotion.reduced(context)) {
      _setFocus(index.toDouble());
      return;
    }
    _settle.value = _focus.value;
    _settle.animateWith(SpringSimulation(_spring, _focus.value, index.toDouble(), velocity));
  }

  void _close() => Navigator.of(context).pop();

  void _open(FeedLane lane) {
    HapticFeedback.selectionClick();
    final controller = ref.read(feedControllerProvider.notifier);
    _close();
    // Switch once the dial has mostly slid away, so the feed doesn't jump
    // behind it while it is still closing.
    Future<void>.delayed(
      AppMotion.of(context, const Duration(milliseconds: 140)),
      () => controller.switchLane(lane, restorePosition: true),
    );
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
        _focus.value = math.max(0, at).toDouble();
        _focusIndex.value = _focus.value.round();
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
                  child: AnimatedSwitcher(
                    duration: AppMotion.of(context, AppMotion.base),
                    child: KeyedSubtree(
                      key: ValueKey(_listMode),
                      child: _listMode
                          ? Padding(
                              padding: const EdgeInsets.fromLTRB(12, 4, 12, 0),
                              child: LaneList(onPick: _open),
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
    final challenge = ref.watch(dailyChallengeProvider).value;
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
                onVerticalDragUpdate: (d) => _setFocus(layout.focusAfterDrag(_focus.value, d.delta.dy, _laneCount)),
                onVerticalDragEnd: (d) {
                  final velocity = d.primaryVelocity ?? 0;
                  _animateTo(
                    layout.settleIndex(_focus.value, velocity, _laneCount),
                    // Finger up = later lanes: px/s to lanes/s, eased down so
                    // the glide doesn't overshoot the lane it picked.
                    velocity: (-velocity / layout.pixelsPerStep * 0.5).clamp(-8.0, 8.0),
                  );
                },
                child: Stack(
                  clipBehavior: Clip.hardEdge,
                  children: [
                    Positioned.fill(
                      child: CustomPaint(
                        painter: _TrackPainter(layout: layout, color: p.border),
                      ),
                    ),
                    Positioned.fill(
                      child: ValueListenableBuilder<double>(
                        valueListenable: _focus,
                        builder: (context, focus, _) {
                          final focusIndex = focus.round().clamp(0, lanes.length - 1);
                          return Stack(
                            clipBehavior: Clip.hardEdge,
                            children: [
                              for (final node in layout.nodes(lanes.length, focus))
                                _positionedNode(
                                  context,
                                  layout,
                                  node,
                                  lanes[node.index],
                                  mastery,
                                  currentId,
                                  node.index == focusIndex,
                                  challenge,
                                ),
                            ],
                          );
                        },
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
          child: ValueListenableBuilder<int>(
            valueListenable: _focusIndex,
            builder: (context, index, _) {
              final focusLane = lanes[index.clamp(0, lanes.length - 1)];
              return _FocusDetail(
                lane: focusLane,
                mastery: focusLane.type == FeedLaneType.topic ? mastery[focusLane.label] : null,
                daily: challenge,
                onOpen: () => _open(focusLane),
              );
            },
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
    DailyChallenge? challenge,
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
                    daily: lane.type == FeedLaneType.daily ? challenge : null,
                    focused: focused,
                    current: lane.id == currentId,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: AnimatedDefaultTextStyle(
                    duration: AppMotion.of(context, AppMotion.fast),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: focused
                        ? Theme.of(context).textTheme.titleSmall!
                        : Theme.of(context).textTheme.labelLarge!.copyWith(color: context.palette.textMuted),
                    child: Text(lane.label),
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

  /// Today's challenge, for the Daily 5 node's progress ring.
  final DailyChallenge? daily;
  final bool focused;
  final bool current;

  const _NodeBubble({
    required this.lane,
    required this.mastery,
    required this.daily,
    required this.focused,
    required this.current,
  });

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final level = mastery?.level ?? MasteryLevel.fresh;
    final dailyDone = daily?.completed ?? false;
    final ringColor = dailyDone
        ? p.success
        : switch (level) {
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
          progress: daily != null
              ? (daily!.total == 0 ? 0 : daily!.answered / daily!.total)
              : (mastery == null ? 0 : mastery!.accuracy / 100),
          color: ringColor,
          track: p.border,
          dashed: lane.type == FeedLaneType.topic && level == MasteryLevel.fresh,
          filled: level == MasteryLevel.mastered || dailyDone,
        ),
        child: Padding(
          padding: const EdgeInsets.all(6),
          child: AnimatedContainer(
            duration: AppMotion.of(context, AppMotion.fast),
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
  final DailyChallenge? daily;
  final VoidCallback onOpen;

  const _FocusDetail({required this.lane, required this.mastery, required this.daily, required this.onOpen});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.palette;
    final text = Theme.of(context).textTheme;
    final lines = <String>[
      switch (lane.type) {
        FeedLaneType.forYou => 'Adapts to what you like and skip',
        FeedLaneType.daily => switch (daily) {
          final d? when d.completed => 'Done today: ${d.correct} of ${d.total} right',
          final d? when d.answered > 0 => '${d.answered} of ${d.total} done today',
          _ => '${lane.count} questions, a fresh set every day',
        },
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
