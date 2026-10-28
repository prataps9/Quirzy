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
import '../../feed/services/mistakes_service.dart';

/// The user's notes on questions, keyed like the Mistakes notebook.
final _notesProvider = FutureProvider.autoDispose<Map<String, String>>((ref) {
  return ref.watch(questionNotesServiceProvider).allNotes();
});

/// The Mistakes notebook: every question answered wrong, what was picked,
/// the right answer, why, and the user's own note. "Retry these" opens the
/// ones still to fix as a feed lane.
class MistakesScreen extends ConsumerStatefulWidget {
  const MistakesScreen({super.key});

  @override
  ConsumerState<MistakesScreen> createState() => _MistakesScreenState();
}

/// What the notebook is showing: the ones to fix, all of them, or a topic.
const _toFix = '__to_fix__';
const _all = '__all__';

class _MistakesScreenState extends ConsumerState<MistakesScreen> {
  String _filter = _toFix;

  void _retry() {
    HapticFeedback.selectionClick();
    ref.read(feedControllerProvider.notifier).switchLane(FeedLane.mistakes);
    ref.read(tabIndexProvider.notifier).state = 0;
    Navigator.of(context).popUntil((route) => route.isFirst);
  }

  @override
  Widget build(BuildContext context) {
    final entriesAsync = ref.watch(mistakesProvider);
    final notes = ref.watch(_notesProvider).value ?? const <String, String>{};

    return Scaffold(
      appBar: AppBar(title: const Text('Mistakes notebook')),
      body: entriesAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, st) => Center(
          child: TextButton.icon(
            onPressed: () => ref.invalidate(mistakesProvider),
            icon: const Icon(Icons.refresh_rounded),
            label: const Text("Couldn't load your mistakes. Retry"),
          ),
        ),
        data: (entries) {
          if (entries.isEmpty) {
            return const FadeRise(
              child: _Empty(
                title: 'No mistakes yet',
                body: 'Questions you get wrong land here, with the right answer, so you can come back and fix them.',
              ),
            );
          }
          final open = entries.where((e) => !e.fixed).toList();
          final topics = {for (final e in entries) e.question.topicName}.toList()..sort();
          final shown = switch (_filter) {
            _toFix => open,
            _all => entries,
            final topic => entries.where((e) => e.question.topicName == topic).toList(),
          };

          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(
                height: 52,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                  children: [
                    _chip('To fix (${open.length})', _toFix),
                    _chip('All (${entries.length})', _all),
                    for (final topic in topics) _chip(topic, topic),
                  ],
                ),
              ),
              Expanded(
                child: shown.isEmpty
                    ? _Empty(
                        title: _filter == _toFix ? 'All fixed' : 'Nothing here',
                        body: _filter == _toFix
                            ? 'You have answered every one of these right twice since. Nice work.'
                            : 'No mistakes in this topic.',
                      )
                    : ListView.separated(
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                        itemCount: shown.length,
                        separatorBuilder: (_, _) => const SizedBox(height: 10),
                        itemBuilder: (context, i) => _MistakeTile(entry: shown[i], note: notes[shown[i].key]),
                      ),
              ),
              if (open.isNotEmpty)
                SafeArea(
                  top: false,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
                    child: AppButton(
                      label: 'Retry the ${open.length} to fix',
                      icon: Icons.replay_rounded,
                      onPressed: _retry,
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }

  Widget _chip(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: ChoiceChip(
        label: Text(label),
        selected: _filter == value,
        showCheckmark: false,
        onSelected: (_) => setState(() => _filter = value),
      ),
    );
  }
}

class _MistakeTile extends StatelessWidget {
  final MistakeEntry entry;
  final String? note;

  const _MistakeTile({required this.entry, required this.note});

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final text = Theme.of(context).textTheme;
    final q = entry.question;
    final picked = entry.pickedText;

    Widget answerLine(IconData icon, Color color, Color fill, String label) => Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(color: fill, borderRadius: BorderRadius.circular(AppRadius.chip)),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: 8),
          Expanded(child: Text(label, style: text.bodyMedium)),
        ],
      ),
    );

    return AppCard(
      padding: const EdgeInsets.all(AppSpace.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  '${q.topicName.toUpperCase()} · WRONG ${entry.timesWrong}×',
                  style: text.micro.copyWith(color: p.textMuted),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (entry.fixed)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(color: p.successSoft, borderRadius: BorderRadius.circular(AppRadius.pill)),
                  child: Text('Fixed', style: text.micro.copyWith(color: p.success)),
                ),
            ],
          ),
          const SizedBox(height: 6),
          Text(q.questionText, style: text.titleSmall),
          if (picked != null) answerLine(Icons.close_rounded, p.danger, p.dangerSoft, 'You picked: $picked'),
          answerLine(Icons.check_rounded, p.success, p.successSoft, q.options[q.correctIndex]),
          if (q.explanation.trim().isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(q.explanation.trim(), style: text.caption.copyWith(color: p.textMuted)),
          ],
          if (entry.reason != null || (note?.isNotEmpty ?? false)) ...[
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 6,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                if (entry.reason != null)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: p.surfaceHigh,
                      borderRadius: BorderRadius.circular(AppRadius.pill),
                    ),
                    child: Text(entry.reason!, style: text.labelMedium),
                  ),
                if (note?.isNotEmpty ?? false)
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.edit_note_rounded, size: 18, color: p.accentText),
                      const SizedBox(width: 4),
                      Flexible(child: Text(note!, style: text.caption)),
                    ],
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _Empty extends StatelessWidget {
  final String title;
  final String body;

  const _Empty({required this.title, required this.body});

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final text = Theme.of(context).textTheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.rule_rounded, size: 52, color: p.accentText),
            const SizedBox(height: 14),
            Text(title, textAlign: TextAlign.center, style: text.titleLarge),
            const SizedBox(height: 8),
            Text(
              body,
              textAlign: TextAlign.center,
              style: text.bodyMedium!.copyWith(color: p.textMuted),
            ),
          ],
        ),
      ),
    );
  }
}
