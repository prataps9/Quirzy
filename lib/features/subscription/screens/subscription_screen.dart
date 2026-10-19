import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:razorpay_flutter/razorpay_flutter.dart';
import '../../../shared/theme/app_palette.dart';
import '../../../shared/utils/user_messages.dart';
import '../../../shared/widgets/app_widgets.dart';
import '../services/payment_service.dart';
import '../services/usage_limits.dart';

/// Plan prices in rupees. Keep in step with [PaymentService]'s amounts.
const int _monthlyPrice = 299;
const int _yearlyPrice = 2999;

/// How much the yearly plan saves over twelve monthly ones, in whole percent.
final int _yearlySavingPercent = ((1 - _yearlyPrice / (12 * _monthlyPrice)) * 100).floor();

final _rupees = NumberFormat.decimalPattern('en_IN');
String _price(int rupees) => '₹${_rupees.format(rupees)}';

class SubscriptionScreen extends ConsumerStatefulWidget {
  const SubscriptionScreen({super.key});

  @override
  ConsumerState<SubscriptionScreen> createState() => _SubscriptionScreenState();
}

class _SubscriptionScreenState extends ConsumerState<SubscriptionScreen> {
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

  Future<void> _onPaymentSuccess(PaymentSuccessResponse response) async {
    // PaymentService has already saved Pro; pick it up everywhere.
    await ref.read(usageLimitsProvider.notifier).refresh();
    if (!mounted) return;
    setState(() => _isProcessing = false);
    HapticFeedback.heavyImpact();
    final expiresAt = ref.read(proStatusProvider).expiresAt;

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
                  'Welcome to Pro',
                  textAlign: TextAlign.center,
                  style: t.headlineMedium,
                ),
                const SizedBox(height: 8),
                Text(
                  expiresAt == null
                      ? 'No daily limits on AI generation.'
                      : 'No daily limits on AI generation until ${_date(expiresAt)}.',
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
                  label: 'Done',
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
    if (!mounted) return;
    setState(() => _isProcessing = false);

    // Closing the checkout (Razorpay code 2) is the user's choice, not an
    // error, so it gets no message. Never show Razorpay's raw text.
    final cancelled = response.code == Razorpay.PAYMENT_CANCELLED ||
        (response.message ?? '').toLowerCase().contains('cancel');
    if (cancelled) return;

    HapticFeedback.heavyImpact();
    showAppSnack(
      context,
      "Payment didn't go through. You haven't been charged — try again.",
      onRetry: _startPayment,
    );
  }

  void _onExternalWallet(ExternalWalletResponse response) {
    if (!mounted) return;
    final wallet = response.walletName;
    showAppSnack(
      context,
      wallet == null || wallet.isEmpty
          ? 'Finishing your payment in your wallet app…'
          : 'Finishing your payment in $wallet…',
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

  static String _date(DateTime d) => DateFormat('d MMM yyyy').format(d);

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final t = Theme.of(context).textTheme;
    final pro = ref.watch(proStatusProvider);

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
                            fontWeight: FontWeight.w800,
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
                      'Quirzy Pro',
                      textAlign: TextAlign.center,
                      style: t.displaySmall,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'No daily limits on AI generation.',
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
                      'Unlimited AI topics',
                      'Free: ${UsageKind.topic.freePerDay} a day.',
                    ),
                    _buildBenefitRow(
                      'Unlimited study sets',
                      'Free: ${UsageKind.studySet.freePerDay} a day.',
                    ),
                    _buildBenefitRow(
                      'Unlimited flashcard sets',
                      'Free: ${UsageKind.flashcardSet.freePerDay} a day.',
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 40),

              if (pro.isPro)
                _buildProCard(pro.expiresAt)
              else ...[
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
                        price: _price(_monthlyPrice),
                        period: '/mo',
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: _buildPlanCard(
                        index: 1,
                        title: 'Yearly',
                        price: _price(_yearlyPrice),
                        period: '/yr',
                        isBestValue: true,
                        saveText: 'Save $_yearlySavingPercent%',
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
                      _buildPaymentMethodChip('Net banking', Icons.language_rounded),
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
                            ? 'Pay ${_price(_monthlyPrice)} for 1 month'
                            : 'Pay ${_price(_yearlyPrice)} for 1 year'),
                  icon: _isProcessing ? null : Icons.bolt_rounded,
                  onPressed: _isProcessing ? null : _startPayment,
                ),

                const SizedBox(height: 16),
                Center(child: Text('One-time payment · no auto-renew', style: t.bodySmall)),
              ],
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }

  /// Shown instead of the plans while Pro is active.
  Widget _buildProCard(DateTime? expiresAt) {
    final p = context.palette;
    final t = Theme.of(context).textTheme;
    return AppCard(
      color: p.accentSoft,
      borderColor: p.accentText,
      child: Row(
        children: [
          Icon(Icons.verified_rounded, color: p.accentText, size: 28),
          const SizedBox(width: AppSpace.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  expiresAt == null ? "You're Pro" : "You're Pro until ${_date(expiresAt)}",
                  style: t.titleMedium,
                ),
                const SizedBox(height: 2),
                Text('Pro ends on its own. Nothing renews.', style: t.bodySmall),
              ],
            ),
          ),
        ],
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
