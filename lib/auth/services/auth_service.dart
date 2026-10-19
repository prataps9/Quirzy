import 'dart:async';

import 'package:appwrite/appwrite.dart';
import 'package:appwrite/models.dart';
import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';
import '../../shared/appwrite/appwrite_client.dart';

/// Auth Service using Appwrite
class AuthService {
  final Account _account = AppwriteClient.instance.account;
  final Databases _db = AppwriteClient.instance.databases;

  static const String usersCollection = 'users';

  // Sign Up
  Future<User> signUp({
    required String email,
    required String password,
    required String name,
  }) async {
    try {
      final user = await _account.create(
        userId: ID.unique(),
        email: email,
        password: password,
        name: name,
      );

      await _account.createEmailPasswordSession(
        email: email,
        password: password,
      );

      await _db.createDocument(
        databaseId: AppwriteConfig.databaseId,
        collectionId: usersCollection,
        documentId: user.$id,
        data: {
          'name': name,
          'email': email,
          'quizCount': 0,
          'createdAt': DateTime.now().toIso8601String(),
        },
      );

      return user;
    } on AppwriteException catch (e) {
      throw Exception(e.message ?? 'Signup failed');
    }
  }

  // Sign In
  Future<User> signIn({required String email, required String password}) async {
    try {
      await _account.createEmailPasswordSession(
        email: email,
        password: password,
      );
      return await _account.get();
    } on AppwriteException catch (e) {
      throw Exception(e.message ?? 'Invalid email or password');
    }
  }

  // Google Sign In using Native Google Sign-In + Appwrite email/password
  Future<User> signInWithGoogle() async {
    try {
      debugPrint('AuthService: Starting Native Google Sign-In...');

      // 1. Get GoogleSignIn instance (singleton)
      final GoogleSignIn googleSignIn = GoogleSignIn.instance;

      // 2. Initialize GoogleSignIn
      await googleSignIn.initialize();

      // 3. Sign out first to ensure fresh state
      await googleSignIn.disconnect();

      // 4. Create a completer to wait for auth event
      final completer = Completer<GoogleSignInAccount>();
      late StreamSubscription<GoogleSignInAuthenticationEvent> subscription;

      subscription = googleSignIn.authenticationEvents.listen(
        (event) {
          if (event is GoogleSignInAuthenticationEventSignIn) {
            if (!completer.isCompleted) {
              completer.complete(event.user);
            }
            subscription.cancel();
          } else if (event is GoogleSignInAuthenticationEventSignOut) {
            if (!completer.isCompleted) {
              completer.completeError(Exception('User signed out'));
            }
            subscription.cancel();
          }
        },
        onError: (error) {
          if (!completer.isCompleted) {
            completer.completeError(error);
          }
          subscription.cancel();
        },
      );

      // 5. Trigger authentication
      if (googleSignIn.supportsAuthenticate()) {
        await googleSignIn.authenticate();
      } else {
        throw Exception('Google Sign-In not supported on this platform');
      }

      // 6. Wait for the auth event (with timeout)
      final GoogleSignInAccount googleUser = await completer.future.timeout(
        const Duration(seconds: 60),
        onTimeout: () => throw Exception('Google Sign-In timed out'),
      );

      debugPrint('AuthService: Google Sign-In successful');

      final String email = googleUser.email;
      final String name = googleUser.displayName ?? email.split('@').first;
      final String? photoUrl = googleUser.photoUrl;

      // 7. Create a secure password derived from Google ID
      final String derivedPassword =
          'google_${googleUser.id}_quirzy_secure_2024';

      // 8. Try to login first (existing user)
      try {
        debugPrint('AuthService: Trying to login existing user...');
        await _account.createEmailPasswordSession(
          email: email,
          password: derivedPassword,
        );
        debugPrint('AuthService: Login successful!');

        // Update photo URL if changed
        final user = await _account.get();
        if (photoUrl != null) {
          try {
            await _account.updatePrefs(prefs: {'photoUrl': photoUrl});
          } catch (_) {}
        }
        return user;
      } on AppwriteException catch (e) {
        // A deleted account is blocked, not removed — don't try to recreate it.
        if (e.type == 'user_blocked') {
          throw AppwriteException('This account has been deleted.', e.code, e.type);
        }
        // User doesn't exist or wrong password - try to create account
        debugPrint(
          'AuthService: Login failed (${e.code}), creating new account...',
        );

        if (e.code == 401 ||
            e.code == 404 ||
            e.message?.contains('Invalid credentials') == true) {
          // 9. Create new Appwrite account
          try {
            final user = await _account.create(
              userId: ID.unique(),
              email: email,
              password: derivedPassword,
              name: name,
            );

            debugPrint('AuthService: Account created');

            // 10. Login to the new account
            await _account.createEmailPasswordSession(
              email: email,
              password: derivedPassword,
            );

            // 11. Set photo URL in preferences
            if (photoUrl != null) {
              try {
                await _account.updatePrefs(prefs: {'photoUrl': photoUrl});
              } catch (_) {}
            }

            // 12. Create user document in database
            try {
              await _db.createDocument(
                databaseId: AppwriteConfig.databaseId,
                collectionId: usersCollection,
                documentId: user.$id,
                data: {
                  'name': name,
                  'email': email,
                  'quizCount': 0,
                  'createdAt': DateTime.now().toIso8601String(),
                },
              );
              debugPrint('AuthService: User document created');
            } catch (dbError) {
              debugPrint(
                'AuthService: User document creation failed (non-critical): $dbError',
              );
            }

            return user;
          } on AppwriteException catch (createError) {
            // Account might already exist with different password (edge case)
            if (createError.code == 409) {
              debugPrint('AuthService: Account exists but password mismatch');
              throw Exception(
                'An account with this email already exists but could not be signed in.',
              );
            }
            rethrow;
          }
        }
        rethrow;
      }
    } on AppwriteException catch (e) {
      debugPrint('AuthService: Appwrite error: ${e.code} - ${e.message}');
      throw Exception(e.message ?? 'Google sign in failed');
    } catch (e) {
      debugPrint('AuthService: Google Sign-In error: $e');
      throw Exception('Google sign-in failed: $e');
    }
  }

  // Sync Google User with Database
  Future<User> syncGoogleUser() async {
    // 1. Get current account
    final user = await _account.get();
    debugPrint('AuthService: syncGoogleUser - got account');

    // 2. Try to sync with database, but don't fail if it doesn't work
    try {
      // Check if user document exists
      try {
        await _db.getDocument(
          databaseId: AppwriteConfig.databaseId,
          collectionId: usersCollection,
          documentId: user.$id,
        );
        debugPrint('AuthService: User document already exists');
        // User exists. Optional: Update login time or photo if changed
      } on AppwriteException catch (e) {
        // Document not found, proceed to create
        debugPrint(
          'AuthService: User document not found (${e.code}), creating...',
        );
        await _db.createDocument(
          databaseId: AppwriteConfig.databaseId,
          collectionId: usersCollection,
          documentId: user.$id,
          data: {
            'name': user.name,
            'email': user.email,
            'quizCount': 0,
            'createdAt': DateTime.now().toIso8601String(),
          },
        );
        debugPrint('AuthService: User document created');
      }
    } catch (e) {
      // Database sync failed, but user is still authenticated
      debugPrint('AuthService: Database sync failed (non-critical): $e');
    }

    // Always return the user - auth succeeded even if profile sync failed
    return user;
  }

  // Get Current User (wraps sync for safety)
  Future<User?> getCurrentUser() async {
    try {
      // Verify session exists first
      await _account.get();
      debugPrint('AuthService: Session verified');
      // Then sync/get full user
      return await syncGoogleUser();
    } catch (e) {
      debugPrint('AuthService: getCurrentUser error: $e');
      return null;
    }
  }

  // Is Logged In
  Future<bool> isLoggedIn() async {
    try {
      await _account.get();
      return true;
    } catch (_) {
      return false;
    }
  }

  // Log Out
  Future<void> logout() async {
    try {
      await _account.deleteSession(sessionId: 'current');
    } catch (_) {
      // Ignore logout errors
    }
  }
}
