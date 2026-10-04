import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../shared/providers/providers.dart';
import '../../feed/models/feed_models.dart';
import '../../feed/providers/feed_providers.dart';

/// Instagram-stories-style row of the user's topics. A ring marks topics
/// that still have questions you haven't seen; tapping one opens it in
/// the Practice feed.
class TopicStoriesRow extends ConsumerWidget {
  final bool isDark;
  final Color primaryColor;
  final Color textMain;

  const TopicStoriesRow({
    super.key,
    required this.isDark,
    required this.primaryColor,
    required this.textMain,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final stories = ref.watch(topicStoriesProvider).value ?? const <TopicStory>[];
    if (stories.isEmpty) return const SizedBox.shrink();

    return SizedBox(
      height: 104,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(24, 8, 24, 8),
        itemCount: stories.length,
        separatorBuilder: (_, _) => const SizedBox(width: 14),
        itemBuilder: (context, index) {
          final story = stories[index];
          return _TopicStory(
            story: story,
            isDark: isDark,
            primaryColor: primaryColor,
            textMain: textMain,
            onTap: () {
              HapticFeedback.selectionClick();
              ref.read(feedControllerProvider.notifier).switchLane(
                    FeedLane(
                      type: FeedLaneType.topic,
                      id: 'topic:${story.topic}',
                      label: story.topic,
                    ),
                  );
              ref.read(tabIndexProvider.notifier).state = 0;
            },
          );
        },
      ),
    );
  }
}

class _TopicStory extends StatelessWidget {
  final TopicStory story;
  final bool isDark;
  final Color primaryColor;
  final Color textMain;
  final VoidCallback onTap;

  const _TopicStory({
    required this.story,
    required this.isDark,
    required this.primaryColor,
    required this.textMain,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final trimmed = story.topic.trim();
    final initial = trimmed.isEmpty ? '?' : trimmed[0].toUpperCase();
    final ringColor = story.hasUnseen
        ? primaryColor
        : (isDark ? Colors.white24 : Colors.black12);

    return Semantics(
      button: true,
      label: '${story.topic}, ${story.count} questions'
          '${story.hasUnseen ? ', new questions' : ''}',
      child: GestureDetector(
        onTap: onTap,
        child: SizedBox(
          width: 66,
          child: Column(
            children: [
              Container(
                width: 62,
                height: 62,
                padding: const EdgeInsets.all(3),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: ringColor, width: 2.5),
                ),
                child: Container(
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: primaryColor.withOpacity(isDark ? 0.22 : 0.10),
                  ),
                  child: Text(
                    initial,
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                      color: primaryColor,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 6),
              Text(
                story.topic,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 11,
                  fontWeight: story.hasUnseen ? FontWeight.w700 : FontWeight.w500,
                  color: textMain,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
