import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../../domain/domain.dart';
import '../../shared/appwrite/user/user_service.dart';
import '../../shared/services/local_data_reset.dart';

/// Auth state provider using AsyncNotifier for proper state management
final authProvider = AsyncNotifierProvider<AuthNotifier, AuthUser?>(
  AuthNotifier.new,
);

/// Auth Notifier - Google sign-in, logout and account deletion.
class AuthNotifier extends AsyncNotifier<AuthUser?> {
  static const _storage = FlutterSecureStorage();

  /// How long app start waits for the server before trusting the cache.
  static const _sessionCheckTimeout = Duration(seconds: 8);

  @override
  Future<AuthUser?> build() => _loadUser();

  /// Asks the server who is signed in. If the server can't be reached
  /// (offline, slow), keeps a previously signed-in user signed in from the
  /// copy saved on this device instead of bouncing them to Welcome.
  Future<AuthUser?> _loadUser() async {
    try {
      final user = await ref.read(getCurrentUserUseCaseProvider).call().timeout(_sessionCheckTimeout);
      if (user != null) {
        // Other screens read the name/photo from secure storage; keep it fresh.
        try {
          await _saveUserToStorage(user);
        } catch (e) {
          debugPrint('AuthProvider: Could not cache user: $e');
        }
      }
      return user;
    } catch (e) {
      debugPrint('AuthProvider: Session check failed, using cached user: $e');
      return cachedUser(_readStorage);
    }
  }

  static Future<String?> _readStorage(String key) async {
    try {
      return await _storage.read(key: key);
    } catch (_) {
      return null;
    }
  }

  /// The user saved on this device at sign-in, or null if there is none.
  @visibleForTesting
  static Future<AuthUser?> cachedUser(Future<String?> Function(String key) read) async {
    final id = await read('user_id');
    if (id == null || id.isEmpty) return null;
    return AuthUser(
      id: id,
      email: await read('user_email') ?? '',
      name: await read('user_name') ?? '',
      photoUrl: await read('user_photo_url'),
    );
  }

  /// Google sign-in (native flow). Throws on failure — including when the
  /// user closes the account picker — so the screen can respond; the auth
  /// state goes back to signed out either way.
  Future<void> googleSignIn() async {
    state = const AsyncValue.loading();
    try {
      final user = await ref.read(signInWithGoogleUseCaseProvider).call();
      debugPrint('AuthProvider: Google Sign-In successful');
      await _saveUserToStorage(user);
      state = AsyncValue.data(user);
    } catch (e) {
      state = const AsyncValue.data(null);
      rethrow;
    }
  }

  /// Ends the Appwrite session and wipes everything stored on this device.
  /// The caller should then restart the app ([AppRestartScope.restart]) so
  /// no provider keeps the previous user's data in memory.
  Future<void> logout() async {
    state = const AsyncValue.loading();
    await _endSessionAndWipe();
    state = const AsyncValue.data(null);
  }

  /// Deletes the user's profile, blocks the Appwrite account so it can't be
  /// signed in to again, then logs out and wipes local data. Throws if the
  /// server-side steps fail — in that case the user stays signed in.
  Future<void> deleteAccount() async {
    final userId = state.value?.id;
    if (userId == null) throw StateError('Not signed in');
    await UserService().deleteUserAccount(userId: userId);
    await _endSessionAndWipe();
    state = const AsyncValue.data(null);
  }

  Future<void> _endSessionAndWipe() async {
    try {
      await ref.read(logoutUseCaseProvider).call();
    } catch (e) {
      // A dead or already-blocked session is fine — we're leaving anyway.
      debugPrint('AuthProvider: Session delete failed: $e');
    }
    await LocalDataReset.wipe();
  }

  Future<void> refresh() async {
    try {
      debugPrint('AuthProvider: Refreshing auth state...');
      final user = await _loadUser();
      debugPrint('AuthProvider: Got user: ${user != null}');
      state = AsyncValue.data(user);
    } catch (e, st) {
      debugPrint('AuthProvider: Refresh error: $e');
      state = AsyncValue.error(e, st);
    }
  }

  /// Save user details to secure storage for quick access
  Future<void> _saveUserToStorage(AuthUser user) async {
    await _storage.write(key: 'user_id', value: user.id);
    await _storage.write(key: 'user_name', value: user.name);
    await _storage.write(key: 'user_email', value: user.email);
    if (user.photoUrl != null) {
      await _storage.write(key: 'user_photo_url', value: user.photoUrl);
    }
  }
}
