import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'app_routes.dart';
import '../features/auth/providers/auth_provider.dart';
import '../shared/widgets/splash_screen.dart';

// Screens
import '../features/auth/screens/screens.dart';
import '../features/home/screens/screens.dart';
import '../features/content/screens/screens.dart';
import '../features/flashcards/screens/screens.dart';
import '../features/profile/screens/screens.dart';
import '../features/content/screens/study_notes_screen.dart';
import '../features/content/screens/add_questions_screen.dart';
import '../features/content/screens/study_material_entry_screen.dart';
import '../features/profile/screens/notification_settings_screen.dart';

class AuthListenator extends ChangeNotifier {
  AuthListenator(this.ref) {
    ref.listen<AsyncValue<dynamic>>(authProvider, (_, __) => notifyListeners());
  }
  final Ref ref;
}

final routerProvider = Provider<GoRouter>((ref) {
  return GoRouter(
    initialLocation: AppRoutes.initial,
    debugLogDiagnostics: true,
    refreshListenable: AuthListenator(ref),
    redirect: (context, state) {
      final authState = ref.watch(authProvider);

      final isLoggedIn = authState.value != null;
      final isLoggingIn =
          state.matchedLocation == AppRoutes.auth ||
          state.matchedLocation == AppRoutes.login ||
          state.matchedLocation == AppRoutes.signup ||
          state.matchedLocation == AppRoutes.success;

      if (authState.isLoading) return null;

      if (!isLoggedIn && !isLoggingIn) return AppRoutes.auth;
      if (isLoggedIn && isLoggingIn) return AppRoutes.home;
      if (isLoggedIn && state.matchedLocation == AppRoutes.initial)
        return AppRoutes.home;

      return null;
    },
    routes: [
      GoRoute(
        path: AppRoutes.initial,
        builder: (context, state) => const SplashScreen(),
      ),
      GoRoute(
        path: AppRoutes.auth,
        builder: (context, state) => const WelcomeScreen(),
      ),
      GoRoute(
        path: AppRoutes.login,
        builder: (context, state) => const LoginScreen(),
      ),
      GoRoute(
        path: AppRoutes.signup,
        builder: (context, state) => const SignupScreen(),
      ),
      GoRoute(
        path: AppRoutes.success,
        builder: (context, state) {
          final extra = state.extra as Map<String, dynamic>?;
          return SuccessScreen(
            onComplete: () => context.go(AppRoutes.home),
            message: extra?['message'] ?? 'Success!',
            subtitle: extra?['subtitle'],
          );
        },
      ),
      GoRoute(
        path: AppRoutes.home,
        builder: (context, state) => const MainScreen(),
      ),
      GoRoute(
        path: AppRoutes.flashcards,
        builder: (context, state) => const FlashcardsScreen(),
      ),
      GoRoute(
        path: AppRoutes.profile,
        builder: (context, state) => const ProfileSettingsScreen(),
      ),
      GoRoute(
        path: AppRoutes.apiKeySettings,
        builder: (context, state) => const ApiKeySettingsScreen(),
      ),
      GoRoute(
        path: AppRoutes.studyNotes,
        builder: (context, state) => const StudyNotesScreen(),
      ),
      GoRoute(
        path: AppRoutes.customQuizCreator,
        builder: (context, state) => const AddQuestionsScreen(),
      ),
      GoRoute(
        path: AppRoutes.studyMaterialEntry,
        builder: (context, state) => const StudyMaterialEntryScreen(),
      ),
      GoRoute(
        path: AppRoutes.notificationSettings,
        builder: (context, state) => const NotificationSettingsScreen(),
      ),
    ],
  );
});
