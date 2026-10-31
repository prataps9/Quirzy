/// Part of the day, for "you practise best in the evening".
enum DayPart {
  morning('Morning', '5 am to noon'),
  afternoon('Afternoon', 'noon to 5 pm'),
  evening('Evening', '5 pm to 9 pm'),
  night('Night', '9 pm to 5 am');

  const DayPart(this.label, this.hours);
  final String label;
  final String hours;

  static DayPart of(int hour) => switch (hour) {
    >= 5 && < 12 => morning,
    >= 12 && < 17 => afternoon,
    >= 17 && < 21 => evening,
    _ => night,
  };
}

/// One topic's week.
class TopicWeek {
  final String topic;
  final int answered;
  final int correct;

  const TopicWeek(this.topic, this.answered, this.correct);

  int get accuracy => answered == 0 ? 0 : (correct * 100 / answered).round();
}

/// A Monday-to-Sunday look back.
class WeeklyReport {
  /// Monday.
  final DateTime start;

  /// Answers on each day, Monday first.
  final List<int> answeredByDay;

  /// Answers with a known result (from the activity log), for accuracy.
  final int graded;
  final int correct;
  final int xp;
  final List<TopicWeek> topics;

  /// Answers per [DayPart].
  final Map<DayPart, int> parts;
  final int mockTests;
  final int badges;

  /// The week before, for the change.
  final int previousAnswered;
  final int? previousAccuracy;

  const WeeklyReport({
    required this.start,
    required this.answeredByDay,
    this.graded = 0,
    this.correct = 0,
    this.xp = 0,
    this.topics = const [],
    this.parts = const {},
    this.mockTests = 0,
    this.badges = 0,
    this.previousAnswered = 0,
    this.previousAccuracy,
  });

  /// Answers needed in a topic before it can be called best or weakest.
  static const minTopicAnswers = 10;

  /// Answers needed before a best time of day is named.
  static const minPartAnswers = 10;

  DateTime get end => DateTime(start.year, start.month, start.day + 6);

  int get answered => answeredByDay.fold(0, (a, b) => a + b);
  int get daysActive => answeredByDay.where((n) => n > 0).length;
  bool get isEmpty => answered == 0;

  /// Percent right, when any answers were graded.
  int? get accuracy => graded == 0 ? null : (correct * 100 / graded).round();

  /// Change in answers against the week before, in percent; null when the
  /// week before had none.
  int? get answeredChange =>
      previousAnswered == 0 ? null : ((answered - previousAnswered) * 100 / previousAnswered).round();

  /// Change in accuracy, in points.
  int? get accuracyChange {
    final now = accuracy, before = previousAccuracy;
    return now == null || before == null ? null : now - before;
  }

  /// The busiest day (Monday = 0), or null for an empty week.
  int? get bestDay {
    if (isEmpty) return null;
    var best = 0;
    for (var i = 1; i < 7; i++) {
      if (answeredByDay[i] > answeredByDay[best]) best = i;
    }
    return best;
  }

  TopicWeek? get mostPractised => topics.isEmpty ? null : topics.first;

  List<TopicWeek> get _qualifying => topics.where((t) => t.answered >= minTopicAnswers).toList();

  TopicWeek? get bestTopic {
    final q = _qualifying;
    if (q.isEmpty) return null;
    return q.reduce((a, b) => b.accuracy > a.accuracy ? b : a);
  }

  /// The lowest scoring topic, if it is not also the best.
  TopicWeek? get weakestTopic {
    final q = _qualifying;
    if (q.length < 2) return null;
    final weakest = q.reduce((a, b) => b.accuracy < a.accuracy ? b : a);
    return weakest.accuracy < bestTopic!.accuracy ? weakest : null;
  }

  DayPart? get bestTime {
    final total = parts.values.fold(0, (a, b) => a + b);
    if (total < minPartAnswers) return null;
    return parts.entries.reduce((a, b) => b.value > a.value ? b : a).key;
  }
}
