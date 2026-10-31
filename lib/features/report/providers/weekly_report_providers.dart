import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/weekly_report.dart';
import '../services/weekly_report_service.dart';

final weeklyReportServiceProvider = Provider<WeeklyReportService>((ref) => WeeklyReportService());

/// The report for the week [weeksAgo] weeks back (0 = this week).
final weeklyReportProvider = FutureProvider.autoDispose.family<WeeklyReport, int>(
  (ref, weeksAgo) => ref.read(weeklyReportServiceProvider).week(weeksAgo),
);
