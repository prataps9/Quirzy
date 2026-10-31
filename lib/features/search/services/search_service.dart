import 'package:shared_preferences/shared_preferences.dart';

import '../../feed/models/feed_models.dart';
import '../models/search_index.dart';

/// Builds the search index from everything the app keeps, and remembers
/// recent searches.
class SearchService {
  static const recentKey = 'search_recent';
  static const maxRecent = 8;

  /// One item per question (saved, mistake and note folded in), plus the
  /// flashcards. Questions from saved and mistakes count even if they have
  /// left the pool; notes only for questions still somewhere in the app.
  static SearchIndex build({
    required List<PracticeQuestion> pool,
    List<PracticeQuestion> saved = const [],
    List<PracticeQuestion> mistakes = const [],
    Map<String, String> notes = const {},
    Iterable<FeedFlashcard> cards = const [],
  }) {
    final savedKeys = {for (final q in saved) q.engagementKey};
    final mistakeKeys = {for (final q in mistakes) q.engagementKey};
    final byKey = <String, PracticeQuestion>{};
    for (final q in [...saved, ...mistakes, ...pool]) {
      byKey.putIfAbsent(q.engagementKey, () => q);
    }
    final items = [
      for (final e in byKey.entries)
        SearchItem.question(
          e.value,
          saved: savedKeys.contains(e.key),
          mistake: mistakeKeys.contains(e.key),
          note: notes[e.key],
        ),
      for (final c in {for (final c in cards) c.srsKey: c}.values) SearchItem.card(c),
    ];
    return SearchIndex(items);
  }

  Future<List<String>> recent() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getStringList(recentKey) ?? const [];
  }

  /// Puts [query] at the top of the recent list (once, ignoring case).
  Future<List<String>> addRecent(String query) async {
    final q = query.trim();
    final list = [...await recent()];
    if (q.length < 2) return list;
    list
      ..removeWhere((r) => r.toLowerCase() == q.toLowerCase())
      ..insert(0, q);
    final kept = list.take(maxRecent).toList();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(recentKey, kept);
    return kept;
  }

  Future<void> clearRecent() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(recentKey);
  }
}
