import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../shared/theme/app_palette.dart';
import '../../../shared/widgets/app_widgets.dart';
import '../../l10n/app_localizations.dart';

/// AdService - Manages ad display and free quiz limits
class AdService {
  static AdService? _instance;
  static const int _freeQuizLimit = 3;
  int _quizCount = 0;
  bool _initialized = false;

  factory AdService() {
    _instance ??= AdService._internal();
    return _instance!;
  }

  AdService._internal();

  Future<void> initialize() async {
    if (_initialized) return;
    final prefs = await SharedPreferences.getInstance();
    _quizCount = prefs.getInt('daily_quiz_count') ?? 0;

    // Reset count if it's a new day
    final lastDate = prefs.getString('last_quiz_date');
    final today = DateTime.now().toIso8601String().split('T').first;
    if (lastDate != today) {
      _quizCount = 0;
      await prefs.setString('last_quiz_date', today);
      await prefs.setInt('daily_quiz_count', 0);
    }
    _initialized = true;
  }

  bool isLimitReached() => _quizCount >= _freeQuizLimit;

  int getRemainingFreeQuizzes() =>
      (_freeQuizLimit - _quizCount).clamp(0, _freeQuizLimit);

  void incrementQuizCount() async {
    _quizCount++;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('daily_quiz_count', _quizCount);
  }

  void showRewardedAd({
    required VoidCallback onRewardEarned,
    required VoidCallback onAdFailed,
  }) {
    // TODO: Integrate with google_mobile_ads for production
    // For now, just reward the user
    onRewardEarned();
  }

  bool isFlashcardLimitReached() => false;
  void incrementFlashcardCount() {}
}

/// Shown while a topic is being generated.
class QuizGenerationLoadingScreen extends StatelessWidget {
  final String? title;
  final String? subtitle;

  const QuizGenerationLoadingScreen({super.key, this.title, this.subtitle});

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final text = Theme.of(context).textTheme;

    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const SizedBox(
                width: 56,
                height: 56,
                child: CircularProgressIndicator(strokeWidth: 4),
              ),
              const SizedBox(height: 28),
              Text(title ?? 'Generating...', textAlign: TextAlign.center, style: text.headlineSmall),
              const SizedBox(height: 8),
              Text(
                subtitle ?? 'AI is crafting questions for you',
                textAlign: TextAlign.center,
                style: text.bodyMedium!.copyWith(color: p.textMuted),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

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
