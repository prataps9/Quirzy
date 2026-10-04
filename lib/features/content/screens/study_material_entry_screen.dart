import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/content_providers.dart';
import '../../../shared/theme/app_palette.dart';
import '../../../shared/widgets/app_widgets.dart';
import 'study_material_screen.dart';

class StudyMaterialEntryScreen extends ConsumerStatefulWidget {
  const StudyMaterialEntryScreen({super.key});

  @override
  ConsumerState<StudyMaterialEntryScreen> createState() => _StudyMaterialEntryScreenState();
}

class _StudyMaterialEntryScreenState extends ConsumerState<StudyMaterialEntryScreen> {
  final _topicCtrl = TextEditingController();
  final _notesCtrl = TextEditingController();
  bool _showNotes = false;
  bool _isGenerating = false;

  @override
  void dispose() {
    _topicCtrl.dispose();
    _notesCtrl.dispose();
    super.dispose();
  }

  Future<void> _generate() async {
    final topic = _topicCtrl.text.trim();
    if (topic.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a topic')),
      );
      return;
    }

    setState(() => _isGenerating = true);

    try {
      final service = ref.read(studyMaterialServiceProvider);
      final material = await service.generateStudyMaterial(
        topic: topic,
        studyNotes: _showNotes && _notesCtrl.text.trim().isNotEmpty ? _notesCtrl.text.trim() : null,
      );

      if (mounted) {
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => StudyMaterialScreen(material: material)),
        );
      }
    } catch (e) {
      if (mounted) {
        final p = context.palette;
        final isLimit = e.toString().contains('daily_limit');
        final msg = e.toString().contains('daily_limit_reached')
            ? 'Daily limit reached (1 free/day). Upgrade to Pro for unlimited!'
            : 'Failed to generate: $e';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                Icon(
                  isLimit ? Icons.info_outline_rounded : Icons.error_outline_rounded,
                  color: isLimit ? p.accentText : p.danger,
                ),
                const SizedBox(width: 12),
                Expanded(child: Text(msg)),
              ],
            ),
            action: isLimit ? SnackBarAction(label: 'Upgrade', onPressed: () {}) : null,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isGenerating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final textTheme = Theme.of(context).textTheme;

    final historyAsync = ref.watch(studyMaterialHistoryProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Study Set Generator')),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Banner
                    AppCard(
                      radius: AppRadius.control,
                      child: Row(
                        children: [
                          Icon(Icons.menu_book_rounded, color: p.accentText, size: 32),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('AI Study Set', style: textTheme.titleSmall),
                                Text('Get Summary + Flashcards + Quiz', style: textTheme.bodySmall),
                              ],
                            ),
                          ),
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: p.accent,
                              borderRadius: BorderRadius.circular(AppRadius.pill),
                            ),
                            child: Text(
                              '1 FREE/DAY',
                              style: textTheme.labelSmall!.copyWith(
                                fontSize: 10,
                                fontWeight: FontWeight.w800,
                                color: p.onAccent,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 24),

                    // Topic input
                    Text('Topic', style: textTheme.titleSmall),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _topicCtrl,
                      decoration: InputDecoration(
                        hintText: 'e.g. "Newton\'s Laws of Motion", "Photosynthesis", "French Revolution"',
                        suffixIcon: Icon(Icons.search_rounded, color: p.textMuted),
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Optional notes toggle
                    GestureDetector(
                      onTap: () => setState(() => _showNotes = !_showNotes),
                      child: Row(
                        children: [
                          Icon(_showNotes ? Icons.expand_less : Icons.expand_more, color: p.accentText, size: 20),
                          const SizedBox(width: 4),
                          Expanded(
                            child: Text(
                              _showNotes ? 'Hide study notes' : 'Add your study notes (optional)',
                              style: textTheme.labelLarge!.copyWith(color: p.accentText),
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (_showNotes) ...[
                      const SizedBox(height: 8),
                      TextField(
                        controller: _notesCtrl,
                        maxLines: 8,
                        style: textTheme.bodyMedium,
                        decoration: const InputDecoration(
                          hintText: 'Paste your notes here for more targeted content...',
                        ),
                      ),
                    ],
                    const SizedBox(height: 24),

                    // Recent history
                    Text('Recent Study Sets', style: textTheme.titleSmall),
                    const SizedBox(height: 12),
                    historyAsync.when(
                      data: (history) {
                        if (history.isEmpty) {
                          return AppCard(
                            radius: AppRadius.control,
                            child: Center(
                              child: Text('No study sets yet', style: textTheme.bodyMedium!.copyWith(color: p.textMuted)),
                            ),
                          );
                        }
                        return Column(
                          children: history.take(5).map((m) => Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: AppCard(
                              radius: AppRadius.control,
                              padding: const EdgeInsets.all(14),
                              onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => StudyMaterialScreen(material: m))),
                              child: Row(
                                children: [
                                  Icon(Icons.menu_book_outlined, color: p.accentText, size: 20),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Text(m.topic, style: textTheme.titleSmall),
                                  ),
                                  Icon(Icons.chevron_right, color: p.textMuted, size: 18),
                                ],
                              ),
                            ),
                          )).toList(),
                        );
                      },
                      loading: () => const Center(child: CircularProgressIndicator()),
                      error: (_, _) => const SizedBox(),
                    ),
                    const SizedBox(height: 24),
                  ],
                ),
              ),
            ),

            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
              child: AppButton(
                label: 'Generate Study Set',
                icon: Icons.auto_awesome,
                loading: _isGenerating,
                onPressed: _generate,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
