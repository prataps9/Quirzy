import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;

import '../../../shared/providers/exam_provider.dart';
import '../../../shared/providers/providers.dart';
import '../../../shared/services/connectivity_service.dart';
import '../../../shared/services/smart_notification_service.dart';
import '../../../shared/theme/app_palette.dart';
import '../../../shared/widgets/app_widgets.dart';
import '../../content/providers/content_providers.dart';
import '../../content/screens/add_questions_screen.dart';
import '../../content/screens/study_material_entry_screen.dart';
import '../../content/screens/study_notes_screen.dart';
import '../../feed/providers/feed_providers.dart';
import '../../feed/services/practice_content_service.dart';
import '../../feed/services/streak_service.dart';
import '../../l10n/app_localizations.dart';
import '../../onboarding/screens/exam_selection_screen.dart';
import '../../subscription/screens/subscription_screen.dart';
import '../providers/home_stats_provider.dart';
import '../widgets/home_widgets.dart';
import '../widgets/topic_stories_row.dart';

/// Home: one clear job — add something to practice. Everything else (your
/// topics, quick practice for your exam, other ways to add content) hangs
/// off that.
class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> with AutomaticKeepAliveClientMixin {
  final TextEditingController _topicController = TextEditingController();
  final FocusNode _inputFocusNode = FocusNode();
  static const FlutterSecureStorage _storage = FlutterSecureStorage();
  String _userName = 'Practice Champ';
  String? _photoUrl;

  late stt.SpeechToText _speech;
  bool _isListening = false;
  String _lastWords = '';

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _loadUserData();
    _speech = stt.SpeechToText();
    _onAppOpen();
  }

  @override
  void dispose() {
    _topicController.dispose();
    _inputFocusNode.dispose();
    super.dispose();
  }

  Future<void> _onAppOpen() async {
    final svc = SmartNotificationService();
    // Cancel re-engagement — user is active
    await svc.cancelReEngagement();
    // Schedule re-engagement in case user doesn't come back
    await svc.scheduleReEngagement();

    final statsService = ref.read(feedStatsServiceProvider);
    final revisionService = ref.read(feedRevisionServiceProvider);

    // Streak protection at 9 PM if not studied today (real feed activity).
    final streak = await ref.read(streakServiceProvider).getStreak();
    await svc.scheduleStreakProtection(
      currentStreak: streak.current,
      studiedToday: streak.practisedToday,
    );

    // Revision due (morning) — real Revision Vault due count.
    final dueCount = await revisionService.getDueCount();
    await svc.scheduleSrsReminder(dueCount: dueCount, studyHour: 9, studyMinute: 0);

    // Weekly digest (Sunday) — real practice activity this week.
    final weekCounts = await statsService.getDailyAnsweredCounts(days: 7);
    final questionsThisWeek = weekCounts.fold<int>(0, (a, b) => a + b);
    await svc.scheduleWeeklyDigest(
      questionsThisWeek: questionsThisWeek,
      flashcardsReviewed: 0,
      bestStreak: streak.best,
    );
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

  // --- SPEECH RECOGNITION ---

  Future<void> _listen() async {
    final localizations = AppLocalizations.of(context)!;
    if (_isListening) {
      setState(() => _isListening = false);
      _speech.stop();
      return;
    }

    final available = await _speech.initialize(
      onStatus: (val) {
        if (val == 'done' || val == 'notListening') {
          if (mounted && _isListening) {
            setState(() => _isListening = false);
            Navigator.pop(context); // Close dialog if listening stops naturally
          }
        }
      },
      onError: (val) => debugPrint('onError: $val'),
    );

    if (!available) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(localizations.speechNotAvailable)));
      }
      return;
    }
    if (!mounted) return;
    setState(() => _isListening = true);

    showDialog(
      context: context,
      builder: (context) {
        final p = context.palette;
        final text = Theme.of(context).textTheme;
        return Dialog(
          insetPadding: const EdgeInsets.all(20),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 36, horizontal: 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(localizations.listening, style: text.headlineSmall),
                const SizedBox(height: 8),
                Text(
                  _lastWords.isEmpty ? localizations.sayYourTopic : _lastWords,
                  textAlign: TextAlign.center,
                  style: text.bodyLarge!.copyWith(color: p.textMuted),
                ),
                const SizedBox(height: 32),
                GestureDetector(
                  onTap: () {
                    _speech.stop();
                    Navigator.pop(context);
                  },
                  child: Container(
                    width: 88,
                    height: 88,
                    decoration: BoxDecoration(color: p.accent, shape: BoxShape.circle),
                    child: Icon(Icons.mic_rounded, color: p.onAccent, size: 44),
                  ),
                ),
                const SizedBox(height: 12),
                Text('Tap to stop', style: text.bodySmall),
              ],
            ),
          ),
        );
      },
    ).then((_) {
      if (_isListening) {
        _speech.stop();
        setState(() => _isListening = false);
      }
    });

    _speech.listen(
      onResult: (val) {
        setState(() {
          _topicController.text = val.recognizedWords;
          _lastWords = val.recognizedWords;
          _topicController.selection = TextSelection.fromPosition(
            TextPosition(offset: _topicController.text.length),
          );
        });
      },
    );
  }

  // --- TOPIC GENERATION FLOW ---

  void _handleGenerate() {
    final localizations = AppLocalizations.of(context)!;
    final topic = _topicController.text.trim();
    if (topic.isEmpty) {
      HapticFeedback.heavyImpact();
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(localizations.pleaseEnterTopic)));
      return;
    }
    _showConfigSheet(topic);
  }

  void _showConfigSheet(String topic) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (context) => QuizConfigSheet(
        topic: topic,
        onGenerate: (count, difficulty) {
          Navigator.pop(context); // Close sheet first

          if (!AdService().isLimitReached()) {
            AdService().incrementQuizCount();
            _startGeneration(topic, count, difficulty);
          } else {
            AdService().showRewardedAd(
              onRewardEarned: () {
                if (mounted) _startGeneration(topic, count, difficulty);
              },
              onAdFailed: () {
                if (mounted) _startGeneration(topic, count, difficulty);
              },
            );
          }
        },
      ),
    );
  }

  Future<void> _startGeneration(String topic, int count, String difficulty) async {
    // Check daily topic-generation limit before generating
    final canGenerate = await ref.read(canGenerateTopicProvider.future);

    if (!canGenerate) {
      if (mounted) {
        showDialog(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Daily limit reached'),
            content: const Text(
              'You\'ve already generated 1 topic today. Come back tomorrow for your next free topic, '
              'or upgrade to Pro for unlimited topics!',
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(context), child: const Text('OK')),
            ],
          ),
        );
      }
      return;
    }

    final isOnline = await ref.read(connectivityServiceProvider).checkIsOnline();
    if (!isOnline) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('You\'re offline — connect to the internet to add a new topic.')),
        );
      }
      return;
    }
    if (!mounted) return;

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => QuizGenerationLoadingScreen(
          title: 'Building "$topic"...',
          subtitle: 'AI is crafting practice questions for your feed',
        ),
      ),
    );

    try {
      final contentService = ref.read(contentServiceProvider);
      final result = await contentService.generateTopicContent(
        topic: topic,
        questionCount: count,
        difficulty: difficulty.toLowerCase(),
      );

      // Record daily generation usage after successful generation
      final quizId = result['quizId']?.toString() ?? result['id']?.toString() ?? '';
      final generationLimitService = ref.read(generationLimitServiceProvider);
      await generationLimitService.recordUsage(topicId: quizId, topic: topic);

      final quizTitle = result['title']?.toString() ?? topic;
      final questions = List<Map<String, dynamic>>.from(result['questions'] ?? []);

      // Add the new questions straight to the practice feed's pool and
      // jump there so they're immediately practicable.
      await ref.read(practiceContentServiceProvider).addToQuestionPool(
            questions,
            topicId: quizId,
            topic: quizTitle,
          );
      await ref.read(feedControllerProvider.notifier).switchToTopic(quizTitle);

      if (mounted) {
        Navigator.pop(context); // Remove the loading screen
        _topicController.clear();
        ref.read(tabIndexProvider.notifier).state = 0; // Practice tab
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Added ${questions.length} questions on "$quizTitle" to your feed')),
        );
      }
    } catch (e) {
      if (mounted) {
        Navigator.pop(context); // Dismiss loading screen on error
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${AppLocalizations.of(context)!.failedToGenerate}$e')),
        );
      }
    }
  }

  // --- UI ---

  String _greeting() {
    final hour = DateTime.now().hour;
    final localizations = AppLocalizations.of(context)!;
    if (hour < 12) return localizations.greetingMorning;
    if (hour < 17) return localizations.greetingAfternoon;
    return localizations.greetingEvening;
  }

  void _push(Widget screen) {
    HapticFeedback.lightImpact();
    Navigator.push(context, MaterialPageRoute(builder: (_) => screen));
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final localizations = AppLocalizations.of(context)!;
    final text = Theme.of(context).textTheme;
    final p = context.palette;
    final stats = ref.watch(homeStatsProvider).value ?? const HomeStats();
    final selectedExam = ref.watch(examProvider);
    final examTopics = _examTopics(selectedExam);

    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.only(bottom: 24),
          children: [
            _HomeHeader(
              userName: _userName,
              photoUrl: _photoUrl,
              greeting: _greeting(),
              stats: stats,
              onStreakTap: () => ref.read(tabIndexProvider.notifier).state = 2,
              onProTap: () => _push(const SubscriptionScreen()),
            ),
            const TopicStoriesRow(),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('What do you want to practice?', style: text.headlineSmall),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _topicController,
                    focusNode: _inputFocusNode,
                    minLines: 1,
                    maxLines: 3,
                    textInputAction: TextInputAction.done,
                    onSubmitted: (_) => _handleGenerate(),
                    style: text.bodyLarge,
                    decoration: InputDecoration(
                      hintText: localizations.enterTopicHint,
                      suffixIcon: IconButton(
                        tooltip: 'Speak a topic',
                        onPressed: () {
                          HapticFeedback.lightImpact();
                          _listen();
                        },
                        icon: Icon(Icons.mic_rounded, color: p.accentText),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  AppButton(
                    label: localizations.generateQuizButton,
                    icon: Icons.auto_awesome_rounded,
                    onPressed: _handleGenerate,
                  ),
                ],
              ),
            ),
            if (selectedExam != null && examTopics.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text('Quick practice for ${selectedExam.toUpperCase()}', style: text.titleMedium),
                          ),
                          TextButton(
                            onPressed: () => _push(const ExamSelectionScreen()),
                            child: const Text('Change'),
                          ),
                        ],
                      ),
                    ),
                    SizedBox(
                      height: 40,
                      child: ListView.separated(
                        scrollDirection: Axis.horizontal,
                        padding: const EdgeInsets.symmetric(horizontal: 20),
                        itemCount: examTopics.length,
                        separatorBuilder: (_, _) => const SizedBox(width: 8),
                        itemBuilder: (context, i) => ActionChip(
                          label: Text(examTopics[i]),
                          onPressed: () {
                            HapticFeedback.selectionClick();
                            _topicController.text = examTopics[i];
                            _handleGenerate();
                          },
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 28, 20, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('More ways to add', style: text.titleMedium),
                  const SizedBox(height: 12),
                  _AddTile(
                    icon: Icons.edit_note_rounded,
                    title: 'Write your own questions',
                    subtitle: 'Type questions and answers yourself',
                    onTap: () => _push(const AddQuestionsScreen()),
                  ),
                  const SizedBox(height: 8),
                  _AddTile(
                    icon: Icons.menu_book_rounded,
                    title: 'Study set',
                    subtitle: 'Summary, flashcards and practice from a topic',
                    onTap: () => _push(const StudyMaterialEntryScreen()),
                  ),
                  const SizedBox(height: 8),
                  _AddTile(
                    icon: Icons.note_alt_rounded,
                    title: 'Paste your notes',
                    subtitle: 'Turn your notes into practice questions',
                    onTap: () => _push(const StudyNotesScreen()),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  List<String> _examTopics(String? exam) {
    const topics = {
      'jee': ['Kinematics', 'Thermodynamics', 'Organic Chemistry', 'Calculus', 'Optics'],
      'neet': ['Cell Biology', 'Human Physiology', 'Genetics', 'Organic Chemistry', 'Mechanics'],
      'cat': ['Percentages', 'Reading Comprehension', 'Syllogisms', 'Geometry', 'Time & Work'],
      'cuet': ['English Grammar', 'General Awareness', 'Reasoning', 'Maths Basics'],
      'mba': ['Data Interpretation', 'Critical Reasoning', 'Sentence Correction'],
      'gre': ['Vocabulary', 'Quantitative Reasoning', 'Analytical Writing'],
      'gmat': ['Critical Reasoning', 'Data Sufficiency', 'Sentence Correction'],
      'ielts': ['Reading Skills', 'Grammar', 'Academic Vocabulary'],
      '10th': ['Algebra', 'Trigonometry', 'Chemistry Basics', 'Biology Basics'],
      '12th': ['Integration', 'Electrostatics', 'Chemical Bonding', 'Human Reproduction'],
    };
    if (exam == null) return [];
    return topics[exam.toLowerCase()] ?? [];
  }
}

class _HomeHeader extends StatelessWidget {
  final String userName;
  final String? photoUrl;
  final String greeting;
  final HomeStats stats;
  final VoidCallback onStreakTap;
  final VoidCallback onProTap;

  const _HomeHeader({
    required this.userName,
    required this.photoUrl,
    required this.greeting,
    required this.stats,
    required this.onStreakTap,
    required this.onProTap,
  });

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final text = Theme.of(context).textTheme;
    final firstName = userName.trim().split(' ').first;
    final initial = firstName.isEmpty ? '?' : firstName[0].toUpperCase();
    final flame = stats.streak > 0 && !stats.streakAtRisk ? p.streak : p.textMuted;

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 4),
      child: Row(
        children: [
          CircleAvatar(
            radius: 22,
            backgroundColor: p.accent,
            foregroundImage: photoUrl == null ? null : NetworkImage(photoUrl!),
            child: Text(initial, style: text.titleMedium!.copyWith(color: p.onAccent)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(greeting, style: text.bodySmall),
                Text(firstName, maxLines: 1, overflow: TextOverflow.ellipsis, style: text.titleMedium),
              ],
            ),
          ),
          StatChip(
            icon: Icons.local_fire_department_rounded,
            label: '${stats.streak}',
            color: flame,
            onTap: onStreakTap,
          ),
          const SizedBox(width: 8),
          GestureDetector(
            onTap: onProTap,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(AppRadius.pill),
                border: Border.all(color: p.accentText, width: 1.5),
              ),
              child: Text(
                'PRO',
                style: text.labelMedium!.copyWith(color: p.accentText, fontWeight: FontWeight.w800),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _AddTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _AddTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final text = Theme.of(context).textTheme;
    return AppCard(
      onTap: onTap,
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(color: p.accentSoft, shape: BoxShape.circle),
            child: Icon(icon, color: p.accentText),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: text.titleSmall),
                Text(subtitle, style: text.bodySmall),
              ],
            ),
          ),
          Icon(Icons.chevron_right_rounded, color: p.textMuted),
        ],
      ),
    );
  }
}
