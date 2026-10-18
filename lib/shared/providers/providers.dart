import 'package:flutter_riverpod/legacy.dart';
import '../services/settings_service.dart';

/// Tab index provider for bottom navigation
final tabIndexProvider = StateProvider<int>((ref) => 0);

/// A topic another screen wants pre-filled in Home's "What do you want to
/// practise?" box (e.g. the feed's "Generate more"). Home clears it once
/// it has filled the box.
final homeTopicDraftProvider = StateProvider<String?>((ref) => null);

/// Settings provider using ChangeNotifierProvider
final settingsProvider = ChangeNotifierProvider<SettingsService>(
  (ref) => SettingsService(),
);
