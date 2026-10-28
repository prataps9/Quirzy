import 'dart:async';
import 'package:app_links/app_links.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:quirzy/features/auth/providers/auth_provider.dart';
import 'package:quirzy/features/challenge/models/challenge.dart';
import 'package:quirzy/features/challenge/providers/challenge_providers.dart';
import 'package:quirzy/shared/providers/app_action_provider.dart';
import 'package:quirzy/shared/providers/providers.dart';

/// Deep Link Service for handling OAuth callbacks and app links:
/// - `quirzy://practice` (home-screen widget) opens the Practice tab
/// - `quirzy://challenge?d=…` opens a challenge a friend sent
/// - `quirzy://daily`, `quirzy://mocktest`, `quirzy://mistakes` (app
///   shortcuts) open the Daily 5, a mock test or the Mistakes notebook
/// - `appwrite-callback-*` refreshes the auth state
class DeepLinkService {
  static DeepLinkService? _instance;
  late AppLinks _appLinks;
  StreamSubscription<Uri>? _linkSubscription;
  WidgetRef? _ref;

  DeepLinkService._() {
    _appLinks = AppLinks();
  }

  static DeepLinkService get instance {
    _instance ??= DeepLinkService._();
    return _instance!;
  }

  /// Initialize deep link handling with Riverpod ref
  Future<void> init(WidgetRef ref) async {
    _ref = ref;
    await _linkSubscription?.cancel();

    // Handle initial link (app opened via link)
    try {
      final initialUri = await _appLinks.getInitialLink();
      if (initialUri != null) {
        debugPrint('DeepLink: Initial link received (${initialUri.scheme})');
        await _handleDeepLink(initialUri);
      }
    } catch (e) {
      debugPrint('DeepLink: Error getting initial link: $e');
    }

    // Listen for incoming links while app is running
    _linkSubscription = _appLinks.uriLinkStream.listen(
      (Uri uri) async {
        debugPrint('DeepLink: Incoming link (${uri.scheme})');
        await _handleDeepLink(uri);
      },
      onError: (err) {
        debugPrint('DeepLink: Link stream error: $err');
      },
    );
  }

  /// Handle incoming deep links
  Future<void> _handleDeepLink(Uri uri) async {
    // Never log the full URI: OAuth callbacks carry user ids and secrets.
    debugPrint('DeepLink: Handling ${uri.scheme}://${uri.host}');

    if (uri.scheme == 'quirzy' && uri.host == 'practice') {
      _openPractice();
    } else if (ChallengeCodec.isChallenge(uri)) {
      _openChallenge(uri);
    } else if (uri.scheme == 'quirzy') {
      final action = switch (uri.host) {
        'daily' => AppAction.daily,
        'mocktest' => AppAction.mockTest,
        'mistakes' => AppAction.mistakes,
        _ => null,
      };
      if (action != null) _openAction(action);
    } else if (uri.scheme.startsWith('appwrite-callback')) {
      // Appwrite OAuth callback
      debugPrint('DeepLink: OAuth callback detected');
      await _handleOAuthCallback(uri);
    }
  }

  /// Switches the main screen to the Practice tab. If the user isn't signed
  /// in yet, the router keeps them on sign-in and Practice is still the
  /// first tab they land on afterwards.
  void _openPractice() {
    final ref = _ref;
    if (ref == null) return;
    try {
      ref.read(tabIndexProvider.notifier).state = 0;
    } catch (e) {
      debugPrint('DeepLink: Could not open Practice: $e');
    }
  }

  /// Hands an app-shortcut destination to the app shell, which opens it once
  /// the user is signed in.
  void _openAction(AppAction action) {
    final ref = _ref;
    if (ref == null) return;
    try {
      ref.read(pendingAppActionProvider.notifier).state = action;
    } catch (e) {
      debugPrint('DeepLink: Could not open shortcut: $e');
    }
  }

  /// Hands a challenge link to the app shell, which opens it once the user
  /// is signed in (straight away if they already are).
  void _openChallenge(Uri uri) {
    final ref = _ref;
    if (ref == null) return;
    IncomingChallenge incoming;
    try {
      incoming = IncomingChallenge.ok(ChallengeCodec.decode(uri));
    } on FormatException {
      incoming = const IncomingChallenge.broken();
    }
    try {
      ref.read(pendingChallengeProvider.notifier).state = incoming;
    } catch (e) {
      debugPrint('DeepLink: Could not open challenge: $e');
    }
  }

  /// Handle OAuth callback from Appwrite (legacy - kept for backwards compatibility)
  /// Note: We now use native Google Sign-In, so OAuth callbacks are mostly ignored
  Future<void> _handleOAuthCallback(Uri uri) async {
    debugPrint('DeepLink: OAuth callback received (legacy handler)');
    debugPrint(
      'DeepLink: Note - Using native Google Sign-In, OAuth callbacks are handled differently',
    );

    // If somehow we receive an OAuth callback, try to refresh auth state
    if (_ref != null) {
      try {
        await Future.delayed(const Duration(milliseconds: 500));
        await _ref!.read(authProvider.notifier).refresh();
        debugPrint('DeepLink: Auth state refreshed');
      } catch (e) {
        debugPrint('DeepLink: Refresh failed: $e');
      }
    }
  }

  /// Dispose of subscriptions. [ref] guards against an old app instance
  /// (torn down by an app restart) cancelling the new instance's listener.
  void dispose([WidgetRef? ref]) {
    if (ref != null && !identical(ref, _ref)) return;
    _linkSubscription?.cancel();
    _linkSubscription = null;
    _ref = null;
  }
}

/// Provider for DeepLinkService
final deepLinkServiceProvider = Provider<DeepLinkService>((ref) {
  return DeepLinkService.instance;
});
