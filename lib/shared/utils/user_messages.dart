import 'dart:async';

import 'package:appwrite/appwrite.dart';
import 'package:flutter/material.dart';

/// An error whose message is already written for the user.
class UserFacingException implements Exception {
  final String message;

  const UserFacingException(this.message);

  @override
  String toString() => message;
}

/// Turns any error into one calm sentence a user can act on. Never shows
/// raw exception text ("Exception: …", stack-ish platform messages).
String friendlyError(Object error) {
  if (error is UserFacingException) return error.message;
  if (error is TimeoutException) {
    return 'That took too long. Check your connection and try again.';
  }
  if (error is AppwriteException) {
    final code = error.code ?? 0;
    if (code == 401) return 'Your session has ended. Please sign in again.';
    if (code == 429) return 'Too many requests right now. Try again in a minute.';
    if (code >= 500) return 'Our servers are having a moment. Try again shortly.';
  }
  if (_looksOffline(error)) {
    return "You seem to be offline. Check your connection and try again.";
  }
  return 'Something went wrong. Please try again.';
}

/// Whether [error] is the user backing out (e.g. closing the Google account
/// picker) — that deserves no error message at all.
bool isCancellation(Object error) {
  final text = error.toString().toLowerCase();
  return text.contains('cancel');
}

bool _looksOffline(Object error) {
  final text = '${error.runtimeType} $error'.toLowerCase();
  return text.contains('socketexception') ||
      text.contains('failed host lookup') ||
      text.contains('network is unreachable') ||
      text.contains('connection refused') ||
      text.contains('connection closed') ||
      text.contains('clientexception');
}

/// Shows one snackbar, replacing any that is showing (so messages never
/// queue up behind each other). Pass [onRetry] to offer a Retry action.
void showAppSnack(
  BuildContext context,
  String message, {
  VoidCallback? onRetry,
  Duration duration = const Duration(seconds: 4),
}) {
  final messenger = ScaffoldMessenger.maybeOf(context);
  if (messenger == null) return;
  messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        content: Text(message),
        duration: duration,
        action: onRetry == null ? null : SnackBarAction(label: 'Retry', onPressed: onRetry),
      ),
    );
}
