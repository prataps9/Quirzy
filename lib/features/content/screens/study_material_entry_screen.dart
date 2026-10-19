import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/content_providers.dart';
import '../../../shared/theme/app_palette.dart';
import '../../../shared/utils/user_messages.dart';
import '../../../shared/widgets/app_widgets.dart';
import '../../../shared/widgets/generation_loading.dart';
import '../services/study_material_service.dart';
import '../../subscription/services/usage_limits.dart';
import '../../subscription/widgets/limit_sheet.dart';
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

  @override
  void dispose() {
    _topicCtrl.dispose();
    _notesCtrl.dispose();
    super.dispose();
  }

  Future<void> _generate() async {
    final topic = _topicCtrl.text.trim();
    if (topic.isEmpty) {
      showAppSnack(context, 'Enter a topic to build a study set.');
      return;
    }
    FocusScope.of(context).unfocus();

    final usage = ref.read(usageLimitsProvider.notifier);
    if (!await usage.canUse(UsageKind.studySet)) {
      if (mounted) showLimitSheet(context, UsageKind.studySet);
      return;
    }
    if (!mounted) return;

    final notes = _showNotes && _notesCtrl.text.trim().isNotEmpty ? _notesCtrl.text.trim() : null;
    try {
      final material = await runWithLoadingScreen<StudyMaterial>(
        context,
        title: 'Building your study set…',
        subtitle: 'A summary, cards and practice questions on $topic.',
        task: () async {
          final material = await ref.read(studyMaterialServiceProvider).generateStudyMaterial(
                topic: topic,
                studyNotes: notes,
              );
          if (material.summary.isEmpty && material.flashcards.isEmpty && material.quiz.isEmpty) {
            throw const UserFacingException('Nothing came back — try a broader topic.');
          }
          await usage.record(UsageKind.studySet);
          return material;
        },
      );
      // The new set is saved server-side; refetch so it shows under Recent.
      ref.invalidate(studyMaterialHistoryProvider);

      if (!mounted) return;
      Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => StudyMaterialScreen(material: material)),
      );
    } catch (e) {
      if (!mounted || isCancellation(e)) return;
      showAppSnack(context, friendlyError(e), onRetry: _generate);
    }
  }

  Widget _buildHistoryError() {
    final p = context.palette;
    final textTheme = Theme.of(context).textTheme;
    return AppCard(
      radius: AppRadius.control,
      padding: const EdgeInsets.fromLTRB(14, 10, 4, 10),
      child: Row(
        children: [
          Icon(Icons.cloud_off_rounded, color: p.textMuted, size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              "Couldn't load your recent study sets.",
              style: textTheme.bodyMedium!.copyWith(color: p.textMuted),
            ),
          ),
          TextButton(
            onPressed: () => ref.invalidate(studyMaterialHistoryProvider),
            child: const Text('Retry'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final textTheme = Theme.of(context).textTheme;

    final historyAsync = ref.watch(studyMaterialHistoryProvider);
    final isPro = ref.watch(proStatusProvider).isPro;

    return Scaffold(
      appBar: AppBar(title: const Text('Study set generator')),
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
                                Text('Study set', style: textTheme.titleSmall),
                                Text('A summary, flashcards and practice questions', style: textTheme.bodySmall),
                              ],
                            ),
                          ),
                          if (!isPro) ...[
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(
                                color: p.accent,
                                borderRadius: BorderRadius.circular(AppRadius.pill),
                              ),
                              child: Text(
                                '${UsageKind.studySet.freePerDay} free a day',
                                style: textTheme.labelSmall!.copyWith(
                                  fontWeight: FontWeight.w800,
                                  color: p.onAccent,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(height: 24),

                    // Topic input
                    Text('Topic', style: textTheme.titleSmall),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _topicCtrl,
                      textInputAction: TextInputAction.done,
                      onSubmitted: (_) => _generate(),
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
                          hintText: 'Paste your notes here for more targeted content…',
                        ),
                      ),
                    ],
                    const SizedBox(height: 24),

                    // Recent history
                    Text('Recent study sets', style: textTheme.titleSmall),
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
                                    child: Text(m.topic, style: textTheme.titleSmall, maxLines: 1, overflow: TextOverflow.ellipsis),
                                  ),
                                  Icon(Icons.chevron_right, color: p.textMuted, size: 18),
                                ],
                              ),
                            ),
                          )).toList(),
                        );
                      },
                      loading: () => const Center(child: CircularProgressIndicator()),
                      error: (_, _) => _buildHistoryError(),
                    ),
                    const SizedBox(height: 24),
                  ],
                ),
              ),
            ),

            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
              child: AppButton(
                label: 'Generate study set',
                icon: Icons.auto_awesome,
                onPressed: _generate,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
