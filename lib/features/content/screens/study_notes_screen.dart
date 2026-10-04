import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/content_providers.dart';
import '../../feed/providers/feed_providers.dart';
import '../../feed/services/practice_content_service.dart';
import '../../../shared/providers/providers.dart';
import '../../../shared/services/connectivity_service.dart';
import '../../home/widgets/home_widgets.dart';
import '../../../shared/theme/app_palette.dart';
import '../../../shared/widgets/app_widgets.dart';

class StudyNotesScreen extends ConsumerStatefulWidget {
  const StudyNotesScreen({super.key});

  @override
  ConsumerState<StudyNotesScreen> createState() => _StudyNotesScreenState();
}

class _StudyNotesScreenState extends ConsumerState<StudyNotesScreen> {
  final _notesController = TextEditingController();
  int _questionCount = 10;
  String _difficulty = 'medium';

  static const _counts = [5, 10, 15, 20];
  static const _difficulties = ['easy', 'medium', 'hard'];

  @override
  void dispose() {
    _notesController.dispose();
    super.dispose();
  }

  Future<void> _generate() async {
    final notes = _notesController.text.trim();
    if (notes.length < 100) {
      _showError('Please enter at least 100 characters of notes (${notes.length}/100)');
      return;
    }

    final isOnline = await ref.read(connectivityServiceProvider).checkIsOnline();
    if (!isOnline) {
      if (mounted) {
        _showError('You\'re offline — connect to the internet to generate questions.');
      }
      return;
    }

    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const QuizGenerationLoadingScreen()),
    );

    try {
      final service = ref.read(studyQuizServiceProvider);
      final result = await service.generateQuizFromNotes(
        studyNotes: notes,
        questionCount: _questionCount,
        difficulty: _difficulty,
      );

      final quizTitle = result['title']?.toString() ?? 'Study Notes';
      final questions = List<Map<String, dynamic>>.from(result['questions'] ?? []);

      await ref.read(practiceContentServiceProvider).addToQuestionPool(
            questions,
            topicId: result['quizId']?.toString() ?? '',
            topic: quizTitle,
          );
      await ref.read(feedControllerProvider.notifier).switchToTopic(quizTitle);

      if (mounted) {
        Navigator.pop(context); // dismiss loading
        Navigator.pop(context); // back out of this screen
        ref.read(tabIndexProvider.notifier).state = 0; // Practice tab
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Added ${questions.length} questions to your feed')),
        );
      }
    } catch (e) {
      if (mounted) {
        Navigator.pop(context); // dismiss loading
        _showError('Failed to generate: $e');
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

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final textTheme = Theme.of(context).textTheme;

    final charCount = _notesController.text.length;
    final hasEnough = charCount >= 100;

    return Scaffold(
      appBar: AppBar(title: const Text('Study Notes → Practice')),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Info banner
                    AppCard(
                      radius: AppRadius.control,
                      child: Row(
                        children: [
                          Icon(Icons.auto_awesome, color: p.accentText, size: 20),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              'Paste your study notes, lecture text, or any content — AI will turn it into practice questions for your feed.',
                              style: textTheme.bodySmall,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),

                    // Notes input
                    Text('Study Notes', style: textTheme.titleSmall),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _notesController,
                      maxLines: 12,
                      style: textTheme.bodyMedium,
                      decoration: InputDecoration(
                        hintText: 'Paste your notes here...\n\nExample: "Photosynthesis is the process by which plants use sunlight, water, and carbon dioxide to produce oxygen and energy in the form of glucose..."',
                        enabledBorder: hasEnough
                            ? OutlineInputBorder(
                                borderRadius: BorderRadius.circular(AppRadius.control),
                                borderSide: BorderSide(color: p.accentText, width: 1.5),
                              )
                            : null,
                      ),
                      onChanged: (_) => setState(() {}),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: Text(
                            hasEnough ? 'Ready to generate' : '${100 - charCount} more characters needed',
                            style: textTheme.labelMedium!.copyWith(
                              color: hasEnough ? p.success : p.streak,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text('$charCount chars', style: textTheme.bodySmall),
                      ],
                    ),
                    const SizedBox(height: 24),

                    // Question count selector
                    Text('Number of Questions', style: textTheme.titleSmall),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        for (var i = 0; i < _counts.length; i++) ...[
                          if (i > 0) const SizedBox(width: 8),
                          Expanded(
                            child: _SelectPill(
                              label: '${_counts[i]}',
                              selected: _counts[i] == _questionCount,
                              onTap: () => setState(() => _questionCount = _counts[i]),
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 20),

                    // Difficulty selector
                    Text('Difficulty', style: textTheme.titleSmall),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        for (var i = 0; i < _difficulties.length; i++) ...[
                          if (i > 0) const SizedBox(width: 8),
                          Expanded(
                            child: _SelectPill(
                              label: _difficulties[i][0].toUpperCase() + _difficulties[i].substring(1),
                              selected: _difficulties[i] == _difficulty,
                              onTap: () => setState(() => _difficulty = _difficulties[i]),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
            ),

            // Generate button
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
              child: AppButton(
                label: 'Add to Feed ($_questionCount Qs)',
                icon: Icons.auto_awesome,
                onPressed: hasEnough ? _generate : null,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A flat selectable pill: lime fill with dark text when selected, a
/// hairline-bordered surface otherwise.
class _SelectPill extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _SelectPill({required this.label, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Semantics(
      button: true,
      selected: selected,
      child: Material(
        color: selected ? p.accent : p.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.chip),
          side: BorderSide(color: selected ? p.accent : p.border),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Text(
              label,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleSmall!.copyWith(
                color: selected ? p.onAccent : p.text,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
