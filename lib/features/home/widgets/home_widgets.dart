import 'package:flutter/material.dart';

import '../../../shared/theme/app_palette.dart';
import '../../../shared/widgets/app_widgets.dart';
import '../../l10n/app_localizations.dart';

/// Bottom sheet to pick how many questions and how hard before generating.
class QuizConfigSheet extends StatefulWidget {
  final String topic;
  final Function(int count, String difficulty) onGenerate;

  const QuizConfigSheet({
    super.key,
    required this.topic,
    required this.onGenerate,
  });

  @override
  State<QuizConfigSheet> createState() => _QuizConfigSheetState();
}

class _QuizConfigSheetState extends State<QuizConfigSheet> {
  int _questionCount = 10;
  String _difficulty = 'Medium';
  final List<String> _difficulties = ['Easy', 'Medium', 'Hard'];
  final List<int> _counts = [5, 10, 15, 20];

  String _localizedDifficulty(AppLocalizations l, String difficulty) {
    switch (difficulty) {
      case 'Easy':
        return l.difficultyEasy;
      case 'Medium':
        return l.difficultyMedium;
      case 'Hard':
        return l.difficultyHard;
      default:
        return difficulty;
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final p = context.palette;
    final text = Theme.of(context).textTheme;

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(24, 12, 24, 16 + MediaQuery.of(context).viewInsets.bottom),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(color: p.border, borderRadius: BorderRadius.circular(AppRadius.pill)),
              ),
            ),
            const SizedBox(height: 20),
            Text(l.configureQuizTitle, style: text.headlineSmall),
            const SizedBox(height: 6),
            Text('${l.topicLabel}: ${widget.topic}', style: text.bodyMedium!.copyWith(color: p.textMuted)),
            const SizedBox(height: 24),
            Text(l.difficultyLabel, style: text.titleSmall),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: SegmentedButton<String>(
                showSelectedIcon: false,
                segments: [
                  for (final d in _difficulties)
                    ButtonSegment<String>(value: d, label: Text(_localizedDifficulty(l, d))),
                ],
                selected: {_difficulty},
                onSelectionChanged: (selection) => setState(() => _difficulty = selection.first),
              ),
            ),
            const SizedBox(height: 20),
            Text(l.questionCountLabel, style: text.titleSmall),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: SegmentedButton<int>(
                showSelectedIcon: false,
                segments: [
                  for (final c in _counts) ButtonSegment<int>(value: c, label: Text('$c')),
                ],
                selected: {_questionCount},
                onSelectionChanged: (selection) => setState(() => _questionCount = selection.first),
              ),
            ),
            const SizedBox(height: 28),
            AppButton(
              label: l.startGeneratingButton,
              icon: Icons.auto_awesome_rounded,
              onPressed: () => widget.onGenerate(_questionCount, _difficulty),
            ),
          ],
        ),
      ),
    );
  }
}
