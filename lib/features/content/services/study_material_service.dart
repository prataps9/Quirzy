import 'dart:convert';
import 'package:appwrite/appwrite.dart';
import '../../../shared/appwrite/appwrite_client.dart';

class StudyMaterial {
  final String id;
  final String topic;
  final List<String> summary;
  final List<Map<String, dynamic>> flashcards;
  final List<Map<String, dynamic>> quiz;

  const StudyMaterial({
    required this.id,
    required this.topic,
    required this.summary,
    required this.flashcards,
    required this.quiz,
  });

  factory StudyMaterial.fromMap(Map<String, dynamic> map) {
    List<dynamic> decodeList(String key) {
      try {
        final raw = map[key];
        if (raw is String) return jsonDecode(raw) as List<dynamic>;
        if (raw is List) return raw;
        return [];
      } catch (_) {
        return [];
      }
    }

    return StudyMaterial(
      id: map['\$id'] as String? ?? map['id'] as String? ?? '',
      topic: map['topic'] as String? ?? '',
      summary: decodeList('summaryJson').map((e) => e.toString()).toList(),
      flashcards: decodeList('flashcardsJson').map((e) => Map<String, dynamic>.from(e as Map)).toList(),
      quiz: decodeList('quizJson').map((e) => Map<String, dynamic>.from(e as Map)).toList(),
    );
  }
}

class StudyMaterialService {
  final Functions _fn = AppwriteClient.instance.functions;
  final Account _account = AppwriteClient.instance.account;
  final Databases _db = AppwriteClient.instance.databases;

  /// Generates a study set. The daily allowance is checked and recorded
  /// by the caller via `usageLimitsProvider` (`UsageKind.studySet`).
  Future<StudyMaterial> generateStudyMaterial({
    required String topic,
    String? studyNotes,
  }) async {
    final user = await _account.get();

    final execution = await _fn.createExecution(
      functionId: AppwriteConfig.studyMaterialFunction,
      body: jsonEncode({
        'topic': topic,
        'userId': user.$id,
        if (studyNotes != null && studyNotes.isNotEmpty) 'studyNotes': studyNotes,
      }),
    );

    if (execution.status.name != 'completed') {
      throw Exception('Study material generation failed');
    }

    final response = jsonDecode(execution.responseBody) as Map<String, dynamic>;
    if (response['error'] != null) throw Exception(response['error']);

    return StudyMaterial(
      id: response['id'] as String? ?? '',
      topic: response['topic'] as String? ?? topic,
      summary: (response['summary'] as List<dynamic>? ?? []).map((e) => e.toString()).toList(),
      flashcards: (response['flashcards'] as List<dynamic>? ?? [])
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList(),
      quiz: (response['quiz'] as List<dynamic>? ?? [])
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList(),
    );
  }

  /// The user's recent study sets. Throws on failure so the screen can show
  /// an error with Retry rather than a misleading empty list.
  Future<List<StudyMaterial>> getStudyHistory() async {
    final user = await _account.get();
    final result = await _db.listDocuments(
      databaseId: AppwriteConfig.databaseId,
      collectionId: AppwriteConfig.studyMaterialsCollection,
      queries: [
        Query.equal('userId', user.$id),
        Query.orderDesc('createdAt'),
        Query.limit(20),
      ],
    );
    return result.documents.map((d) => StudyMaterial.fromMap(d.data)).toList();
  }
}
