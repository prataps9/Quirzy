import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../shared/providers/providers.dart';
import 'home_screen.dart';
import '../../feed/providers/feed_providers.dart';
import '../../feed/screens/feed_screen.dart';
import '../../flashcards/screens/screens.dart';
import '../../profile/screens/screens.dart';
import '../../onboarding/screens/screens.dart';
import '../../progress/screens/my_prep_screen.dart';

import 'package:shared_preferences/shared_preferences.dart';

import '../../../shared/widgets/quirzy_navigation_bar.dart';

class MainScreen extends ConsumerStatefulWidget {
  const MainScreen({super.key});

  @override
  ConsumerState<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends ConsumerState<MainScreen> {
  @override
  void initState() {
    super.initState();
    _checkOnboarding();
  }

  Future<void> _checkOnboarding() async {
    final prefs = await SharedPreferences.getInstance();

    if (prefs.getString('selected_exam') == null) {
      if (mounted) {
        await Navigator.of(
          context,
        ).push(MaterialPageRoute(builder: (_) => const ExamSelectionScreen()));
      }
    }
  }

  // Screens list — Practice (the ScrollPrep-style feed) is the default tab.
  List<Widget> get _screens => const [
    RepaintBoundary(child: FeedScreen()),
    RepaintBoundary(child: HomeScreen()),
    RepaintBoundary(child: MyPrepScreen()),
    RepaintBoundary(child: FlashcardsScreen()),
    RepaintBoundary(child: ProfileSettingsScreen()),
  ];

  @override
  Widget build(BuildContext context) {
    final selectedIndex = ref.watch(tabIndexProvider);
    ref.listen<int>(tabIndexProvider, (_, next) {
      ref.read(feedControllerProvider.notifier).setTabVisible(next == 0);
    });

    return Scaffold(
      body: IndexedStack(index: selectedIndex, children: _screens),
      bottomNavigationBar: QuirzyNavigationBar(
        selectedIndex: selectedIndex,
        onDestinationSelected: (index) {
          HapticFeedback.lightImpact();
          ref.read(tabIndexProvider.notifier).state = index;
        },
      ),
    );
  }
}
