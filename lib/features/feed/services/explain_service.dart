import 'dart:convert';

import 'package:appwrite/appwrite.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../shared/appwrite/appwrite_client.dart';
import '../../../shared/utils/user_messages.dart';
import '../models/feed_models.dart';

/// What the user wants explained about a question.
enum ExplainMode {
  simpler('Explain simpler'),
  example('Give an example'),
  others('Why are the others wrong?'),
  memory('Memory trick'),
  followUp('Your question');

  const ExplainMode(this.label);
  final String label;
}

/// Sends one request to the `explain-question` function and returns the
/// answer text. Swapped for a fake in tests.
typedef ExplainCall = Future<String> Function(Map<String, dynamic> payload);

/// Asks the AI to explain a question further. Answers to the canned modes
/// are kept on the device, so asking the same thing again is instant, free
/// and works offline.
class ExplainService {
  ExplainService({ExplainCall? call}) : _call = call ?? _callAppwrite;

  static const _cacheKey = 'explain_cache_v1';
  static const maxCached = 100;
  static const maxFollowUpLength = 300;

  final ExplainCall _call;

  static Future<String> _callAppwrite(Map<String, dynamic> payload) async {
    final client = AppwriteClient.instance;
    try {
      final user = await client.account.get();
      final execution = await client.functions.createExecution(
        functionId: AppwriteConfig.explainFunction,
        body: jsonEncode({...payload, 'userId': user.$id}),
      );
      if (execution.status.name != 'completed') throw const _Unavailable();
      final response = jsonDecode(execution.responseBody);
      if (response is! Map || response['error'] != null) throw const _Unavailable();
      final answer = (response['answer'] as String?)?.trim() ?? '';
      if (answer.isEmpty) throw const _Unavailable();
      return answer;
    } on AppwriteException catch (e) {
      // A missing function is "not available", not the user's connection.
      if (e.code == 404) throw const _Unavailable();
      rethrow;
    }
  }

  String _cacheId(PracticeQuestion q, ExplainMode mode) => '${q.engagementKey}|${mode.name}';

  /// A previously fetched answer, or null.
  Future<String?> cached(PracticeQuestion q, ExplainMode mode) async {
    if (mode == ExplainMode.followUp) return null;
    final id = _cacheId(q, mode);
    for (final entry in await _readCache()) {
      if (entry['k'] == id) return entry['a'] as String?;
    }
    return null;
  }

  /// The answer for [mode], from the device if we have it, otherwise from
  /// the AI. [fromCache] is true when no AI call was made, so the caller
  /// knows not to count it against the daily allowance.
  Future<({String answer, bool fromCache})> explain(
    PracticeQuestion q,
    ExplainMode mode, {
    String? followUp,
  }) async {
    final hit = await cached(q, mode);
    if (hit != null) return (answer: hit, fromCache: true);

    final question = followUp?.trim() ?? '';
    if (mode == ExplainMode.followUp && question.isEmpty) {
      throw const UserFacingException('Type a question first.');
    }
    final answer = await _call({
      'question': q.questionText,
      'options': q.options,
      'correctIndex': q.correctIndex,
      'explanation': q.explanation,
      'topic': q.topicName,
      'mode': mode.name,
      if (mode == ExplainMode.followUp)
        'followUp': question.length > maxFollowUpLength ? question.substring(0, maxFollowUpLength) : question,
    });
    if (mode != ExplainMode.followUp) await _store(_cacheId(q, mode), answer);
    return (answer: answer, fromCache: false);
  }

  Future<List<Map<String, dynamic>>> _readCache() async {
    final prefs = await SharedPreferences.getInstance();
    try {
      final raw = prefs.getString(_cacheKey);
      if (raw == null) return [];
      return (jsonDecode(raw) as List).cast<Map<String, dynamic>>();
    } catch (_) {
      return [];
    }
  }

  Future<void> _store(String id, String answer) async {
    final all = await _readCache()
      ..removeWhere((e) => e['k'] == id)
      ..add({'k': id, 'a': answer});
    final kept = all.length > maxCached ? all.sublist(all.length - maxCached) : all;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_cacheKey, jsonEncode(kept));
  }
}

class _Unavailable extends UserFacingException {
  const _Unavailable() : super("Ask AI isn't available right now. Please try again later.");
}
