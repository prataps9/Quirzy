import 'package:flutter/material.dart';
import 'app.dart';
import 'shared/services/cache_service.dart';
import 'shared/services/reminder_service.dart';
import 'shared/services/settings_service.dart';
import 'shared/services/smart_notification_service.dart';
import 'shared/widgets/app_restart_scope.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await SettingsService().init();
  await CacheService.init();
  await ReminderService.init();
  await SmartNotificationService().init();

  runApp(const AppRestartScope(child: QuirzyApp()));
}
