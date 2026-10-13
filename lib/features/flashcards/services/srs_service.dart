import 'dart:convert';
import 'dart:math';
import 'package:shared_preferences/shared_preferences.dart';

import '../../feed/services/streak_service.dart';

enum SrsRating { again, hard, good, easy }

class SrsCard {
  final String key;
  double easeFactor;
  int interval; // days
  int repetitions;
  DateTime dueDate;

  SrsCard({
    required this.key,
    this.easeFactor = 2.5,
    this.interval = 1,
    this.repetitions = 0,
    DateTime? dueDate,
  }) : dueDate = dueDate ?? DateTime.now();

  bool get isDue {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final due = DateTime(dueDate.year, dueDate.month, dueDate.day);
    return !today.isBefore(due);
  }

  bool get isNew => repetitions == 0;

  String get nextReviewText {
    if (interval <= 1) return 'Tomorrow';
    if (interval < 7) return 'In $interval days';
    final weeks = (interval / 7).round();
    if (interval < 30) return 'In $weeks week${weeks > 1 ? 's' : ''}';
    final months = (interval / 30).round();
    return 'In $months month${months > 1 ? 's' : ''}';
  }

  Map<String, dynamic> toJson() => {
    'ef': easeFactor,
    'i': interval,
    'r': repetitions,
    'd': dueDate.toIso8601String(),
  };

  factory SrsCard.fromJson(String key, Map<String, dynamic> j) => SrsCard(
    key: key,
    easeFactor: (j['ef'] as num?)?.toDouble() ?? 2.5,
    interval: (j['i'] as int?) ?? 1,
    repetitions: (j['r'] as int?) ?? 0,
    dueDate: j['d'] != null ? DateTime.parse(j['d'] as String) : DateTime.now(),
  );
}

/// SM-2 spaced repetition algorithm — all data stored locally in SharedPreferences.
class SrsService {
  static const _prefsKey = 'srs_v1';

  Future<Map<String, SrsCard>> _loadAll() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_prefsKey);
    if (raw == null) return {};
    final map = jsonDecode(raw) as Map<String, dynamic>;
    return map.map((k, v) => MapEntry(k, SrsCard.fromJson(k, v as Map<String, dynamic>)));
  }

  Future<void> _saveAll(Map<String, SrsCard> cards) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsKey, jsonEncode(
      cards.map((k, v) => MapEntry(k, v.toJson())),
    ));
  }

  String cardKey(String setId, int index) => '${setId}_$index';

  /// Rate a card using SM-2. Returns the updated card so the UI can show nextReviewText.
  Future<SrsCard> rateCard(String setId, int cardIndex, SrsRating rating) async {
    final cards = await _loadAll();
    final key = cardKey(setId, cardIndex);
    final card = cards[key] ?? SrsCard(key: key);

    final q = rating.index; // 0=again, 1=hard, 2=good, 3=easy

    if (q < 2) {
      // Failed — reset streak
      card.repetitions = 0;
      card.interval = 1;
    } else {
      // Passed — advance schedule
      if (card.repetitions == 0) {
        card.interval = 1;
      } else if (card.repetitions == 1) {
        card.interval = 6;
      } else {
        card.interval = (card.interval * card.easeFactor).round();
      }
      card.easeFactor = max(
        1.3,
        card.easeFactor + 0.1 - (3 - q) * 0.08 - pow(3 - q, 2).toDouble() * 0.02,
      );
      card.repetitions++;
    }

    card.dueDate = DateTime.now().add(Duration(days: card.interval));
    cards[key] = card;
    await _saveAll(cards);
    await StreakService().recordFlashcardReview();
    return card;
  }

  /// Returns indices of cards due for review today (new cards are always due).
  Future<List<int>> getDueIndices(String setId, int totalCards) async {
    final cards = await _loadAll();
    final due = <int>[];
    for (int i = 0; i < totalCards; i++) {
      final key = cardKey(setId, i);
      final card = cards[key];
      if (card == null || card.isDue) due.add(i);
    }
    return due;
  }

  Future<SrsCard> getCard(String setId, int cardIndex) async {
    final cards = await _loadAll();
    final key = cardKey(setId, cardIndex);
    return cards[key] ?? SrsCard(key: key);
  }

  /// Stats summary for a set: due, learning, review, new counts.
  Future<Map<String, int>> getSetStats(String setId, int totalCards) async {
    final cards = await _loadAll();
    int due = 0, learning = 0, review = 0, newCount = 0;
    for (int i = 0; i < totalCards; i++) {
      final key = cardKey(setId, i);
      final card = cards[key];
      if (card == null) {
        newCount++;
        due++;
      } else {
        if (card.isDue) due++;
        if (card.repetitions == 0) {
          learning++;
        } else {
          review++;
        }
      }
    }
    return {'due': due, 'learning': learning, 'review': review, 'new': newCount};
  }
}
