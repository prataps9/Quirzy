import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'app.dart';
import 'shared/services/cache_service.dart';
import 'shared/services/settings_service.dart';
import 'shared/services/smart_notification_service.dart';
import 'shared/widgets/app_restart_scope.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Plus Jakarta Sans ships with the app (assets/google_fonts); never wait
  // on the network for a font.
  GoogleFonts.config.allowRuntimeFetching = false;

  // Independent setup, done together so the splash shows for less time.
  await Future.wait([
    SettingsService().init(),
    CacheService.init(),
    SmartNotificationService().init(),
  ]);

  runApp(const AppRestartScope(child: QuirzyApp()));
}
