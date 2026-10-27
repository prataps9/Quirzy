import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/feed_models.dart';

/// The user's own notes on questions, shown in the solution panel.
class QuestionNotesService {
  static const _key = 'feed_notes_v1';
  static const maxNotes = 300;
  static const maxLength = 500;

  Future<Map<String, dynamic>> _read() async {
    final prefs = await SharedPreferences.getInstance();
    try {
      final raw = prefs.getString(_key);
      if (raw == null) return {};
      return Map<String, dynamic>.from(jsonDecode(raw) as Map);
    } catch (_) {
      return {};
    }
  }

  Future<String> noteFor(PracticeQuestion q) async {
    final entry = (await _read())[q.engagementKey];
    return entry is Map ? (entry['text'] as String? ?? '') : '';
  }

  /// Saves [text] (trimmed, capped); an empty note removes it. The oldest
  /// notes go first once there are more than [maxNotes].
  Future<void> setNote(PracticeQuestion q, String text) async {
    final notes = await _read();
    final trimmed = text.trim();
    final key = q.engagementKey;
    notes.remove(key);
    if (trimmed.isNotEmpty) {
      notes[key] = {
        'text': trimmed.length > maxLength ? trimmed.substring(0, maxLength) : trimmed,
        'ms': DateTime.now().millisecondsSinceEpoch,
      };
    }
    if (notes.length > maxNotes) {
      final oldest = notes.entries.toList()
        ..sort((a, b) => ((a.value as Map)['ms'] as int).compareTo((b.value as Map)['ms'] as int));
      for (final e in oldest.take(notes.length - maxNotes)) {
        notes.remove(e.key);
      }
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, jsonEncode(notes));
  }
}
