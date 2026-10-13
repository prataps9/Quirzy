import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class SettingsService extends ChangeNotifier {
  static final SettingsService _instance = SettingsService._internal();
  factory SettingsService() => _instance;
  SettingsService._internal();

  static const _themeKey = 'theme_mode';
  static const autoAdvanceKey = 'feed_auto_advance';
  static const readAloudKey = 'feed_read_aloud';
  static const soundEffectsKey = 'feed_sound_effects';

  /// Device preferences that survive logout (see LocalDataReset).
  static const deviceKeys = {_themeKey, autoAdvanceKey, readAloudKey, soundEffectsKey};

  /// Dark is the default look; the choice is remembered across launches.
  ThemeMode _themeMode = ThemeMode.dark;
  ThemeMode get themeMode => _themeMode;

  /// Practice feed: move to the next card after a correct answer.
  bool _autoAdvance = true;
  bool get autoAdvance => _autoAdvance;

  /// Practice feed: read each card aloud. Off by default.
  bool _readAloud = false;
  bool get readAloud => _readAloud;

  /// Practice feed: short correct/wrong sounds. Off by default.
  bool _soundEffects = false;
  bool get soundEffects => _soundEffects;

  /// This is a process-wide singleton, so a provider tearing down its scope
  /// must not dispose it for everyone else — hence no `super.dispose()`.
  @override
  // ignore: must_call_super
  void dispose() {}

  Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    _themeMode = _parseThemeMode(prefs.getString(_themeKey));
    _autoAdvance = prefs.getBool(autoAdvanceKey) ?? true;
    _readAloud = prefs.getBool(readAloudKey) ?? false;
    _soundEffects = prefs.getBool(soundEffectsKey) ?? false;
  }

  static ThemeMode _parseThemeMode(String? value) {
    switch (value) {
      case 'light':
        return ThemeMode.light;
      case 'system':
        return ThemeMode.system;
      default:
        return ThemeMode.dark;
    }
  }

  void setThemeMode(ThemeMode mode) {
    if (_themeMode == mode) return;
    _themeMode = mode;
    notifyListeners();
    SharedPreferences.getInstance().then((prefs) => prefs.setString(_themeKey, mode.name));
  }

  void setAutoAdvance(bool value) => _setBool(autoAdvanceKey, value, () => _autoAdvance = value, _autoAdvance);

  void setReadAloud(bool value) => _setBool(readAloudKey, value, () => _readAloud = value, _readAloud);

  void setSoundEffects(bool value) =>
      _setBool(soundEffectsKey, value, () => _soundEffects = value, _soundEffects);

  void _setBool(String key, bool value, VoidCallback apply, bool current) {
    if (current == value) return;
    apply();
    notifyListeners();
    SharedPreferences.getInstance().then((prefs) => prefs.setBool(key, value));
  }
}
