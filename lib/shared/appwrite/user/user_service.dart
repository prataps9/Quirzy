import 'package:appwrite/appwrite.dart';
import 'package:appwrite/models.dart';
import 'package:flutter/foundation.dart';
import '../appwrite_client.dart';
import '../leaderboard/leaderboard_service.dart';

/// User Service - Complete user management with Appwrite
/// 
/// Features:
/// - User profile CRUD operations
/// - User statistics tracking
/// - Avatar management
/// - Account settings
class UserService {
  static UserService? _instance;
  final Databases _db = AppwriteClient.instance.databases;
  final Storage _storage = AppwriteClient.instance.storage;

  factory UserService() {
    _instance ??= UserService._internal();
    return _instance!;
  }

  UserService._internal();

  // ==========================================
  // USER PROFILE OPERATIONS
  // ==========================================

  /// Get user profile by ID
  Future<Map<String, dynamic>> getUserProfile({required String userId}) async {
    try {
      final document = await _db.getDocument(
        databaseId: AppwriteConfig.databaseId,
        collectionId: AppwriteConfig.usersCollection,
        documentId: userId,
      );
      return document.data;
    } catch (e) {
      debugPrint('UserService: Get profile error: $e');
      rethrow;
    }
  }

  /// Update user profile
  Future<void> updateUserProfile({
    required String userId,
    String? name,
    String? bio,
    String? avatarUrl,
    String? country,
    Map<String, dynamic>? customData,
  }) async {
    try {
      final data = <String, dynamic>{};
      
      if (name != null) data['name'] = name;
      if (bio != null) data['bio'] = bio;
      if (avatarUrl != null) data['avatarUrl'] = avatarUrl;
      if (country != null) data['country'] = country;
      if (customData != null) data.addAll(customData);

      await _db.updateDocument(
        databaseId: AppwriteConfig.databaseId,
        collectionId: AppwriteConfig.usersCollection,
        documentId: userId,
        data: data,
      );
    } catch (e) {
      debugPrint('UserService: Update profile error: $e');
      rethrow;
    }
  }

  /// Delete user profile
  Future<void> deleteUserProfile({required String userId}) async {
    try {
      await _db.deleteDocument(
        databaseId: AppwriteConfig.databaseId,
        collectionId: AppwriteConfig.usersCollection,
        documentId: userId,
      );
    } catch (e) {
      debugPrint('UserService: Delete profile error: $e');
      rethrow;
    }
  }

  // ==========================================
  // USER STATISTICS
  // ==========================================

  /// Get user statistics
  Future<Map<String, dynamic>> getUserStats({required String userId}) async {
    try {
      final document = await _db.getDocument(
        databaseId: AppwriteConfig.databaseId,
        collectionId: AppwriteConfig.usersCollection,
        documentId: userId,
      );
      
      return {
        'totalQuizzes': document.data['totalQuizzes'] ?? 0,
        'totalFlashcards': document.data['totalFlashcards'] ?? 0,
        'totalXP': document.data['totalXP'] ?? 0,
        'currentStreak': document.data['currentStreak'] ?? 0,
        'bestStreak': document.data['bestStreak'] ?? 0,
        'averageScore': document.data['averageScore'] ?? 0.0,
        'perfectScores': document.data['perfectScores'] ?? 0,
        'joinDate': document.data['joinDate'],
        'lastActive': document.data['lastActive'],
      };
    } catch (e) {
      debugPrint('UserService: Get stats error: $e');
      rethrow;
    }
  }

  /// Update user statistics
  Future<void> updateUserStats({
    required String userId,
    int? totalQuizzes,
    int? totalFlashcards,
    int? totalXP,
    int? currentStreak,
    int? bestStreak,
    double? averageScore,
    int? perfectScores,
  }) async {
    try {
      final data = <String, dynamic>{};
      
      if (totalQuizzes != null) data['totalQuizzes'] = totalQuizzes;
      if (totalFlashcards != null) data['totalFlashcards'] = totalFlashcards;
      if (totalXP != null) data['totalXP'] = totalXP;
      if (currentStreak != null) data['currentStreak'] = currentStreak;
      if (bestStreak != null) data['bestStreak'] = bestStreak;
      if (averageScore != null) data['averageScore'] = averageScore;
      if (perfectScores != null) data['perfectScores'] = perfectScores;
      
      data['lastActive'] = DateTime.now().toIso8601String();

      await _db.updateDocument(
        databaseId: AppwriteConfig.databaseId,
        collectionId: AppwriteConfig.usersCollection,
        documentId: userId,
        data: data,
      );
    } catch (e) {
      debugPrint('UserService: Update stats error: $e');
      rethrow;
    }
  }

  // ==========================================
  // AVATAR MANAGEMENT
  // ==========================================

  /// Upload user avatar
  Future<String> uploadAvatar({required String filePath}) async {
    try {
      final file = InputFile.fromPath(
        path: filePath,
        filename: 'avatar_${DateTime.now().millisecondsSinceEpoch}.jpg',
      );

      final response = await _storage.createFile(
        bucketId: AppwriteConfig.storageId,
        fileId: ID.unique(),
        file: file,
      );

      final fileId = response.$id;
      final avatarUrl = '${AppwriteConfig.endpoint}/storage/buckets/${AppwriteConfig.storageId}/files/$fileId/view?project=${AppwriteConfig.projectId}';
      
      return avatarUrl;
    } catch (e) {
      debugPrint('UserService: Upload avatar error: $e');
      rethrow;
    }
  }

  /// Delete user avatar
  Future<void> deleteAvatar({required String fileId}) async {
    try {
      await _storage.deleteFile(
        bucketId: AppwriteConfig.storageId,
        fileId: fileId,
      );
    } catch (e) {
      debugPrint('UserService: Delete avatar error: $e');
      rethrow;
    }
  }

  // ==========================================
  // USER PREFERENCES
  // ==========================================

  /// Get user preferences
  Future<Map<String, dynamic>> getUserPreferences({required String userId}) async {
    try {
      final document = await _db.getDocument(
        databaseId: AppwriteConfig.databaseId,
        collectionId: AppwriteConfig.usersCollection,
        documentId: userId,
      );
      
      return {
        'theme': document.data['theme'] ?? 'system',
        'language': document.data['language'] ?? 'en',
        'notifications': document.data['notifications'] ?? true,
        'sound': document.data['sound'] ?? true,
        'vibration': document.data['vibration'] ?? true,
        'dailyReminder': document.data['dailyReminder'] ?? true,
        'reminderTime': document.data['reminderTime'] ?? '18:00',
      };
    } catch (e) {
      debugPrint('UserService: Get preferences error: $e');
      rethrow;
    }
  }

  /// Update user preferences
  Future<void> updateUserPreferences({
    required String userId,
    String? theme,
    String? language,
    bool? notifications,
    bool? sound,
    bool? vibration,
    bool? dailyReminder,
    String? reminderTime,
  }) async {
    try {
      final data = <String, dynamic>{};
      
      if (theme != null) data['theme'] = theme;
      if (language != null) data['language'] = language;
      if (notifications != null) data['notifications'] = notifications;
      if (sound != null) data['sound'] = sound;
      if (vibration != null) data['vibration'] = vibration;
      if (dailyReminder != null) data['dailyReminder'] = dailyReminder;
      if (reminderTime != null) data['reminderTime'] = reminderTime;

      await _db.updateDocument(
        databaseId: AppwriteConfig.databaseId,
        collectionId: AppwriteConfig.usersCollection,
        documentId: userId,
        data: data,
      );
    } catch (e) {
      debugPrint('UserService: Update preferences error: $e');
      rethrow;
    }
  }

  // ==========================================
  // ACCOUNT MANAGEMENT
  // ==========================================

  /// Check if user exists
  Future<bool> userExists({required String userId}) async {
    try {
      await _db.getDocument(
        databaseId: AppwriteConfig.databaseId,
        collectionId: AppwriteConfig.usersCollection,
        documentId: userId,
      );
      return true;
    } catch (e) {
      return false;
    }
  }

  /// Create new user profile
  Future<void> createUserProfile({
    required String userId,
    required String email,
    required String name,
    String? photoUrl,
    String? country,
  }) async {
    try {
      await _db.createDocument(
        databaseId: AppwriteConfig.databaseId,
        collectionId: AppwriteConfig.usersCollection,
        documentId: userId,
        data: {
          'email': email,
          'name': name,
          'avatarUrl': photoUrl,
          'country': country ?? 'Unknown',
          'totalQuizzes': 0,
          'totalFlashcards': 0,
          'totalXP': 0,
          'currentStreak': 0,
          'bestStreak': 0,
          'averageScore': 0.0,
          'perfectScores': 0,
          'theme': 'system',
          'language': 'en',
          'notifications': true,
          'sound': true,
          'vibration': true,
          'dailyReminder': true,
          'reminderTime': '18:00',
          'joinDate': DateTime.now().toIso8601String(),
          'lastActive': DateTime.now().toIso8601String(),
        },
      );
    } catch (e) {
      debugPrint('UserService: Create profile error: $e');
      rethrow;
    }
  }

  /// Deletes the user's profile document, then blocks the Appwrite account
  /// (`PATCH /account/status`) so it can't be signed in to again. A profile
  /// that was never created (404) is not an error. The caller still has to
  /// end the session and clear local data.
  Future<void> deleteUserAccount({required String userId}) async {
    try {
      await deleteUserProfile(userId: userId);
    } on AppwriteException catch (e) {
      if (e.code != 404) rethrow;
    }
    await LeaderboardService().removeEntry(userId);
    try {
      await AppwriteClient.instance.account.updateStatus();
    } catch (e) {
      debugPrint('UserService: Block account error: $e');
      rethrow;
    }
  }

  /// Get current logged-in user
  Future<User?> getCurrentUser() async {
    try {
      final account = AppwriteClient.instance.account;
      return await account.get();
    } catch (e) {
      return null;
    }
  }

  /// Check if user is logged in
  Future<bool> isLoggedIn() async {
    try {
      await getCurrentUser();
      return true;
    } catch (e) {
      return false;
    }
  }
}
