/// How well a topic is going, from its answer history.
enum MasteryLevel { fresh, learning, weak, solid, mastered }

/// One topic's progress, shown on the topic dial.
class TopicMastery {
  final String topic;
  final int attempts;

  /// 0–100.
  final double accuracy;

  /// Missed questions in this topic that are due for revision.
  final int dueCount;
  final DateTime? lastPracticed;

  const TopicMastery({
    required this.topic,
    this.attempts = 0,
    this.accuracy = 0,
    this.dueCount = 0,
    this.lastPracticed,
  });

  /// Too few answers to judge.
  static const int freshBelow = 5;

  /// Matches the "My Weak Topics" rule in FeedStatsService.getWeakTopics.
  static const int weakMinAttempts = 10;
  static const double weakBelow = 55;

  static const int masteredMinAttempts = 20;
  static const double masteredFrom = 85;
  static const double solidFrom = 70;

  MasteryLevel get level {
    if (attempts < freshBelow) return MasteryLevel.fresh;
    if (attempts >= weakMinAttempts && accuracy < weakBelow) return MasteryLevel.weak;
    if (attempts >= masteredMinAttempts && accuracy >= masteredFrom) return MasteryLevel.mastered;
    if (accuracy >= solidFrom) return MasteryLevel.solid;
    return MasteryLevel.learning;
  }

  /// "Today", "Yesterday", "3 days ago" … or "Not yet".
  String lastPractisedLabel(DateTime now) {
    final last = lastPracticed;
    if (last == null) return 'Not yet';
    final days = DateTime(now.year, now.month, now.day)
        .difference(DateTime(last.year, last.month, last.day))
        .inDays;
    if (days <= 0) return 'Today';
    if (days == 1) return 'Yesterday';
    if (days < 14) return '$days days ago';
    return '${days ~/ 7} weeks ago';
  }
}
