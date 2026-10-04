import 'package:flutter/material.dart';

import '../../shared/theme/app_palette.dart';

class SuccessScreen extends StatefulWidget {
  final VoidCallback onComplete;
  final String message;
  final String? subtitle;

  const SuccessScreen({
    super.key,
    required this.onComplete,
    this.message = 'Account Created!',
    this.subtitle = 'Welcome to Quirzy',
  });

  @override
  State<SuccessScreen> createState() => _SuccessScreenState();
}

class _SuccessScreenState extends State<SuccessScreen>
    with TickerProviderStateMixin {
  late AnimationController _scaleController;
  late AnimationController _checkController;
  late AnimationController _fadeController;

  late Animation<double> _scaleAnimation;
  late Animation<double> _checkAnimation;
  late Animation<double> _fadeAnimation;

  @override
  void initState() {
    super.initState();

    _scaleController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 250),
    );
    _scaleAnimation = CurvedAnimation(
      parent: _scaleController,
      curve: Curves.easeOutCubic,
    );

    _checkController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 200),
    );
    _checkAnimation = CurvedAnimation(
      parent: _checkController,
      curve: Curves.easeOut,
    );

    _fadeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 250),
    );
    _fadeAnimation = CurvedAnimation(
      parent: _fadeController,
      curve: Curves.easeIn,
    );

    _startAnimations();
  }

  void _startAnimations() async {
    await Future.delayed(const Duration(milliseconds: 200));
    if (!mounted) return;
    _scaleController.forward();

    await Future.delayed(const Duration(milliseconds: 400));
    if (!mounted) return;
    _checkController.forward();

    await Future.delayed(const Duration(milliseconds: 200));
    if (!mounted) return;
    _fadeController.forward();

    await Future.delayed(const Duration(milliseconds: 1500));
    if (!mounted) return;
    widget.onComplete();
  }

  @override
  void dispose() {
    _scaleController.dispose();
    _checkController.dispose();
    _fadeController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final textTheme = Theme.of(context).textTheme;
    final size = MediaQuery.of(context).size;

    return Scaffold(
      backgroundColor: p.bg,
      body: SafeArea(
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              ScaleTransition(
                scale: _scaleAnimation,
                child: Container(
                  width: 120,
                  height: 120,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: p.accent,
                  ),
                  child: ScaleTransition(
                    scale: _checkAnimation,
                    child: Icon(
                      Icons.check_rounded,
                      size: 60,
                      color: p.onAccent,
                    ),
                  ),
                ),
              ),
              SizedBox(height: size.height * 0.04),
              FadeTransition(
                opacity: _fadeAnimation,
                child: Column(
                  children: [
                    Text(
                      widget.message,
                      textAlign: TextAlign.center,
                      style: textTheme.headlineLarge!.copyWith(color: p.text),
                    ),
                    if (widget.subtitle != null) ...[
                      SizedBox(height: size.height * 0.01),
                      Text(
                        widget.subtitle!,
                        textAlign: TextAlign.center,
                        style: textTheme.bodyLarge!.copyWith(
                          color: p.textMuted,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              SizedBox(height: size.height * 0.02),
              FadeTransition(
                opacity: _fadeAnimation,
                child: SizedBox(
                  width: 30,
                  height: 30,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.5,
                    color: p.accentText,
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
