/// One thing to do today, with progress.
enum PlanTaskKind { daily, mistakes, revision, focusTopic, goal }

class PlanTask {
  final PlanTaskKind kind;
  final String title;
  final int done;
  final int target;

  /// The topic for [PlanTaskKind.focusTopic].
  final String? topic;

  const PlanTask({required this.kind, required this.title, required this.done, required this.target, this.topic});

  bool get complete => done >= target;
  double get progress => target == 0 ? 1 : (done / target).clamp(0.0, 1.0);
}

/// How today's pace compares with what the exam needs.
enum PlanPace {
  /// No exam date set.
  noDate,

  /// The exam is today or has passed.
  examDay,
  onTrack,
  behind,
}

/// Today's study plan.
class StudyPlan {
  final List<PlanTask> tasks;
  final PlanPace pace;

  /// Days until the exam (0 on the day), when a date is set.
  final int? daysLeft;

  /// Answers a day needed to get through the unseen questions in time.
  final int? neededPerDay;

  /// Average answers a day over the last week.
  final int averagePerDay;

  const StudyPlan({required this.tasks, required this.pace, this.daysLeft, this.neededPerDay, this.averagePerDay = 0});

  bool get complete => tasks.isNotEmpty && tasks.every((t) => t.complete);
  int get completeCount => tasks.where((t) => t.complete).length;

  /// One line for the top of the plan.
  String get paceLine => switch (pace) {
    PlanPace.noDate => 'Set your exam date to plan towards it',
    PlanPace.examDay => daysLeft == 0 ? 'Exam day. Good luck!' : 'Your exam date has passed',
    PlanPace.onTrack => 'Exam in $daysLeft ${daysLeft == 1 ? 'day' : 'days'} · On track',
    PlanPace.behind => 'Exam in $daysLeft ${daysLeft == 1 ? 'day' : 'days'} · Aim for $neededPerDay a day',
  };
}
