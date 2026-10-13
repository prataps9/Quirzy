import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Owns the root [ProviderScope]. [restart] throws the whole scope away and
/// builds a fresh one, so every provider (feed, XP, streak, Pro…) reloads
/// from storage — used after logout or account deletion so nothing from the
/// previous user lingers in memory.
class AppRestartScope extends StatefulWidget {
  final Widget child;

  const AppRestartScope({super.key, required this.child});

  static void restart(BuildContext context) {
    context.findAncestorStateOfType<_AppRestartScopeState>()?._restart();
  }

  @override
  State<AppRestartScope> createState() => _AppRestartScopeState();
}

class _AppRestartScopeState extends State<AppRestartScope> {
  Key _key = UniqueKey();

  void _restart() => setState(() => _key = UniqueKey());

  @override
  Widget build(BuildContext context) {
    return ProviderScope(key: _key, child: widget.child);
  }
}
