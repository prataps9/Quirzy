import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// What the user practised on one day: answers and right answers per topic,
/// and answers per hour of the day.
class DayActivity {
  final DateTime day;

  /// Topic to (answered, correct).
  final Map<String, (int, int)> topics;

  /// 24 counts, one per hour.
  final List<int> hours;

  const DayActivity({required this.day, this.topics = const {}, this.hours = const []});

  int get answered => topics.values.fold(0, (sum, t) => sum + t.$1);
  int get correct => topics.values.fold(0, (sum, t) => sum + t.$2);

  int answeredIn(String topic) => topics[topic]?.$1 ?? 0;

  int atHour(int hour) => hour < hours.length ? hours[hour] : 0;
}

/// A day-by-day record of practice, for the study plan and the weekly
/// report. Written alongside topic stats on every answer; days older than
/// [keepDays] are dropped.
class ActivityLog {
  ActivityLog({DateTime Function()? clock}) : _clock = clock ?? DateTime.now;

  static const keyPrefix = 'feed_activity_';
  static const keepDays = 70;

  final DateTime Function() _clock;

  static String dateKey(DateTime day) =>
      '${day.year.toString().padLeft(4, '0')}-${day.month.toString().padLeft(2, '0')}-${day.day.toString().padLeft(2, '0')}';

  static String keyFor(DateTime day) => '$keyPrefix${dateKey(day)}';

  static DateTime _dayOf(DateTime t) => DateTime(t.year, t.month, t.day);

  Future<void> record(String topic, bool correct, {DateTime? at}) async {
    final time = at ?? _clock();
    final prefs = await SharedPreferences.getInstance();
    final key = keyFor(time);
    final isNewDay = !prefs.containsKey(key);
    final day = _parse(_dayOf(time), prefs.getString(key));

    final topics = {...day.topics};
    final (a, c) = topics[topic] ?? (0, 0);
    topics[topic] = (a + 1, c + (correct ? 1 : 0));
    final hours = List<int>.generate(24, (h) => day.atHour(h));
    hours[time.hour]++;

    await prefs.setString(
      key,
      jsonEncode({
        'topics': {
          for (final e in topics.entries) e.key: [e.value.$1, e.value.$2],
        },
        'hours': hours,
      }),
    );
    if (isNewDay) await _prune(prefs, time);
  }

  /// Drops days older than [keepDays]. Only runs when a new day starts.
  Future<void> _prune(SharedPreferences prefs, DateTime now) async {
    final oldest = dateKey(DateTime(now.year, now.month, now.day - keepDays));
    for (final key in prefs.getKeys().where((k) => k.startsWith(keyPrefix)).toList()) {
      if (key.substring(keyPrefix.length).compareTo(oldest) < 0) await prefs.remove(key);
    }
  }

  Future<DayActivity> day(DateTime day) async {
    final prefs = await SharedPreferences.getInstance();
    return _parse(_dayOf(day), prefs.getString(keyFor(day)));
  }

  /// Every day from [from] to [to], inclusive, oldest first.
  Future<List<DayActivity>> range(DateTime from, DateTime to) async {
    final prefs = await SharedPreferences.getInstance();
    final start = _dayOf(from);
    final end = _dayOf(to);
    return [
      for (var d = start; !d.isAfter(end); d = DateTime(d.year, d.month, d.day + 1))
        _parse(d, prefs.getString(keyFor(d))),
    ];
  }

  static DayActivity _parse(DateTime day, String? raw) {
    if (raw == null) return DayActivity(day: day);
    try {
      final json = Map<String, dynamic>.from(jsonDecode(raw) as Map);
      final topics = <String, (int, int)>{
        for (final e in Map<String, dynamic>.from(json['topics'] as Map? ?? {}).entries)
          e.key: ((e.value as List)[0] as int, (e.value as List)[1] as int),
      };
      final hours = [for (final h in json['hours'] as List? ?? const []) h as int];
      return DayActivity(day: day, topics: topics, hours: hours);
    } catch (_) {
      return DayActivity(day: day);
    }
  }
}
