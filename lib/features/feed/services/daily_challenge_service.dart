import 'dart:convert';
import 'dart:math' as math;

import 'package:shared_preferences/shared_preferences.dart';

import '../models/daily_challenge.dart';
import '../models/feed_models.dart';

/// Picks and tracks the Daily 5. The set is the same all day (and the same
/// pick for the same questions), leans on the user's weak topics, and pays a
/// bonus once when it is finished.
class DailyChallengeService {
  static const size = 5;

  /// Most of the set comes from weak topics when there are any.
  static const weakShare = 3;
  static const completeXp = 10;
  static const strongXp = 25;

  /// Finishing with at least this share correct earns [strongXp].
  static const strongShare = 0.8;

  static const _key = 'daily_challenge_v1';

  static String dateKey(DateTime now) =>
      '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';

  /// XP for a finished challenge.
  static int bonusFor(DailyChallenge challenge) =>
      challenge.total > 0 && challenge.correct / challenge.total >= strongShare ? strongXp : completeXp;

  Future<DailyChallenge?> _load() async {
    final prefs = await SharedPreferences.getInstance();
    try {
      final raw = prefs.getString(_key);
      if (raw == null) return null;
      return DailyChallenge.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
  }

  Future<void> _save(DailyChallenge challenge) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, jsonEncode(challenge.toJson()));
  }

  /// Today's challenge from [pool], or null when there is nothing to ask.
  /// Questions that have left the pool since the pick are dropped.
  Future<DailyChallenge?> today(
    List<PracticeQuestion> pool, {
    Set<String> weakTopics = const {},
    DateTime? now,
  }) async {
    final date = dateKey(now ?? DateTime.now());
    final available = {for (final q in pool.where(_usable)) q.engagementKey};

    final saved = await _load();
    if (saved != null && saved.date == date) {
      final keys = saved.keys.where(available.contains).toList();
      if (keys.isNotEmpty) {
        if (keys.length == saved.keys.length) return saved;
        return saved.copyWith(
          keys: keys,
          results: {for (final e in saved.results.entries) if (keys.contains(e.key)) e.key: e.value},
        );
      }
    }

    final picked = _pick(pool.where(_usable).toList(), weakTopics, date);
    if (picked.isEmpty) return null;
    final fresh = DailyChallenge(date: date, keys: [for (final q in picked) q.engagementKey]);
    await _save(fresh);
    return fresh;
  }

  bool _usable(PracticeQuestion q) => q.options.length >= 2 && q.correctIndex >= 0 && q.correctIndex < q.options.length;

  /// Deterministic for a date and a pool: the same inputs give the same set.
  List<PracticeQuestion> _pick(List<PracticeQuestion> usable, Set<String> weakTopics, String date) {
    final byKey = <String, PracticeQuestion>{for (final q in usable) q.engagementKey: q};
    final keys = byKey.keys.toList()..sort();
    final rng = math.Random(int.parse(date.replaceAll('-', '')));
    keys.shuffle(rng);

    final weak = [for (final k in keys) if (weakTopics.contains(byKey[k]!.topicName)) k];
    final rest = [for (final k in keys) if (!weakTopics.contains(byKey[k]!.topicName)) k];
    final chosen = <String>[...weak.take(weakShare), ...rest.take(size)];
    if (chosen.length < size) chosen.addAll(weak.skip(weakShare));
    final set = chosen.take(size).toList()..shuffle(rng);
    return [for (final k in set) byKey[k]!];
  }

  /// Records an answer. Ignored for questions not in the challenge or
  /// already answered, so a re-opened lane can't double count.
  Future<DailyChallenge> record(DailyChallenge challenge, String key, bool correct) async {
    if (!challenge.keys.contains(key) || challenge.isAnswered(key)) return challenge;
    final updated = challenge.copyWith(results: {...challenge.results, key: correct});
    await _save(updated);
    return updated;
  }

  Future<DailyChallenge> saveBonus(DailyChallenge challenge, int xp) async {
    final updated = challenge.copyWith(bonusXp: xp);
    await _save(updated);
    return updated;
  }
}
