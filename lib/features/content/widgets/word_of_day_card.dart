import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../shared/providers/exam_provider.dart';
import '../../../shared/providers/providers.dart';
import '../../../shared/theme/app_palette.dart';
import '../../../shared/utils/user_messages.dart';
import '../../../shared/widgets/app_widgets.dart';
import '../../feed/models/feed_models.dart';
import '../../feed/providers/feed_providers.dart';
import '../../flashcards/providers/flashcard_providers.dart';
import '../services/exam_bank_service.dart';

/// Home's "Word of the day": a new English word each day, with its meaning
/// and an example, for exams that practise vocabulary. Save it as a
/// flashcard, or practise more words.
class WordOfDayCard extends ConsumerStatefulWidget {
  /// Today, for tests; defaults to now.
  final DateTime? today;

  const WordOfDayCard({super.key, this.today});

  @override
  ConsumerState<WordOfDayCard> createState() => _WordOfDayCardState();
}

class _WordOfDayCardState extends ConsumerState<WordOfDayCard> {
  bool _saved = false;
  String? _checked;

  Future<void> _checkSaved(WordOfDay word) async {
    if (_checked == word.question.id) return;
    _checked = word.question.id;
    final saved = await ref.read(savedCardsServiceProvider).isSaved(word.question);
    if (mounted) setState(() => _saved = saved);
  }

  Future<void> _save(WordOfDay word) async {
    HapticFeedback.mediumImpact();
    final added = await ref.read(savedCardsServiceProvider).save(word.question);
    if (!mounted) return;
    setState(() => _saved = true);
    if (added) {
      ref.invalidate(dueFeedFlashcardsProvider);
      ref.read(savedCardsVersionProvider.notifier).state++;
      showAppSnack(context, 'Saved to Cards. It will come back in your feed when it is due.');
    }
  }

  void _practise() {
    HapticFeedback.selectionClick();
    unawaited(
      ref
          .read(feedControllerProvider.notifier)
          .switchLane(const FeedLane(type: FeedLaneType.topic, id: 'topic:Vocabulary', label: 'Vocabulary')),
    );
    ref.read(tabIndexProvider.notifier).state = 0;
  }

  @override
  Widget build(BuildContext context) {
    final exam = ref.watch(examProvider);
    if (exam == null) return const SizedBox.shrink();
    final word = ExamBankService.wordOfTheDay(exam, widget.today ?? DateTime.now());
    if (word == null) return const SizedBox.shrink();
    unawaited(_checkSaved(word));
    final p = context.palette;
    final text = Theme.of(context).textTheme;

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
      child: AppCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(Icons.translate_rounded, color: p.accentText),
                const SizedBox(width: 10),
                Expanded(child: Text('Word of the day', style: text.titleMedium)),
              ],
            ),
            const SizedBox(height: 10),
            Semantics(header: true, child: Text(word.word, style: text.headlineMedium)),
            const SizedBox(height: 4),
            Text(word.meaning, style: text.bodyLarge),
            if (word.example.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(
                word.example,
                style: text.bodyMedium!.copyWith(color: p.textMuted, fontStyle: FontStyle.italic),
              ),
            ],
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  flex: 2,
                  child: _saved
                      ? const AppButton.secondary(label: 'Saved', icon: Icons.check_rounded, onPressed: null)
                      : AppButton.secondary(label: 'Save', icon: Icons.style_rounded, onPressed: () => _save(word)),
                ),
                const SizedBox(width: 8),
                Expanded(
                  flex: 3,
                  child: AppButton(label: 'More words', icon: Icons.play_arrow_rounded, onPressed: _practise),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
