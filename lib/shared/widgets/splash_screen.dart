import 'package:flutter/material.dart';

import '../theme/app_palette.dart';

/// Simple splash screen matching the native splash.
class SplashScreen extends StatelessWidget {
  const SplashScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final textTheme = Theme.of(context).textTheme;

    return Scaffold(
      backgroundColor: p.bg,
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Image.asset(
              'assets/icon/quirzy_splash.png',
              width: 120,
              height: 120,
              fit: BoxFit.contain,
              errorBuilder: (context, error, stackTrace) =>
                  Icon(Icons.bolt_rounded, size: 80, color: p.accent),
            ),

            const SizedBox(height: 24),

            // App Name
            Text(
              'Quirzy',
              style: textTheme.displaySmall!.copyWith(color: p.text),
            ),

            const SizedBox(height: 48),

            // Simple loading indicator
            SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(
                strokeWidth: 2.5,
                color: p.accentText,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
