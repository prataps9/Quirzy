import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'features/l10n/app_localizations.dart';
import 'routes/router.dart';
import 'shared/theme/app_theme.dart';
import 'shared/services/settings_service.dart';
import 'shared/services/deep_link_service.dart';

class QuirzyApp extends ConsumerStatefulWidget {
  const QuirzyApp({super.key});

  @override
  ConsumerState<QuirzyApp> createState() => _QuirzyAppState();
}

class _QuirzyAppState extends ConsumerState<QuirzyApp> {
  @override
  void initState() {
    super.initState();
    // Initialize deep link service after first frame
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initDeepLinks();
    });
  }

  Future<void> _initDeepLinks() async {
    try {
      await DeepLinkService.instance.init(ref);
      debugPrint('DeepLink: Service initialized');
    } catch (e) {
      debugPrint('DeepLink: Initialization error: $e');
    }
  }

  @override
  void dispose() {
    DeepLinkService.instance.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final router = ref.watch(routerProvider);
    final settings = SettingsService();

    return AnimatedBuilder(
      animation: settings,
      builder: (context, child) {
        return MaterialApp.router(
          title: 'ExamAI',
          theme: AppTheme.light,
          darkTheme: AppTheme.dark,
          themeMode: settings.themeMode,
          routerConfig: router,
          debugShowCheckedModeBanner: false,
          localizationsDelegates: const [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: const [Locale('en')],
        );
      },
    );
  }
}
