import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../../../shared/theme/app_palette.dart';
import '../../../shared/widgets/app_widgets.dart';

/// FlashcardCacheService - Manages local caching of flashcards
class FlashcardCacheService {
  static Future<void> init() async {
    // Initialize Hive box for flashcard caching
  }
}

/// FlashcardStudyScreen - Screen for studying flashcards
class FlashcardStudyScreen extends StatefulWidget {
  final String setId;
  final String title;
  final List<Map<String, dynamic>> cards;

  const FlashcardStudyScreen({
    super.key,
    required this.setId,
    required this.title,
    required this.cards,
  });

  @override
  State<FlashcardStudyScreen> createState() => _FlashcardStudyScreenState();
}

class _FlashcardStudyScreenState extends State<FlashcardStudyScreen> {
  int _currentIndex = 0;
  bool _showAnswer = false;
  int _knownCount = 0;
  int _unknownCount = 0;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final textTheme = Theme.of(context).textTheme;
    final card = widget.cards.isNotEmpty
        ? widget.cards[_currentIndex]
        : {'front': 'No cards', 'back': ''};

    return Scaffold(
      appBar: AppBar(title: Text(widget.title)),
      body: widget.cards.isEmpty
          ? const Center(child: Text('No cards in this set'))
          : Padding(
              padding: const EdgeInsets.all(AppSpace.xl),
              child: Column(
                children: [
                  // Progress
                  Text(
                    'Card ${_currentIndex + 1} of ${widget.cards.length}',
                    style: textTheme.bodyMedium!.copyWith(color: p.textMuted),
                  ),
                  const SizedBox(height: AppSpace.sm),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(AppRadius.pill),
                    child: LinearProgressIndicator(
                      value: (_currentIndex + 1) / widget.cards.length,
                      minHeight: 6,
                    ),
                  ),
                  const SizedBox(height: AppSpace.xxl),

                  // Card
                  Expanded(
                    child: GestureDetector(
                      onTap: () => setState(() => _showAnswer = !_showAnswer),
                      child: AnimatedSwitcher(
                        duration: const Duration(milliseconds: 200),
                        child: AppCard(
                          key: ValueKey(_showAnswer),
                          padding: const EdgeInsets.all(AppSpace.xl),
                          child: SizedBox(
                            width: double.infinity,
                            child: Column(
                              children: [
                                Expanded(
                                  child: Center(
                                    child: SingleChildScrollView(
                                      child: Column(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Text(
                                            _showAnswer ? 'Answer' : 'Question',
                                            style: textTheme.labelMedium!.copyWith(
                                              color: p.accentText,
                                            ),
                                          ),
                                          const SizedBox(height: AppSpace.lg),
                                          Text(
                                            _showAnswer
                                                ? card['back'] ?? ''
                                                : card['front'] ?? '',
                                            textAlign: TextAlign.center,
                                            style: textTheme.titleLarge!.copyWith(
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                                Text(
                                  'Tap to flip',
                                  style: textTheme.bodySmall,
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),

                  const SizedBox(height: AppSpace.xl),

                  // Action buttons
                  if (_showAnswer)
                    Column(
                      children: [
                        AppButton(
                          label: 'Got It!',
                          icon: Icons.check_rounded,
                          onPressed: () => _nextCard(true),
                        ),
                        const SizedBox(height: AppSpace.md),
                        AppButton.secondary(
                          label: 'Still Learning',
                          icon: Icons.close_rounded,
                          onPressed: () => _nextCard(false),
                        ),
                      ],
                    ).animate().fade(duration: 200.ms).slideY(
                          begin: 0.1,
                          end: 0,
                          duration: 200.ms,
                        ),
                ],
              ),
            ),
    );
  }

  void _nextCard(bool known) {
    if (known) {
      _knownCount++;
    } else {
      _unknownCount++;
    }

    if (_currentIndex < widget.cards.length - 1) {
      setState(() {
        _currentIndex++;
        _showAnswer = false;
      });
    } else {
      // Show completion dialog
      _showCompletionDialog();
    }
  }

  void _showCompletionDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Session Complete! 🎉'),
        content: Text('Known: $_knownCount\nStill Learning: $_unknownCount'),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              Navigator.pop(context);
            },
            child: const Text('Done'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              setState(() {
                _currentIndex = 0;
                _showAnswer = false;
                _knownCount = 0;
                _unknownCount = 0;
              });
            },
            child: const Text('Study Again'),
          ),
        ],
      ),
    );
  }
}

/// ShimmerPlaceholders - Flat loading placeholders for lists
class ShimmerPlaceholders {
  static Widget historyList({int itemCount = 3}) {
    return Column(
      children: List.generate(
        itemCount,
        (index) => const _SkeletonBox(height: 80, radius: AppRadius.control),
      ),
    );
  }

  static Widget flashcardSets({int itemCount = 3}) {
    return Column(
      children: List.generate(
        itemCount,
        (index) => const _SkeletonBox(height: 120, radius: AppRadius.card),
      ),
    );
  }
}

/// A plain, static placeholder block.
class _SkeletonBox extends StatelessWidget {
  final double height;
  final double radius;

  const _SkeletonBox({required this.height, required this.radius});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: AppSpace.md),
      height: height,
      decoration: BoxDecoration(
        color: context.palette.surfaceHigh,
        borderRadius: BorderRadius.circular(radius),
      ),
    );
  }
}
