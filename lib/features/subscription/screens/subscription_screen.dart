import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:razorpay_flutter/razorpay_flutter.dart';
import '../../../shared/theme/app_palette.dart';
import '../../../shared/widgets/app_widgets.dart';
import '../services/payment_service.dart';

class SubscriptionScreen extends StatefulWidget {
  const SubscriptionScreen({super.key});

  @override
  State<SubscriptionScreen> createState() => _SubscriptionScreenState();
}

class _SubscriptionScreenState extends State<SubscriptionScreen> {
  int _selectedPlan = 1; // 0: Monthly, 1: Yearly
  bool _isProcessing = false;
  late PaymentService _paymentService;

  @override
  void initState() {
    super.initState();
    _paymentService = PaymentService();

    _paymentService.onPaymentSuccess = _onPaymentSuccess;
    _paymentService.onPaymentError = _onPaymentError;
    _paymentService.onExternalWallet = _onExternalWallet;
  }

  void _onPaymentSuccess(PaymentSuccessResponse response) {
    setState(() => _isProcessing = false);
    HapticFeedback.heavyImpact();

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        final p = ctx.palette;
        final t = Theme.of(ctx).textTheme;
        return Dialog(
          insetPadding: const EdgeInsets.all(24),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 80,
                  height: 80,
                  decoration: BoxDecoration(
                    color: p.accent,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(Icons.check_rounded, color: p.onAccent, size: 44),
                ).animate().scale(duration: 250.ms, curve: Curves.easeOut),
                const SizedBox(height: 24),
                Text(
                  '🎉 Welcome to Pro!',
                  textAlign: TextAlign.center,
                  style: t.headlineMedium,
                ),
                const SizedBox(height: 8),
                Text(
                  'You now have unlimited access\nto all premium features!',
                  textAlign: TextAlign.center,
                  style: t.bodyMedium!.copyWith(color: p.textMuted),
                ),
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: p.accentSoft,
                    borderRadius: BorderRadius.circular(AppRadius.chip),
                  ),
                  child: Text(
                    'Payment ID: ${response.paymentId ?? 'N/A'}',
                    style: t.labelSmall!.copyWith(color: p.accentText),
                  ),
                ),
                const SizedBox(height: 24),
                AppButton(
                  label: 'Start Exploring! 🚀',
                  onPressed: () {
                    Navigator.pop(ctx);
                    Navigator.pop(context);
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _onPaymentError(PaymentFailureResponse response) {
    setState(() => _isProcessing = false);
    HapticFeedback.heavyImpact();

    final p = context.palette;
    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(Icons.error_outline_rounded, color: p.danger, size: 20),
            const SizedBox(width: 12),
            Expanded(
              child: Text(response.message ?? 'Payment failed. Please try again.'),
            ),
          ],
        ),
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        duration: const Duration(seconds: 4),
      ),
    );
  }

  void _onExternalWallet(ExternalWalletResponse response) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Processing via ${response.walletName}...'),
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      ),
    );
  }

  void _startPayment() {
    HapticFeedback.mediumImpact();
    setState(() => _isProcessing = true);

    if (_selectedPlan == 0) {
      _paymentService.startMonthlyPlan();
    } else {
      _paymentService.startYearlyPlan();
    }

    // Reset processing after a timeout (in case Razorpay doesn't respond)
    Future.delayed(const Duration(seconds: 30), () {
      if (mounted && _isProcessing) {
        setState(() => _isProcessing = false);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final t = Theme.of(context).textTheme;

    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close_rounded, size: 24),
                    style: IconButton.styleFrom(backgroundColor: p.surfaceHigh),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: p.accent,
                      borderRadius: BorderRadius.circular(AppRadius.pill),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.star_rounded, color: p.onAccent, size: 16),
                        const SizedBox(width: 4),
                        Text(
                          'PRO',
                          style: t.labelMedium!.copyWith(
                            fontWeight: FontWeight.w900,
                            color: p.onAccent,
                            letterSpacing: 1.0,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 32),

              // Title
              Center(
                child: Column(
                  children: [
                    Text(
                      'Unlock Your\nFull Potential 🚀',
                      textAlign: TextAlign.center,
                      style: t.displaySmall,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Get unlimited access to everything.',
                      textAlign: TextAlign.center,
                      style: t.bodyLarge!.copyWith(color: p.textMuted),
                    ),
                  ],
                ),
              ).animate().fadeIn(duration: 200.ms),

              const SizedBox(height: 32),

              // Benefits
              AppCard(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpace.lg,
                  vertical: AppSpace.sm,
                ),
                child: Column(
                  children: [
                    _buildBenefitRow(
                      'Unlimited AI Topics',
                      'Add as many practice topics to your feed as you want.',
                    ),
                    _buildBenefitRow(
                      'Unlimited Practice Feed',
                      'No daily cap on questions — keep swiping.',
                    ),
                    _buildBenefitRow(
                      'AI Study Materials',
                      'Instant Summary + Flashcards + Practice Questions for any topic.',
                    ),
                    _buildBenefitRow(
                      'Exam Specific Content',
                      'Access premium JEE, NEET, & MBA question sets.',
                    ),
                    _buildBenefitRow(
                      'No Ads',
                      'Enjoy a completely distraction-free experience.',
                    ),
                    _buildBenefitRow(
                      'Advanced Analytics',
                      'Track your progress with detailed insights.',
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 40),

              // Plan Selection
              Text('Choose your plan', style: t.titleLarge),
              const SizedBox(height: 20),

              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: _buildPlanCard(
                      index: 0,
                      title: 'Monthly',
                      price: '₹299',
                      period: '/mo',
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: _buildPlanCard(
                      index: 1,
                      title: 'Yearly',
                      price: '₹2,999',
                      period: '/yr',
                      isBestValue: true,
                      saveText: 'Save 20%',
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 12),

              // Secure payment info
              Center(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.lock_rounded, size: 14, color: p.textMuted),
                    const SizedBox(width: 6),
                    Text('Secured by Razorpay', style: t.bodySmall),
                  ],
                ),
              ),

              const SizedBox(height: 24),

              // Payment Methods Row
              Center(
                child: Wrap(
                  spacing: 16,
                  runSpacing: 8,
                  alignment: WrapAlignment.center,
                  children: [
                    _buildPaymentMethodChip('UPI', Icons.account_balance_rounded),
                    _buildPaymentMethodChip('Cards', Icons.credit_card_rounded),
                    _buildPaymentMethodChip('Net Banking', Icons.language_rounded),
                    _buildPaymentMethodChip(
                      'Wallet',
                      Icons.account_balance_wallet_rounded,
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 32),

              // CTA Button
              AppButton(
                label: _isProcessing
                    ? 'Processing...'
                    : (_selectedPlan == 0
                          ? 'Start Monthly Plan'
                          : 'Start Yearly Plan'),
                icon: _isProcessing ? null : Icons.bolt_rounded,
                onPressed: _isProcessing ? null : _startPayment,
              ),

              const SizedBox(height: 16),
              Center(child: Text('Cancel anytime. Terms apply.', style: t.bodySmall)),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPaymentMethodChip(String label, IconData icon) {
    final p = context.palette;
    final t = Theme.of(context).textTheme;
    return AppCard(
      radius: AppRadius.pill,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: p.textMuted),
          const SizedBox(width: 6),
          Text(label, style: t.labelMedium!.copyWith(color: p.textMuted)),
        ],
      ),
    );
  }

  Widget _buildBenefitRow(String title, String subtitle) {
    final p = context.palette;
    final t = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.check_circle_rounded, color: p.accentText, size: 22),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: t.titleMedium),
                const SizedBox(height: 2),
                Text(subtitle, style: t.bodySmall),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPlanCard({
    required int index,
    required String title,
    required String price,
    required String period,
    bool isBestValue = false,
    String? saveText,
  }) {
    final p = context.palette;
    final t = Theme.of(context).textTheme;
    final isSelected = _selectedPlan == index;

    return Stack(
      clipBehavior: Clip.none,
      children: [
        AppCard(
          color: isSelected ? p.accentSoft : p.surface,
          borderColor: isSelected ? p.accentText : p.border,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 20),
          onTap: () => setState(() => _selectedPlan = index),
          child: SizedBox(
            width: double.infinity,
            child: Column(
              children: [
                Text(
                  title,
                  style: t.titleSmall!.copyWith(color: p.textMuted),
                ),
                const SizedBox(height: 12),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(price, style: t.headlineMedium),
                      Text(
                        period,
                        style: t.bodyMedium!.copyWith(
                          color: p.textMuted,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                // Always laid out so both plan cards keep the same height.
                Visibility(
                  visible: isSelected,
                  maintainSize: true,
                  maintainAnimation: true,
                  maintainState: true,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.check_circle_rounded,
                          size: 14,
                          color: p.accentText,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          'Selected',
                          style: t.labelSmall!.copyWith(
                            fontWeight: FontWeight.w700,
                            color: p.accentText,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        if (isBestValue)
          Positioned(
            top: -12,
            left: 0,
            right: 0,
            child: Center(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                decoration: BoxDecoration(
                  color: p.accent,
                  borderRadius: BorderRadius.circular(AppRadius.pill),
                ),
                child: Text(
                  saveText ?? 'BEST VALUE',
                  style: t.labelSmall!.copyWith(
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                    color: p.onAccent,
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}
