import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:go_router/go_router.dart';
import '../../routes/app_routes.dart';
import '../providers/auth_provider.dart';
import '../../shared/providers/providers.dart';
import '../../shared/theme/app_palette.dart';
import '../../shared/widgets/app_widgets.dart';
import 'signup_screen.dart';
import 'success_screen.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  // Controllers
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();

  // State
  bool _isPasswordVisible = false;

  // Email regex
  final RegExp _emailRegex = RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$');

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  void _showError(String message) {
    if (!mounted) return;
    HapticFeedback.heavyImpact();
    final p = context.palette;
    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(Icons.error_outline_rounded, color: p.danger, size: 20),
            const SizedBox(width: 12),
            Expanded(child: Text(message)),
          ],
        ),
        duration: const Duration(seconds: 3),
      ),
    );
  }

  void _navigateHome() {
    if (!mounted) return;
    ref.read(tabIndexProvider.notifier).state = 0;
    context.go(AppRoutes.home);
  }

  void _showSuccessScreen() {
    if (!mounted) return;
    ref.read(tabIndexProvider.notifier).state = 0;
    HapticFeedback.mediumImpact();
    Navigator.pushReplacement(
      context,
      PageRouteBuilder(
        pageBuilder: (context, animation, secondaryAnimation) => SuccessScreen(
          onComplete: _navigateHome,
          message: 'Signed In!',
          subtitle: 'Welcome back to Quirzy',
        ),
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          return FadeTransition(
            opacity: animation,
            child: ScaleTransition(
              scale: Tween<double>(begin: 0.95, end: 1.0).animate(
                CurvedAnimation(parent: animation, curve: Curves.easeOutCubic),
              ),
              child: child,
            ),
          );
        },
        transitionDuration: const Duration(milliseconds: 400),
      ),
    );
  }

  Future<void> _signIn() async {
    HapticFeedback.selectionClick();
    final authNotifier = ref.read(authProvider.notifier);
    final email = _emailController.text.trim();
    final password = _passwordController.text;

    if (email.isEmpty) return _showError('Please enter your email');
    if (!_emailRegex.hasMatch(email)) {
      return _showError('Invalid email format');
    }
    if (password.isEmpty) {
      return _showError('Please enter your password');
    }
    if (password.length < 6) {
      return _showError('Password must be at least 6 characters');
    }

    // Auth is handled by ref.listen in build()
    await authNotifier.login(email, password);
  }

  Future<void> _signInWithGoogle() async {
    HapticFeedback.selectionClick();

    // Show a quick message that browser is opening
    if (mounted) {
      final p = context.palette;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(
                  color: p.accentText,
                  strokeWidth: 2,
                ),
              ),
              const SizedBox(width: 12),
              const Text('Opening Google sign-in...'),
            ],
          ),
          duration: const Duration(seconds: 3),
        ),
      );
    }

    // Auth is handled by ref.listen in build()
    await ref.read(authProvider.notifier).googleSignIn();
  }

  Route _createRoute(Widget page) {
    return PageRouteBuilder(
      transitionDuration: const Duration(milliseconds: 400),
      reverseTransitionDuration: const Duration(milliseconds: 300),
      pageBuilder: (context, animation, secondaryAnimation) => page,
      transitionsBuilder: (context, animation, secondaryAnimation, child) {
        return FadeTransition(
          opacity: CurvedAnimation(parent: animation, curve: Curves.easeOut),
          child: SlideTransition(
            position:
                Tween<Offset>(
                  begin: const Offset(0.03, 0),
                  end: Offset.zero,
                ).animate(
                  CurvedAnimation(
                    parent: animation,
                    curve: Curves.easeOutCubic,
                  ),
                ),
            child: child,
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    // Listen to Auth State Changes
    ref.listen<AsyncValue<dynamic>>(authProvider, (previous, next) {
      next.when(
        data: (user) {
          if (user != null && (previous?.value == null)) {
            try {
              ref.read(notificationProvider.notifier).sendTokenAfterLogin();
            } catch (e) {
              debugPrint('⚠️ Could not send FCM token: $e');
            }
            _showSuccessScreen();
          }
        },
        error: (error, stackTrace) {
          // Only show error if it's new
          if (previous == null ||
              !previous.hasError ||
              previous.error != error) {
            _showError(error.toString().replaceAll('Exception: ', ''));
          }
        },
        loading: () {},
      );
    });

    final p = context.palette;
    final textTheme = Theme.of(context).textTheme;
    final heroStyle = textTheme.displayMedium!.copyWith(
      color: p.text,
      height: 1.1,
      letterSpacing: -1,
    );

    return Scaffold(
      backgroundColor: p.bg,
      appBar: AppBar(
        leading: IconButton(
          onPressed: () {
            HapticFeedback.lightImpact();
            Navigator.pop(context);
          },
          icon: const Icon(Icons.arrow_back_rounded),
        ),
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(color: p.accent, shape: BoxShape.circle),
              child: Icon(Icons.bolt_rounded, color: p.onAccent, size: 18),
            ),
            const SizedBox(width: 10),
            Text('Quirzy', style: textTheme.titleLarge),
          ],
        ),
        centerTitle: true,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          physics: const BouncingScrollPhysics(),
          padding: const EdgeInsets.symmetric(horizontal: 24.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 24),

              // ============ HERO TEXT ============
              Text('Welcome Back', style: heroStyle),
              const SizedBox(height: 4),
              Text('to Quirzy', style: heroStyle.copyWith(color: p.accentText)),

              const SizedBox(height: 8),
              Text(
                'Sign in to continue your learning journey',
                style: textTheme.bodyLarge!.copyWith(color: p.textMuted),
              ),

              const SizedBox(height: 32),

              // ============ EMAIL FIELD ============
              _FormField(
                controller: _emailController,
                label: 'Email Address',
                hintText: 'name@example.com',
                keyboardType: TextInputType.emailAddress,
                prefixIcon: Icons.mail_outline_rounded,
              ),

              const SizedBox(height: 20),

              // ============ PASSWORD FIELD ============
              _FormField(
                controller: _passwordController,
                label: 'Password',
                hintText: 'Enter your password',
                obscureText: !_isPasswordVisible,
                prefixIcon: Icons.lock_outline_rounded,
                suffixIcon: IconButton(
                  onPressed: () =>
                      setState(() => _isPasswordVisible = !_isPasswordVisible),
                  icon: Icon(
                    _isPasswordVisible
                        ? Icons.visibility_rounded
                        : Icons.visibility_off_rounded,
                    color: p.textMuted,
                    size: 20,
                  ),
                ),
              ),

              // ============ FORGOT PASSWORD ============
              Align(
                alignment: Alignment.centerRight,
                child: Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: TextButton(
                    onPressed: () {
                      HapticFeedback.selectionClick();
                    },
                    child: const Text('Forgot Password?'),
                  ),
                ),
              ),

              const SizedBox(height: 16),

              // ============ ERROR DISPLAY ============
              const _ErrorBanner(),

              // ============ SIGN IN BUTTON ============
              Consumer(
                builder: (context, ref, _) {
                  final isLoading = ref.watch(authProvider).isLoading;
                  return AppButton(
                    label: 'Sign In',
                    icon: Icons.login_rounded,
                    loading: isLoading,
                    onPressed: _signIn,
                  );
                },
              ),

              const SizedBox(height: 24),

              // ============ REGISTER LINK ============
              Center(
                child: TextButton(
                  onPressed: () {
                    HapticFeedback.selectionClick();
                    Navigator.pushReplacement(
                      context,
                      _createRoute(const SignupScreen()),
                    );
                  },
                  child: Text.rich(
                    TextSpan(
                      style: textTheme.bodyMedium!.copyWith(
                        color: p.textMuted,
                        fontWeight: FontWeight.w600,
                      ),
                      children: [
                        const TextSpan(text: "Don't have an account? "),
                        TextSpan(
                          text: 'Register',
                          style: TextStyle(
                            color: p.accentText,
                            fontWeight: FontWeight.w800,
                            decoration: TextDecoration.underline,
                            decorationColor: p.accentText,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),

              const SizedBox(height: 24),

              // ============ SOCIAL LOGIN DIVIDER ============
              Row(
                children: [
                  const Expanded(child: Divider()),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Text('or continue with', style: textTheme.bodySmall),
                  ),
                  const Expanded(child: Divider()),
                ],
              ),

              const SizedBox(height: 24),

              // ============ SOCIAL BUTTONS ============
              Row(
                children: [
                  Expanded(
                    child: AppButton.secondary(
                      label: 'Google',
                      icon: Icons.g_mobiledata_rounded,
                      onPressed: _signInWithGoogle,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: AppButton.secondary(
                      label: 'Apple',
                      icon: Icons.apple_rounded,
                      onPressed: () {
                        HapticFeedback.selectionClick();
                      },
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 40),
            ],
          ),
        ).animate().fadeIn(duration: 250.ms),
      ),
    );
  }
}

// ==================== FORM WIDGETS ====================

class _FormField extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final String hintText;
  final TextInputType? keyboardType;
  final bool obscureText;
  final IconData prefixIcon;
  final Widget? suffixIcon;

  const _FormField({
    required this.controller,
    required this.label,
    required this.hintText,
    this.keyboardType,
    this.obscureText = false,
    required this.prefixIcon,
    this.suffixIcon,
  });

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final textTheme = Theme.of(context).textTheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: textTheme.labelLarge!.copyWith(color: p.textMuted)),
        const SizedBox(height: 8),
        TextField(
          controller: controller,
          keyboardType: keyboardType,
          obscureText: obscureText,
          decoration: InputDecoration(
            hintText: hintText,
            prefixIcon: Icon(prefixIcon, size: 20),
            suffixIcon: suffixIcon,
          ),
        ),
      ],
    );
  }
}

class _ErrorBanner extends ConsumerWidget {
  const _ErrorBanner();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Only watch error for better performance
    final error = ref.watch(authProvider.select((s) => s.error?.toString()));
    if (error == null || error.isEmpty) return const SizedBox.shrink();

    final p = context.palette;
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: p.dangerSoft,
          borderRadius: BorderRadius.circular(AppRadius.control),
          border: Border.all(color: p.danger),
        ),
        child: Row(
          children: [
            Icon(Icons.error_outline_rounded, color: p.danger, size: 20),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                error,
                style: Theme.of(
                  context,
                ).textTheme.bodyMedium!.copyWith(color: p.danger),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
