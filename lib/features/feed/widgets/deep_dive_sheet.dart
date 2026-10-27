import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../shared/theme/app_palette.dart';
import '../../../shared/theme/app_text.dart';
import '../../../shared/utils/user_messages.dart';
import '../../../shared/widgets/app_widgets.dart';
import '../../flashcards/providers/flashcard_providers.dart';
import '../../subscription/services/usage_limits.dart';
import '../../subscription/widgets/limit_sheet.dart';
import '../models/feed_models.dart';
import '../providers/feed_providers.dart';
import '../services/explain_service.dart';

/// The solution panel: the answer and its explanation, an "Ask AI" box for
/// a simpler explanation or an example, the user's own note, a one-tap save
/// to flashcards, and a short list of similar questions.
class DeepDiveSheet extends ConsumerStatefulWidget {
  final PracticeQuestion question;
  final int cardIndex;

  const DeepDiveSheet({super.key, required this.question, required this.cardIndex});

  static Future<void> show(BuildContext context, PracticeQuestion question, int cardIndex) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (_) => DeepDiveSheet(question: question, cardIndex: cardIndex),
    );
  }

  @override
  ConsumerState<DeepDiveSheet> createState() => _DeepDiveSheetState();
}

class _DeepDiveSheetState extends ConsumerState<DeepDiveSheet> {
  static const _askTimeout = Duration(seconds: 60);

  late final _notes = ref.read(questionNotesServiceProvider);
  final _noteController = TextEditingController();
  final _followUpController = TextEditingController();
  Timer? _noteDebounce;
  bool _noteDirty = false;
  bool _noteLoaded = false;

  bool _cardSaved = false;

  ExplainMode? _mode;
  String? _answer;
  String? _error;
  bool _loading = false;

  PracticeQuestion get _q => widget.question;

  @override
  void initState() {
    super.initState();
    _loadNote();
    ref.read(savedCardsServiceProvider).isSaved(_q).then((saved) {
      if (mounted) setState(() => _cardSaved = saved);
    });
  }

  Future<void> _loadNote() async {
    final text = await _notes.noteFor(_q);
    if (!mounted) return;
    _noteController.text = text;
    setState(() => _noteLoaded = true);
  }

  @override
  void dispose() {
    _noteDebounce?.cancel();
    if (_noteDirty) unawaited(_notes.setNote(_q, _noteController.text));
    _noteController.dispose();
    _followUpController.dispose();
    super.dispose();
  }

  void _onNoteChanged(String _) {
    _noteDirty = true;
    _noteDebounce?.cancel();
    _noteDebounce = Timer(const Duration(milliseconds: 600), () {
      _noteDirty = false;
      unawaited(_notes.setNote(_q, _noteController.text));
    });
  }

  Future<void> _saveCard() async {
    HapticFeedback.mediumImpact();
    final added = await ref.read(savedCardsServiceProvider).save(_q);
    if (!mounted) return;
    setState(() => _cardSaved = true);
    if (added) {
      ref.invalidate(dueFeedFlashcardsProvider);
      ref.read(savedCardsVersionProvider.notifier).state++;
      showAppSnack(context, 'Saved to Cards. It will come back in your feed when it is due.');
    }
  }

  Future<void> _ask(ExplainMode mode, {String? followUp}) async {
    if (_loading) return;
    final service = ref.read(explainServiceProvider);
    final usage = ref.read(usageLimitsProvider.notifier);
    setState(() {
      _mode = mode;
      _answer = null;
      _error = null;
      _loading = true;
    });
    try {
      // An answer already on the device costs nothing, so only check the
      // daily allowance when we'd have to ask the AI.
      if (await service.cached(_q, mode) == null && !await usage.canUse(UsageKind.aiExplain)) {
        if (mounted) {
          setState(() => _loading = false);
          unawaited(showLimitSheet(context, UsageKind.aiExplain));
        }
        return;
      }
      final result = await service.explain(_q, mode, followUp: followUp).timeout(_askTimeout);
      if (!result.fromCache) await usage.record(UsageKind.aiExplain);
      if (!mounted) return;
      setState(() {
        _answer = result.answer;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = friendlyError(e);
        _loading = false;
      });
    }
  }

  void _askFollowUp() {
    final text = _followUpController.text.trim();
    if (text.isEmpty) return;
    FocusScope.of(context).unfocus();
    _ask(ExplainMode.followUp, followUp: text);
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final text = Theme.of(context).textTheme;
    final controller = ref.read(feedControllerProvider.notifier);
    final similar = controller.similarTo(_q);
    final remaining = ref.watch(usageLimitsProvider).value?.remaining(UsageKind.aiExplain);
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;

    return DraggableScrollableSheet(
      initialChildSize: 0.75,
      minChildSize: 0.4,
      maxChildSize: 0.92,
      expand: false,
      builder: (context, scrollController) {
        return ListView(
          controller: scrollController,
          padding: EdgeInsets.fromLTRB(20, 12, 20, 28 + bottomInset),
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(color: p.border, borderRadius: BorderRadius.circular(AppRadius.pill)),
              ),
            ),
            const SizedBox(height: 18),
            Text('Solution', style: text.titleLarge),
            const SizedBox(height: 12),
            Text(_q.questionText, style: text.bodyMedium!.copyWith(fontWeight: FontWeight.w600)),
            const SizedBox(height: 14),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(color: p.successSoft, borderRadius: BorderRadius.circular(AppRadius.control)),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.check_circle_rounded, color: p.success, size: 20),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      _q.options[_q.correctIndex],
                      style: text.bodyMedium!.copyWith(fontWeight: FontWeight.w700),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            Text(
              _q.explanation.trim().isEmpty ? 'No solution notes for this question yet.' : _q.explanation,
              style: text.bodyMedium!.copyWith(height: 1.6, color: p.textMuted),
            ),
            const SizedBox(height: 24),
            _buildAskAi(context, remaining),
            const SizedBox(height: 24),
            _buildNote(context),
            const SizedBox(height: 16),
            if (_cardSaved)
              const AppButton.secondary(label: 'Saved to Cards', icon: Icons.check_rounded, onPressed: null)
            else
              AppButton.secondary(
                label: 'Save as flashcard',
                icon: Icons.style_rounded,
                onPressed: _saveCard,
              ),
            if (similar.isNotEmpty) ...[
              const SizedBox(height: 26),
              Text('Similar questions', style: text.titleMedium),
              const SizedBox(height: 10),
              for (final q in similar)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(AppRadius.control),
                    onTap: () {
                      controller.insertNext(widget.cardIndex, q);
                      Navigator.of(context).pop();
                    },
                    child: Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        border: Border.all(color: p.border),
                        borderRadius: BorderRadius.circular(AppRadius.control),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(q.questionText, maxLines: 2, overflow: TextOverflow.ellipsis, style: text.bodyMedium),
                          ),
                          const SizedBox(width: 8),
                          Icon(Icons.chevron_right_rounded, size: 20, color: p.accentText),
                        ],
                      ),
                    ),
                  ),
                ),
            ],
          ],
        );
      },
    );
  }

  Widget _buildAskAi(BuildContext context, int? remaining) {
    final p = context.palette;
    final text = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Icon(Icons.auto_awesome_rounded, size: 20, color: p.accentText),
            const SizedBox(width: 8),
            Expanded(child: Text('Ask AI', style: text.titleMedium)),
            if (remaining != null)
              Text('$remaining left today', style: text.caption.copyWith(color: p.textMuted)),
          ],
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final mode in ExplainMode.values.where((m) => m != ExplainMode.followUp))
              ChoiceChip(
                label: Text(mode.label),
                selected: _mode == mode && !_loading && _answer != null,
                onSelected: _loading ? null : (_) => _ask(mode),
              ),
          ],
        ),
        const SizedBox(height: 10),
        TextField(
          controller: _followUpController,
          enabled: !_loading,
          textInputAction: TextInputAction.send,
          maxLength: ExplainService.maxFollowUpLength,
          maxLines: 1,
          onSubmitted: (_) => _askFollowUp(),
          decoration: InputDecoration(
            hintText: 'Ask your own question about this',
            counterText: '',
            suffixIcon: IconButton(
              tooltip: 'Send',
              onPressed: _loading ? null : _askFollowUp,
              icon: const Icon(Icons.send_rounded),
            ),
          ),
        ),
        if (_loading || _answer != null || _error != null) ...[
          const SizedBox(height: 12),
          _AnswerBox(
            label: _mode?.label ?? '',
            loading: _loading,
            answer: _answer,
            error: _error,
            onRetry: _mode == null
                ? null
                : () => _ask(_mode!, followUp: _mode == ExplainMode.followUp ? _followUpController.text : null),
          ),
        ],
      ],
    );
  }

  Widget _buildNote(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Icon(Icons.edit_note_rounded, size: 22, color: context.palette.accentText),
            const SizedBox(width: 8),
            Text('My note', style: text.titleMedium),
          ],
        ),
        const SizedBox(height: 10),
        TextField(
          controller: _noteController,
          enabled: _noteLoaded,
          minLines: 2,
          maxLines: 5,
          maxLength: 500,
          textCapitalization: TextCapitalization.sentences,
          onChanged: _onNoteChanged,
          decoration: const InputDecoration(hintText: 'Add a note to remember this', counterText: ''),
        ),
      ],
    );
  }
}

class _AnswerBox extends StatelessWidget {
  final String label;
  final bool loading;
  final String? answer;
  final String? error;
  final VoidCallback? onRetry;

  const _AnswerBox({
    required this.label,
    required this.loading,
    required this.answer,
    required this.error,
    required this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final text = Theme.of(context).textTheme;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: error != null ? p.dangerSoft : p.accentSoft,
        borderRadius: BorderRadius.circular(AppRadius.control),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (loading) ...[
            Text('Thinking…', style: text.caption.copyWith(color: p.textMuted)),
            const SizedBox(height: 8),
            const LinearProgressIndicator(),
          ] else if (error != null) ...[
            Text(error!, style: text.bodyMedium),
            if (onRetry != null)
              TextButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh_rounded),
                label: const Text('Retry'),
              ),
          ] else if (answer != null) ...[
            Text(label, style: text.micro.copyWith(color: p.accentText)),
            const SizedBox(height: 6),
            SelectableText(answer!, style: text.bodyMedium!.copyWith(height: 1.6)),
          ],
        ],
      ),
    );
  }
}
