import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../feed/providers/feed_providers.dart';
import '../../flashcards/services/flashcard_cache.dart';
import '../models/search_index.dart';
import '../services/search_service.dart';

final searchServiceProvider = Provider<SearchService>((ref) => SearchService());

/// Everything searchable, gathered when search opens.
final searchIndexProvider = FutureProvider.autoDispose<SearchIndex>((ref) async {
  final pool = await ref.watch(feedQuestionPoolProvider.future);
  final saved = await ref.read(feedBookmarkServiceProvider).getBookmarks();
  final mistakes = await ref.read(mistakesServiceProvider).all();
  final notes = await ref.read(questionNotesServiceProvider).allNotes();
  final cached = await FlashcardCache.cardsByKey();
  final own = await ref.read(savedCardsServiceProvider).cardsByKey();
  return SearchService.build(
    pool: pool,
    saved: saved,
    mistakes: [for (final m in mistakes) m.question],
    notes: notes,
    cards: [...own.values, ...cached.values],
  );
});
