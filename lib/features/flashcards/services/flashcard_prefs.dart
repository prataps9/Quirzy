import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Local, per-device flashcard preferences: favourite sets and when each set
/// was last studied.
class FlashcardPrefsState {
  final Set<String> favourites;
  final Map<String, DateTime> lastStudied;

  const FlashcardPrefsState({
    this.favourites = const {},
    this.lastStudied = const {},
  });

  bool isFavourite(String setId) => favourites.contains(setId);

  /// Set IDs that have been studied, most recent first.
  List<String> get recentIds {
    final entries = lastStudied.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return [for (final e in entries) e.key];
  }
}

class FlashcardPrefsService {
  static const favouritesKey = 'flashcard_favourites';
  static const lastStudiedKey = 'flashcard_last_studied';

  final DateTime Function() _clock;

  FlashcardPrefsService({DateTime Function()? clock})
    : _clock = clock ?? DateTime.now;

  Future<FlashcardPrefsState> load() async {
    final prefs = await SharedPreferences.getInstance();
    return FlashcardPrefsState(
      favourites: (prefs.getStringList(favouritesKey) ?? const []).toSet(),
      lastStudied: _readLastStudied(prefs),
    );
  }

  /// Flips the favourite flag. Returns true if the set is now a favourite.
  Future<bool> toggleFavourite(String setId) async {
    final prefs = await SharedPreferences.getInstance();
    final favourites = (prefs.getStringList(favouritesKey) ?? const []).toSet();
    final nowFavourite = favourites.add(setId);
    if (!nowFavourite) favourites.remove(setId);
    await prefs.setStringList(favouritesKey, favourites.toList());
    return nowFavourite;
  }

  Future<void> markStudied(String setId) async {
    final prefs = await SharedPreferences.getInstance();
    final map = _readLastStudied(prefs)..[setId] = _clock();
    await _writeLastStudied(prefs, map);
  }

  /// Forgets a set entirely (used after the set is deleted).
  Future<void> remove(String setId) async {
    final prefs = await SharedPreferences.getInstance();
    final favourites = (prefs.getStringList(favouritesKey) ?? const []).toSet()
      ..remove(setId);
    await prefs.setStringList(favouritesKey, favourites.toList());
    final map = _readLastStudied(prefs)..remove(setId);
    await _writeLastStudied(prefs, map);
  }

  Map<String, DateTime> _readLastStudied(SharedPreferences prefs) {
    final raw = prefs.getString(lastStudiedKey);
    if (raw == null) return {};
    try {
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      final result = <String, DateTime>{};
      decoded.forEach((id, value) {
        final at = value is String ? DateTime.tryParse(value) : null;
        if (at != null) result[id] = at;
      });
      return result;
    } catch (_) {
      return {};
    }
  }

  Future<void> _writeLastStudied(
    SharedPreferences prefs,
    Map<String, DateTime> map,
  ) {
    return prefs.setString(
      lastStudiedKey,
      jsonEncode(map.map((k, v) => MapEntry(k, v.toIso8601String()))),
    );
  }
}

final flashcardPrefsServiceProvider = Provider<FlashcardPrefsService>(
  (ref) => FlashcardPrefsService(),
);

class FlashcardPrefsController extends AsyncNotifier<FlashcardPrefsState> {
  FlashcardPrefsService get _service => ref.read(flashcardPrefsServiceProvider);

  @override
  Future<FlashcardPrefsState> build() => _service.load();

  Future<void> toggleFavourite(String setId) async {
    await _service.toggleFavourite(setId);
    state = AsyncData(await _service.load());
  }

  Future<void> markStudied(String setId) async {
    await _service.markStudied(setId);
    state = AsyncData(await _service.load());
  }

  Future<void> remove(String setId) async {
    await _service.remove(setId);
    state = AsyncData(await _service.load());
  }
}

final flashcardPrefsProvider =
    AsyncNotifierProvider<FlashcardPrefsController, FlashcardPrefsState>(
      FlashcardPrefsController.new,
    );
