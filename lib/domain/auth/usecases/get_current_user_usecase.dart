import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:appwrite/models.dart';
import '../../../core/di/app_providers.dart';
import '../entities/auth_user.dart';

/// Get Current User Use Case - retrieves currently authenticated user
final getCurrentUserUseCaseProvider = Provider<GetCurrentUserUseCase>((ref) {
  return GetCurrentUserUseCase(authService: ref.watch(authServiceProvider));
});

class GetCurrentUserUseCase {
  final dynamic _authService;

  GetCurrentUserUseCase({required dynamic authService})
      : _authService = authService;

  /// The signed-in user, or null when signed out. Throws when the server
  /// can't be reached, so callers can fall back to the cached user.
  Future<AuthUser?> call() async {
    final User? user = await _authService.getCurrentUser();
    if (user == null) return null;

    final prefs = user.prefs.data;
    return AuthUser(
      id: user.$id,
      email: user.email,
      name: user.name,
      photoUrl: prefs['photoUrl'] as String?,
    );
  }
}
