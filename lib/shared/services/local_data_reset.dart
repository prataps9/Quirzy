import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../features/subscription/services/pro_status.dart';
import 'settings_service.dart';

/// Wipes everything this device remembers about the signed-in user — the
/// practice feed, XP, streak counters, flashcard progress, exam choice and
/// scheduled reminders — so the next account starts clean. Device
/// preferences (theme, feed sound and auto-scroll) and the purchased Pro
/// plan survive ([keep]); Pro only applies again when the account that
/// bought it signs back in.
class LocalDataReset {
  static const keep = {...SettingsService.deviceKeys, ...ProStatusStore.keys};

  static Future<void> wipe() async {
    final prefs = await SharedPreferences.getInstance();
    for (final key in prefs.getKeys().toList()) {
      if (!keep.contains(key)) await prefs.remove(key);
    }
    try {
      await const FlutterSecureStorage().deleteAll();
    } catch (e) {
      debugPrint('LocalDataReset: secure storage wipe failed: $e');
    }
    try {
      await FlutterLocalNotificationsPlugin().cancelAll();
    } catch (e) {
      debugPrint('LocalDataReset: cancelling notifications failed: $e');
    }
  }
}
