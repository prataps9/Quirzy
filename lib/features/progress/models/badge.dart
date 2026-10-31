import 'package:flutter/material.dart';

/// The numbers badges are earned from.
class BadgeMetrics {
  final int totalAnswers;
  final int bestStreak;
  final int dailyPlayed;
  final int dailyPerfect;
  final int masteredTopics;
  final int flashcardsReviewed;
  final int mockTests;
  final int bestMockPercent;
  final int mistakesFixed;
  final int planDays;

  const BadgeMetrics({
    this.totalAnswers = 0,
    this.bestStreak = 0,
    this.dailyPlayed = 0,
    this.dailyPerfect = 0,
    this.masteredTopics = 0,
    this.flashcardsReviewed = 0,
    this.mockTests = 0,
    this.bestMockPercent = 0,
    this.mistakesFixed = 0,
    this.planDays = 0,
  });
}

enum BadgeId {
  firstAnswer,
  answers100,
  answers500,
  answers1000,
  streak3,
  streak7,
  streak30,
  dailyPerfect,
  daily7,
  topicMastered,
  cards50,
  firstMock,
  mock90,
  fixed10,
  onPlan,
}

/// One badge: what it's called, how it's earned, and how far along the user
/// is ([measure] read against [target]).
class BadgeDef {
  final BadgeId id;
  final String title;
  final String description;
  final IconData icon;
  final int target;
  final int Function(BadgeMetrics) measure;

  const BadgeDef({
    required this.id,
    required this.title,
    required this.description,
    required this.icon,
    required this.target,
    required this.measure,
  });

  int progress(BadgeMetrics m) => measure(m).clamp(0, target);
  bool reached(BadgeMetrics m) => measure(m) >= target;

  static BadgeDef of(BadgeId id) => catalog.firstWhere((b) => b.id == id);

  static final List<BadgeDef> catalog = [
    BadgeDef(
      id: BadgeId.firstAnswer,
      title: 'First answer',
      description: 'Answer your first question.',
      icon: Icons.flag_rounded,
      target: 1,
      measure: (m) => m.totalAnswers,
    ),
    BadgeDef(
      id: BadgeId.answers100,
      title: 'Century',
      description: 'Answer 100 questions.',
      icon: Icons.workspace_premium_rounded,
      target: 100,
      measure: (m) => m.totalAnswers,
    ),
    BadgeDef(
      id: BadgeId.answers500,
      title: 'Five hundred',
      description: 'Answer 500 questions.',
      icon: Icons.military_tech_rounded,
      target: 500,
      measure: (m) => m.totalAnswers,
    ),
    BadgeDef(
      id: BadgeId.answers1000,
      title: 'Thousand club',
      description: 'Answer 1,000 questions.',
      icon: Icons.diamond_rounded,
      target: 1000,
      measure: (m) => m.totalAnswers,
    ),
    BadgeDef(
      id: BadgeId.streak3,
      title: 'On a roll',
      description: 'Practise 3 days in a row.',
      icon: Icons.local_fire_department_rounded,
      target: 3,
      measure: (m) => m.bestStreak,
    ),
    BadgeDef(
      id: BadgeId.streak7,
      title: 'Week streak',
      description: 'Practise 7 days in a row.',
      icon: Icons.whatshot_rounded,
      target: 7,
      measure: (m) => m.bestStreak,
    ),
    BadgeDef(
      id: BadgeId.streak30,
      title: 'Month streak',
      description: 'Practise 30 days in a row.',
      icon: Icons.local_fire_department_outlined,
      target: 30,
      measure: (m) => m.bestStreak,
    ),
    BadgeDef(
      id: BadgeId.dailyPerfect,
      title: 'Perfect Daily 5',
      description: 'Get every question in a Daily 5 right.',
      icon: Icons.bolt_rounded,
      target: 1,
      measure: (m) => m.dailyPerfect,
    ),
    BadgeDef(
      id: BadgeId.daily7,
      title: 'Daily habit',
      description: 'Finish the Daily 5 on 7 days.',
      icon: Icons.event_available_rounded,
      target: 7,
      measure: (m) => m.dailyPlayed,
    ),
    BadgeDef(
      id: BadgeId.topicMastered,
      title: 'Mastered',
      description: 'Master a topic: 85% or better over 20 or more answers.',
      icon: Icons.verified_rounded,
      target: 1,
      measure: (m) => m.masteredTopics,
    ),
    BadgeDef(
      id: BadgeId.cards50,
      title: 'Card shark',
      description: 'Review 50 flashcards.',
      icon: Icons.style_rounded,
      target: 50,
      measure: (m) => m.flashcardsReviewed,
    ),
    BadgeDef(
      id: BadgeId.firstMock,
      title: 'Test taker',
      description: 'Finish a mock test.',
      icon: Icons.timer_outlined,
      target: 1,
      measure: (m) => m.mockTests,
    ),
    BadgeDef(
      id: BadgeId.mock90,
      title: 'Top marks',
      description: 'Score 90% or more on a mock test.',
      icon: Icons.emoji_events_rounded,
      target: 90,
      measure: (m) => m.bestMockPercent,
    ),
    BadgeDef(
      id: BadgeId.fixed10,
      title: 'Fixer',
      description: 'Fix 10 mistakes: get each right twice in a row.',
      icon: Icons.rule_rounded,
      target: 10,
      measure: (m) => m.mistakesFixed,
    ),
    BadgeDef(
      id: BadgeId.onPlan,
      title: 'On plan',
      description: "Finish the day's study plan on 5 days.",
      icon: Icons.checklist_rounded,
      target: 5,
      measure: (m) => m.planDays,
    ),
  ];
}

/// A badge as shown in My Prep: earned (and when) or how far along.
class BadgeStatus {
  final BadgeDef def;
  final int progress;
  final DateTime? earnedAt;

  const BadgeStatus({required this.def, required this.progress, this.earnedAt});

  bool get earned => earnedAt != null;
}
