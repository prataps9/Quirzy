import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_staggered_grid_view/flutter_staggered_grid_view.dart';
import '../../../shared/providers/exam_provider.dart';
import '../../../shared/theme/app_palette.dart';
import '../../../shared/widgets/app_widgets.dart';

class ExamSelectionScreen extends ConsumerStatefulWidget {
  const ExamSelectionScreen({super.key});

  @override
  ConsumerState<ExamSelectionScreen> createState() =>
      _ExamSelectionScreenState();
}

class _ExamSelectionScreenState extends ConsumerState<ExamSelectionScreen> {
  String? _selectedExam;

  final List<Map<String, dynamic>> _exams = [
    {'id': 'mba', 'name': 'MBA', 'icon': '💼'},
    {'id': 'cat', 'name': 'CAT', 'icon': '📊'},
    {'id': 'cuet', 'name': 'CUET', 'icon': '🎓'},
    {'id': 'jee', 'name': 'JEE', 'icon': '⚙️'},
    {'id': 'neet', 'name': 'NEET', 'icon': '⚕️'},
    {'id': '10th', 'name': '10th Board', 'icon': '🔟'},
    {'id': '12th', 'name': '12th Board', 'icon': '🏫'},
    {'id': 'ielts', 'name': 'IELTS', 'icon': '🌏'},
    {'id': 'gre', 'name': 'GRE', 'icon': '📈'},
    {'id': 'gmat', 'name': 'GMAT', 'icon': '📉'},
  ];

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final textTheme = Theme.of(context).textTheme;

    return Scaffold(
      backgroundColor: p.bg,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 20),
              Text(
                'Prepare for Success 🎯',
                style: textTheme.headlineLarge!.copyWith(color: p.text),
              ),
              const SizedBox(height: 8),
              Text(
                'Which exam are you targeting?',
                style: textTheme.bodyLarge!.copyWith(color: p.textMuted),
              ),
              const SizedBox(height: 32),

              Expanded(
                child: MasonryGridView.count(
                  crossAxisCount: 2,
                  mainAxisSpacing: 16,
                  crossAxisSpacing: 16,
                  itemCount: _exams.length,
                  itemBuilder: (context, index) {
                    final exam = _exams[index];
                    final isSelected = _selectedExam == exam['id'];

                    return AppCard(
                      color: isSelected ? p.accentSoft : p.surface,
                      borderColor: isSelected ? p.accentText : p.border,
                      onTap: () {
                        setState(() {
                          _selectedExam = exam['id'];
                        });
                      },
                      child: Column(
                        children: [
                          Text(
                            exam['icon'],
                            style: const TextStyle(fontSize: 40),
                          ),
                          const SizedBox(height: 12),
                          Text(
                            exam['name'],
                            style: textTheme.titleMedium!.copyWith(
                              color: p.text,
                            ),
                            textAlign: TextAlign.center,
                          ),
                          if (isSelected) ...[
                            const SizedBox(height: 8),
                            Icon(
                              Icons.check_circle_rounded,
                              color: p.accentText,
                              size: 20,
                            ),
                          ],
                        ],
                      ),
                    );
                  },
                ),
              ),

              const SizedBox(height: 24),
              AppButton(
                label: 'Start Preparing',
                onPressed: _selectedExam != null
                    ? () {
                        ref.read(examProvider.notifier).setExam(_selectedExam!);
                        Navigator.of(
                          context,
                        ).pop(); // Go back to Main/Home assuming it was pushed
                        // OR if it's the root, we might need to navigate differently.
                        // For now, let's assume MainScreen will redirect here if needed, and popping returns.
                        // IF we are replacing MainScreen, we should use go_router or pushReplacement.
                        // I'll stick to pop if pushed. If checking in MainScreen, MainScreen stays in stack?
                        // Actually, if prompted from MainScreen, popping works.
                      }
                    : null,
              ),
              const SizedBox(height: 12),
            ],
          ),
        ),
      ),
    );
  }
}
