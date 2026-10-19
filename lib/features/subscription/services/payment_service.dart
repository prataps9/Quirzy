import 'package:flutter/foundation.dart';
import 'package:razorpay_flutter/razorpay_flutter.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'pro_status.dart';

/// Your Razorpay key id. TODO: replace the placeholder with your live key
/// (`rzp_live_…`) from the Razorpay dashboard before release — checkout
/// cannot open with the placeholder.
const String kRazorpayKeyId = 'rzp_test_XXXXXXXXXXXX';

/// PaymentService - Handles Razorpay payments for Quirzy Pro subscriptions
class PaymentService {
  static PaymentService? _instance;
  late Razorpay _razorpay;
  final FlutterSecureStorage _storage = const FlutterSecureStorage();

  /// The plan being paid for, so the success callback knows what to unlock.
  ProPlan? _pendingPlan;

  // Callbacks
  Function(PaymentSuccessResponse)? onPaymentSuccess;
  Function(PaymentFailureResponse)? onPaymentError;
  Function(ExternalWalletResponse)? onExternalWallet;

  factory PaymentService() {
    _instance ??= PaymentService._internal();
    return _instance!;
  }

  PaymentService._internal() {
    _razorpay = Razorpay();
    _razorpay.on(Razorpay.EVENT_PAYMENT_SUCCESS, _handlePaymentSuccess);
    _razorpay.on(Razorpay.EVENT_PAYMENT_ERROR, _handlePaymentError);
    _razorpay.on(Razorpay.EVENT_EXTERNAL_WALLET, _handleExternalWallet);
  }

  /// Start a payment for a subscription plan
  Future<void> startPayment({
    required ProPlan plan,
    required int amountInPaise, // ₹299 = 29900 paise
    required String description,
    String? email,
    String? phone,
  }) async {
    // Get user details from storage
    _pendingPlan = plan;
    final userName = await _storage.read(key: 'user_name') ?? 'Quirzy User';
    final userEmail = email ?? await _storage.read(key: 'user_email') ?? '';
    final userPhone = phone ?? '';

    var options = {
      'key': kRazorpayKeyId,
      'amount': amountInPaise,
      'name': 'Quirzy Pro',
      'description': description,
      'prefill': {'name': userName, 'email': userEmail, 'contact': userPhone},
      'theme': {'color': '#0A0A0C'},
      'notes': {'plan': plan.name, 'app': 'quirzy'},
      'modal': {'confirm_close': true},
    };

    try {
      _razorpay.open(options);
    } catch (e) {
      debugPrint('Razorpay Error: $e');
    }
  }

  /// Start Monthly Plan Payment (₹299)
  Future<void> startMonthlyPlan({String? email, String? phone}) async {
    await startPayment(
      plan: ProPlan.monthly,
      amountInPaise: 29900, // ₹299
      description: 'Quirzy Pro - Monthly Plan',
      email: email,
      phone: phone,
    );
  }

  /// Start Yearly Plan Payment (₹2,999)
  Future<void> startYearlyPlan({String? email, String? phone}) async {
    await startPayment(
      plan: ProPlan.yearly,
      amountInPaise: 299900, // ₹2,999
      description: 'Quirzy Pro - Yearly Plan',
      email: email,
      phone: phone,
    );
  }

  void _handlePaymentSuccess(PaymentSuccessResponse response) async {
    debugPrint('Payment Success');

    await ProStatusStore().activate(
      _pendingPlan ?? ProPlan.monthly,
      paymentId: response.paymentId,
    );
    _pendingPlan = null;

    onPaymentSuccess?.call(response);
  }

  void _handlePaymentError(PaymentFailureResponse response) {
    debugPrint('Payment Error: ${response.code} - ${response.message}');
    onPaymentError?.call(response);
  }

  void _handleExternalWallet(ExternalWalletResponse response) {
    debugPrint('External Wallet: ${response.walletName}');
    onExternalWallet?.call(response);
  }

  /// Whether the user currently has an unexpired Pro plan.
  static Future<bool> isPro() async => (await ProStatusStore().load()).isPro;

  /// Dispose Razorpay instance
  void dispose() {
    _razorpay.clear();
  }
}
