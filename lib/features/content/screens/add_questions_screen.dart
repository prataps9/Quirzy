import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/content_providers.dart';
import '../../feed/providers/feed_providers.dart';
import '../../feed/services/practice_content_service.dart';
import '../../../shared/providers/providers.dart';
import '../../../shared/services/connectivity_service.dart';
import '../../../shared/theme/app_palette.dart';
import '../../../shared/widgets/app_widgets.dart';

class _QuestionData {
  final TextEditingController questionCtrl = TextEditingController();
  final List<TextEditingController> optionCtrls = List.generate(4, (_) => TextEditingController());
  int correctAnswer = 0;

  void dispose() {
    questionCtrl.dispose();
    for (final c in optionCtrls) {
      c.dispose();
    }
  }
}

/// Manual "add your own questions" flow — no AI, saves straight into the
/// practice feed (and to Appwrite for durability), no linear quiz UI.
class AddQuestionsScreen extends ConsumerStatefulWidget {
  const AddQuestionsScreen({super.key});

  @override
  ConsumerState<AddQuestionsScreen> createState() => _AddQuestionsScreenState();
}

class _AddQuestionsScreenState extends ConsumerState<AddQuestionsScreen> {
  final _titleCtrl = TextEditingController();
  final List<_QuestionData> _questions = [];
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _addQuestion();
    _addQuestion();
    _addQuestion();
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    for (final q in _questions) {
      q.dispose();
    }
    super.dispose();
  }

  void _addQuestion() {
    setState(() => _questions.add(_QuestionData()));
  }

  void _removeQuestion(int index) {
    if (_questions.length <= 3) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Minimum 3 questions required')),
      );
      return;
    }
    setState(() {
      _questions[index].dispose();
      _questions.removeAt(index);
    });
  }

  Future<void> _save() async {
    final title = _titleCtrl.text.trim();
    if (title.isEmpty) {
      _showError('Please enter a topic title');
      return;
    }

    for (int i = 0; i < _questions.length; i++) {
      final q = _questions[i];
      if (q.questionCtrl.text.trim().isEmpty) {
        _showError('Question ${i + 1} text is empty');
        return;
      }
      for (int j = 0; j < 4; j++) {
        if (q.optionCtrls[j].text.trim().isEmpty) {
          _showError('Question ${i + 1}: Option ${String.fromCharCode(65 + j)} is empty');
          return;
        }
      }
    }

    final isOnline = await ref.read(connectivityServiceProvider).checkIsOnline();
    if (!isOnline) {
      if (mounted) _showError('You\'re offline — connect to the internet to save this topic.');
      return;
    }

    setState(() => _isSaving = true);

    try {
      final contentService = ref.read(contentServiceProvider);
      final questionsData = _questions.map((q) => {
        'questionText': q.questionCtrl.text.trim(),
        'options': q.optionCtrls.map((c) => c.text.trim()).toList(),
        'correctAnswer': q.correctAnswer,
      }).toList();

      final result = await contentService.addManualQuestions(
        title: title,
        questions: questionsData,
      );

      final quizTitle = result['title']?.toString() ?? title;
      final questions = List<Map<String, dynamic>>.from(result['questions'] ?? []);

      await ref.read(practiceContentServiceProvider).addToQuestionPool(
            questions,
            topicId: result['quizId']?.toString() ?? '',
            topic: quizTitle,
          );
      await ref.read(feedControllerProvider.notifier).switchToTopic(quizTitle);

      if (mounted) {
        Navigator.pop(context);
        ref.read(tabIndexProvider.notifier).state = 0; // Practice tab
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Added ${questions.length} questions to your feed')),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isSaving = false);
        _showError('Failed to save: $e');
      }
    }
  }

  void _showError(String msg) {
    final p = context.palette;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(Icons.error_outline_rounded, color: p.danger),
            const SizedBox(width: 12),
            Expanded(child: Text(msg)),
          ],
        ),
      ),
    );
  }

  OutlineInputBorder _fieldBorder(Color color, {double width = 1.5}) {
    return OutlineInputBorder(
      borderRadius: BorderRadius.circular(AppRadius.chip),
      borderSide: BorderSide(color: color, width: width),
    );
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Scaffold(
      appBar: AppBar(title: const Text('Add Your Own Questions')),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: ListView(
                padding: const EdgeInsets.all(20),
                children: [
                  // Title field
                  Text('Topic Title', style: textTheme.titleSmall),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _titleCtrl,
                    decoration: const InputDecoration(
                      hintText: 'e.g. "Chapter 5: Cell Biology"',
                    ),
                  ),
                  const SizedBox(height: 24),

                  // Questions
                  ...List.generate(_questions.length, _buildQuestionCard),

                  // Add question button
                  const SizedBox(height: 8),
                  AppButton.secondary(
                    label: 'Add Question',
                    icon: Icons.add_circle_outline,
                    onPressed: _addQuestion,
                  ),
                  const SizedBox(height: 8),
                ],
              ),
            ),

            // Save button
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
              child: AppButton(
                label: 'Add to Feed',
                loading: _isSaving,
                onPressed: _save,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildQuestionCard(int index) {
    final p = context.palette;
    final textTheme = Theme.of(context).textTheme;
    final q = _questions[index];

    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: AppCard(
        padding: const EdgeInsets.all(16),
        radius: AppRadius.control,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 28,
                  height: 28,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(color: p.accent, shape: BoxShape.circle),
                  child: Text(
                    '${index + 1}',
                    style: textTheme.labelMedium!.copyWith(
                      color: p.onAccent,
                      fontWeight: FontWeight.w800,
                      fontSize: 13,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Text('Question', style: textTheme.titleSmall),
                const Spacer(),
                if (_questions.length > 3)
                  IconButton(
                    icon: Icon(Icons.delete_outline, color: p.danger, size: 20),
                    onPressed: () => _removeQuestion(index),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            TextField(
              controller: q.questionCtrl,
              maxLines: 2,
              style: textTheme.bodyMedium,
              decoration: InputDecoration(
                hintText: 'Enter your question...',
                fillColor: p.surfaceHigh,
                border: _fieldBorder(p.border),
                enabledBorder: _fieldBorder(p.border),
                focusedBorder: _fieldBorder(p.accentText, width: 2),
                contentPadding: const EdgeInsets.all(12),
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'Options (tap radio to mark correct answer)',
              style: textTheme.bodySmall,
            ),
            const SizedBox(height: 8),
            ...List.generate(4, (j) {
              final label = String.fromCharCode(65 + j);
              final isCorrect = q.correctAnswer == j;
              return Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  children: [
                    IconButton(
                      isSelected: isCorrect,
                      visualDensity: VisualDensity.compact,
                      icon: Icon(Icons.radio_button_unchecked_rounded, color: p.textMuted),
                      selectedIcon: Icon(Icons.check_circle_rounded, color: p.accentText),
                      onPressed: () => setState(() => q.correctAnswer = j),
                    ),
                    Expanded(
                      child: TextField(
                        controller: q.optionCtrls[j],
                        style: textTheme.bodyMedium!.copyWith(
                          fontWeight: isCorrect ? FontWeight.w700 : FontWeight.w500,
                        ),
                        decoration: InputDecoration(
                          hintText: 'Option $label',
                          fillColor: isCorrect ? p.accentSoft : p.surfaceHigh,
                          border: _fieldBorder(isCorrect ? p.accentText : p.border),
                          enabledBorder: _fieldBorder(isCorrect ? p.accentText : p.border),
                          focusedBorder: _fieldBorder(p.accentText, width: 2),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                        ),
                        onChanged: (_) => setState(() {}),
                      ),
                    ),
                  ],
                ),
              );
            }),
          ],
        ),
      ),
    );
  }
}
