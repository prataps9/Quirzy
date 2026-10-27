import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../shared/providers/providers.dart';
import '../../../shared/services/notification_scheduler.dart';
import '../../../shared/theme/app_motion.dart';
import '../../../shared/utils/user_messages.dart';
import '../../../shared/widgets/quirzy_navigation_bar.dart';
import '../../feed/providers/feed_providers.dart';
import '../../feed/screens/feed_screen.dart';
import '../../feed/services/leaderboard_sync.dart';
import '../../flashcards/screens/screens.dart';
import '../../onboarding/screens/screens.dart';
import '../../profile/screens/screens.dart';
import '../../progress/screens/my_prep_screen.dart';
import 'home_screen.dart';

/// The signed-in shell: five tabs with Practice first.
///
/// Tabs are built the first time they are opened (then kept alive), so
/// launch only does the Practice tab's work. Back on another tab returns to
/// Practice; on Practice it takes a second press to leave the app.
class MainScreen extends ConsumerStatefulWidget {
  const MainScreen({super.key});

  @override
  ConsumerState<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends ConsumerState<MainScreen> {
  static const _exitWindow = Duration(seconds: 2);

  final Set<int> _builtTabs = {0};
  DateTime? _lastBackPress;

  @override
  void initState() {
    super.initState();
    _builtTabs.add(ref.read(tabIndexProvider));
    _onAppOpen();
  }

  Future<void> _onAppOpen() async {
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getString('selected_exam') == null && mounted) {
      await Navigator.of(context).push(MaterialPageRoute(builder: (_) => const ExamSelectionScreen()));
    }
    if (!mounted) return;
    // Ask for notification permission once, after onboarding rather than
    // on a cold first frame, so reminders can actually be delivered.
    await ref.read(notificationSchedulerProvider).requestPermissionOnce();
    if (!mounted) return;
    // Reschedule reminders from fresh data and push the latest score to the
    // leaderboard. Both are fire-and-forget and never throw.
    unawaited(ref.read(leaderboardSyncProvider).syncNow());
    unawaited(ref.read(notificationSchedulerProvider).onAppOpen());
  }

  Widget _tab(int index) {
    if (!_builtTabs.contains(index)) return const SizedBox.shrink();
    return RepaintBoundary(
      child: switch (index) {
        0 => const FeedScreen(),
        1 => const HomeScreen(),
        2 => const MyPrepScreen(),
        3 => const FlashcardsScreen(),
        _ => const ProfileSettingsScreen(),
      },
    );
  }

  void _handleBack(bool didPop, Object? result) {
    if (didPop) return;
    final tabs = ref.read(tabIndexProvider.notifier);
    if (tabs.state != 0) {
      tabs.state = 0;
      return;
    }
    final now = DateTime.now();
    if (_lastBackPress != null && now.difference(_lastBackPress!) < _exitWindow) {
      SystemNavigator.pop();
      return;
    }
    _lastBackPress = now;
    showAppSnack(context, 'Press back again to exit', duration: _exitWindow);
  }

  @override
  Widget build(BuildContext context) {
    final selectedIndex = ref.watch(tabIndexProvider);
    _builtTabs.add(selectedIndex);
    ref.listen<int>(tabIndexProvider, (_, next) {
      ref.read(feedControllerProvider.notifier).setTabVisible(next == 0);
    });

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: _handleBack,
      child: Scaffold(
        body: _FadingIndexedStack(index: selectedIndex, children: [for (var i = 0; i < 5; i++) _tab(i)]),
        bottomNavigationBar: QuirzyNavigationBar(
          selectedIndex: selectedIndex,
          onDestinationSelected: (index) {
            HapticFeedback.lightImpact();
            ref.read(tabIndexProvider.notifier).state = index;
          },
        ),
      ),
    );
  }
}

/// An [IndexedStack] that fades the newly shown tab in, so switching tabs
/// doesn't snap. Every tab stays alive underneath, as with a plain stack.
class _FadingIndexedStack extends StatefulWidget {
  final int index;
  final List<Widget> children;

  const _FadingIndexedStack({required this.index, required this.children});

  @override
  State<_FadingIndexedStack> createState() => _FadingIndexedStackState();
}

class _FadingIndexedStackState extends State<_FadingIndexedStack> with SingleTickerProviderStateMixin {
  late final AnimationController _fade = AnimationController(vsync: this, duration: AppMotion.base, value: 1);
  late final Animation<double> _opacity = Tween<double>(
    begin: 0.35,
    end: 1,
  ).animate(CurvedAnimation(parent: _fade, curve: AppMotion.enter));

  @override
  void didUpdateWidget(_FadingIndexedStack old) {
    super.didUpdateWidget(old);
    if (old.index != widget.index && !AppMotion.reduced(context)) _fade.forward(from: 0);
  }

  @override
  void dispose() {
    _fade.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _opacity,
      child: IndexedStack(index: widget.index, children: widget.children),
    );
  }
}
