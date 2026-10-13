import 'package:flutter_riverpod/legacy.dart';
import '../services/settings_service.dart';

/// Tab index provider for bottom navigation
final tabIndexProvider = StateProvider<int>((ref) => 0);

/// Settings provider using ChangeNotifierProvider
final settingsProvider = ChangeNotifierProvider<SettingsService>(
  (ref) => SettingsService(),
);
