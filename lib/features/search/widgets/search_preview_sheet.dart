import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../shared/providers/providers.dart';
import '../../../shared/theme/app_motion.dart';
import '../../../shared/theme/app_palette.dart';
import '../../../shared/theme/app_text.dart';
import '../../../shared/widgets/app_widgets.dart';
import '../../feed/models/feed_models.dart';
import '../../feed/providers/feed_providers.dart';
import '../../feed/services/question_notes_service.dart';
import '../models/search_index.dart';
import 'highlight_text.dart';

/// A search result up close. A question shows its options with the answer
/// behind "Show answer", the user's note, and ways to act on it: practise
/// its topic, save it, add a note. A flashcard flips.
class SearchPreviewSheet extends ConsumerStatefulWidget {
  final SearchItem item;
  final List<String> words;

  const SearchPreviewSheet({super.key, required this.item, this.words = const []});

  /// Shows the sheet; true if the item was saved, unsaved or its note edited.
  static Future<bool> show(BuildContext context, SearchItem item, List<String> words) async {
    final changed = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (_) => SearchPreviewSheet(item: item, words: words),
    );
    return changed ?? false;
  }

  @override
  ConsumerState<SearchPreviewSheet> createState() => _SearchPreviewSheetState();
}

class _SearchPreviewSheetState extends ConsumerState<SearchPreviewSheet> {
  late SearchItem _item = widget.item;
  bool _revealed = false;
  bool _changed = false;

  void _close() => Navigator.of(context).pop(_changed);

  Future<void> _toggleSave(PracticeQuestion q) async {
    HapticFeedback.lightImpact();
    final bookmarks = ref.read(feedBookmarkServiceProvider);
    final saved = !_item.saved;
    if (saved) {
      await bookmarks.addBookmark(q);
    } else {
      await bookmarks.removeBookmark(q.id);
    }
    ref.invalidate(feedLanesProvider);
    if (!mounted) return;
    setState(() {
      _item = _item.copyWith(saved: saved);
      _changed = true;
    });
  }

  Future<void> _editNote(PracticeQuestion q) async {
    final text = await showDialog<String>(
      context: context,
      builder: (_) => _NoteDialog(initial: _item.note ?? '', editing: _item.hasNote),
    );
    if (text == null) return;
    await ref.read(questionNotesServiceProvider).setNote(q, text);
    if (!mounted) return;
    setState(() {
      _item = _item.copyWith(note: text.trim());
      _changed = true;
    });
  }

  void _practise(PracticeQuestion q) {
    final topic = q.topicName;
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
    final card = _item.card;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _close();
      },
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.88),
        child: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(AppSpace.xl, AppSpace.sm, AppSpace.xl, AppSpace.xl),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(_item.topic, style: text.labelLarge!.copyWith(color: p.accentText)),
                const SizedBox(height: AppSpace.sm),
                if (card != null) _FlipCard(card: card, words: widget.words) else ..._question(_item.question!),
              ],
            ),
          ),
        ),
      ),
    );
  }

  List<Widget> _question(PracticeQuestion q) {
    final p = context.palette;
    final text = Theme.of(context).textTheme;
    return [
      HighlightText(q.questionText, words: widget.words, style: text.question),
      const SizedBox(height: AppSpace.md),
      for (final (i, option) in q.options.indexed)
        Padding(
          padding: const EdgeInsets.only(bottom: AppSpace.sm),
          child: AnimatedContainer(
            duration: AppMotion.of(context, AppMotion.base),
            padding: const EdgeInsets.symmetric(horizontal: AppSpace.md, vertical: 10),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(AppRadius.control),
              border: Border.all(
                color: _revealed && i == q.correctIndex ? p.success : p.border,
                width: _revealed && i == q.correctIndex ? 2 : 1,
              ),
            ),
            child: Row(
              children: [
                Text(String.fromCharCode(65 + i), style: text.labelLarge!.copyWith(color: p.textMuted)),
                const SizedBox(width: AppSpace.md),
                Expanded(
                  child: HighlightText(option, words: widget.words, style: text.option),
                ),
                if (_revealed && i == q.correctIndex) Icon(Icons.check_circle_rounded, color: p.success, size: 20),
              ],
            ),
          ),
        ),
      Reveal(
        show: _revealed && q.explanation.trim().isNotEmpty,
        child: Padding(
          padding: const EdgeInsets.only(top: AppSpace.xs, bottom: AppSpace.sm),
          child: HighlightText(q.explanation, words: widget.words, style: text.bodyMedium!),
        ),
      ),
      if (!_revealed)
        AppButton.secondary(
          label: 'Show answer',
          icon: Icons.visibility_rounded,
          onPressed: () => setState(() => _revealed = true),
        ),
      const SizedBox(height: AppSpace.md),
      if (_item.hasNote)
        AppCard(
          padding: const EdgeInsets.all(AppSpace.md),
          onTap: () => _editNote(q),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.sticky_note_2_outlined, size: 20, color: p.accentText),
              const SizedBox(width: AppSpace.sm),
              Expanded(
                child: HighlightText(_item.note!, words: widget.words, style: text.bodyMedium!),
              ),
              Icon(Icons.edit_rounded, size: 18, color: p.textMuted),
            ],
          ),
        )
      else
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: () => _editNote(q),
            icon: const Icon(Icons.note_add_outlined),
            label: const Text('Add note'),
          ),
        ),
      const SizedBox(height: AppSpace.md),
      Row(
        children: [
          Expanded(
            child: AppButton(
              label: 'Practise this topic',
              icon: Icons.play_arrow_rounded,
              onPressed: () => _practise(q),
            ),
          ),
          const SizedBox(width: AppSpace.sm),
          AppButton.secondary(
            label: _item.saved ? 'Saved' : 'Save',
            icon: _item.saved ? Icons.bookmark_rounded : Icons.bookmark_outline_rounded,
            expanded: false,
            onPressed: () => _toggleSave(q),
          ),
        ],
      ),
    ];
  }
}

/// Writes or edits a note. Owns its text controller so the controller
/// lives until the dialog has finished closing.
class _NoteDialog extends StatefulWidget {
  final String initial;
  final bool editing;

  const _NoteDialog({required this.initial, required this.editing});

  @override
  State<_NoteDialog> createState() => _NoteDialogState();
}

class _NoteDialogState extends State<_NoteDialog> {
  late final _controller = TextEditingController(text: widget.initial);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.editing ? 'Edit note' : 'Add a note'),
      content: TextField(
        controller: _controller,
        autofocus: true,
        minLines: 2,
        maxLines: 6,
        maxLength: QuestionNotesService.maxLength,
        decoration: const InputDecoration(hintText: 'What to remember about this one'),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancel')),
        TextButton(onPressed: () => Navigator.of(context).pop(_controller.text), child: const Text('Save')),
      ],
    );
  }
}

/// A flashcard that turns over when tapped.
class _FlipCard extends StatefulWidget {
  final FeedFlashcard card;
  final List<String> words;

  const _FlipCard({required this.card, required this.words});

  @override
  State<_FlipCard> createState() => _FlipCardState();
}

class _FlipCardState extends State<_FlipCard> {
  bool _back = false;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final text = Theme.of(context).textTheme;
    Widget face(String label, String body) => AppCard(
      color: p.surfaceHigh,
      padding: const EdgeInsets.all(AppSpace.xl),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 180),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(label, style: text.labelMedium!.copyWith(color: p.textMuted)),
            const SizedBox(height: AppSpace.md),
            HighlightText(body, words: widget.words, style: text.titleMedium!),
          ],
        ),
      ),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Semantics(
          button: true,
          label: _back
              ? 'Answer: ${widget.card.back}. Tap to see the question'
              : '${widget.card.front}. Tap to turn over',
          excludeSemantics: true,
          child: GestureDetector(
            onTap: () {
              HapticFeedback.selectionClick();
              setState(() => _back = !_back);
            },
            child: TweenAnimationBuilder<double>(
              tween: Tween(end: _back ? math.pi : 0),
              duration: AppMotion.of(context, AppMotion.slow),
              curve: Curves.easeInOutCubic,
              builder: (context, angle, _) {
                final showBack = angle > math.pi / 2;
                return Transform(
                  alignment: Alignment.center,
                  transform: Matrix4.identity()
                    ..setEntry(3, 2, 0.001)
                    ..rotateY(angle),
                  child: showBack
                      ? Transform(
                          alignment: Alignment.center,
                          transform: Matrix4.rotationY(math.pi),
                          child: face('Answer', widget.card.back),
                        )
                      : face('Question', widget.card.front),
                );
              },
            ),
          ),
        ),
        const SizedBox(height: AppSpace.sm),
        Text('Tap the card to turn it over', textAlign: TextAlign.center, style: text.bodySmall),
      ],
    );
  }
}
