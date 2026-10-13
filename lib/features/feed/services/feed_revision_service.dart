import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/feed_models.dart';

/// Lightweight SM-2 variant for the Revision Vault (PRD §9):
/// wrong -> +1 day; 1st correct after wrong -> +3 days;
/// 2nd consecutive correct -> +7 days; 3rd -> graduated out;
/// wrong at any stage resets to +1 day.
class _RevisionEntry {
  final PracticeQuestion question;
  final DateTime dueDate;
  final int consecutiveCorrect;

  const _RevisionEntry({
    required this.question,
    required this.dueDate,
    this.consecutiveCorrect = 0,
  });

  Map<String, dynamic> toJson() => {
    'question': question.toJson(),
    'dueDate': dueDate.toIso8601String(),
    'consecutiveCorrect': consecutiveCorrect,
  };

  factory _RevisionEntry.fromJson(Map<String, dynamic> json) => _RevisionEntry(
    question: PracticeQuestion.fromJson(
      json['question'] as Map<String, dynamic>,
    ),
    dueDate: DateTime.parse(json['dueDate'] as String),
    consecutiveCorrect: json['consecutiveCorrect'] as int? ?? 0,
  );
}

class FeedRevisionService {
  static const _key = 'feed_revision_vault';

  Future<List<_RevisionEntry>> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null || raw.isEmpty) return [];
    final decoded = jsonDecode(raw) as List;
    return decoded
        .map((e) => _RevisionEntry.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<void> _save(List<_RevisionEntry> entries) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _key,
      jsonEncode(entries.map((e) => e.toJson()).toList()),
    );
  }

  /// Cards due today or earlier.
  Future<List<PracticeQuestion>> getDueQuestions() async {
    final entries = await _load();
    final now = DateTime.now();
    return entries
        .where((e) => !e.dueDate.isAfter(now))
        .map((e) => e.question)
        .toList();
  }

  Future<int> getDueCount() async => (await getDueQuestions()).length;

  /// Every question still in the vault — ones the user has missed and not
  /// yet mastered — most recently missed first.
  Future<List<PracticeQuestion>> getMissedQuestions() async {
    final entries = await _load();
    return entries.reversed.map((e) => e.question).toList();
  }

  /// Called after every feed answer (wrong OR right). Only questions that
  /// have entered the vault via a wrong answer ever progress or graduate.
  Future<void> recordOutcome(PracticeQuestion question, bool correct) async {
    final entries = await _load();
    final index = entries.indexWhere((e) => e.question.id == question.id);

    if (!correct) {
      final reset = _RevisionEntry(
        question: question,
        dueDate: DateTime.now().add(const Duration(days: 1)),
      );
      if (index >= 0) {
        entries[index] = reset;
      } else {
        entries.add(reset);
      }
      await _save(entries);
      return;
    }

    if (index < 0) return; // never wrong before - nothing to schedule

    final current = entries[index];
    final nextStreak = current.consecutiveCorrect + 1;
    if (nextStreak >= 3) {
      entries.removeAt(index); // graduated out of the vault
    } else {
      final intervalDays = nextStreak == 1 ? 3 : 7;
      entries[index] = _RevisionEntry(
        question: question,
        dueDate: DateTime.now().add(Duration(days: intervalDays)),
        consecutiveCorrect: nextStreak,
      );
    }
    await _save(entries);
  }
}
