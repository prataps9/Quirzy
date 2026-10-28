import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/feed_models.dart';

/// One question the user got wrong, kept in the Mistakes notebook.
class MistakeEntry {
  final PracticeQuestion question;
  final int timesWrong;
  final int firstWrongMs;
  final int lastWrongMs;

  /// The option picked on the last wrong answer, when known (multiple
  /// choice); null for True/False.
  final int? lastPick;

  /// Why the user says they got it wrong ("Misread it"), if they said.
  final String? reason;

  /// Right answers in a row since the last wrong one.
  final int rightStreak;

  const MistakeEntry({
    required this.question,
    required this.timesWrong,
    required this.firstWrongMs,
    required this.lastWrongMs,
    this.lastPick,
    this.reason,
    this.rightStreak = 0,
  });

  String get key => question.engagementKey;

  /// Answered right [MistakesService.fixAfter] times in a row since.
  bool get fixed => rightStreak >= MistakesService.fixAfter;

  /// The wrong option as text, when it is known and still valid.
  String? get pickedText {
    final pick = lastPick;
    if (pick == null || pick < 0 || pick >= question.options.length || pick == question.correctIndex) return null;
    return question.options[pick];
  }

  MistakeEntry copyWith({
    int? timesWrong,
    int? lastWrongMs,
    int? lastPick,
    bool clearPick = false,
    String? reason,
    bool clearReason = false,
    int? rightStreak,
  }) => MistakeEntry(
    question: question,
    timesWrong: timesWrong ?? this.timesWrong,
    firstWrongMs: firstWrongMs,
    lastWrongMs: lastWrongMs ?? this.lastWrongMs,
    lastPick: clearPick ? null : (lastPick ?? this.lastPick),
    reason: clearReason ? null : (reason ?? this.reason),
    rightStreak: rightStreak ?? this.rightStreak,
  );

  Map<String, dynamic> toJson() => {
    'q': question.toJson(),
    'n': timesWrong,
    'first': firstWrongMs,
    'last': lastWrongMs,
    if (lastPick != null) 'pick': lastPick,
    if (reason != null) 'why': reason,
    'right': rightStreak,
  };

  factory MistakeEntry.fromJson(Map<String, dynamic> json) => MistakeEntry(
    question: PracticeQuestion.fromJson(Map<String, dynamic>.from(json['q'] as Map)),
    timesWrong: json['n'] as int? ?? 1,
    firstWrongMs: json['first'] as int? ?? 0,
    lastWrongMs: json['last'] as int? ?? 0,
    lastPick: json['pick'] as int?,
    reason: json['why'] as String?,
    rightStreak: json['right'] as int? ?? 0,
  );
}

/// What the notebook says about the user's mistakes as a whole.
class MistakeInsight {
  /// Mistakes not fixed yet.
  final int open;
  final int total;
  final int fixed;

  /// The reason given most often, and its share of the reasons given (0–100).
  final String? topReason;
  final int topReasonPercent;

  /// The topic with the most mistakes still to fix.
  final String? topTopic;

  const MistakeInsight({
    this.open = 0,
    this.total = 0,
    this.fixed = 0,
    this.topReason,
    this.topReasonPercent = 0,
    this.topTopic,
  });
}

/// Every question the user has answered wrong, with what they picked, why,
/// and whether they have since got it right. Unlike the Revision Vault,
/// nothing leaves the notebook when it is learned: it is marked fixed.
class MistakesService {
  static const _key = 'feed_mistakes_v1';
  static const maxEntries = 300;

  /// Right answers in a row that mark a mistake as fixed.
  static const fixAfter = 2;

  Future<List<MistakeEntry>> _read() async {
    final prefs = await SharedPreferences.getInstance();
    try {
      final raw = prefs.getString(_key);
      if (raw == null) return [];
      return [for (final e in jsonDecode(raw) as List) MistakeEntry.fromJson(Map<String, dynamic>.from(e as Map))];
    } catch (_) {
      return [];
    }
  }

  Future<void> _write(List<MistakeEntry> entries) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, jsonEncode([for (final e in entries) e.toJson()]));
  }

  /// Every mistake, most recently missed first.
  Future<List<MistakeEntry>> all() async => (await _read())..sort((a, b) => b.lastWrongMs.compareTo(a.lastWrongMs));

  /// Records an answer to [question]. A wrong one adds it (or counts it
  /// again); a right one counts towards fixing a question already here.
  Future<void> recordAnswer(PracticeQuestion question, {required bool correct, int? pick, DateTime? now}) async {
    final entries = await _read();
    final key = question.engagementKey;
    final index = entries.indexWhere((e) => e.key == key);
    final ms = (now ?? DateTime.now()).millisecondsSinceEpoch;

    if (correct) {
      if (index < 0) return;
      entries[index] = entries[index].copyWith(rightStreak: entries[index].rightStreak + 1);
    } else if (index < 0) {
      entries.add(MistakeEntry(question: question, timesWrong: 1, firstWrongMs: ms, lastWrongMs: ms, lastPick: pick));
    } else {
      entries[index] = entries[index].copyWith(
        timesWrong: entries[index].timesWrong + 1,
        lastWrongMs: ms,
        lastPick: pick,
        clearPick: pick == null,
        clearReason: true,
        rightStreak: 0,
      );
    }

    if (entries.length > maxEntries) {
      // Drop fixed ones first, then the longest ago.
      entries.sort((a, b) {
        if (a.fixed != b.fixed) return a.fixed ? -1 : 1;
        return a.lastWrongMs.compareTo(b.lastWrongMs);
      });
      entries.removeRange(0, entries.length - maxEntries);
    }
    await _write(entries);
  }

  /// Saves why the user got [question] wrong.
  Future<void> setReason(PracticeQuestion question, String reason) async {
    final entries = await _read();
    final index = entries.indexWhere((e) => e.key == question.engagementKey);
    if (index < 0) return;
    entries[index] = entries[index].copyWith(reason: reason);
    await _write(entries);
  }

  /// Questions still to fix, most recently missed first.
  Future<List<PracticeQuestion>> toRetry() async => [
    for (final e in await all())
      if (!e.fixed) e.question,
  ];

  Future<int> fixedCount() async => (await _read()).where((e) => e.fixed).length;

  Future<MistakeInsight> insight() async {
    final entries = await _read();
    final open = entries.where((e) => !e.fixed).toList();

    final reasons = <String, int>{};
    for (final e in entries) {
      final why = e.reason;
      if (why != null) reasons[why] = (reasons[why] ?? 0) + 1;
    }
    final given = reasons.values.fold(0, (a, b) => a + b);
    final topReason = reasons.isEmpty
        ? null
        : (reasons.entries.toList()..sort((a, b) => b.value.compareTo(a.value))).first;

    final topics = <String, int>{};
    for (final e in open) {
      topics[e.question.topicName] = (topics[e.question.topicName] ?? 0) + 1;
    }
    final topTopic = topics.isEmpty
        ? null
        : (topics.entries.toList()..sort((a, b) => b.value.compareTo(a.value))).first.key;

    return MistakeInsight(
      open: open.length,
      total: entries.length,
      fixed: entries.length - open.length,
      topReason: topReason?.key,
      topReasonPercent: topReason == null ? 0 : (topReason.value * 100 / given).round(),
      topTopic: topTopic,
    );
  }
}
