import 'package:appwrite/appwrite.dart';
import 'package:flutter/foundation.dart';
import '../appwrite_client.dart';

/// Leaderboard Service - Social competition and rankings
class LeaderboardService {
  static LeaderboardService? _instance;
  final Databases _db = AppwriteClient.instance.databases;

  factory LeaderboardService() {
    _instance ??= LeaderboardService._internal();
    return _instance!;
  }

  LeaderboardService._internal();

  /// Update user's leaderboard entry
  Future<void> updateLeaderboard({
    required String userId,
    required String userName,
    required int totalXP,
    required int quizzesCompleted,
    required int currentStreak,
    required String rank,
  }) async {
    try {
      // Check if user already has an entry
      final existing = await _db.listDocuments(
        databaseId: AppwriteConfig.databaseId,
        collectionId: AppwriteConfig.leaderboardCollection,
        queries: [Query.equal('userId', userId)],
      );

      final data = {
        'userId': userId,
        'userName': userName,
        'totalXP': totalXP,
        'quizzesCompleted': quizzesCompleted,
        'currentStreak': currentStreak,
        'rank': rank,
        'updatedAt': DateTime.now().toIso8601String(),
      };

      if (existing.documents.isNotEmpty) {
        await _db.updateDocument(
          databaseId: AppwriteConfig.databaseId,
          collectionId: AppwriteConfig.leaderboardCollection,
          documentId: existing.documents.first.$id,
          data: data,
        );
      } else {
        await _db.createDocument(
          databaseId: AppwriteConfig.databaseId,
          collectionId: AppwriteConfig.leaderboardCollection,
          documentId: ID.unique(),
          data: data,
        );
      }
    } catch (e) {
      debugPrint('LeaderboardService: Update error: $e');
    }
  }

  /// Removes [userId]'s row from the board (on account deletion).
  Future<void> removeEntry(String userId) async {
    final existing = await _db.listDocuments(
      databaseId: AppwriteConfig.databaseId,
      collectionId: AppwriteConfig.leaderboardCollection,
      queries: [Query.equal('userId', userId)],
    );
    for (final doc in existing.documents) {
      await _db.deleteDocument(
        databaseId: AppwriteConfig.databaseId,
        collectionId: AppwriteConfig.leaderboardCollection,
        documentId: doc.$id,
      );
    }
  }

  /// Get top players
  Future<List<Map<String, dynamic>>> getTopPlayers({int limit = 50}) async {
    try {
      final result = await _db.listDocuments(
        databaseId: AppwriteConfig.databaseId,
        collectionId: AppwriteConfig.leaderboardCollection,
        queries: [
          Query.orderDesc('totalXP'),
          Query.limit(limit),
        ],
      );

      return result.documents.map((doc) => doc.data).toList();
    } catch (e) {
      debugPrint('LeaderboardService: Get top players error: $e');
      return [];
    }
  }

  /// Get user's rank
  Future<Map<String, dynamic>> getUserRank({required String userId}) async {
    try {
      final result = await _db.listDocuments(
        databaseId: AppwriteConfig.databaseId,
        collectionId: AppwriteConfig.leaderboardCollection,
        queries: [Query.equal('userId', userId)],
      );

      if (result.documents.isEmpty) {
        return {'rank': 'Unranked', 'totalXP': 0};
      }

      final userDoc = result.documents.first;
      final userXP = (userDoc.data['totalXP'] as num?)?.toInt() ?? 0;

      // Rank = players with strictly more XP + 1. Only the count is needed.
      final ahead = await _db.listDocuments(
        databaseId: AppwriteConfig.databaseId,
        collectionId: AppwriteConfig.leaderboardCollection,
        queries: [
          Query.greaterThan('totalXP', userXP),
          Query.limit(1),
        ],
      );
      final position = ahead.total + 1;

      return {
        'position': position,
        'totalXP': userXP,
        'rank': userDoc.data['rank'],
      };
    } catch (e) {
      debugPrint('LeaderboardService: Get rank error: $e');
      return {'position': -1, 'totalXP': 0, 'rank': 'Unranked'};
    }
  }
}
