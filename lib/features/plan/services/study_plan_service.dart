import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../../feed/models/daily_challenge.dart';
import '../../feed/models/topic_mastery.dart';
import '../models/study_plan.dart';

/// Everything today's plan is worked out from.
class StudyPlanInputs {
  final DateTime now;
  final DateTime? examDate;

  /// Questions per topic in the pool.
  final Map<String, int> poolTopics;

  /// Pool questions never shown yet.
  final int unseenQuestions;
  final Map<String, TopicMastery> mastery;
  final int mistakesOpen;
  final int mistakesReviewedToday;
  final int revisionDue;
  final int revisionReviewedToday;
  final DailyChallenge? daily;

  /// Answers per topic today.
  final Map<String, int> todayByTopic;
  final int todayAnswered;

  /// Answers on each of the last 7 days before today.
  final List<int> lastWeek;

  const StudyPlanInputs({
    required this.now,
    this.examDate,
    this.poolTopics = const {},
    this.unseenQuestions = 0,
    this.mastery = const {},
    this.mistakesOpen = 0,
    this.mistakesReviewedToday = 0,
    this.revisionDue = 0,
    this.revisionReviewedToday = 0,
    this.daily,
    this.todayByTopic = const {},
    this.todayAnswered = 0,
    this.lastWeek = const [],
  });
}

/// Turns where the user stands into a short plan for today, and keeps count
/// of the days they finish it.
class StudyPlanService {
  static const defaultGoal = 50;
  static const minGoal = 20;
  static const maxGoal = 120;
  static const maxMistakes = 10;
  static const focusTarget = 20;

  static const _doneDaysKey = 'plan_days_done';

  static String _dateKey(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  /// The weakest topic worth practising: one marked "needs work" first,
  /// then the lowest accuracy among those being learned, then the least
  /// practised. Only topics with questions in the pool.
  static String? focusTopic(Map<String, int> poolTopics, Map<String, TopicMastery> mastery) {
    final candidates = poolTopics.entries.where((e) => e.value > 0).map((e) => e.key).toList();
    if (candidates.isEmpty) return null;
    int rank(MasteryLevel level) => switch (level) {
      MasteryLevel.weak => 0,
      MasteryLevel.learning => 1,
      MasteryLevel.fresh => 2,
      MasteryLevel.solid => 3,
      MasteryLevel.mastered => 4,
    };
    TopicMastery of(String t) => mastery[t] ?? TopicMastery(topic: t);
    candidates.sort((a, b) {
      final ma = of(a), mb = of(b);
      final byLevel = rank(ma.level).compareTo(rank(mb.level));
      if (byLevel != 0) return byLevel;
      if (ma.level == MasteryLevel.fresh) return ma.attempts.compareTo(mb.attempts);
      final byAccuracy = ma.accuracy.compareTo(mb.accuracy);
      return byAccuracy != 0 ? byAccuracy : a.compareTo(b);
    });
    return candidates.first;
  }

  static StudyPlan build(StudyPlanInputs i) {
    final today = DateTime(i.now.year, i.now.month, i.now.day);
    final exam = i.examDate;
    final daysLeft = exam == null ? null : DateTime(exam.year, exam.month, exam.day).difference(today).inDays;
    final average = i.lastWeek.isEmpty ? 0 : (i.lastWeek.fold(0, (a, b) => a + b) / i.lastWeek.length).round();

    int? needed;
    var pace = PlanPace.noDate;
    if (daysLeft != null) {
      if (daysLeft <= 0) {
        pace = PlanPace.examDay;
      } else {
        needed = (i.unseenQuestions / daysLeft).ceil().clamp(minGoal, maxGoal);
        pace = average >= needed ? PlanPace.onTrack : PlanPace.behind;
      }
    }
    final goal = needed == null ? defaultGoal : needed.clamp(defaultGoal, maxGoal);

    final tasks = <PlanTask>[];
    final daily = i.daily;
    if (daily != null && daily.total > 0) {
      tasks.add(
        PlanTask(
          kind: PlanTaskKind.daily,
          title: 'Play the Daily ${daily.total}',
          done: daily.answered,
          target: daily.total,
        ),
      );
    }
    final mistakesTarget = (i.mistakesOpen + i.mistakesReviewedToday).clamp(0, maxMistakes);
    if (mistakesTarget > 0) {
      tasks.add(
        PlanTask(
          kind: PlanTaskKind.mistakes,
          title: 'Fix $mistakesTarget ${mistakesTarget == 1 ? 'mistake' : 'mistakes'}',
          done: i.mistakesReviewedToday.clamp(0, mistakesTarget),
          target: mistakesTarget,
        ),
      );
    }
    final revisionTarget = i.revisionDue + i.revisionReviewedToday;
    if (revisionTarget > 0) {
      tasks.add(
        PlanTask(
          kind: PlanTaskKind.revision,
          title: 'Revise $revisionTarget due ${revisionTarget == 1 ? 'question' : 'questions'}',
          done: i.revisionReviewedToday.clamp(0, revisionTarget),
          target: revisionTarget,
        ),
      );
    }
    final focus = focusTopic(i.poolTopics, i.mastery);
    if (focus != null) {
      final target = (i.poolTopics[focus] ?? focusTarget).clamp(1, focusTarget);
      tasks.add(
        PlanTask(
          kind: PlanTaskKind.focusTopic,
          title: 'Practise $target in $focus',
          done: (i.todayByTopic[focus] ?? 0).clamp(0, target),
          target: target,
          topic: focus,
        ),
      );
    }
    tasks.add(
      PlanTask(
        kind: PlanTaskKind.goal,
        title: 'Answer $goal questions',
        done: i.todayAnswered.clamp(0, goal),
        target: goal,
      ),
    );

    return StudyPlan(tasks: tasks, pace: pace, daysLeft: daysLeft, neededPerDay: needed, averagePerDay: average);
  }

  /// Notes that today's plan was finished. True the first time each day.
  Future<bool> markComplete({DateTime? now}) async {
    final prefs = await SharedPreferences.getInstance();
    final days = _readDays(prefs);
    final key = _dateKey(now ?? DateTime.now());
    if (days.contains(key)) return false;
    days.add(key);
    final kept = (days.toList()..sort()).reversed.take(400).toList();
    await prefs.setString(_doneDaysKey, jsonEncode(kept));
    return true;
  }

  Future<int> completedDays() async => _readDays(await SharedPreferences.getInstance()).length;

  Set<String> _readDays(SharedPreferences prefs) {
    try {
      final raw = prefs.getString(_doneDaysKey);
      return raw == null ? <String>{} : {for (final d in jsonDecode(raw) as List) d as String};
    } catch (_) {
      return <String>{};
    }
  }
}
