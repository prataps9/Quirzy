import 'package:flutter_riverpod/legacy.dart';

/// Places an app shortcut (long-press the icon) or a `quirzy://` link can
/// open.
enum AppAction { practice, daily, mockTest, mistakes, search }

/// An action waiting to be opened. Set by the deep-link handler (which may
/// run before sign-in); the signed-in app shell opens it and clears it.
final pendingAppActionProvider = StateProvider<AppAction?>((ref) => null);
