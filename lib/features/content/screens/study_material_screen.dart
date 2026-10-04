import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../../../shared/theme/app_palette.dart';
import '../../../shared/widgets/app_widgets.dart';
import '../services/study_material_service.dart';

class StudyMaterialScreen extends StatefulWidget {
  final StudyMaterial material;

  const StudyMaterialScreen({super.key, required this.material});

  @override
  State<StudyMaterialScreen> createState() => _StudyMaterialScreenState();
}

class _StudyMaterialScreenState extends State<StudyMaterialScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  int _currentFlashcard = 0;
  bool _isFlipped = false;

  // Mini quiz state
  List<int?> _quizAnswers = [];
  bool _quizSubmitted = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _quizAnswers = List.filled(widget.material.quiz.length, null);
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
              overflow: TextOverflow.ellipsis,
            ),
            Text('Study Set', style: textTheme.labelSmall!.copyWith(color: p.accentText)),
          ],
        ),
        bottom: TabBar(
          controller: _tabController,
          labelStyle: textTheme.labelLarge!.copyWith(fontSize: 13, fontWeight: FontWeight.w800),
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
              Text('Key Concepts', style: textTheme.titleSmall!.copyWith(color: p.accentText)),
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
          ).animate().fadeIn(duration: 200.ms);
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
      return Center(child: Text('No flashcards', style: textTheme.bodyMedium!.copyWith(color: p.textMuted)));
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
                        label: 'Definition',
                        isBack: true,
                      )
                    : _flashcardFace(
                        key: const ValueKey('front'),
                        text: cards[_currentFlashcard]['front'] as String? ?? '',
                        label: 'Concept',
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
                  label: '← Prev',
                  onPressed: _currentFlashcard > 0
                      ? () => setState(() { _currentFlashcard--; _isFlipped = false; })
                      : null,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: AppButton(
                  label: 'Next →',
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
                  style: textTheme.titleMedium!.copyWith(fontSize: 18, height: 1.5),
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

  // ── PRACTICE QUIZ TAB ────────────────────────────────────────────────────

  Widget _buildPracticeTab() {
    final p = context.palette;
    final textTheme = Theme.of(context).textTheme;
    final quiz = widget.material.quiz;

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
          final correctAnswer = q['correctAnswer'] as int? ?? 0;
          final options = (q['options'] as List<dynamic>? ?? []).map((e) => e.toString()).toList();

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
          ).animate().fadeIn(duration: 200.ms);
        }),
        const SizedBox(height: 8),
        if (!_quizSubmitted)
          AppButton(
            label: 'Submit Answers',
            onPressed: () => setState(() => _quizSubmitted = true),
          )
        else
          AppButton.secondary(
            label: 'Try Again',
            onPressed: () => setState(() {
              _quizAnswers = List.filled(quiz.length, null);
              _quizSubmitted = false;
            }),
          ),
        const SizedBox(height: 40),
      ],
    );
  }
}
