import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:showcaseview/showcaseview.dart';

import '../providers/auth_provider.dart';
import '../../shared/providers/providers.dart';
import '../../shared/theme/app_palette.dart';
import '../../shared/utils/user_messages.dart';
import '../../shared/widgets/app_widgets.dart';
import '../../features/profile/screens/privacy_policy_screen.dart';
import '../../features/l10n/app_localizations.dart';

class WelcomeScreen extends ConsumerStatefulWidget {
  const WelcomeScreen({super.key});

  @override
  ConsumerState<WelcomeScreen> createState() => _WelcomeScreenState();
}

class _WelcomeScreenState extends ConsumerState<WelcomeScreen> {
  bool _isPrivacyPolicyAccepted = false;
  bool _isGoogleLoading = false;

  final GlobalKey _checkboxKey = GlobalKey();

  late final TapGestureRecognizer _privacyTap = TapGestureRecognizer()
    ..onTap = () => Navigator.of(context).push(_createRoute(const PrivacyPolicyScreen()));
  late final TapGestureRecognizer _termsTap = TapGestureRecognizer()
    ..onTap = () => Navigator.of(context).push(_createRoute(const TermsScreen()));

  @override
  void dispose() {
    _privacyTap.dispose();
    _termsTap.dispose();
    super.dispose();
  }

  void _showConsentRequiredMessage() {
    HapticFeedback.lightImpact();
    showAppSnack(context, 'Please accept the Privacy Policy and Terms to continue');
  }

  void _triggerShowcase(BuildContext showcaseContext) {
    if (mounted) ShowCaseWidget.of(showcaseContext).startShowCase([_checkboxKey]);
  }

  Future<void> _handleGoogleSignIn(BuildContext showcaseContext) async {
    if (!_isPrivacyPolicyAccepted) {
      _showConsentRequiredMessage();
      _triggerShowcase(showcaseContext);
      return;
    }
    if (_isGoogleLoading) return;

    setState(() => _isGoogleLoading = true);
    HapticFeedback.mediumImpact();

    try {
      await ref.read(authProvider.notifier).googleSignIn();
      if (!mounted) return;
      // The router sends a signed-in user home on its own.
      ref.read(tabIndexProvider.notifier).state = 0;
    } catch (e) {
      if (!mounted) return;
      // Closing the account picker is a choice, not an error.
      if (isCancellation(e)) return;
      showAppSnack(
        context,
        "Couldn't sign in with Google. Check your connection and try again.",
        onRetry: () => _handleGoogleSignIn(showcaseContext),
      );
    } finally {
      if (mounted) setState(() => _isGoogleLoading = false);
    }
  }

  Route _createRoute(Widget page) {
    return PageRouteBuilder(
      transitionDuration: const Duration(milliseconds: 300),
      pageBuilder: (context, animation, secondaryAnimation) => page,
      transitionsBuilder: (context, animation, secondaryAnimation, child) =>
          FadeTransition(opacity: animation, child: child),
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final textTheme = Theme.of(context).textTheme;
    final l10n = AppLocalizations.of(context)!;
    final isAuthLoading = ref.watch(authProvider.select((s) => s.isLoading));
    final isProcessing = isAuthLoading || _isGoogleLoading;

    return ShowCaseWidget(
      builder: (showcaseContext) {
        return Scaffold(
          backgroundColor: p.bg,
          body: SafeArea(
            child: Column(
              children: [
                // Logo + headline
                Expanded(
                  child: Center(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.symmetric(horizontal: 28),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 72,
                            height: 72,
                            decoration: BoxDecoration(
                              color: p.accent,
                              borderRadius: BorderRadius.circular(AppRadius.card),
                            ),
                            child: Icon(
                              Icons.bolt_rounded,
                              color: p.onAccent,
                              size: 38,
                            ),
                          ),
                          const SizedBox(height: 20),
                          Text(
                            'Quirzy',
                            style: textTheme.displayLarge!.copyWith(
                              fontSize: 44,
                              color: p.text,
                            ),
                          ),
                          const SizedBox(height: 10),
                          Text(
                            l10n.welcomeTitle,
                            textAlign: TextAlign.center,
                            style: textTheme.titleMedium!.copyWith(color: p.text),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            l10n.welcomeSubtitle,
                            textAlign: TextAlign.center,
                            style: textTheme.bodyMedium!.copyWith(
                              color: p.textMuted,
                            ),
                          ),
                        ],
                      ),
                    ).animate().fadeIn(duration: 250.ms),
                  ),
                ),

                // Bottom sign-in section
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _buildPrivacyCheckbox(p, textTheme, l10n, showcaseContext),
                      const SizedBox(height: 16),
                      AppButton(
                        label: l10n.continueWithGoogle,
                        loading: isProcessing,
                        onPressed: () => _handleGoogleSignIn(showcaseContext),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'Free to start. Pro for unlimited access.',
                        textAlign: TextAlign.center,
                        style: textTheme.bodySmall,
                      ),
                    ],
                  ),
                ).animate().fadeIn(duration: 250.ms),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildPrivacyCheckbox(
    AppPalette p,
    TextTheme textTheme,
    AppLocalizations l10n,
    BuildContext showcaseContext,
  ) {
    final accepted = _isPrivacyPolicyAccepted;
    final linkStyle = TextStyle(fontWeight: FontWeight.w800, color: p.text);

    return Showcase(
      key: _checkboxKey,
      title: l10n.required,
      description: l10n.acceptPrivacy,
      targetBorderRadius: BorderRadius.circular(AppRadius.control),
      tooltipBackgroundColor: p.surfaceHigh,
      textColor: p.text,
      child: GestureDetector(
        onTap: () {
          HapticFeedback.lightImpact();
          setState(() => _isPrivacyPolicyAccepted = !_isPrivacyPolicyAccepted);
        },
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: accepted ? p.accentSoft : p.surface,
            borderRadius: BorderRadius.circular(AppRadius.control),
            border: Border.all(
              color: accepted ? p.accentText : p.border,
              width: 1.5,
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 22,
                height: 22,
                decoration: BoxDecoration(
                  color: accepted ? p.accent : Colors.transparent,
                  borderRadius: BorderRadius.circular(7),
                  border: Border.all(
                    color: accepted ? p.accent : p.textMuted,
                    width: 2,
                  ),
                ),
                child: accepted
                    ? Icon(Icons.check_rounded, color: p.onAccent, size: 14)
                    : null,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: RichText(
                  text: TextSpan(
                    style: textTheme.bodySmall!.copyWith(
                      fontSize: 12.5,
                      color: p.textMuted,
                    ),
                    children: [
                      TextSpan(text: l10n.iAgreeToThe),
                      TextSpan(
                        text: l10n.privacyPolicy,
                        style: linkStyle,
                        recognizer: _privacyTap,
                      ),
                      TextSpan(text: l10n.and),
                      TextSpan(
                        text: l10n.terms,
                        style: linkStyle,
                        recognizer: _termsTap,
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
