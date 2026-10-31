import '../../feed/models/feed_models.dart';

/// What a search can be narrowed to.
enum SearchFilter {
  all('All'),
  questions('Questions'),
  saved('Saved'),
  mistakes('Mistakes'),
  notes('Notes'),
  cards('Cards');

  const SearchFilter(this.label);
  final String label;
}

/// One searchable thing: a question (with whether it is saved, in the
/// Mistakes notebook, and the user's note on it) or a flashcard.
class SearchItem {
  final PracticeQuestion? question;
  final FeedFlashcard? card;
  final bool saved;
  final bool mistake;
  final String? note;

  final String _primary;
  final String _secondary;

  SearchItem.question(PracticeQuestion this.question, {this.saved = false, this.mistake = false, this.note})
    : card = null,
      _primary = SearchIndex.normalize(question.questionText),
      _secondary = SearchIndex.normalize(
        [...question.options, question.explanation, note ?? '', question.topicName].join('\n'),
      );

  SearchItem.card(FeedFlashcard this.card)
    : question = null,
      saved = false,
      mistake = false,
      note = null,
      _primary = SearchIndex.normalize(card.front),
      _secondary = SearchIndex.normalize('${card.back}\n${card.setTitle}');

  bool get isCard => card != null;

  bool get hasNote => note != null && note!.trim().isNotEmpty;

  /// The question, or the card's front.
  String get title => question?.questionText ?? card!.front;

  /// The topic, or the card's set.
  String get topic => question?.topicName ?? card!.setTitle;

  /// A stable id for list keys.
  String get id => question?.engagementKey ?? 'card:${card!.srsKey}';

  bool passes(SearchFilter filter) => switch (filter) {
    SearchFilter.all => true,
    SearchFilter.questions => !isCard,
    SearchFilter.saved => saved,
    SearchFilter.mistakes => mistake,
    SearchFilter.notes => hasNote,
    SearchFilter.cards => isCard,
  };

  SearchItem copyWith({bool? saved, String? note}) {
    final q = question;
    if (q == null) return this;
    return SearchItem.question(q, saved: saved ?? this.saved, mistake: mistake, note: note ?? this.note);
  }
}

/// How well an item matched; higher is better.
enum MatchStrength { elsewhere, allWordsInTitle, phraseInTitle }

class SearchHit {
  final SearchItem item;
  final MatchStrength strength;

  const SearchHit(this.item, this.strength);
}

/// Everything the user can search, matched word by word. Case and accents
/// are ignored, every word has to appear, and a phrase in the question
/// itself ranks above words spread across the options or a note.
class SearchIndex {
  final List<SearchItem> items;

  SearchIndex(this.items);

  static const _accents = {
    'à': 'a', 'á': 'a', 'â': 'a', 'ã': 'a', 'ä': 'a', 'å': 'a', 'ā': 'a', //
    'ç': 'c', 'è': 'e', 'é': 'e', 'ê': 'e', 'ë': 'e', 'ē': 'e', //
    'ì': 'i', 'í': 'i', 'î': 'i', 'ï': 'i', 'ī': 'i', 'ñ': 'n', //
    'ò': 'o', 'ó': 'o', 'ô': 'o', 'õ': 'o', 'ö': 'o', 'ø': 'o', 'ō': 'o', //
    'ù': 'u', 'ú': 'u', 'û': 'u', 'ü': 'u', 'ū': 'u', 'ý': 'y', 'ÿ': 'y', //
  };

  /// Lower case without accents. Keeps the length, so a match found in the
  /// normalised text is at the same place in the original.
  static String normalize(String text) {
    final out = StringBuffer();
    for (var i = 0; i < text.length; i++) {
      final c = text[i];
      final lower = c.toLowerCase();
      final single = lower.length == 1 ? lower : c;
      out.write(_accents[single] ?? single);
    }
    return out.toString();
  }

  static final _wordBreak = RegExp(r'[^\p{L}\p{N}]+', unicode: true);

  /// The words of [query], normalised, without repeats.
  static List<String> terms(String query) =>
      normalize(query).split(_wordBreak).where((w) => w.isNotEmpty).toSet().toList();

  /// Topics across all items, A to Z.
  late final List<String> topics = (items.map((i) => i.topic).toSet().toList()..sort());

  List<SearchHit> search(String query, {SearchFilter filter = SearchFilter.all, String? topic, int limit = 100}) {
    final words = terms(query);
    if (words.isEmpty) return const [];
    final phrase = words.join(' ');
    final hits = <SearchHit>[];
    for (final item in items) {
      if (!item.passes(filter)) continue;
      if (topic != null && item.topic != topic) continue;
      final inTitle = words.every(item._primary.contains);
      if (!inTitle && !words.every((w) => item._primary.contains(w) || item._secondary.contains(w))) continue;
      final strength = !inTitle
          ? MatchStrength.elsewhere
          : _hasPhrase(item._primary, phrase)
          ? MatchStrength.phraseInTitle
          : MatchStrength.allWordsInTitle;
      hits.add(SearchHit(item, strength));
    }
    hits.sort((a, b) {
      final byStrength = b.strength.index.compareTo(a.strength.index);
      if (byStrength != 0) return byStrength;
      // The user's own things first, then shorter (more to the point) ones.
      final byOwn = _own(b.item).compareTo(_own(a.item));
      if (byOwn != 0) return byOwn;
      return a.item.title.length.compareTo(b.item.title.length);
    });
    return hits.length > limit ? hits.sublist(0, limit) : hits;
  }

  static int _own(SearchItem i) => (i.saved ? 1 : 0) + (i.mistake ? 1 : 0) + (i.hasNote ? 1 : 0);

  /// The phrase with words separated by anything but letters and numbers.
  static bool _hasPhrase(String text, String phrase) {
    if (text.contains(phrase)) return true;
    return text.split(_wordBreak).where((w) => w.isNotEmpty).join(' ').contains(phrase);
  }

  /// Where [words] appear in [text], as sorted, merged (start, end) ranges.
  static List<(int, int)> matches(String text, List<String> words) {
    final norm = normalize(text);
    final ranges = <(int, int)>[];
    for (final w in words) {
      var from = 0;
      while (true) {
        final at = norm.indexOf(w, from);
        if (at < 0) break;
        ranges.add((at, at + w.length));
        from = at + w.length;
      }
    }
    ranges.sort((a, b) => a.$1.compareTo(b.$1));
    final merged = <(int, int)>[];
    for (final r in ranges) {
      if (merged.isNotEmpty && r.$1 <= merged.last.$2) {
        final last = merged.removeLast();
        merged.add((last.$1, r.$2 > last.$2 ? r.$2 : last.$2));
      } else {
        merged.add(r);
      }
    }
    return merged;
  }

  /// A short piece of the item's other text that shows why it matched:
  /// the first line (option, explanation, note or card back) holding a word.
  static String? snippet(SearchItem item, List<String> words) {
    final q = item.question;
    final lines = q != null ? [if (item.hasNote) item.note!, ...q.options, q.explanation] : [item.card!.back];
    for (final line in lines) {
      final norm = normalize(line);
      if (words.any(norm.contains)) return line;
    }
    return null;
  }
}
