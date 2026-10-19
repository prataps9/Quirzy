import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../shared/providers/exam_provider.dart';
import '../../../shared/theme/app_palette.dart';
import '../../../shared/widgets/app_widgets.dart';

/// Picks the exam the feed and suggestions are built around.
///
/// On first run (no exam saved yet) it is a required step: back is blocked
/// and the button says "Continue". Opened later to change the exam, it has
/// a back arrow, starts on the current exam and says "Save".
class ExamSelectionScreen extends ConsumerStatefulWidget {
  const ExamSelectionScreen({super.key});

  @override
  ConsumerState<ExamSelectionScreen> createState() => _ExamSelectionScreenState();
}

class _ExamSelectionScreenState extends ConsumerState<ExamSelectionScreen> {
  static const _exams = <({String id, IconData icon})>[
    (id: 'jee', icon: Icons.precision_manufacturing_rounded),
    (id: 'neet', icon: Icons.medical_services_rounded),
    (id: 'cuet', icon: Icons.school_rounded),
    (id: 'cat', icon: Icons.insights_rounded),
    (id: 'mba', icon: Icons.business_center_rounded),
    (id: 'gmat', icon: Icons.query_stats_rounded),
    (id: 'gre', icon: Icons.trending_up_rounded),
    (id: 'ielts', icon: Icons.translate_rounded),
    (id: '12th', icon: Icons.auto_stories_rounded),
    (id: '10th', icon: Icons.menu_book_rounded),
  ];

  String? _current;
  String? _selectedExam;
  bool _saving = false;

  bool get _isChange => _current != null;

  @override
  void initState() {
    super.initState();
    _current = _selectedExam = ref.read(examProvider);
    // The provider loads from storage asynchronously; don't mistake a change
    // for first run just because it hasn't finished yet.
    if (_current == null) {
      SharedPreferences.getInstance().then((prefs) {
        final saved = prefs.getString('selected_exam');
        if (saved != null && mounted) setState(() => _current = _selectedExam = saved);
      });
    }
  }

  /// Saves the choice and returns to whoever opened this screen.
  /// (Navigator.pop is not blocked by the PopScope below — only back is.)
  Future<void> _save() async {
    setState(() => _saving = true);
    await ref.read(examProvider.notifier).setExam(_selectedExam!);
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final text = Theme.of(context).textTheme;

    return PopScope(
      // Picking an exam is required the first time: the feed is built around it.
      canPop: _isChange,
      child: Scaffold(
        appBar: _isChange ? AppBar(title: const Text('Change exam')) : null,
        body: SafeArea(
          top: !_isChange,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (!_isChange) ...[
                  const SizedBox(height: 12),
                  Text('Which exam are you preparing for?', style: text.headlineMedium),
                  const SizedBox(height: 8),
                  Text(
                    'Your feed, flashcard suggestions and countdown are built around it. You can change it any time.',
                    style: text.bodyMedium!.copyWith(color: p.textMuted),
                  ),
                  const SizedBox(height: 24),
                ],
                Expanded(
                  child: GridView.count(
                    crossAxisCount: 2,
                    mainAxisSpacing: 12,
                    crossAxisSpacing: 12,
                    childAspectRatio: 1.45,
                    children: [
                      for (final exam in _exams)
                        _ExamTile(
                          name: examDisplayName(exam.id),
                          icon: exam.icon,
                          selected: _selectedExam == exam.id,
                          onTap: () {
                            HapticFeedback.selectionClick();
                            setState(() => _selectedExam = exam.id);
                          },
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                AppButton(
                  label: _isChange ? 'Save' : 'Continue',
                  loading: _saving,
                  onPressed: _selectedExam != null && _selectedExam != (_isChange ? _current : null) ? _save : null,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ExamTile extends StatelessWidget {
  final String name;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  const _ExamTile({required this.name, required this.icon, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final text = Theme.of(context).textTheme;
    return Semantics(
      button: true,
      selected: selected,
      label: name,
      child: AppCard(
        padding: const EdgeInsets.all(AppSpace.md),
        color: selected ? p.accentSoft : p.surface,
        borderColor: selected ? p.accentText : p.border,
        onTap: onTap,
        child: Stack(
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Icon(icon, size: 28, color: selected ? p.accentText : p.textMuted),
                Text(name, maxLines: 2, overflow: TextOverflow.ellipsis, style: text.titleMedium),
              ],
            ),
            // Always laid out, so selecting never shifts the grid.
            Positioned(
              top: 0,
              right: 0,
              child: AnimatedOpacity(
                opacity: selected ? 1 : 0,
                duration: const Duration(milliseconds: 150),
                child: Icon(Icons.check_circle_rounded, size: 22, color: p.accentText),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
