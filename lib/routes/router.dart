import 'package:flutter/foundation.dart';
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

class AuthListenator extends ChangeNotifier {
  AuthListenator(this.ref) {
    ref.listen<AsyncValue<dynamic>>(authProvider, (_, _) => notifyListeners());
  }
  final Ref ref;
}

final routerProvider = Provider<GoRouter>((ref) {
  return GoRouter(
    initialLocation: AppRoutes.initial,
    debugLogDiagnostics: kDebugMode,
    refreshListenable: AuthListenator(ref),
    redirect: (context, state) {
      final authState = ref.read(authProvider);

      final isLoggedIn = authState.value != null;
      final isLoggingIn = state.matchedLocation == AppRoutes.auth;

      if (authState.isLoading) return null;

      if (!isLoggedIn && !isLoggingIn) return AppRoutes.auth;
      if (isLoggedIn && isLoggingIn) return AppRoutes.home;
      if (isLoggedIn && state.matchedLocation == AppRoutes.initial) {
        return AppRoutes.home;
      }

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
