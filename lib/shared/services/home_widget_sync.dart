import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Keeps the Android home-screen widget's numbers current: the streak,
/// today's answers against the goal, and Daily 5 progress. The widget reads
/// these from shared preferences; the channel asks it to redraw.
class HomeWidgetSync {
  static const _channel = MethodChannel('quirzy/widget');

  static const streakKey = 'widget_streak';
  static const todayKey = 'widget_today';
  static const goalKey = 'widget_goal';
  static const dailyDoneKey = 'widget_daily_done';
  static const dailyTotalKey = 'widget_daily_total';

  Future<void> update({
    required int streak,
    required int today,
    required int goal,
    int dailyDone = 0,
    int dailyTotal = 0,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await Future.wait([
      prefs.setInt(streakKey, streak),
      prefs.setInt(todayKey, today),
      prefs.setInt(goalKey, goal),
      prefs.setInt(dailyDoneKey, dailyDone),
      prefs.setInt(dailyTotalKey, dailyTotal),
    ]);
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return;
    try {
      await _channel.invokeMethod<void>('refresh');
    } on MissingPluginException {
      // No widget host (tests, other platforms): the numbers are still saved.
    } on PlatformException catch (e) {
      debugPrint('HomeWidgetSync: refresh failed: ${e.code}');
    }
  }
}

final homeWidgetSyncProvider = Provider<HomeWidgetSync>((ref) => HomeWidgetSync());
