import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../shared/theme/app_palette.dart';
import '../models/feed_models.dart';
import '../providers/feed_providers.dart';

/// The "More" menu: tune the feed (show less of a topic, hide it), rate the
/// question's difficulty, or report a problem.
class LongPressMenuSheet extends ConsumerWidget {
  final PracticeQuestion question;

  const LongPressMenuSheet({super.key, required this.question});

  static Future<void> show(BuildContext context, PracticeQuestion question) {
    return showModalBottomSheet(
      context: context,
      builder: (_) => LongPressMenuSheet(question: question),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.palette;
    final controller = ref.read(feedControllerProvider.notifier);
    final topic = question.topicName;

    void notify(String message, {VoidCallback? onUndo}) {
      final messenger = ScaffoldMessenger.of(context);
      Navigator.of(context).pop();
      messenger.showSnackBar(
        SnackBar(
          content: Text(message),
          duration: Duration(milliseconds: onUndo == null ? 1600 : 4000),
          action: onUndo == null ? null : SnackBarAction(label: 'Undo', onPressed: onUndo),
        ),
      );
    }

    Widget item({
      required IconData icon,
      required Color color,
      required String title,
      String? subtitle,
      required VoidCallback onTap,
    }) {
      return ListTile(
        leading: Icon(icon, color: color),
        title: Text(title),
        subtitle: subtitle == null ? null : Text(subtitle),
        onTap: onTap,
      );
    }

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 12, 8, 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.only(bottom: 8),
              decoration: BoxDecoration(
                color: p.border,
                borderRadius: BorderRadius.circular(AppRadius.pill),
              ),
            ),
            item(
              icon: Icons.thumb_down_rounded,
              color: p.accentText,
              title: 'Show less of "$topic"',
              subtitle: 'Your For You feed moves on right away',
              onTap: () {
                controller.showLessOf(topic);
                notify("You'll see less of $topic.", onUndo: () => controller.undoShowLess(topic));
              },
            ),
            item(
              icon: Icons.visibility_off_rounded,
              color: p.accentText,
              title: 'Hide "$topic"',
              subtitle: 'Unhide anytime from the lane switcher',
              onTap: () {
                controller.muteTopic(topic);
                notify('$topic is hidden from your feed.', onUndo: () => controller.unmuteTopic(topic));
              },
            ),
            item(
              icon: Icons.thumb_up_rounded,
              color: p.success,
              title: 'Too easy',
              onTap: () {
                controller.markTooEasy(question);
                notify("Got it — you'll see this one less.");
              },
            ),
            item(
              icon: Icons.warning_rounded,
              color: p.streak,
              title: 'Too hard',
              onTap: () {
                controller.markTooHard(question);
                notify('Added to your Revision Vault.');
              },
            ),
            item(
              icon: Icons.error_outline_rounded,
              color: p.danger,
              title: 'Report a problem',
              subtitle: 'Wrong answer key, typo, or bad question',
              onTap: () {
                controller.reportQuestion(question.id);
                notify('Reported — removed from your feed.');
              },
            ),
          ],
        ),
      ),
    );
  }
}
