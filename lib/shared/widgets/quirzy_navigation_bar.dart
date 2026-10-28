import 'package:flutter/material.dart';

import '../theme/app_motion.dart';
import '../theme/app_palette.dart';

/// The bottom bar. Colours and label styles come from the app theme, so
/// this only declares the five destinations and a hairline on top.
class QuirzyNavigationBar extends StatelessWidget {
  final int selectedIndex;
  final ValueChanged<int> onDestinationSelected;

  const QuirzyNavigationBar({
    super.key,
    required this.selectedIndex,
    required this.onDestinationSelected,
  });

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: p.bg,
        border: Border(top: BorderSide(color: p.border)),
      ),
      child: NavigationBar(
        selectedIndex: selectedIndex,
        onDestinationSelected: onDestinationSelected,
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.bolt_outlined),
            selectedIcon: _Pop(child: Icon(Icons.bolt_rounded)),
            label: 'Practice',
          ),
          NavigationDestination(
            icon: Icon(Icons.grid_view_outlined),
            selectedIcon: _Pop(child: Icon(Icons.grid_view_rounded)),
            label: 'Home',
          ),
          NavigationDestination(
            icon: Icon(Icons.trending_up_rounded),
            selectedIcon: _Pop(child: Icon(Icons.trending_up_rounded)),
            label: 'My Prep',
          ),
          NavigationDestination(
            icon: Icon(Icons.style_outlined),
            selectedIcon: _Pop(child: Icon(Icons.style_rounded)),
            label: 'Cards',
          ),
          NavigationDestination(
            icon: Icon(Icons.person_outline_rounded),
            selectedIcon: _Pop(child: Icon(Icons.person_rounded)),
            label: 'Profile',
          ),
        ],
      ),
    );
  }
}

/// The selected tab's icon springs up a little when it is chosen.
class _Pop extends StatelessWidget {
  final Widget child;

  const _Pop({required this.child});

  @override
  Widget build(BuildContext context) {
    if (AppMotion.reduced(context)) return child;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0.72, end: 1),
      duration: const Duration(milliseconds: 420),
      curve: Curves.easeOutBack,
      builder: (context, scale, child) => Transform.scale(scale: scale, child: child),
      child: child,
    );
  }
}
