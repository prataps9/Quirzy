import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../../feed/models/feed_models.dart';

/// Keeps the text of recently opened flashcard sets on the device, so due
/// cards can be reviewed in the practice feed without the network.
class FlashcardCache {
  static const _key = 'flashcard_cache_v1';
  static const maxSets = 30;

  /// Stores [set] (the map [FlashcardService.getFlashcardSetById] returns),
  /// most recent first, keeping at most [maxSets].
  static Future<void> save(Map<String, dynamic> set) async {
    final id = set['id'] as String?;
    final cards = set['cards'] as List?;
    if (id == null || cards == null || cards.isEmpty) return;

    final prefs = await SharedPreferences.getInstance();
    final all = _read(prefs)..removeWhere((s) => s['id'] == id);
    all.insert(0, {
      'id': id,
      'title': (set['title'] ?? set['topic'] ?? 'Flashcards').toString(),
      'cards': [
        for (final c in cards)
          {'front': (c as Map)['front']?.toString() ?? '', 'back': c['back']?.toString() ?? ''},
      ],
    });
    await prefs.setString(_key, jsonEncode(all.take(maxSets).toList()));
  }

  static Future<void> remove(String setId) async {
    final prefs = await SharedPreferences.getInstance();
    final all = _read(prefs)..removeWhere((s) => s['id'] == setId);
    await prefs.setString(_key, jsonEncode(all));
  }

  /// The cached card for an SRS key (`<setId>_<index>`), if any.
  static Future<Map<String, FeedFlashcard>> cardsByKey() async {
    final prefs = await SharedPreferences.getInstance();
    final out = <String, FeedFlashcard>{};
    for (final set in _read(prefs)) {
      final cards = set['cards'] as List;
      for (var i = 0; i < cards.length; i++) {
        final c = cards[i] as Map;
        final card = FeedFlashcard(
          setId: set['id'] as String,
          index: i,
          front: c['front'] as String,
          back: c['back'] as String,
          setTitle: set['title'] as String,
        );
        if (card.front.trim().isEmpty || card.back.trim().isEmpty) continue;
        out[card.srsKey] = card;
      }
    }
    return out;
  }

  static List<Map<String, dynamic>> _read(SharedPreferences prefs) {
    try {
      final raw = prefs.getString(_key);
      if (raw == null) return [];
      return (jsonDecode(raw) as List).cast<Map<String, dynamic>>();
    } catch (_) {
      return [];
    }
  }
}
