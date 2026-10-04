import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/feed_models.dart';

/// A behaviour signal and how much it moves a topic's interest score.
enum EngagementSignal {
  like(1.0),
  unlike(-1.0),
  save(1.5),
  explanationOpened(0.5),
  answered(0.3),
  quickPass(-0.6),
  showLess(-3.0),
  undoShowLess(3.0);

  const EngagementSignal(this.weight);
  final double weight;
}

class _Interest {
  final double score;
  final int updatedMs;

  const _Interest(this.score, this.updatedMs);
}

/// What the feed has learned from how the user behaves: a per-topic
/// interest score, liked questions, and when each question was last seen.
///
/// Signals arrive on nearly every swipe, so state lives in memory and is
/// written to SharedPreferences on a short debounce, or immediately via
/// [flush] when the feed is left or the app is backgrounded.
class FeedEngagementService {
  FeedEngagementService({
    DateTime Function()? clock,
    Duration flushDelay = const Duration(seconds: 5),
  }) : _clock = clock ?? DateTime.now,
       _flushDelay = flushDelay;

  static const profileKey = 'feed_eng_profile';
  static const seenKey = 'feed_eng_seen';
  static const maxInterest = 6.0;
  static const dailyDecay = 0.9;

  final DateTime Function() _clock;
  final Duration _flushDelay;
  final Map<String, _Interest> _interest = {};
  final Set<String> _liked = {};
  final Map<String, SeenRecord> _seen = {};
  Future<void>? _loading;
  Timer? _flushTimer;
  bool _dirty = false;

  /// Loads persisted state once. When [liveKeys] is given, seen entries
  /// for questions no longer in the pool are dropped.
  Future<void> load({Set<String>? liveKeys}) async {
    await (_loading ??= _read());
    if (liveKeys != null) {
      final before = _seen.length;
      _seen.removeWhere((key, _) => !liveKeys.contains(key));
      if (_seen.length != before) _markDirty();
    }
  }

  Future<void> _read() async {
    final prefs = await SharedPreferences.getInstance();
    final profileRaw = prefs.getString(profileKey);
    if (profileRaw != null && profileRaw.isNotEmpty) {
      final profile = jsonDecode(profileRaw) as Map<String, dynamic>;
      final interest = profile['interest'] as Map<String, dynamic>? ?? {};
      for (final entry in interest.entries) {
        final value = entry.value as Map<String, dynamic>;
        _interest[entry.key] = _Interest(
          (value['s'] as num).toDouble(),
          value['t'] as int,
        );
      }
      _liked.addAll(List<String>.from(profile['liked'] as List? ?? const []));
    }
    final seenRaw = prefs.getString(seenKey);
    if (seenRaw != null && seenRaw.isNotEmpty) {
      final seen = jsonDecode(seenRaw) as Map<String, dynamic>;
      for (final entry in seen.entries) {
        final value = entry.value as List;
        _seen[entry.key] = SeenRecord(
          lastSeenMs: value[0] as int,
          count: value[1] as int,
        );
      }
    }
  }

  double _decayed(_Interest interest) {
    final elapsedMs = _clock().millisecondsSinceEpoch - interest.updatedMs;
    final days = math.max(0, elapsedMs) / Duration.millisecondsPerDay;
    return interest.score * math.pow(dailyDecay, days);
  }

  /// Current interest in [topic], with time decay applied.
  double interestOf(String topic) {
    final interest = _interest[topic];
    return interest == null ? 0 : _decayed(interest);
  }

  /// Decayed interest for every topic with a recorded signal.
  Map<String, double> interestSnapshot() =>
      _interest.map((topic, value) => MapEntry(topic, _decayed(value)));

  void record(String topic, EngagementSignal signal) {
    final score = (interestOf(topic) + signal.weight)
        .clamp(-maxInterest, maxInterest)
        .toDouble();
    _interest[topic] = _Interest(score, _clock().millisecondsSinceEpoch);
    _markDirty();
  }

  bool isLiked(String engagementKey) => _liked.contains(engagementKey);

  void setLiked(String engagementKey, bool liked) {
    final changed = liked
        ? _liked.add(engagementKey)
        : _liked.remove(engagementKey);
    if (changed) _markDirty();
  }

  void markSeen(String engagementKey) {
    final previous = _seen[engagementKey];
    _seen[engagementKey] = SeenRecord(
      lastSeenMs: _clock().millisecondsSinceEpoch,
      count: (previous?.count ?? 0) + 1,
    );
    _markDirty();
  }

  Map<String, SeenRecord> get seen => Map.unmodifiable(_seen);

  void _markDirty() {
    _dirty = true;
    _flushTimer?.cancel();
    _flushTimer = Timer(_flushDelay, flush);
  }

  /// Writes pending changes now.
  Future<void> flush() async {
    _flushTimer?.cancel();
    _flushTimer = null;
    if (!_dirty) return;
    _dirty = false;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      profileKey,
      jsonEncode({
        'interest': _interest.map(
          (topic, value) =>
              MapEntry(topic, {'s': value.score, 't': value.updatedMs}),
        ),
        'liked': _liked.toList(),
      }),
    );
    await prefs.setString(
      seenKey,
      jsonEncode(
        _seen.map((key, value) => MapEntry(key, [value.lastSeenMs, value.count])),
      ),
    );
  }

  void dispose() {
    unawaited(flush());
  }
}

final feedEngagementServiceProvider = Provider<FeedEngagementService>((ref) {
  final service = FeedEngagementService();
  ref.onDispose(service.dispose);
  return service;
});
