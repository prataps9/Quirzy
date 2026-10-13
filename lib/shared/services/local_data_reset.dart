import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Wipes everything this device remembers about the signed-in user — the
/// practice feed, XP, streak counters, Pro, flashcard progress, exam choice
/// and scheduled reminders — so the next account starts clean. Device-level
/// preferences in [keep] (the theme) survive.
class LocalDataReset {
  static const keep = {'theme_mode'};

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
