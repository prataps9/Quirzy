import 'package:flutter_test/flutter_test.dart';
import 'package:quirzy/features/subscription/services/pro_status.dart';
import 'package:quirzy/shared/services/local_data_reset.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('wipe clears user data but keeps the theme and the purchased plan', () async {
    SharedPreferences.setMockInitialValues({
      'theme_mode': 'light',
      'xp_total': 420,
      'selected_exam': 'jee',
      'feed_answered_count_2026-10-04': 12,
      ProStatusStore.isProKey: true,
      ProStatusStore.ownerKey: 'alice',
    });

    await LocalDataReset.wipe();

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getKeys(), {'theme_mode', ProStatusStore.isProKey, ProStatusStore.ownerKey});
    expect(prefs.getString('theme_mode'), 'light');
  });
}
