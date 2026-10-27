import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../l10n/app_localizations.dart';
import '../../subscription/services/usage_limits.dart';
import '../../subscription/widgets/limit_sheet.dart';
import '../providers/flashcard_providers.dart';
import '../widgets/flashcard_widgets.dart';
import '../../../shared/providers/exam_provider.dart';
import '../../../shared/theme/app_palette.dart';
import '../../../shared/utils/user_messages.dart';
import '../../../shared/widgets/app_widgets.dart';
import '../../../shared/widgets/tab_header.dart';
import '../../../shared/widgets/generation_loading.dart';
import '../../onboarding/screens/screens.dart';
import '../services/flashcard_cache.dart';
import '../services/flashcard_prefs.dart';
import '../services/recommended_topics.dart';
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

  /// Set when the last library load failed. Sets already shown are kept.
  bool _loadFailed = false;

  /// One due-count future per set id, so rebuilds don't refetch (and
  /// flicker). Cleared whenever the counts may have changed.
  final Map<String, Future<Map<String, int>>> _dueFutures = {};
  int _selectedTab = 0;

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
    _loadFlashcardSets();
  }

  Future<void> _loadFlashcardSets() async {
    try {
      final flashcardService = ref.read(flashcardServiceProvider);
      final sets = await flashcardService.getMyFlashcardSets();
      if (!mounted) return;
      setState(() {
        _flashcardSets = sets;
        _isLoading = false;
        _loadFailed = false;
        _dueFutures.clear();
      });
    } catch (e) {
      if (!mounted) return;
      final hadSets = _flashcardSets.isNotEmpty;
      setState(() {
        _isLoading = false;
        _loadFailed = true;
      });
      // With sets already on screen, keep them and just say the refresh
      // failed; with none, the list shows an error state with Retry.
      if (hadSets) {
        _showSnackBar(
          "Couldn't refresh your flashcards. Check your connection and try again.",
          onRetry: _retryLoad,
        );
      }
    }
  }

  void _retryLoad() {
    setState(() {
      _isLoading = _flashcardSets.isEmpty;
      _loadFailed = false;
    });
    _loadFlashcardSets();
  }

  Future<void> _generateFlashcards() async {
    final topic = _topicController.text.trim();
    if (topic.isEmpty) {
      HapticFeedback.heavyImpact();
      _showSnackBar('Enter a topic to generate flashcards.');
      return;
    }

    HapticFeedback.mediumImpact();
    _focusNode.unfocus();
    await _startFlashcardGeneration(topic, clearInput: true);
  }

  /// Shared by the topic field and the Recommended tiles: checks the daily
  /// limit, generates a set (saved to My Library), then opens it.
  Future<void> _startFlashcardGeneration(
    String topic, {
    bool clearInput = false,
  }) async {
    final allowed = await ref
        .read(usageLimitsProvider.notifier)
        .canUse(UsageKind.flashcardSet);
    if (!mounted) return;
    if (!allowed) {
      showLimitSheet(context, UsageKind.flashcardSet);
      return;
    }

    final Map<String, dynamic> result;
    try {
      result = await runWithLoadingScreen<Map<String, dynamic>>(
        context,
        title: 'Making your flashcards…',
        subtitle: 'Picking out the key ideas in $topic.',
        task: () async {
          final generated = await ref
              .read(flashcardServiceProvider)
              .generateFlashcards(topic: topic, cardCount: 10);
          final cards = generated['cards'];
          if (cards is! List || cards.isEmpty) {
            throw const UserFacingException(
              'No cards came back — try a broader topic.',
            );
          }
          await ref
              .read(usageLimitsProvider.notifier)
              .record(UsageKind.flashcardSet);
          return Map<String, dynamic>.from(generated);
        },
      );
    } catch (e) {
      if (!mounted || isCancellation(e)) return;
      _showSnackBar(
        friendlyError(e),
        onRetry: () => _startFlashcardGeneration(topic, clearInput: clearInput),
      );
      return;
    }
    if (!mounted) return;

    if (clearInput) _topicController.clear();
    _loadFlashcardSets();
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
    ).then((_) => _refreshDueBadges());
  }

  void _showSnackBar(String message, {VoidCallback? onRetry}) {
    if (!mounted) return;
    showAppSnack(context, message, onRetry: onRetry);
  }

  Future<void> _openFlashcardSet(Map<String, dynamic> set) async {
    HapticFeedback.lightImpact();
    if (!mounted) return;

    // A small loading dialog the user can tap away; it times out rather
    // than spinning forever on a bad connection.
    final navigator = Navigator.of(context, rootNavigator: true);
    final loadingRoute = DialogRoute<void>(
      context: context,
      barrierDismissible: true,
      barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    );
    unawaited(navigator.push(loadingRoute));

    try {
      final flashcardService = ref.read(flashcardServiceProvider);
      final fullSet = await flashcardService
          .getFlashcardSetById(set['id'] as String)
          .timeout(const Duration(seconds: 20));

      final cards = List<Map<String, dynamic>>.from(fullSet['cards'] ?? []);
      final setId = fullSet['id'] as String;
      final title = fullSet['title'] as String;

      // Get SRS stats for this set
      final stats = await SrsService().getSetStats(setId, cards.length);
      final dueCount = stats['due'] ?? 0;

      // The user tapped away while it loaded: they've moved on.
      if (!loadingRoute.isActive) return;
      navigator.removeRoute(loadingRoute);
      if (!mounted) return;
      _showStudyModeSheet(
        setId: setId,
        title: title,
        cards: cards,
        dueCount: dueCount,
      );
    } catch (e) {
      final dismissed = !loadingRoute.isActive;
      if (!dismissed) navigator.removeRoute(loadingRoute);
      if (!mounted || dismissed) return;
      _showSnackBar(
        e is TimeoutException
            ? 'That set is taking too long to open. Check your connection and try again.'
            : friendlyError(e),
        onRetry: () => _openFlashcardSet(set),
      );
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
                title: 'Study all',
                subtitle: cards.length == 1
                    ? '1 card, in order — no schedule'
                    : '${cards.length} cards, in order — no schedule',
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
                  ).then((_) => _refreshDueBadges());
                },
              ),
              const SizedBox(height: 12),

              // Spaced Repetition
              _modeCard(
                icon: Icons.repeat_rounded,
                color: p.success,
                softColor: p.successSoft,
                title: 'Spaced review',
                subtitle: dueCount > 0
                    ? '$dueCount card${dueCount != 1 ? 's' : ''} due today'
                    : 'All caught up — no cards due today',
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
                        ).then((_) => _refreshDueBadges());
                      }
                    : null,
              ),
            ],
          ),
        );
      },
    );
  }

  /// Drops the cached due counts so the badges pick up new SRS ratings.
  void _refreshDueBadges() {
    if (!mounted) return;
    setState(_dueFutures.clear);
  }

  Future<void> _confirmDelete(Map<String, dynamic> set) async {
    final setId = set['id'] as String?;
    if (setId == null) return;
    final title = (set['title'] as String?) ?? 'this set';
    final p = context.palette;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete set?'),
        content: Text('"$title" and its cards will be deleted. This can\'t be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            style: TextButton.styleFrom(foregroundColor: p.textMuted),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: p.danger),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    try {
      await ref.read(flashcardServiceProvider).deleteFlashcardSet(setId);
      await ref.read(flashcardPrefsProvider.notifier).remove(setId);
      await SrsService().removeSet(setId);
      await FlashcardCache.remove(setId);
      if (!mounted) return;
      setState(() {
        _flashcardSets.removeWhere((s) => s['id'] == setId);
        _dueFutures.remove(setId);
      });
      _showSnackBar('Set deleted');
      _loadFlashcardSets();
    } catch (e) {
      if (!mounted) return;
      _showSnackBar(
        "Couldn't delete the set. Please try again.",
        onRetry: () => _confirmDelete(set),
      );
    }
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
    ref.listen<int>(savedCardsVersionProvider, (_, _) => _loadFlashcardSets());

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
    const tabs = ['Recommended', 'My Library', 'Recent', 'Favourites'];

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
      child: Row(
        children: [
          for (var i = 0; i < tabs.length; i++) ...[
            if (i > 0) const SizedBox(width: AppSpace.sm),
            ChoiceChip(
              label: Text(tabs[i]),
              selected: _selectedTab == i,
              onSelected: (_) {
                HapticFeedback.lightImpact();
                setState(() => _selectedTab = i);
              },
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildFlashcardsList() {
    if (_selectedTab == 0) return _buildRecommended();

    if (_isLoading) {
      return SliverPadding(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        sliver: SliverToBoxAdapter(
          child: ShimmerPlaceholders.historyList(itemCount: 3),
        ),
      );
    }

    final prefs = ref.watch(flashcardPrefsProvider).value ??
        const FlashcardPrefsState();
    List<Map<String, dynamic>> filteredSets;

    switch (_selectedTab) {
      case 2:
        // Recent: studied sets only, most recently studied first.
        final byId = {for (final s in _flashcardSets) s['id']: s};
        filteredSets = [
          for (final id in prefs.recentIds)
            if (byId[id] != null) byId[id]!,
        ];
      case 3:
        filteredSets = _flashcardSets
            .where((s) => prefs.isFavourite(s['id'] as String? ?? ''))
            .toList();
      default:
        filteredSets = List.from(_flashcardSets);
    }

    if (filteredSets.isEmpty && _loadFailed) {
      return SliverFillRemaining(
        hasScrollBody: false,
        child: _buildLoadError(),
      );
    }

    if (filteredSets.isEmpty) {
      return SliverFillRemaining(
        hasScrollBody: false,
        child: switch (_selectedTab) {
          2 => _buildEmptyState(
            icon: Icons.history_rounded,
            title: 'Nothing studied yet',
            message: 'Sets you study will show up here.',
          ),
          3 => _buildEmptyState(
            icon: Icons.star_outline_rounded,
            title: 'No favourites yet',
            message: 'Tap the star on a set to keep it here.',
          ),
          _ => _buildEmptyState(
            icon: Icons.style_rounded,
            title: 'No flashcards yet',
            message: 'Create your first set above.',
          ),
        },
      );
    }

    return SliverPadding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      sliver: SliverList(
        delegate: SliverChildBuilderDelegate((context, index) {
          final set = filteredSets[index];
          return _buildFlashcardSetCard(
            set,
            isFavourite: prefs.isFavourite(set['id'] as String? ?? ''),
            lastStudied: prefs.lastStudied[set['id']],
          );
        }, childCount: filteredSets.length),
      ),
    );
  }

  Widget _buildRecommended() {
    final p = context.palette;
    final textTheme = Theme.of(context).textTheme;
    final selectedExam = ref.watch(examProvider);
    final topics = recommendedTopicsFor(selectedExam);

    return SliverPadding(
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 0),
      sliver: SliverList(
        delegate: SliverChildListDelegate([
          if (selectedExam == null)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpace.lg),
              child: AppCard(
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const ExamSelectionScreen(),
                    ),
                  );
                },
                child: Row(
                  children: [
                    Icon(Icons.school_rounded, color: p.accentText, size: 28),
                    const SizedBox(width: AppSpace.md),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Pick your exam', style: textTheme.titleMedium),
                          const SizedBox(height: 2),
                          Text(
                            'Get topics picked for what you\'re studying.',
                            style: textTheme.bodySmall!.copyWith(
                              color: p.textMuted,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Icon(
                      Icons.arrow_forward_rounded,
                      size: 18,
                      color: p.textMuted,
                    ),
                  ],
                ),
              ),
            ),
          SectionHeader(
            title: selectedExam == null
                ? 'Suggested topics'
                : 'Suggested for ${examLabel(selectedExam)}',
          ),
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpace.md),
            child: Text(
              'Tap a topic to generate a set. It\'s saved to My Library.',
              style: textTheme.bodySmall!.copyWith(color: p.textMuted),
            ),
          ),
          for (final topic in topics)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpace.md),
              child: _buildTopicTile(topic),
            ),
        ]),
      ),
    );
  }

  Widget _buildTopicTile(String topic) {
    final p = context.palette;
    final textTheme = Theme.of(context).textTheme;
    return AppCard(
      onTap: () {
        HapticFeedback.mediumImpact();
        _startFlashcardGeneration(topic);
      },
      child: Row(
        children: [
          Expanded(
            child: Text(
              topic,
              style: textTheme.titleMedium,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: AppSpace.md),
          Icon(Icons.auto_awesome_rounded, size: 16, color: p.accentText),
          const SizedBox(width: 4),
          Text(
            'Generate',
            style: textTheme.labelLarge!.copyWith(color: p.accentText),
          ),
        ],
      ),
    );
  }

  String _studiedLabel(DateTime at) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final day = DateTime(at.year, at.month, at.day);
    final days = today.difference(day).inDays;
    if (days <= 0) return 'Studied today';
    if (days == 1) return 'Studied yesterday';
    return 'Studied $days days ago';
  }

  Widget _buildFlashcardSetCard(
    Map<String, dynamic> set, {
    required bool isFavourite,
    DateTime? lastStudied,
  }) {
    final p = context.palette;
    final textTheme = Theme.of(context).textTheme;
    final setId = set['id'] as String? ?? '';
    final title = set['title'] ?? 'Untitled set';
    final cardCount = set['cardCount'] ?? set['cards']?.length ?? 0;

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpace.lg),
      child: GestureDetector(
        onLongPress: () {
          HapticFeedback.mediumImpact();
          _confirmDelete(set);
        },
        child: AppCard(
          onTap: () => _openFlashcardSet(set),
          padding: const EdgeInsets.fromLTRB(20, 12, 8, 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
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
                        Icon(
                          Icons.layers_rounded,
                          size: 14,
                          color: p.accentText,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          cardCount == 1 ? '1 card' : '$cardCount cards',
                          style: textTheme.labelMedium!.copyWith(
                            color: p.accentText,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    tooltip: isFavourite
                        ? 'Remove from favourites'
                        : 'Add to favourites',
                    onPressed: setId.isEmpty
                        ? null
                        : () {
                            HapticFeedback.selectionClick();
                            ref
                                .read(flashcardPrefsProvider.notifier)
                                .toggleFavourite(setId);
                          },
                    icon: Icon(
                      isFavourite
                          ? Icons.star_rounded
                          : Icons.star_outline_rounded,
                      color: isFavourite
                          ? p.streak
                          : p.textMuted.withValues(alpha: 0.6),
                    ),
                  ),
                  PopupMenuButton<String>(
                    tooltip: 'More',
                    icon: Icon(Icons.more_vert_rounded, color: p.textMuted),
                    onSelected: (value) {
                      if (value == 'delete') _confirmDelete(set);
                    },
                    itemBuilder: (context) => [
                      PopupMenuItem(
                        value: 'delete',
                        child: Row(
                          children: [
                            Icon(
                              Icons.delete_outline_rounded,
                              color: p.danger,
                              size: 20,
                            ),
                            const SizedBox(width: AppSpace.sm),
                            Text('Delete', style: TextStyle(color: p.danger)),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              Padding(
                padding: const EdgeInsets.only(right: 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: 8),
                    Text(
                      title,
                      style: textTheme.titleLarge,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Text(
                          lastStudied != null
                              ? _studiedLabel(lastStudied)
                              : 'Tap to study',
                          style: textTheme.bodySmall,
                        ),
                        const Spacer(),
                        _buildDueBadge(set),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDueBadge(Map<String, dynamic> set) {
    final p = context.palette;
    final textTheme = Theme.of(context).textTheme;
    final id = set['id'] as String?;
    final count = (set['cardCount'] ?? 0) as int;
    return FutureBuilder<Map<String, int>>(
      future: id == null || count == 0
          ? null
          : _dueFutures.putIfAbsent(
              id,
              () => SrsService().getSetStats(id, count),
            ),
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
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
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
    );
  }

  Widget _buildLoadError() {
    final p = context.palette;
    final textTheme = Theme.of(context).textTheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 48, vertical: 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.cloud_off_rounded, size: 48, color: p.textMuted),
            const SizedBox(height: AppSpace.lg),
            Text(
              "Couldn't load your flashcards. Check your connection and try again.",
              textAlign: TextAlign.center,
              style: textTheme.bodyMedium!.copyWith(color: p.textMuted),
            ),
            const SizedBox(height: AppSpace.lg),
            AppButton.secondary(
              label: 'Retry',
              icon: Icons.refresh_rounded,
              expanded: false,
              onPressed: _retryLoad,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState({
    required IconData icon,
    required String title,
    required String message,
  }) {
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
            child: Icon(icon, size: 48, color: p.accentText),
          ),
          const SizedBox(height: 24),
          Text(title, style: textTheme.titleLarge),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 48),
            child: Text(
              message,
              textAlign: TextAlign.center,
              style: textTheme.bodyMedium!.copyWith(color: p.textMuted),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAppBar() {
    return TabHeader(
      title: AppLocalizations.of(context)!.navCards,
      subtitle: "Make a set, then review what's due",
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
            keyboardType: TextInputType.text,
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => _generateFlashcards(),
            decoration: const InputDecoration(
              hintText: 'e.g. Photosynthesis or the French Revolution',
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
        label: 'Generate flashcards',
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
          const SectionHeader(title: 'Explore categories'),
          Text(
            'Tap a category to use it as your topic',
            style: textTheme.bodySmall!.copyWith(color: p.textMuted),
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
}
