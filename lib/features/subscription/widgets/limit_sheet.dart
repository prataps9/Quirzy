import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../shared/theme/app_palette.dart';
import '../../../shared/widgets/app_widgets.dart';
import '../screens/subscription_screen.dart';
import '../services/usage_limits.dart';

/// Opens the Pro paywall. Every upsell in the app goes through here.
Future<void> openPaywall(BuildContext context) {
  return Navigator.of(context).push(
    MaterialPageRoute(builder: (_) => const SubscriptionScreen()),
  );
}

/// Tells a free user they've used today's allowance of [kind] and offers
/// Pro. Resolves once the sheet (and the paywall, if opened) is closed.
Future<void> showLimitSheet(BuildContext context, UsageKind kind) {
  HapticFeedback.mediumImpact();
  return showModalBottomSheet<void>(
    context: context,
    builder: (sheetContext) {
      final p = sheetContext.palette;
      final text = Theme.of(sheetContext).textTheme;
      return SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 8, 24, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Icon(Icons.hourglass_bottom_rounded, size: 44, color: p.accentText),
              const SizedBox(height: 14),
              Text(
                "That's today's free ${kind.plural}",
                textAlign: TextAlign.center,
                style: text.titleLarge,
              ),
              const SizedBox(height: 8),
              Text(
                "You've used your ${kind.freeAllowance} for today. They reset at midnight, "
                'or go Pro for unlimited ${kind.plural}.',
                textAlign: TextAlign.center,
                style: text.bodyMedium!.copyWith(color: p.textMuted),
              ),
              const SizedBox(height: 22),
              AppButton(
                label: 'Go Pro',
                icon: Icons.bolt_rounded,
                onPressed: () {
                  Navigator.of(sheetContext).pop();
                  openPaywall(context);
                },
              ),
              const SizedBox(height: 10),
              AppButton.secondary(
                label: 'Maybe later',
                onPressed: () => Navigator.of(sheetContext).pop(),
              ),
            ],
          ),
        ),
      );
    },
  );
}
