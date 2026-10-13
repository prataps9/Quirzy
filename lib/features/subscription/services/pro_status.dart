import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The two Pro plans the paywall sells. Both are one-time payments that
/// unlock Pro for a fixed period — there is no auto-renew.
enum ProPlan {
  monthly(days: 31),
  yearly(days: 366);

  const ProPlan({required this.days});

  final int days;
}

/// Whether the user currently has Pro, and until when.
class ProStatus {
  final bool isPro;
  final ProPlan? plan;
  final DateTime? expiresAt;

  const ProStatus({required this.isPro, this.plan, this.expiresAt});

  static const free = ProStatus(isPro: false);
}

/// Reads and writes Pro locally. Pro is bought for a fixed period, so it
/// lapses on its own once [ProPlan.days] have passed since the purchase.
///
/// Pro belongs to the account that bought it: it survives logout (see
/// [keys], kept by LocalDataReset) but only applies while that same
/// account is signed in.
class ProStatusStore {
  ProStatusStore({DateTime Function()? clock, Future<String?> Function()? currentUserId})
    : _clock = clock ?? DateTime.now,
      _currentUserId = currentUserId ?? _signedInUserId;

  static const isProKey = 'is_pro';
  static const planKey = 'subscription_plan';
  static const dateKey = 'subscription_date';
  static const paymentIdKey = 'payment_id';
  static const ownerKey = 'pro_owner_id';

  /// Everything Pro stores, so a logout wipe can leave it in place.
  static const keys = {isProKey, planKey, dateKey, paymentIdKey, ownerKey};

  final DateTime Function() _clock;
  final Future<String?> Function() _currentUserId;

  static Future<String?> _signedInUserId() async {
    try {
      return await const FlutterSecureStorage().read(key: 'user_id');
    } catch (_) {
      return null;
    }
  }

  Future<ProStatus> load() async {
    final prefs = await SharedPreferences.getInstance();
    if (!(prefs.getBool(isProKey) ?? false)) return ProStatus.free;

    final owner = prefs.getString(ownerKey);
    if (owner != null) {
      final current = await _currentUserId();
      if (current != null && current != owner) return ProStatus.free;
    }

    final boughtAt = DateTime.tryParse(prefs.getString(dateKey) ?? '');
    final plan = ProPlan.values.asNameMap()[prefs.getString(planKey)] ?? ProPlan.monthly;
    if (boughtAt == null) return ProStatus.free;

    final expiresAt = boughtAt.add(Duration(days: plan.days));
    if (!_clock().isBefore(expiresAt)) {
      await prefs.setBool(isProKey, false);
      return ProStatus.free;
    }
    return ProStatus(isPro: true, plan: plan, expiresAt: expiresAt);
  }

  /// Records a successful purchase. Buying again while still Pro extends
  /// from the current expiry rather than from today.
  Future<ProStatus> activate(ProPlan plan, {String? paymentId}) async {
    final prefs = await SharedPreferences.getInstance();
    final current = await load();
    // Stacking: the new period starts when the current one ends.
    final start = current.isPro ? current.expiresAt! : _clock();

    await prefs.setBool(isProKey, true);
    await prefs.setString(planKey, plan.name);
    await prefs.setString(dateKey, start.toIso8601String());
    if (paymentId != null) await prefs.setString(paymentIdKey, paymentId);
    final owner = await _currentUserId();
    if (owner != null) await prefs.setString(ownerKey, owner);
    return load();
  }
}
