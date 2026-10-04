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
import 'login_screen.dart';
import 'success_screen.dart';

class SignupScreen extends ConsumerStatefulWidget {
  const SignupScreen({super.key});

  @override
  ConsumerState<SignupScreen> createState() => _SignupScreenState();
}

class _SignupScreenState extends ConsumerState<SignupScreen> {
  // Controllers
  final _usernameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();

  // State
  bool _isProcessing = false;
  bool _isPasswordVisible = false;

  @override
  void dispose() {
    _usernameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
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
          message: 'Account Created!',
          subtitle: 'Welcome to Quirzy',
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

  void _showError(String message) {
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

  Future<void> _signUp() async {
    if (_isProcessing) return;

    HapticFeedback.selectionClick();
    FocusScope.of(context).unfocus();

    final username = _usernameController.text.trim();
    final email = _emailController.text.trim();
    final password = _passwordController.text.trim();
    final emailRegex = RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$');

    if (username.isEmpty) return _showError('Please enter a username');
    if (email.isEmpty) return _showError('Please enter your email');
    if (!emailRegex.hasMatch(email)) {
      return _showError('Please enter a valid email address');
    }
    if (password.isEmpty) return _showError('Please enter a password');
    if (password.length < 6) {
      return _showError('Password must be at least 6 characters');
    }

    setState(() => _isProcessing = true);

    try {
      await ref.read(authProvider.notifier).signUp(email, password, username);

      if (!mounted) return;

      if (ref.read(authProvider).value != null) {
        try {
          await ref.read(notificationProvider.notifier).sendTokenAfterLogin();
        } catch (e) {
          debugPrint('⚠️ Could not send FCM token: $e');
        }
        _showSuccessScreen();
      }
    } catch (e) {
      if (mounted) _showError(e.toString());
    } finally {
      if (mounted) {
        setState(() => _isProcessing = false);
      }
    }
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
              const SizedBox(height: 16),

              // ============ HERO TEXT ============
              Text('Create Account', style: heroStyle),
              const SizedBox(height: 4),
              Text(
                '& Start Learning',
                style: heroStyle.copyWith(color: p.accentText),
              ),

              const SizedBox(height: 8),
              Text(
                'Join thousands of learners on Quirzy',
                style: textTheme.bodyLarge!.copyWith(color: p.textMuted),
              ),

              const SizedBox(height: 28),

              // ============ ERROR MESSAGE ============
              const _ErrorBanner(),

              // ============ USERNAME FIELD ============
              _FormField(
                controller: _usernameController,
                label: 'Username',
                hintText: 'Choose a username',
                prefixIcon: Icons.person_outline_rounded,
              ),

              const SizedBox(height: 16),

              // ============ EMAIL FIELD ============
              _FormField(
                controller: _emailController,
                label: 'Email Address',
                hintText: 'name@example.com',
                keyboardType: TextInputType.emailAddress,
                prefixIcon: Icons.mail_outline_rounded,
              ),

              const SizedBox(height: 16),

              // ============ PASSWORD FIELD ============
              _FormField(
                controller: _passwordController,
                label: 'Password',
                hintText: 'Create a password (min. 6 chars)',
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

              const SizedBox(height: 16),

              // ============ PASSWORD STRENGTH INDICATOR ============
              ValueListenableBuilder<TextEditingValue>(
                valueListenable: _passwordController,
                builder: (context, value, _) =>
                    _PasswordStrengthIndicator(password: value.text),
              ),

              const SizedBox(height: 28),

              // ============ CREATE ACCOUNT BUTTON ============
              Consumer(
                builder: (context, ref, _) {
                  // Only watch isLoading for better performance
                  final isLoading =
                      ref.watch(authProvider.select((s) => s.isLoading)) ||
                      _isProcessing;
                  return AppButton(
                    label: 'Create Account',
                    icon: Icons.person_add_rounded,
                    loading: isLoading,
                    onPressed: _signUp,
                  );
                },
              ),

              const SizedBox(height: 24),

              // ============ SIGN IN LINK ============
              Center(
                child: TextButton(
                  onPressed: () {
                    HapticFeedback.selectionClick();
                    Navigator.pushReplacement(
                      context,
                      _createRoute(const LoginScreen()),
                    );
                  },
                  child: Text.rich(
                    TextSpan(
                      style: textTheme.bodyMedium!.copyWith(
                        color: p.textMuted,
                        fontWeight: FontWeight.w600,
                      ),
                      children: [
                        const TextSpan(text: 'Already have an account? '),
                        TextSpan(
                          text: 'Sign In',
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

              // ============ TERMS & CONDITIONS ============
              Center(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Text(
                    'By creating an account, you agree to our Terms of Service and Privacy Policy',
                    textAlign: TextAlign.center,
                    style: textTheme.bodySmall!.copyWith(
                      fontSize: 11,
                      height: 1.5,
                    ),
                  ),
                ),
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

class _PasswordStrengthIndicator extends StatelessWidget {
  final String password;

  const _PasswordStrengthIndicator({required this.password});

  int _getStrength() {
    if (password.isEmpty) return 0;
    int strength = 0;
    if (password.length >= 6) strength++;
    if (password.length >= 8) strength++;
    if (RegExp(r'[A-Z]').hasMatch(password)) strength++;
    if (RegExp(r'[0-9]').hasMatch(password)) strength++;
    if (RegExp(r'[!@#$%^&*(),.?":{}|<>]').hasMatch(password)) strength++;
    return strength;
  }

  String _getStrengthText(int strength) {
    switch (strength) {
      case 0:
        return '';
      case 1:
        return 'Weak';
      case 2:
        return 'Fair';
      case 3:
        return 'Good';
      case 4:
        return 'Strong';
      default:
        return 'Very Strong';
    }
  }

  Color _getStrengthColor(AppPalette p, int strength) {
    switch (strength) {
      case 0:
        return p.textMuted;
      case 1:
        return p.danger;
      case 2:
      case 3:
        return p.streak;
      default:
        return p.success;
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final strength = _getStrength();
    final strengthColor = _getStrengthColor(p, strength);

    return AnimatedOpacity(
      duration: const Duration(milliseconds: 200),
      opacity: password.isEmpty ? 0 : 1,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: List.generate(5, (index) {
              return Expanded(
                child: Container(
                  height: 4,
                  margin: EdgeInsets.only(right: index < 4 ? 4 : 0),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(2),
                    color: index < strength ? strengthColor : p.border,
                  ),
                ),
              );
            }),
          ),
          const SizedBox(height: 6),
          Text(
            _getStrengthText(strength),
            style: Theme.of(context).textTheme.labelSmall!.copyWith(
              color: strengthColor,
            ),
          ),
        ],
      ),
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
