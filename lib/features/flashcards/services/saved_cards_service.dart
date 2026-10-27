import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../../feed/models/feed_models.dart';
import 'srs_service.dart';

/// Questions the user saved as flashcards from the practice feed. They live
/// on the device as one set, "Saved from practice", which shows up in Cards
/// and is reviewed with the same spaced repetition as any other set.
class SavedCardsService {
  SavedCardsService({SrsService? srs}) : _srs = srs ?? SrsService();

  static const setId = 'local_saved';
  static const setTitle = 'Saved from practice';
  static const _key = 'saved_cards_v1';
  static const maxCards = 300;

  final SrsService _srs;

  Future<List<Map<String, dynamic>>> _read() async {
    final prefs = await SharedPreferences.getInstance();
    try {
      final raw = prefs.getString(_key);
      if (raw == null) return [];
      return (jsonDecode(raw) as List).cast<Map<String, dynamic>>();
    } catch (_) {
      return [];
    }
  }

  Future<void> _write(List<Map<String, dynamic>> cards) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, jsonEncode(cards));
  }

  /// The card's text: the question, and the answer with its explanation.
  static ({String front, String back}) textFor(PracticeQuestion q) {
    final answer = (q.correctIndex >= 0 && q.correctIndex < q.options.length) ? q.options[q.correctIndex] : '';
    final explanation = q.explanation.trim();
    return (
      front: q.questionText.trim(),
      back: explanation.isEmpty ? answer : '$answer\n\n$explanation',
    );
  }

  Future<bool> isSaved(PracticeQuestion q) async {
    final key = q.engagementKey;
    return (await _read()).any((c) => c['k'] == key && (c['front'] as String).isNotEmpty);
  }

  /// Saves [q] and makes it due now. Returns false if it was already saved
  /// or the set is full. Indexes never shift, so review schedules stay valid.
  Future<bool> save(PracticeQuestion q) async {
    final cards = await _read();
    final key = q.engagementKey;
    if (cards.any((c) => c['k'] == key && (c['front'] as String).isNotEmpty)) return false;
    if (cards.length >= maxCards) return false;
    final text = textFor(q);
    if (text.front.isEmpty || text.back.isEmpty) return false;
    cards.add({'k': key, 'front': text.front, 'back': text.back, 'ms': DateTime.now().millisecondsSinceEpoch});
    await _write(cards);
    await _srs.enroll(setId, cards.length - 1);
    return true;
  }

  Future<int> count() async => (await _read()).where((c) => (c['front'] as String).isNotEmpty).length;

  /// The set in the shape the Cards tab uses for server sets, or null when
  /// nothing is saved yet.
  Future<Map<String, dynamic>?> asSet({bool withCards = false}) async {
    final all = await _read();
    final live = [
      for (var i = 0; i < all.length; i++)
        if ((all[i]['front'] as String).isNotEmpty) (i, all[i]),
    ];
    if (live.isEmpty) return null;
    return {
      'id': setId,
      'title': setTitle,
      'topic': 'Practice',
      'cardCount': live.length,
      if (withCards)
        'cards': [
          for (final (i, c) in live) {'front': c['front'], 'back': c['back'], 'cardNumber': i + 1},
        ],
    };
  }

  /// Cards by SRS key, for the feed.
  Future<Map<String, FeedFlashcard>> cardsByKey() async {
    final all = await _read();
    return {
      for (var i = 0; i < all.length; i++)
        if ((all[i]['front'] as String).isNotEmpty)
          '${setId}_$i': FeedFlashcard(
            setId: setId,
            index: i,
            front: all[i]['front'] as String,
            back: all[i]['back'] as String,
            setTitle: setTitle,
          ),
    };
  }

  /// Deletes every saved card and its review schedule.
  Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_key);
    await _srs.removeSet(setId);
  }
}
