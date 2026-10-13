import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'pro_status.dart';

/// The AI generations a free account can run a limited number of times a
/// day. Manual question entry is never limited.
enum UsageKind {
  topic(
    freePerDay: 2,
    singular: 'topic',
    plural: 'topics',
    countKey: 'daily_quiz_generation_count',
    dateKey: 'last_quiz_generation_date',
  ),
  studySet(
    freePerDay: 1,
    singular: 'study set',
    plural: 'study sets',
    countKey: 'daily_study_material_count',
    dateKey: 'last_study_material_count_date',
  ),
  flashcardSet(
    freePerDay: 3,
    singular: 'flashcard set',
    plural: 'flashcard sets',
    countKey: 'daily_flashcard_set_count',
    dateKey: 'last_flashcard_set_date',
  );

  const UsageKind({
    required this.freePerDay,
    required this.singular,
    required this.plural,
    required this.countKey,
    required this.dateKey,
  });

  final int freePerDay;
  final String singular;
  final String plural;
  final String countKey;
  final String dateKey;

  /// "2 free topics", "1 free study set".
  String get freeAllowance => '$freePerDay free ${freePerDay == 1 ? singular : plural}';
}

/// Today's usage for every [UsageKind], plus whether the user is Pro.
class UsageState {
  final ProStatus pro;
  final Map<UsageKind, int> used;

  const UsageState({required this.pro, required this.used});

  bool get isPro => pro.isPro;

  int usedToday(UsageKind kind) => used[kind] ?? 0;

  /// How many more free uses are left today, or null when unlimited (Pro).
  int? remaining(UsageKind kind) {
    if (isPro) return null;
    return (kind.freePerDay - usedToday(kind)).clamp(0, kind.freePerDay);
  }

  bool canUse(UsageKind kind) => isPro || usedToday(kind) < kind.freePerDay;
}

/// Persists the per-day counters. Counters reset on the first use of a new
/// local day.
class UsageLimitsService {
  UsageLimitsService({DateTime Function()? clock, ProStatusStore? proStore})
    : _clock = clock ?? DateTime.now,
      _proStore = proStore ?? ProStatusStore(clock: clock);

  final DateTime Function() _clock;
  final ProStatusStore _proStore;

  String _today() {
    final now = _clock();
    final m = now.month.toString().padLeft(2, '0');
    final d = now.day.toString().padLeft(2, '0');
    return '${now.year}-$m-$d';
  }

  Future<int> usedToday(UsageKind kind) async {
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getString(kind.dateKey) != _today()) return 0;
    return prefs.getInt(kind.countKey) ?? 0;
  }

  Future<UsageState> load() async {
    final pro = await _proStore.load();
    return UsageState(
      pro: pro,
      used: {for (final kind in UsageKind.values) kind: await usedToday(kind)},
    );
  }

  Future<void> record(UsageKind kind) async {
    final prefs = await SharedPreferences.getInstance();
    final count = await usedToday(kind);
    await prefs.setString(kind.dateKey, _today());
    await prefs.setInt(kind.countKey, count + 1);
  }
}

final usageLimitsServiceProvider = Provider<UsageLimitsService>((ref) => UsageLimitsService());

/// Live usage state. Call [UsageLimitsController.record] after a successful
/// generation and [UsageLimitsController.refresh] after a purchase.
class UsageLimitsController extends AsyncNotifier<UsageState> {
  @override
  Future<UsageState> build() => ref.read(usageLimitsServiceProvider).load();

  /// Whether [kind] can be used right now. Always reads fresh state so a
  /// new day or an expired Pro is picked up.
  Future<bool> canUse(UsageKind kind) async {
    final next = await ref.read(usageLimitsServiceProvider).load();
    state = AsyncData(next);
    return next.canUse(kind);
  }

  Future<void> record(UsageKind kind) async {
    final service = ref.read(usageLimitsServiceProvider);
    await service.record(kind);
    state = AsyncData(await service.load());
  }

  Future<void> refresh() async {
    state = AsyncData(await ref.read(usageLimitsServiceProvider).load());
  }
}

final usageLimitsProvider = AsyncNotifierProvider<UsageLimitsController, UsageState>(
  UsageLimitsController.new,
);

/// Pro status on its own, for UI that only needs to know "is this user Pro".
final proStatusProvider = Provider<ProStatus>((ref) {
  return ref.watch(usageLimitsProvider).value?.pro ?? ProStatus.free;
});
