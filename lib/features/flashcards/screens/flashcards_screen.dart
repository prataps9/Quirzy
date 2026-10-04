import 'package:flutter/material.dart';
import 'dart:math';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../../l10n/app_localizations.dart';
import '../../home/widgets/home_widgets.dart' show AdService, QuizGenerationLoadingScreen;
import '../providers/flashcard_providers.dart';
import '../widgets/flashcard_widgets.dart';
import '../../../shared/providers/exam_provider.dart';
import '../../../shared/theme/app_palette.dart';
import '../../../shared/widgets/app_widgets.dart';
import '../../onboarding/screens/screens.dart';
import '../services/srs_service.dart';
import 'srs_review_screen.dart';

// ==========================================
// FLASHCARDS SCREEN
// Colours come from the app palette (dark/light aware).
// ==========================================

class FlashcardsScreen extends ConsumerStatefulWidget {
  const FlashcardsScreen({super.key});

  @override
  ConsumerState<FlashcardsScreen> createState() => _FlashcardsScreenState();
}

class _FlashcardsScreenState extends ConsumerState<FlashcardsScreen>
    with TickerProviderStateMixin, AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  final TextEditingController _topicController = TextEditingController();
  final FocusNode _focusNode = FocusNode();

  List<Map<String, dynamic>> _flashcardSets = [];
  bool _isLoading = true;
  int _selectedTab = 0;
  final FlutterSecureStorage _storage = const FlutterSecureStorage();
  String _userName = 'Practice Champ';
  String? _photoUrl;

  static const _suggestedTopics = [
    'Science',
    'Languages',
    'Mathematics',
    'History',
    'Coding',
    'Aptitude',
    'Geography',
    'Economics',
  ];

  @override
  void initState() {
    super.initState();
    _loadUserData();
    _initAndLoad();
  }

  Future<void> _initAndLoad() async {
    // FlashcardCacheService.init() is optional - Hive handles this via main.dart
    await _loadFlashcardSets();
  }

  Future<void> _loadUserData() async {
    final name = await _storage.read(key: 'user_name');
    final photoUrl = await _storage.read(key: 'user_photo_url');
    if (mounted) {
      setState(() {
        if (name != null) _userName = name;
        _photoUrl = photoUrl;
      });
    }
  }

  Future<void> _loadFlashcardSets() async {
    try {
      final flashcardService = ref.read(flashcardServiceProvider);
      final sets = await flashcardService.getMyFlashcardSets();
      if (!mounted) return;
      setState(() {
        _flashcardSets = sets;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoading = false);
    }
  }

  Future<void> _generateFlashcards() async {
    final topic = _topicController.text.trim();
    if (topic.isEmpty) {
      HapticFeedback.heavyImpact();
      _showSnackBar('Please enter a topic', isError: true);
      return;
    }

    HapticFeedback.mediumImpact();
    _focusNode.unfocus();

    // Check daily limit (53 free flashcards per day)
    final adService = AdService();
    if (!adService.isFlashcardLimitReached()) {
      // Still have free flashcards
      adService.incrementFlashcardCount();
      _startFlashcardGeneration(topic);
    } else {
      // Limit reached - show ad
      adService.showRewardedAd(
        onRewardEarned: () {
          if (mounted) {
            _startFlashcardGeneration(topic);
          }
        },
        onAdFailed: () {
          // Fallback: Proceed even if ad fails
          if (mounted) {
            _startFlashcardGeneration(topic);
          }
        },
      );
    }
  }

  Future<void> _startFlashcardGeneration(String topic) async {
    // Show AI Generation Loading Screen
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => const QuizGenerationLoadingScreen(
          title: 'Creating Flashcards...',
          subtitle: 'AI is distilling key concepts\ninto bite-sized cards.',
        ),
      ),
    );

    try {
      final flashcardService = ref.read(flashcardServiceProvider);
      final result = await flashcardService.generateFlashcards(
        topic: topic,
        cardCount: 10,
      );

      if (!mounted) return;

      // Pop loading screen
      Navigator.pop(context);

      _topicController.clear();
      Navigator.push(
        context,
        PageRouteBuilder(
          pageBuilder: (context, animation, secondaryAnimation) =>
              FlashcardStudyScreen(
                setId: result['id'],
                title: result['title'] ?? topic,
                cards: List<Map<String, dynamic>>.from(result['cards'] ?? []),
              ),
          transitionsBuilder: (context, animation, secondaryAnimation, child) {
            return FadeTransition(
              opacity: animation,
              child: SlideTransition(
                position:
                    Tween<Offset>(
                      begin: const Offset(0.02, 0),
                      end: Offset.zero,
                    ).animate(
                      CurvedAnimation(
                        parent: animation,
                        curve: Curves.easeOutCubic,
                      ),
                    ),
                child: child,
              ),
            );
          },
          transitionDuration: const Duration(milliseconds: 300),
        ),
      ).then((_) => _loadFlashcardSets());
    } catch (e) {
      if (!mounted) return;
      // Pop loading screen on error
      Navigator.pop(context);
      _showSnackBar(e.toString().replaceAll('Exception: ', ''), isError: true);
    }
  }

  void _showSnackBar(String message, {bool isError = false}) {
    if (!mounted) return;
    final p = context.palette;
    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          message,
          style: isError ? TextStyle(color: p.danger) : null,
        ),
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 80),
      ),
    );
  }

  void _openFlashcardSet(Map<String, dynamic> set) async {
    HapticFeedback.lightImpact();
    if (!mounted) return;

    if (set['isPremium'] == true) {
      _showPremiumDialog(set['title'] as String);
      return;
    }

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    );

    try {
      final flashcardService = ref.read(flashcardServiceProvider);
      final fullSet = await flashcardService.getFlashcardSetById(set['id'] as String);
      if (!mounted) return;
      Navigator.pop(context);

      final cards = List<Map<String, dynamic>>.from(fullSet['cards'] ?? []);
      final setId = fullSet['id'] as String;
      final title = fullSet['title'] as String;

      // Get SRS stats for this set
      final srs = SrsService();
      final stats = await srs.getSetStats(setId, cards.length);
      final dueCount = stats['due'] ?? 0;

      if (!mounted) return;
      _showStudyModeSheet(
        setId: setId,
        title: title,
        cards: cards,
        dueCount: dueCount,
      );
    } catch (e) {
      if (mounted) Navigator.pop(context);
      _showSnackBar('Failed to load flashcards', isError: true);
    }
  }

  void _showStudyModeSheet({
    required String setId,
    required String title,
    required List<Map<String, dynamic>> cards,
    required int dueCount,
  }) {
    showModalBottomSheet(
      context: context,
      builder: (context) {
        final p = context.palette;
        return Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 36,
                height: 4,
                margin: const EdgeInsets.only(bottom: 20),
                decoration: BoxDecoration(
                  color: p.textMuted.withValues(alpha: 0.4),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              Text(
                title,
                style: Theme.of(context).textTheme.titleMedium,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 20),

              // Study All
              _modeCard(
                icon: Icons.style_rounded,
                color: p.accentText,
                softColor: p.accentSoft,
                title: 'Study All',
                subtitle: '${cards.length} cards — free review, no schedule',
                onTap: () {
                  Navigator.pop(context);
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => FlashcardStudyScreen(
                        setId: setId,
                        title: title,
                        cards: cards,
                      ),
                    ),
                  );
                },
              ),
              const SizedBox(height: 12),

              // Spaced Repetition
              _modeCard(
                icon: Icons.repeat_rounded,
                color: p.success,
                softColor: p.successSoft,
                title: 'Spaced Review',
                subtitle: dueCount > 0
                    ? '$dueCount card${dueCount != 1 ? 's' : ''} due today — SRS algorithm'
                    : 'All caught up! No cards due today',
                badge: dueCount > 0 ? '$dueCount due' : null,
                onTap: dueCount > 0
                    ? () async {
                        Navigator.pop(context);
                        final srs = SrsService();
                        final dueIndices =
                            await srs.getDueIndices(setId, cards.length);
                        if (!mounted) return;
                        Navigator.push(
                          this.context,
                          MaterialPageRoute(
                            builder: (_) => SrsReviewScreen(
                              setId: setId,
                              title: title,
                              cards: cards,
                              dueIndices: dueIndices,
                            ),
                          ),
                        );
                      }
                    : null,
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _modeCard({
    required IconData icon,
    required Color color,
    required Color softColor,
    required String title,
    required String subtitle,
    required VoidCallback? onTap,
    String? badge,
  }) {
    final p = context.palette;
    final textTheme = Theme.of(context).textTheme;
    return Opacity(
      opacity: onTap != null ? 1.0 : 0.5,
      child: AppCard(
        color: p.surfaceHigh,
        onTap: onTap,
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: softColor,
                borderRadius: BorderRadius.circular(AppRadius.chip),
              ),
              child: Icon(icon, color: color, size: 22),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: textTheme.titleMedium),
                  const SizedBox(height: 2),
                  Text(subtitle, style: textTheme.bodySmall),
                ],
              ),
            ),
            if (badge != null)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: p.dangerSoft,
                  borderRadius: BorderRadius.circular(AppRadius.pill),
                ),
                child: Text(
                  badge,
                  style: textTheme.labelSmall!.copyWith(
                    fontWeight: FontWeight.w800,
                    color: p.danger,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    _topicController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);

    return Scaffold(
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _loadFlashcardSets,
          child: CustomScrollView(
            slivers: [
              SliverToBoxAdapter(child: _buildAppBar()),
              SliverToBoxAdapter(child: _buildHeroSection()),
              SliverToBoxAdapter(child: _buildCreateSection()),
              SliverToBoxAdapter(child: _buildGenerateButton()),
              SliverToBoxAdapter(child: _buildSuggestionsSection()),
              SliverToBoxAdapter(child: _buildStatsCards()),
              SliverToBoxAdapter(child: _buildTabBar()),
              _buildFlashcardsList(),
              const SliverPadding(padding: EdgeInsets.only(bottom: 100)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTabBar() {
    final p = context.palette;
    final textTheme = Theme.of(context).textTheme;
    final tabs = ['Recommended', 'My Library', 'Recent'];

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
      child: Row(
        children: [
          for (var i = 0; i < tabs.length; i++) ...[
            if (i > 0) const SizedBox(width: AppSpace.sm),
            Expanded(
              child: GestureDetector(
                onTap: () {
                  HapticFeedback.lightImpact();
                  setState(() => _selectedTab = i);
                },
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpace.sm,
                    vertical: AppSpace.md,
                  ),
                  decoration: BoxDecoration(
                    color: _selectedTab == i ? p.accent : p.surface,
                    borderRadius: BorderRadius.circular(AppRadius.pill),
                    border: Border.all(
                      color: _selectedTab == i ? p.accent : p.border,
                    ),
                  ),
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      tabs[i],
                      maxLines: 1,
                      style: textTheme.labelLarge!.copyWith(
                        fontWeight: _selectedTab == i
                            ? FontWeight.w800
                            : FontWeight.w600,
                        color: _selectedTab == i ? p.onAccent : p.textMuted,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildFlashcardsList() {
    final p = context.palette;
    final textTheme = Theme.of(context).textTheme;

    if (_isLoading) {
      return SliverPadding(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        sliver: SliverToBoxAdapter(
          child: ShimmerPlaceholders.historyList(itemCount: 3),
        ),
      );
    }

    List<Map<String, dynamic>> filteredSets = [];
    final selectedExam = ref.watch(examProvider);

    if (_selectedTab == 0) {
      // Recommended / Exam Specific
      if (selectedExam == null) {
        // Show prompt to select exam
        return SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
            child: AppCard(
              padding: const EdgeInsets.all(24),
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const ExamSelectionScreen(),
                  ),
                );
              },
              child: SizedBox(
                width: double.infinity,
                child: Column(
                  children: [
                    Icon(Icons.school_rounded, color: p.accentText, size: 40),
                    const SizedBox(height: 12),
                    Text('Select Your Goal', style: textTheme.titleLarge),
                    const SizedBox(height: 4),
                    Text(
                      'Choose an exam to get tailored flashcards.',
                      textAlign: TextAlign.center,
                      style: textTheme.bodyMedium!.copyWith(
                        color: p.textMuted,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      } else {
        // Return categorized content
        final sections = _getExamData(selectedExam);
        return SliverList(
          delegate: SliverChildBuilderDelegate((context, index) {
            final subject = sections.keys.elementAt(index);
            final sets = sections[subject]!;
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 24, 24, 12),
                  child: SectionHeader(title: subject),
                ),
                ...sets.map(
                  (set) => Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    child: _buildFlashcardSetCard(set),
                  ),
                ),
              ],
            );
          }, childCount: sections.length),
        );
      }
    } else {
      filteredSets = List.from(_flashcardSets);
      if (_selectedTab == 2) {
        // Recent
        filteredSets = filteredSets.take(5).toList();
      }
      // My Library (tab 1): all user sets, no filter.
    }

    if (filteredSets.isEmpty) {
      return SliverFillRemaining(
        hasScrollBody: false,
        child: _buildEmptyState(),
      );
    }

    return SliverPadding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      sliver: SliverList(
        delegate: SliverChildBuilderDelegate((context, index) {
          return _buildFlashcardSetCard(filteredSets[index]);
        }, childCount: filteredSets.length),
      ),
    );
  }

  Widget _buildFlashcardSetCard(Map<String, dynamic> set) {
    final p = context.palette;
    final textTheme = Theme.of(context).textTheme;
    final title = set['title'] ?? 'Untitled Set';
    final cardCount = set['cardCount'] ?? set['cards']?.length ?? 0;
    final isFavorite = set['isFavorite'] == true;

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpace.lg),
      child: AppCard(
        onTap: () => _openFlashcardSet(set),
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: p.accentSoft,
                    borderRadius: BorderRadius.circular(AppRadius.pill),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.layers_rounded, size: 14, color: p.accentText),
                      const SizedBox(width: 4),
                      Text(
                        '$cardCount Cards',
                        style: textTheme.labelMedium!.copyWith(
                          color: p.accentText,
                        ),
                      ),
                    ],
                  ),
                ),
                // Favorite Button
                GestureDetector(
                  onTap: () {
                    HapticFeedback.selectionClick();
                    // Logic to toggle favorite would go here
                    _showSnackBar('Added to favorites', isError: false);
                  },
                  child: Icon(
                    isFavorite
                        ? Icons.star_rounded
                        : Icons.star_outline_rounded,
                    color: isFavorite
                        ? p.streak
                        : p.textMuted.withValues(alpha: 0.6),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Text(
              title,
              style: textTheme.titleMedium!.copyWith(fontSize: 18),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Text('Tap to study', style: textTheme.bodySmall),
                const Spacer(),
                FutureBuilder<Map<String, int>>(
                  future: () async {
                    final id = set['id'] as String?;
                    final count = (set['cardCount'] ?? 0) as int;
                    if (id == null || count == 0) return <String, int>{};
                    return SrsService().getSetStats(id, count);
                  }(),
                  builder: (context, snap) {
                    final due = snap.data?['due'] ?? 0;
                    if (due == 0) {
                      return Icon(
                        Icons.arrow_forward_rounded,
                        size: 16,
                        color: p.textMuted,
                      );
                    }
                    return Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: p.dangerSoft,
                        borderRadius: BorderRadius.circular(AppRadius.pill),
                      ),
                      child: Text(
                        '$due due',
                        style: textTheme.labelSmall!.copyWith(
                          fontWeight: FontWeight.w800,
                          color: p.danger,
                        ),
                      ),
                    );
                  },
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    final p = context.palette;
    final textTheme = Theme.of(context).textTheme;
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(28),
            decoration: BoxDecoration(
              color: p.accentSoft,
              shape: BoxShape.circle,
            ),
            child: Icon(Icons.style_rounded, size: 48, color: p.accentText),
          ),
          const SizedBox(height: 24),
          Text('No Flashcards', style: textTheme.titleLarge),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 48),
            child: Text(
              'Create your first set above to get started!',
              textAlign: TextAlign.center,
              style: textTheme.bodyMedium!.copyWith(color: p.textMuted),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInitial() {
    final p = context.palette;
    return Center(
      child: Text(
        _userName.isNotEmpty ? _userName[0].toUpperCase() : 'Q',
        style: Theme.of(context).textTheme.titleLarge!.copyWith(
          color: p.onAccent,
        ),
      ),
    );
  }

  Widget _buildAppBar() {
    final p = context.palette;
    final textTheme = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 8),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(shape: BoxShape.circle, color: p.accent),
            child: _photoUrl != null
                ? ClipOval(
                    child: Image.network(
                      _photoUrl!,
                      width: 44,
                      height: 44,
                      fit: BoxFit.cover,
                      errorBuilder: (context, error, stackTrace) =>
                          _buildInitial(),
                    ),
                  )
                : _buildInitial(),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  AppLocalizations.of(context)!.flashcardsTitle,
                  style: textTheme.titleLarge,
                ),
                Text(
                  AppLocalizations.of(context)!.yourCollection,
                  style: textTheme.bodySmall,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeroSection() {
    final p = context.palette;
    final textTheme = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 24, 24, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text.rich(
            TextSpan(
              children: [
                TextSpan(text: AppLocalizations.of(context)!.studySmarter1),
                TextSpan(
                  text: AppLocalizations.of(context)!.studySmarter2,
                  style: TextStyle(color: p.accentText),
                ),
              ],
            ),
            style: textTheme.displaySmall!.copyWith(letterSpacing: -0.5),
          ),
          const SizedBox(height: 8),
          Text(
            AppLocalizations.of(context)!.studySmarterSubtitle,
            style: textTheme.bodyMedium!.copyWith(color: p.textMuted),
          ),
        ],
      ),
    );
  }

  Widget _buildCreateSection() {
    final p = context.palette;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.auto_awesome_rounded, color: p.accentText, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  AppLocalizations.of(context)!.whatsTheTopic,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _topicController,
            focusNode: _focusNode,
            maxLines: 2,
            minLines: 1,
            decoration: const InputDecoration(
              hintText: "e.g., 'Photosynthesis' or paste your notes here...",
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildGenerateButton() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
      child: AppButton(
        label: 'Generate Flashcards',
        icon: Icons.auto_awesome_rounded,
        onPressed: _generateFlashcards,
      ),
    );
  }

  Widget _buildSuggestionsSection() {
    final textTheme = Theme.of(context).textTheme;
    final p = context.palette;
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SectionHeader(title: 'Explore Categories'),
          Text(
            'Tap to explore or generate flashcards',
            style: textTheme.bodySmall!.copyWith(
              fontSize: 13,
              color: p.textMuted,
            ),
          ),
          const SizedBox(height: AppSpace.md),
          Wrap(
            spacing: AppSpace.sm,
            runSpacing: AppSpace.sm,
            children: [
              for (final topic in _suggestedTopics)
                ActionChip(
                  label: Text(topic),
                  onPressed: () {
                    HapticFeedback.lightImpact();
                    _topicController.text = topic;
                    _focusNode.requestFocus();
                  },
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStatsCards() {
    final totalSets = _flashcardSets.length;
    final totalCards = _flashcardSets.fold<int>(
      0,
      (sum, set) =>
          sum + ((set['cardCount'] ?? set['cards']?.length ?? 0) as int),
    );

    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
      child: Row(
        children: [
          Expanded(child: _buildStatTile('MY SETS', '$totalSets', accent: true)),
          const SizedBox(width: 12),
          Expanded(child: _buildStatTile('TOTAL CARDS', '$totalCards')),
        ],
      ),
    );
  }

  Widget _buildStatTile(String label, String value, {bool accent = false}) {
    final p = context.palette;
    final textTheme = Theme.of(context).textTheme;
    return AppCard(
      child: SizedBox(
        width: double.infinity,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: textTheme.labelSmall!.copyWith(
                fontWeight: FontWeight.w800,
                color: p.textMuted,
                letterSpacing: 1,
              ),
            ),
            const SizedBox(height: AppSpace.md),
            Text(
              value,
              style: textTheme.headlineLarge!.copyWith(
                color: accent ? p.accentText : p.text,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Map<String, List<Map<String, dynamic>>> _getExamData(String exam) {
    final subjects = _getSubjectsForExam(exam);
    final data = <String, List<Map<String, dynamic>>>{};

    for (final subject in subjects) {
      data[subject] = [
        {
          'id': '${exam}_${subject}_1',
          'title': '$subject - Key Concepts',
          'cardCount': 20 + Random().nextInt(30),
          'isPremium': true,
        },
        {
          'id': '${exam}_${subject}_2',
          'title': '$subject - Practice Set',
          'cardCount': 40 + Random().nextInt(20),
          'isPremium': true,
        },
        {
          'id': '${exam}_${subject}_3',
          'title': 'Advanced $subject',
          'cardCount': 50,
          'isPremium': true,
        },
      ];
    }
    return data;
  }

  List<String> _getSubjectsForExam(String exam) {
    switch (exam.toLowerCase()) {
      case 'jee':
        return ['Physics', 'Chemistry', 'Mathematics'];
      case 'neet':
        return ['Biology', 'Physics', 'Chemistry'];
      case 'mba':
      case 'cat':
      case 'gmat':
      case 'gre':
        return ['Quantitative', 'Verbal Ability', 'Logical Reasoning'];
      case '10th':
      case '12th':
        return ['Science', 'Mathematics', 'English', 'Social Studies'];
      case 'ielts':
        return ['Reading', 'Writing', 'Listening', 'Speaking'];
      default:
        return ['General Knowledge', 'Aptitude'];
    }
  }

  void _showPremiumDialog(String itemName) {
    if (!mounted) return;
    final p = context.palette;
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Premium Content 💎'),
        content: Text(
          'Unlock "$itemName" and thousands of other expert-curated materials with Quirzy Pro.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            style: TextButton.styleFrom(foregroundColor: p.textMuted),
            child: const Text('Maybe Later'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              _showSnackBar('Subscription feature coming soon! 🚀');
            },
            child: const Text('Get Premium'),
          ),
        ],
      ),
    );
  }
}
