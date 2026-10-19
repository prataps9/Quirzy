import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/notification_scheduler.dart';

final examProvider = NotifierProvider<ExamNotifier, String?>(ExamNotifier.new);

class ExamNotifier extends Notifier<String?> {
  @override
  String? build() {
    // Determine initial state
    _loadExam();
    return null;
  }

  Future<void> _loadExam() async {
    final prefs = await SharedPreferences.getInstance();
    final exam = prefs.getString('selected_exam');
    state = exam;
  }

  Future<void> setExam(String exam) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('selected_exam', exam);
    state = exam;
  }

  bool get hasSelected => state != null;
}

/// Display names for the exam ids chosen during onboarding.
const Map<String, String> kExamNames = {
  'mba': 'MBA',
  'cat': 'CAT',
  'cuet': 'CUET',
  'jee': 'JEE',
  'neet': 'NEET',
  '10th': 'Class 10 boards',
  '12th': 'Class 12 boards',
  'ielts': 'IELTS',
  'gre': 'GRE',
  'gmat': 'GMAT',
};

/// A readable name for [examId], or "your exam" when none is chosen.
String examDisplayName(String? examId) {
  if (examId == null || examId.isEmpty) return 'your exam';
  return kExamNames[examId.toLowerCase()] ?? examId.toUpperCase();
}

const _examDateKey = 'exam_date';

/// Reads the saved exam date (pref `exam_date`, ISO string), if any.
Future<DateTime?> readExamDate() async {
  final prefs = await SharedPreferences.getInstance();
  final raw = prefs.getString(_examDateKey);
  return raw == null ? null : DateTime.tryParse(raw);
}

/// Whole days from today until [examDate] (0 on the day, negative after).
int daysUntilExam(DateTime examDate, {DateTime? now}) {
  final today = now ?? DateTime.now();
  return DateTime.utc(examDate.year, examDate.month, examDate.day)
      .difference(DateTime.utc(today.year, today.month, today.day))
      .inDays;
}

/// The user's exam date, or null when they haven't set one. Setting or
/// clearing it reschedules the exam countdown notification.
final examDateProvider =
    AsyncNotifierProvider<ExamDateNotifier, DateTime?>(ExamDateNotifier.new);

class ExamDateNotifier extends AsyncNotifier<DateTime?> {
  @override
  Future<DateTime?> build() => readExamDate();

  Future<void> setDate(DateTime date) async {
    final day = DateTime(date.year, date.month, date.day);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_examDateKey, day.toIso8601String());
    state = AsyncData(day);
    await NotificationScheduler().reschedule(NotificationScheduler.examCountdown);
  }

  Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_examDateKey);
    state = const AsyncData(null);
    await NotificationScheduler().reschedule(NotificationScheduler.examCountdown);
  }
}
