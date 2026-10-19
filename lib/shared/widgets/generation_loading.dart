import 'dart:async';

import 'package:flutter/material.dart';

import '../theme/app_palette.dart';

/// Full-screen "Building your topic…" shown while AI content is generated.
class GenerationLoadingScreen extends StatelessWidget {
  final String title;
  final String subtitle;

  const GenerationLoadingScreen({super.key, required this.title, required this.subtitle});

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final text = Theme.of(context).textTheme;
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const SizedBox(width: 56, height: 56, child: CircularProgressIndicator(strokeWidth: 4)),
              const SizedBox(height: 28),
              Text(title, textAlign: TextAlign.center, style: text.headlineSmall),
              const SizedBox(height: 8),
              Text(subtitle, textAlign: TextAlign.center, style: text.bodyMedium!.copyWith(color: p.textMuted)),
            ],
          ),
        ),
      ),
    );
  }
}

/// Runs [task] behind [GenerationLoadingScreen] and always removes exactly
/// that screen afterwards — never whatever happens to be on top — so back
/// presses or other navigation during generation can't close the wrong
/// page. Back is disabled while it runs, and [timeout] stops it hanging.
/// Returns the task's result or rethrows its error (a [TimeoutException]
/// on timeout).
Future<T> runWithLoadingScreen<T>(
  BuildContext context, {
  required String title,
  required String subtitle,
  required Future<T> Function() task,
  Duration timeout = const Duration(seconds: 90),
}) async {
  final navigator = Navigator.of(context);
  final route = MaterialPageRoute<void>(
    builder: (_) => PopScope(
      canPop: false,
      child: GenerationLoadingScreen(title: title, subtitle: subtitle),
    ),
  );
  unawaited(navigator.push(route));
  try {
    return await task().timeout(timeout);
  } finally {
    if (route.isActive) navigator.removeRoute(route);
  }
}
