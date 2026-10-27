import 'dart:convert';
import 'package:appwrite/appwrite.dart';
import '../../../shared/appwrite/appwrite_client.dart';
import 'flashcard_cache.dart';
import 'saved_cards_service.dart';

/// Flashcard Service using Appwrite. Errors (including [AppwriteException])
/// are passed through unchanged so the UI can turn them into friendly copy.
class FlashcardService {
  FlashcardService({SavedCardsService? saved}) : _saved = saved ?? SavedCardsService();

  /// Cards saved from the practice feed; they live on the device and show
  /// up beside the server sets.
  final SavedCardsService _saved;

  final Databases _db = AppwriteClient.instance.databases;
  final Functions _fn = AppwriteClient.instance.functions;
  final Account _account = AppwriteClient.instance.account;

  static const String setsCollection = 'flashcard_sets';
  static const String cardsCollection = 'flashcards';
  static const String generateFunction = 'flashcard-generate';

  // Generate Flashcards (calls Appwrite Function)
  Future<Map<String, dynamic>> generateFlashcards({
    required String topic,
    int cardCount = 10,
  }) async {
    final user = await _account.get();

    final execution = await _fn.createExecution(
      functionId: generateFunction,
      body: jsonEncode({
        'topic': topic,
        'cardCount': cardCount,
        'userId': user.$id,
      }),
    );

    if (execution.status.name == 'completed') {
      final response = jsonDecode(execution.responseBody);
      if (response['error'] != null) throw Exception(response['error']);
      return response;
    }
    throw Exception('Flashcard generation failed');
  }

  // Get My Flashcard Sets
  Future<List<Map<String, dynamic>>> getMyFlashcardSets() async {
    final user = await _account.get();
    final response = await _db.listDocuments(
      databaseId: AppwriteConfig.databaseId,
      collectionId: setsCollection,
      queries: [
        Query.equal('userId', user.$id),
        Query.orderDesc('createdAt'),
      ],
    );

    final sets = <Map<String, dynamic>>[];
    final saved = await _saved.asSet();
    if (saved != null) sets.add(saved);
    for (final doc in response.documents) {
      final cardsResponse = await _db.listDocuments(
        databaseId: AppwriteConfig.databaseId,
        collectionId: cardsCollection,
        queries: [Query.equal('setId', doc.$id)],
      );

      sets.add({
        'id': doc.$id,
        'title': doc.data['title'],
        'topic': doc.data['topic'],
        'cardCount': cardsResponse.total,
        'createdAt': doc.data['createdAt'],
      });
    }
    return sets;
  }

  // Get Flashcard Set by ID
  Future<Map<String, dynamic>> getFlashcardSetById(String setId) async {
    if (setId == SavedCardsService.setId) {
      final saved = await _saved.asSet(withCards: true);
      if (saved == null) throw const FormatException('No saved cards');
      return saved;
    }
    final set = await _db.getDocument(
      databaseId: AppwriteConfig.databaseId,
      collectionId: setsCollection,
      documentId: setId,
    );

    final cardsResponse = await _db.listDocuments(
      databaseId: AppwriteConfig.databaseId,
      collectionId: cardsCollection,
      queries: [Query.equal('setId', setId), Query.orderAsc('cardNumber')],
    );

    final result = {
      'id': set.$id,
      'title': set.data['title'],
      'topic': set.data['topic'],
      'cards': cardsResponse.documents.map((doc) {
        return {
          'id': doc.$id,
          'front': doc.data['front'],
          'back': doc.data['back'],
          'cardNumber': doc.data['cardNumber'],
          'timesReviewed': doc.data['timesReviewed'] ?? 0,
          'timesCorrect': doc.data['timesCorrect'] ?? 0,
        };
      }).toList(),
    };
    // Keep the text on the device so due cards can show up in the feed.
    await FlashcardCache.save(result);
    return result;
  }

  // Delete Flashcard Set
  Future<void> deleteFlashcardSet(String setId) async {
    if (setId == SavedCardsService.setId) return _saved.clear();
    final cards = await _db.listDocuments(
      databaseId: AppwriteConfig.databaseId,
      collectionId: cardsCollection,
      queries: [Query.equal('setId', setId)],
    );

    for (final card in cards.documents) {
      await _db.deleteDocument(
        databaseId: AppwriteConfig.databaseId,
        collectionId: cardsCollection,
        documentId: card.$id,
      );
    }

    await _db.deleteDocument(
      databaseId: AppwriteConfig.databaseId,
      collectionId: setsCollection,
      documentId: setId,
    );
  }

  // Update Card Progress
  Future<void> updateCardProgress({
    required String cardId,
    required bool known,
  }) async {
    final card = await _db.getDocument(
      databaseId: AppwriteConfig.databaseId,
      collectionId: cardsCollection,
      documentId: cardId,
    );

    await _db.updateDocument(
      databaseId: AppwriteConfig.databaseId,
      collectionId: cardsCollection,
      documentId: cardId,
      data: {
        'timesReviewed': (card.data['timesReviewed'] ?? 0) + 1,
        'timesCorrect': known
            ? (card.data['timesCorrect'] ?? 0) + 1
            : card.data['timesCorrect'] ?? 0,
        'lastReviewed': DateTime.now().toIso8601String(),
      },
    );
  }
}
