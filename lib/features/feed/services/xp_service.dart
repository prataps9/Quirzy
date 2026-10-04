import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

const List<String> kXpLevelTitles = [
  'Newcomer',
  'Learner',
  'Bronze',
  'Silver',
  'Gold',
  'Platinum',
  'Diamond',
];

/// A level derived from lifetime XP — 100 XP per level, capped at the
/// last named tier (title stays "Diamond" beyond that, level keeps rising).
class XpLevel {
  final int level;
  final String title;
  final int xpIntoLevel;
  final int xpForNextLevel;

  const XpLevel({
    required this.level,
    required this.title,
    required this.xpIntoLevel,
    required this.xpForNextLevel,
  });

  double get progress => xpForNextLevel == 0 ? 1 : xpIntoLevel / xpForNextLevel;

  factory XpLevel.fromTotal(int totalXp) {
    const xpPerLevel = 100;
    final level = 1 + (totalXp ~/ xpPerLevel);
    final titleIndex = (level - 1).clamp(0, kXpLevelTitles.length - 1);
    return XpLevel(
      level: level,
      title: kXpLevelTitles[titleIndex],
      xpIntoLevel: totalXp % xpPerLevel,
      xpForNextLevel: xpPerLevel,
    );
  }
}

/// Tracks XP earned from practicing — today's total (shown on Home), the
/// lifetime total (drives the level shown on My Prep), and the feed's
/// per-answer awards.
class XpService {
  static const _totalKey = 'xp_total';

  Future<void> addXPToday(int xp) async {
    final prefs = await SharedPreferences.getInstance();
    final today = DateTime.now().toIso8601String().split('T').first;
    final key = 'xp_today_$today';
    final current = prefs.getInt(key) ?? 0;
    await prefs.setInt(key, current + xp);

    final total = prefs.getInt(_totalKey) ?? 0;
    await prefs.setInt(_totalKey, total + xp);
  }

  Future<int> getXPToday() async {
    final prefs = await SharedPreferences.getInstance();
    final today = DateTime.now().toIso8601String().split('T').first;
    return prefs.getInt('xp_today_$today') ?? 0;
  }

  Future<int> getXPTotal() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(_totalKey) ?? 0;
  }

  Future<XpLevel> getLevel() async {
    return XpLevel.fromTotal(await getXPTotal());
  }
}

/// Provider for [XpService]
final xpServiceProvider = Provider<XpService>((ref) {
  return XpService();
});

/// Lifetime XP, refreshed when XP is earned.
final xpTotalProvider = FutureProvider<int>((ref) {
  return ref.watch(xpServiceProvider).getXPTotal();
});
