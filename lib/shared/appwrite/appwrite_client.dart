import 'package:appwrite/appwrite.dart';
import 'package:flutter/foundation.dart';

/// Appwrite project configuration — collection/function IDs are live
/// backend identifiers and must match the Appwrite console exactly.
class AppwriteConfig {
  static const String endpoint = 'https://sgp.cloud.appwrite.io/v1';
  static const String projectId = '695be801003d58b523fc';
  static const String databaseId = '695d45fe000f2d83ddee';

  // Collections
  static const String quizzesCollection = 'quizzes';
  static const String questionsCollection = 'questions';
  static const String quizResultsCollection = 'quiz_results';

  // Functions
  static const String quizGenerateFunction = 'quiz-generate';
  static const String studyGenerateFunction = 'study-generate';
  static const String challengeManageFunction = 'challenge-manage';
  static const String explainFunction = 'explain-question';

  // Additional collections (used by shared services)
  static const String usersCollection = 'users';
  static const String flashcardsCollection = 'flashcard_sets';
  static const String achievementsCollection = 'achievements';
  static const String leaderboardCollection = 'leaderboard';
  static const String storageId = 'main_storage';

  // Premium feature collections
  static const String mockTestsCollection = 'mock_tests';
  static const String studyMaterialsCollection = 'study_materials';

  // Premium feature functions
  static const String mockTestFunction = 'mock-test-generate';
  static const String studyMaterialFunction = 'study-material-generate';
}

/// Singleton Appwrite client — shared by every feature that talks to
/// the backend (Auth, Practice content, Flashcards, Profile, Leaderboard).
class AppwriteClient {
  static AppwriteClient? _instance;
  late final Client client;
  late final Account account;
  late final Databases databases;
  late final Functions functions;
  late final Storage storage;

  AppwriteClient._() {
    client = Client()
        .setEndpoint(AppwriteConfig.endpoint)
        .setProject(AppwriteConfig.projectId)
        .setSelfSigned(status: kDebugMode);

    account = Account(client);
    databases = Databases(client);
    functions = Functions(client);
    storage = Storage(client);
  }

  static AppwriteClient get instance {
    _instance ??= AppwriteClient._();
    return _instance!;
  }
}
