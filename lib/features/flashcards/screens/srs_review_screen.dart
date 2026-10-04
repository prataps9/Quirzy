import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../shared/theme/app_palette.dart';
import '../../../shared/widgets/app_widgets.dart';
import '../services/srs_service.dart';

class SrsReviewScreen extends StatefulWidget {
  final String setId;
  final String title;
  final List<Map<String, dynamic>> cards;
  final List<int> dueIndices;

  const SrsReviewScreen({
    super.key,
    required this.setId,
    required this.title,
    required this.cards,
    required this.dueIndices,
  });

  @override
  State<SrsReviewScreen> createState() => _SrsReviewScreenState();
}

class _SrsReviewScreenState extends State<SrsReviewScreen>
    with TickerProviderStateMixin {
  final SrsService _srs = SrsService();

  late List<int> _queue;
  int _queuePos = 0;
  bool _isFlipped = false;
  bool _showingAnswer = false;
  SrsCard? _lastRated;

  late AnimationController _flipCtrl;
  late Animation<double> _flipAnim;
  late AnimationController _slideCtrl;
  late Animation<Offset> _slideAnim;

  @override
  void initState() {
    super.initState();
    _queue = List.from(widget.dueIndices)..shuffle(Random());

    _flipCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 250),
    );
    _flipAnim = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(parent: _flipCtrl, curve: Curves.easeInOut),
    );

    _slideCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 250),
    );
    _slideAnim = Tween<Offset>(
      begin: const Offset(1.2, 0),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _slideCtrl, curve: Curves.easeOutCubic));
    _slideCtrl.forward();
  }

  @override
  void dispose() {
    _flipCtrl.dispose();
    _slideCtrl.dispose();
    super.dispose();
  }

  int get _currentCardIndex => _queue[_queuePos];
  Map<String, dynamic> get _currentCard => widget.cards[_currentCardIndex];

  String get _front =>
      _currentCard['front'] ?? _currentCard['question'] ?? '';
  String get _back =>
      _currentCard['back'] ?? _currentCard['answer'] ?? '';

  void _flip() {
    HapticFeedback.selectionClick();
    if (!_isFlipped) {
      _flipCtrl.forward();
    } else {
      _flipCtrl.reverse();
    }
    setState(() {
      _isFlipped = !_isFlipped;
      _showingAnswer = _isFlipped;
    });
  }

  Future<void> _rate(SrsRating rating) async {
    HapticFeedback.lightImpact();
    final updated = await _srs.rateCard(widget.setId, _currentCardIndex, rating);
    setState(() => _lastRated = updated);

    if (rating == SrsRating.again) {
      // Re-insert near end of queue
      _queue.add(_currentCardIndex);
    }

    if (_queuePos >= _queue.length - 1) {
      _showSessionComplete();
      return;
    }

    setState(() {
      _queuePos++;
      _isFlipped = false;
      _showingAnswer = false;
    });
    _flipCtrl.reset();
    _slideCtrl.reset();
    _slideCtrl.forward();
  }

  void _showSessionComplete() {
    final done = widget.dueIndices.length;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        final p = dialogContext.palette;
        final textTheme = Theme.of(dialogContext).textTheme;
        return Dialog(
          child: Padding(
            padding: const EdgeInsets.all(28),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 72,
                  height: 72,
                  decoration: BoxDecoration(
                    color: p.accent,
                    borderRadius: BorderRadius.circular(AppRadius.card),
                  ),
                  child: Icon(Icons.check_rounded, color: p.onAccent, size: 38),
                ),
                const SizedBox(height: 20),
                Text('Session Complete!', style: textTheme.headlineSmall),
                const SizedBox(height: AppSpace.sm),
                Text(
                  'You reviewed $done card${done != 1 ? 's' : ''}. Come back tomorrow to keep your streak.',
                  textAlign: TextAlign.center,
                  style: textTheme.bodyMedium!.copyWith(color: p.textMuted),
                ),
                const SizedBox(height: AppSpace.xl),
                AppButton(
                  label: 'Done',
                  onPressed: () {
                    Navigator.pop(dialogContext);
                    Navigator.pop(context);
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final textTheme = Theme.of(context).textTheme;

    final remaining = _queue.length - _queuePos;
    final progress = _queue.isEmpty ? 0.0 : _queuePos / _queue.length;

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            // Header
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
              child: Row(
                children: [
                  GestureDetector(
                    onTap: () => Navigator.pop(context),
                    child: Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: p.surface,
                        borderRadius: BorderRadius.circular(AppRadius.chip),
                        border: Border.all(color: p.border),
                      ),
                      child: Icon(Icons.close_rounded, color: p.text, size: 20),
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'SPACED REVIEW',
                          style: textTheme.labelSmall!.copyWith(
                            fontWeight: FontWeight.w800,
                            letterSpacing: 1.5,
                            color: p.accentText,
                          ),
                        ),
                        Text(
                          widget.title,
                          style: textTheme.titleMedium,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  // Due count badge
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: p.accentSoft,
                      borderRadius: BorderRadius.circular(AppRadius.pill),
                    ),
                    child: Text(
                      '$remaining left',
                      style: textTheme.labelMedium!.copyWith(color: p.accentText),
                    ),
                  ),
                ],
              ),
            ),

            // Progress bar
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(AppRadius.pill),
                child: LinearProgressIndicator(value: progress, minHeight: 6),
              ),
            ),

            const SizedBox(height: 24),

            // Card area
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: SlideTransition(
                  position: _slideAnim,
                  child: GestureDetector(
                    onTap: _flip,
                    child: AnimatedBuilder(
                      animation: _flipAnim,
                      builder: (context, _) {
                        final angle = _flipAnim.value * pi;
                        final isFrontVisible = angle < pi / 2;
                        return Transform(
                          alignment: Alignment.center,
                          transform: Matrix4.identity()
                            ..setEntry(3, 2, 0.001)
                            ..rotateY(angle),
                          child: isFrontVisible
                              ? _buildFace(
                                  text: _front,
                                  label: 'CONCEPT',
                                  color: p.accentText,
                                  softColor: p.accentSoft,
                                  hint: 'Tap to reveal answer',
                                )
                              : Transform(
                                  alignment: Alignment.center,
                                  transform: Matrix4.identity()..rotateY(pi),
                                  child: _buildFace(
                                    text: _back,
                                    label: 'ANSWER',
                                    color: p.success,
                                    softColor: p.successSoft,
                                    hint: 'Rate your recall below',
                                  ),
                                ),
                        );
                      },
                    ),
                  ),
                ),
              ),
            ),

            const SizedBox(height: 20),

            // Rating buttons (only shown after flip)
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 200),
              child: _showingAnswer
                  ? _buildRatingRow()
                  : Padding(
                      padding: const EdgeInsets.fromLTRB(20, 0, 20, 28),
                      child: AppButton(
                        label: 'Show Answer',
                        icon: Icons.visibility_rounded,
                        onPressed: _flip,
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFace({
    required String text,
    required String label,
    required Color color,
    required Color softColor,
    required String hint,
  }) {
    final p = context.palette;
    final textTheme = Theme.of(context).textTheme;
    return AppCard(
      radius: AppRadius.sheet,
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: SizedBox(
        width: double.infinity,
        child: Center(
          child: ListView(
            shrinkWrap: true,
            padding: const EdgeInsets.symmetric(vertical: 40),
            children: [
              Align(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                  decoration: BoxDecoration(
                    color: softColor,
                    borderRadius: BorderRadius.circular(AppRadius.pill),
                  ),
                  child: Text(
                    label,
                    style: textTheme.labelSmall!.copyWith(
                      fontWeight: FontWeight.w800,
                      color: color,
                      letterSpacing: 1.2,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 28),
              Text(
                text,
                textAlign: TextAlign.center,
                style: textTheme.titleLarge!.copyWith(
                  fontWeight: FontWeight.w600,
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 36),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.touch_app_rounded, size: 14, color: p.textMuted),
                  const SizedBox(width: 6),
                  Flexible(child: Text(hint, style: textTheme.bodySmall)),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildRatingRow() {
    final p = context.palette;
    final textTheme = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Text(
              'How well did you recall?',
              style: textTheme.bodySmall!.copyWith(fontSize: 13),
            ),
          ),
          Row(
            children: [
              _rateBtn(SrsRating.again, 'Again', p.danger, p.dangerSoft),
              const SizedBox(width: AppSpace.sm),
              _rateBtn(SrsRating.hard, 'Hard', p.streak, p.streakSoft),
              const SizedBox(width: AppSpace.sm),
              _rateBtn(SrsRating.good, 'Good', p.accentText, p.accentSoft),
              const SizedBox(width: AppSpace.sm),
              _rateBtn(SrsRating.easy, 'Easy', p.success, p.successSoft),
            ],
          ),
          if (_lastRated != null)
            Padding(
              padding: const EdgeInsets.only(top: AppSpace.sm),
              child: Text(
                'Next review: ${_lastRated!.nextReviewText}',
                style: textTheme.bodySmall,
              ),
            ),
        ],
      ),
    );
  }

  Widget _rateBtn(SrsRating rating, String label, Color color, Color softColor) {
    return Expanded(
      child: Material(
        color: softColor,
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.control),
          side: BorderSide(color: color.withValues(alpha: 0.4)),
        ),
        child: InkWell(
          onTap: () => _rate(rating),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 14),
            child: Center(
              child: Text(
                label,
                style: Theme.of(context).textTheme.labelLarge!.copyWith(
                  fontWeight: FontWeight.w800,
                  color: color,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
