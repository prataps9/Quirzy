/// Today's Daily 5: a fixed set of questions picked once a day, and how
/// each one was answered.
class DailyChallenge {
  /// `yyyy-MM-dd` of the day this challenge is for.
  final String date;

  /// Question keys (`PracticeQuestionKeys.engagementKey`), in play order.
  final List<String> keys;

  /// Answered questions: key to whether it was correct.
  final Map<String, bool> results;

  /// XP earned for finishing, or null until it is finished and paid out.
  final int? bonusXp;

  const DailyChallenge({
    required this.date,
    required this.keys,
    this.results = const {},
    this.bonusXp,
  });

  int get total => keys.length;
  int get answered => keys.where(results.containsKey).length;
  int get correct => keys.where((k) => results[k] == true).length;
  int get remaining => total - answered;
  bool get completed => keys.isNotEmpty && remaining == 0;

  bool isAnswered(String key) => results.containsKey(key);

  DailyChallenge copyWith({List<String>? keys, Map<String, bool>? results, int? bonusXp}) => DailyChallenge(
    date: date,
    keys: keys ?? this.keys,
    results: results ?? this.results,
    bonusXp: bonusXp ?? this.bonusXp,
  );

  Map<String, dynamic> toJson() => {
    'date': date,
    'keys': keys,
    'results': results,
    if (bonusXp != null) 'bonus': bonusXp,
  };

  factory DailyChallenge.fromJson(Map<String, dynamic> json) => DailyChallenge(
    date: json['date'] as String,
    keys: (json['keys'] as List).cast<String>(),
    results: (json['results'] as Map? ?? {}).map((k, v) => MapEntry(k as String, v == true)),
    bonusXp: json['bonus'] as int?,
  );
}
