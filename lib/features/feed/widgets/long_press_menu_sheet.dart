import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../shared/theme/practice_theme.dart';
import '../models/feed_models.dart';
import '../providers/feed_providers.dart';

/// Long-press / "More" menu: tune the feed (show less of a topic, hide
/// it), rate the question's difficulty, or report a problem.
class LongPressMenuSheet extends ConsumerWidget {
  final PracticeQuestion question;

  const LongPressMenuSheet({super.key, required this.question});

  static Future<void> show(BuildContext context, PracticeQuestion question) {
    return showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => LongPressMenuSheet(question: question),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
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

    return SafeArea(
      child: Container(
        decoration: BoxDecoration(
          color: isDark ? PracticeTheme.surfaceDark : PracticeTheme.surfaceLight,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        ),
        padding: const EdgeInsets.fromLTRB(8, 12, 8, 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: 12),
                decoration: BoxDecoration(
                  color: isDark ? Colors.white24 : Colors.black12,
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.thumb_down_rounded, color: PracticeTheme.primary),
              title: Text('Show less of "$topic"', style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w600)),
              subtitle: const Text('Your For You feed moves on right away'),
              onTap: () {
                controller.showLessOf(topic);
                notify("You'll see less of $topic.", onUndo: () => controller.undoShowLess(topic));
              },
            ),
            ListTile(
              leading: const Icon(Icons.visibility_off_rounded, color: PracticeTheme.primary),
              title: Text('Hide "$topic"', style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w600)),
              subtitle: const Text('Unhide anytime from the lane switcher'),
              onTap: () {
                controller.muteTopic(topic);
                notify('$topic is hidden from your feed.', onUndo: () => controller.unmuteTopic(topic));
              },
            ),
            ListTile(
              leading: const Icon(Icons.thumb_up_rounded, color: PracticeTheme.success),
              title: Text('Too easy', style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w600)),
              onTap: () {
                controller.markTooEasy(question);
                notify("Got it — you'll see this one less.");
              },
            ),
            ListTile(
              leading: const Icon(Icons.warning_rounded, color: PracticeTheme.warning),
              title: Text('Too hard', style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w600)),
              onTap: () {
                controller.markTooHard(question);
                notify('Added to your Revision Vault.');
              },
            ),
            ListTile(
              leading: const Icon(Icons.error_outline_rounded, color: PracticeTheme.error),
              title: Text('Report a problem', style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w600)),
              subtitle: const Text('Wrong answer key, typo, or bad question'),
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
