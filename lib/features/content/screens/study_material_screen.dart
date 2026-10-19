import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../shared/providers/providers.dart';
import '../../../shared/theme/app_palette.dart';
import '../../../shared/utils/user_messages.dart';
import '../../../shared/widgets/app_widgets.dart';
import '../../feed/providers/feed_providers.dart';
import '../../feed/services/practice_content_service.dart';
import '../services/study_material_service.dart';

class StudyMaterialScreen extends ConsumerStatefulWidget {
  final StudyMaterial material;

  const StudyMaterialScreen({super.key, required this.material});

  @override
  ConsumerState<StudyMaterialScreen> createState() => _StudyMaterialScreenState();
}

class _StudyMaterialScreenState extends ConsumerState<StudyMaterialScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  int _currentFlashcard = 0;
  bool _isFlipped = false;

  /// The set's questions, normalised once (see [_quizAsFeedQuestions]) so
  /// display, grading and "Add to my feed" all read the same shape.
  late final List<Map<String, dynamic>> _questions = _quizAsFeedQuestions();

  // Practice questions state
  List<int?> _quizAnswers = [];
  bool _quizSubmitted = false;

  bool _addingToFeed = false;
  bool _addedToFeed = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _quizAnswers = List.filled(_questions.length, null);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final textTheme = Theme.of(context).textTheme;

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.material.topic,
              style: textTheme.titleMedium,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            Text('Study set', style: textTheme.labelSmall!.copyWith(color: p.accentText)),
          ],
        ),
        bottom: TabBar(
          controller: _tabController,
          labelStyle: textTheme.labelLarge!.copyWith(fontWeight: FontWeight.w800),
          unselectedLabelStyle: textTheme.labelMedium!.copyWith(fontWeight: FontWeight.w600),
          labelColor: p.accentText,
          unselectedLabelColor: p.textMuted,
          indicatorColor: p.accentText,
          dividerColor: p.border,
          tabs: const [
            Tab(icon: Icon(Icons.list_alt_rounded, size: 18), text: 'Summary'),
            Tab(icon: Icon(Icons.style_rounded, size: 18), text: 'Flashcards'),
            Tab(icon: Icon(Icons.quiz_rounded, size: 18), text: 'Practice'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildSummaryTab(),
          _buildFlashcardsTab(),
          _buildPracticeTab(),
        ],
      ),
    );
  }

  /// Turns the study set's quiz items into practice-feed questions. Items
  /// come back as `questionText`/`options`/`correctAnswer` (an index), but
  /// older sets may use `question` and an `answer` given as the option text.
  List<Map<String, dynamic>> _quizAsFeedQuestions() {
    final material = widget.material;
    final out = <Map<String, dynamic>>[];
    for (var i = 0; i < material.quiz.length; i++) {
      final q = material.quiz[i];
      final text = (q['questionText'] ?? q['question'] ?? '').toString().trim();
      final options = (q['options'] as List<dynamic>? ?? []).map((e) => e.toString()).toList();
      if (text.isEmpty || options.length < 2) continue;

      final raw = q['correctAnswer'] ?? q['correctIndex'] ?? q['answer'];
      var correct = raw is int ? raw : int.tryParse('$raw') ?? options.indexOf('$raw');
      // A bare letter ("B") means the option at that position.
      if (correct < 0 && raw is String && RegExp(r'^[A-Da-d]$').hasMatch(raw.trim())) {
        correct = raw.trim().toUpperCase().codeUnitAt(0) - 65;
      }
      if (correct < 0 || correct >= options.length) correct = 0;

      out.add({
        // Stable ids so adding the same set twice doesn't duplicate questions.
        'id': '${material.id}_q$i',
        'questionText': text,
        'options': options,
        'correctAnswer': correct,
        'explanation': q['explanation']?.toString() ?? '',
      });
    }
    return out;
  }

  Future<void> _addToFeed() async {
    final questions = _questions;
    if (questions.isEmpty) return;
    HapticFeedback.mediumImpact();
    setState(() => _addingToFeed = true);

    final topic = widget.material.topic;
    try {
      await ref.read(practiceContentServiceProvider).addToQuestionPool(
            questions,
            topicId: widget.material.id,
            topic: topic,
          );
      await ref.read(feedControllerProvider.notifier).switchToTopic(topic);
      if (!mounted) return;
      setState(() => _addedToFeed = true);
      final navigator = Navigator.of(context);
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(
              questions.length == 1
                  ? 'Added 1 question on "$topic" to your feed'
                  : 'Added ${questions.length} questions on "$topic" to your feed',
            ),
            action: SnackBarAction(
              label: 'Practise',
              onPressed: () {
                ref.read(tabIndexProvider.notifier).state = 0; // Practice tab
                navigator.popUntil((route) => route.isFirst);
              },
            ),
          ),
        );
    } catch (e) {
      if (mounted) showAppSnack(context, friendlyError(e), onRetry: _addToFeed);
    } finally {
      if (mounted) setState(() => _addingToFeed = false);
    }
  }

  // ── SUMMARY TAB ──────────────────────────────────────────────────────────

  Widget _buildSummaryTab() {
    final p = context.palette;
    final textTheme = Theme.of(context).textTheme;

    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        AppCard(
          color: p.accentSoft,
          radius: AppRadius.control,
          child: Row(
            children: [
              Icon(Icons.lightbulb_outline_rounded, color: p.accentText, size: 20),
              const SizedBox(width: 8),
              Text('Key concepts', style: textTheme.titleSmall!.copyWith(color: p.accentText)),
            ],
          ),
        ),
        const SizedBox(height: 16),
        ...widget.material.summary.asMap().entries.map((entry) {
          return Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: AppCard(
              radius: AppRadius.control,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 26,
                    height: 26,
                    margin: const EdgeInsets.only(right: 12, top: 1),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(color: p.accentSoft, shape: BoxShape.circle),
                    child: Text(
                      '${entry.key + 1}',
                      style: textTheme.labelSmall!.copyWith(
                        fontWeight: FontWeight.w800,
                        color: p.accentText,
                      ),
                    ),
                  ),
                  Expanded(
                    child: Text(entry.value, style: textTheme.bodyMedium!.copyWith(height: 1.5)),
                  ),
                ],
              ),
            ),
          );
        }),
      ],
    );
  }

  // ── FLASHCARDS TAB ────────────────────────────────────────────────────────

  Widget _buildFlashcardsTab() {
    final p = context.palette;
    final textTheme = Theme.of(context).textTheme;
    final cards = widget.material.flashcards;

    if (cards.isEmpty) {
      return Center(child: Text('No cards in this set', style: textTheme.bodyMedium!.copyWith(color: p.textMuted)));
    }

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '${_currentFlashcard + 1} / ${cards.length}',
                style: textTheme.titleSmall!.copyWith(color: p.textMuted),
              ),
              Text('Tap card to flip', style: textTheme.bodySmall),
            ],
          ),
        ),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: GestureDetector(
              onTap: () {
                HapticFeedback.selectionClick();
                setState(() => _isFlipped = !_isFlipped);
              },
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 200),
                child: _isFlipped
                    ? _flashcardFace(
                        key: const ValueKey('back'),
                        text: cards[_currentFlashcard]['back'] as String? ?? '',
                        label: 'Answer',
                        isBack: true,
                      )
                    : _flashcardFace(
                        key: const ValueKey('front'),
                        text: cards[_currentFlashcard]['front'] as String? ?? '',
                        label: 'Question',
                        isBack: false,
                      ),
              ),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
          child: Row(
            children: [
              Expanded(
                child: AppButton.secondary(
                  label: 'Previous',
                  icon: Icons.arrow_back_rounded,
                  onPressed: _currentFlashcard > 0
                      ? () => setState(() { _currentFlashcard--; _isFlipped = false; })
                      : null,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: AppButton(
                  label: 'Next',
                  icon: Icons.arrow_forward_rounded,
                  onPressed: _currentFlashcard < cards.length - 1
                      ? () => setState(() { _currentFlashcard++; _isFlipped = false; })
                      : null,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _flashcardFace({
    required Key key,
    required String text,
    required String label,
    required bool isBack,
  }) {
    final p = context.palette;
    final textTheme = Theme.of(context).textTheme;

    return AppCard(
      key: key,
      borderColor: isBack ? p.accentText : p.border,
      padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
      child: SizedBox.expand(
        child: Center(
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                  decoration: BoxDecoration(
                    color: isBack ? p.accent : p.surfaceHigh,
                    borderRadius: BorderRadius.circular(AppRadius.pill),
                  ),
                  child: Text(
                    label,
                    style: textTheme.labelMedium!.copyWith(
                      fontWeight: FontWeight.w800,
                      color: isBack ? p.onAccent : p.textMuted,
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                Text(
                  text,
                  style: textTheme.titleLarge!.copyWith(height: 1.5),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 32),
                Icon(Icons.touch_app_rounded, color: p.textMuted, size: 24),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ── PRACTICE TAB ────────────────────────────────────────────────────

  Widget _buildPracticeTab() {
    final p = context.palette;
    final textTheme = Theme.of(context).textTheme;
    final quiz = _questions;

    if (quiz.isEmpty) {
      return Center(child: Text('No practice questions', style: textTheme.bodyMedium!.copyWith(color: p.textMuted)));
    }

    final correctCount = _quizSubmitted
        ? quiz.asMap().entries.where((e) => _quizAnswers[e.key] == e.value['correctAnswer']).length
        : 0;
    final passed = correctCount >= quiz.length * 0.8;
    final resultColor = passed ? p.success : p.streak;

    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        if (_quizSubmitted) ...[
          Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: AppCard(
              color: passed ? p.successSoft : p.streakSoft,
              borderColor: resultColor,
              radius: AppRadius.control,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    passed ? Icons.check_circle_rounded : Icons.star_half_rounded,
                    color: resultColor,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '$correctCount / ${quiz.length} correct',
                    style: textTheme.titleSmall!.copyWith(color: resultColor),
                  ),
                ],
              ),
            ),
          ),
        ],
        ...quiz.asMap().entries.map((entry) {
          final qi = entry.key;
          final q = entry.value;
          final selected = _quizAnswers[qi];
          final correctAnswer = q['correctAnswer'] as int;
          final options = q['options'] as List<String>;

          return Padding(
            padding: const EdgeInsets.only(bottom: 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                AppCard(
                  padding: const EdgeInsets.all(14),
                  radius: AppRadius.control,
                  child: SizedBox(
                    width: double.infinity,
                    child: Text(
                      'Q${qi + 1}. ${q['questionText']}',
                      style: textTheme.bodyMedium!.copyWith(height: 1.4),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                ...options.asMap().entries.map((optEntry) {
                  final oi = optEntry.key;
                  final opt = optEntry.value;
                  Color? tone;
                  Color? fill;
                  IconData? trailingIcon;

                  if (_quizSubmitted) {
                    if (oi == correctAnswer) {
                      tone = p.success;
                      fill = p.successSoft;
                      trailingIcon = Icons.check_circle_rounded;
                    } else if (oi == selected && selected != correctAnswer) {
                      tone = p.danger;
                      fill = p.dangerSoft;
                      trailingIcon = Icons.cancel_rounded;
                    }
                  } else if (oi == selected) {
                    tone = p.accentText;
                    fill = p.accentSoft;
                  }

                  return Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: AppCard(
                      color: fill,
                      borderColor: tone,
                      radius: AppRadius.chip,
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                      onTap: _quizSubmitted ? null : () => setState(() => _quizAnswers[qi] = oi),
                      child: Row(
                        children: [
                          Text(
                            '${String.fromCharCode(65 + oi)}. ',
                            style: textTheme.titleSmall!.copyWith(color: tone ?? p.text),
                          ),
                          Expanded(child: Text(opt, style: textTheme.bodyMedium)),
                          if (trailingIcon != null) Icon(trailingIcon, color: tone, size: 18),
                        ],
                      ),
                    ),
                  );
                }),
              ],
            ),
          );
        }),
        const SizedBox(height: 8),
        if (!_quizSubmitted)
          AppButton(
            label: 'Submit answers',
            onPressed: () => setState(() => _quizSubmitted = true),
          )
        else
          AppButton.secondary(
            label: 'Try again',
            onPressed: () => setState(() {
              _quizAnswers = List.filled(quiz.length, null);
              _quizSubmitted = false;
            }),
          ),
        const SizedBox(height: 12),
        AppButton.secondary(
          label: _addedToFeed ? 'Added to your feed' : 'Add these questions to my feed',
          icon: _addedToFeed ? Icons.check_rounded : Icons.playlist_add_rounded,
          loading: _addingToFeed,
          onPressed: _addedToFeed || _addingToFeed ? null : _addToFeed,
        ),
        const SizedBox(height: 40),
      ],
    );
  }
}
