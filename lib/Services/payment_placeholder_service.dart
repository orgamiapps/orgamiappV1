import 'package:flutter/material.dart';
import 'package:attendus/Utils/logger.dart';
import 'package:attendus/Utils/toast.dart';

/// Payment Placeholder Service
///
/// This service provides a placeholder payment UI for development and App Store review.
///
/// IMPORTANT: This is a PLACEHOLDER for future real payment implementation.
/// - Shows Apple Pay / Google Pay UI elements
/// - Simulates payment flow without actual charges
/// - Compliant with App Store guidelines (no actual payment for app features)
///
/// TO IMPLEMENT REAL PAYMENTS:
/// 1. For App Features: Use Apple In-App Purchase (StoreKit 2)
/// 2. For Event Tickets: Use Stripe (already configured, set paymentMode = 'production')
///
/// See PAYMENT_IMPLEMENTATION_GUIDE.md for details.
class PaymentPlaceholderService {
  static final PaymentPlaceholderService _instance =
      PaymentPlaceholderService._internal();
  factory PaymentPlaceholderService() => _instance;
  PaymentPlaceholderService._internal();

  /// Payment mode: 'placeholder' or 'production'
  ///
  /// - 'placeholder': Shows payment UI but grants access without charging
  /// - 'production': Actually processes payments (requires full implementation)
  static const String paymentMode = 'placeholder';

  static bool get isPlaceholderMode => paymentMode == 'placeholder';

  /// Show Apple Pay placeholder sheet
  ///
  /// This displays a mock Apple Pay UI that simulates the payment flow
  /// without actually charging the user.
  Future<bool> showApplePayPlaceholder({
    required BuildContext context,
    required String productName,
    required double amount,
    required String currency,
  }) async {
    Logger.debug('🍎 [PLACEHOLDER] Showing Apple Pay UI for $productName');

    return await showModalBottomSheet<bool>(
          context: context,
          backgroundColor: Colors.transparent,
          isScrollControlled: true,
          builder: (context) => _ApplePayPlaceholderSheet(
            productName: productName,
            amount: amount,
            currency: currency,
          ),
        ) ??
        false;
  }

  /// Show Google Pay placeholder sheet
  ///
  /// This displays a mock Google Pay UI that simulates the payment flow
  /// without actually charging the user.
  Future<bool> showGooglePayPlaceholder({
    required BuildContext context,
    required String productName,
    required double amount,
    required String currency,
  }) async {
    Logger.debug('📱 [PLACEHOLDER] Showing Google Pay UI for $productName');

    return await showModalBottomSheet<bool>(
          context: context,
          backgroundColor: Colors.transparent,
          isScrollControlled: true,
          builder: (context) => _GooglePayPlaceholderSheet(
            productName: productName,
            amount: amount,
            currency: currency,
          ),
        ) ??
        false;
  }

  /// Simulate successful payment
  ///
  /// In placeholder mode, this grants access without charging.
  /// In production mode, this would verify actual payment completion.
  Future<bool> processPlaceholderPayment({
    required String productName,
    required double amount,
  }) async {
    Logger.debug('💳 [PLACEHOLDER] Processing payment for $productName');

    // Simulate payment processing delay
    await Future.delayed(const Duration(seconds: 2));

    Logger.success(
      '✅ [PLACEHOLDER] Payment successful - Access granted without charge',
    );
    return true;
  }
}

/// Apple Pay Placeholder UI
class _ApplePayPlaceholderSheet extends StatefulWidget {
  final String productName;
  final double amount;
  final String currency;

  const _ApplePayPlaceholderSheet({
    required this.productName,
    required this.amount,
    required this.currency,
  });

  @override
  State<_ApplePayPlaceholderSheet> createState() =>
      _ApplePayPlaceholderSheetState();
}

class _ApplePayPlaceholderSheetState extends State<_ApplePayPlaceholderSheet> {
  bool _isProcessing = false;

  Future<void> _handlePayment() async {
    setState(() => _isProcessing = true);

    final success = await PaymentPlaceholderService().processPlaceholderPayment(
      productName: widget.productName,
      amount: widget.amount,
    );

    if (!mounted) return;

    if (success) {
      ShowToast().showNormalToast(
        msg: '✅ [Demo Mode] Payment successful - Access granted!',
      );
      Navigator.of(context).pop(true);
    } else {
      setState(() => _isProcessing = false);
      ShowToast().showNormalToast(msg: 'Payment failed. Please try again.');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Handle bar
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey[300],
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 24),

              // Apple Pay branding
              Container(
                width: 60,
                height: 60,
                decoration: BoxDecoration(
                  color: Colors.black,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.apple, color: Colors.white, size: 40),
              ),
              const SizedBox(height: 16),

              const Text(
                'Apple Pay',
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),

              // Demo mode badge
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: Colors.amber[100],
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.amber[300]!),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.info_outline,
                      size: 16,
                      color: Colors.amber[900],
                    ),
                    const SizedBox(width: 4),
                    Text(
                      'Demo Mode - No actual charge',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.amber[900],
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),

              // Purchase details
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.grey[100],
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: Text(
                            widget.productName,
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        Text(
                          '${widget.currency.toUpperCase()} ${widget.amount.toStringAsFixed(2)}',
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                    const Divider(height: 24),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'Total',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Text(
                          '${widget.currency.toUpperCase()} ${widget.amount.toStringAsFixed(2)}',
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),

              // Payment button
              SizedBox(
                width: double.infinity,
                height: 56,
                child: ElevatedButton(
                  onPressed: _isProcessing ? null : _handlePayment,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.black,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: _isProcessing
                      ? const SizedBox(
                          width: 24,
                          height: 24,
                          child: CircularProgressIndicator(
                            color: Colors.white,
                            strokeWidth: 2,
                          ),
                        )
                      : Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(Icons.apple, size: 24),
                            const SizedBox(width: 8),
                            Text(
                              'Pay with Apple Pay',
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                ),
              ),
              const SizedBox(height: 12),

              // Cancel button
              TextButton(
                onPressed: _isProcessing
                    ? null
                    : () => Navigator.of(context).pop(false),
                child: const Text('Cancel'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Google Pay Placeholder UI
class _GooglePayPlaceholderSheet extends StatefulWidget {
  final String productName;
  final double amount;
  final String currency;

  const _GooglePayPlaceholderSheet({
    required this.productName,
    required this.amount,
    required this.currency,
  });

  @override
  State<_GooglePayPlaceholderSheet> createState() =>
      _GooglePayPlaceholderSheetState();
}

class _GooglePayPlaceholderSheetState
    extends State<_GooglePayPlaceholderSheet> {
  bool _isProcessing = false;

  Future<void> _handlePayment() async {
    setState(() => _isProcessing = true);

    final success = await PaymentPlaceholderService().processPlaceholderPayment(
      productName: widget.productName,
      amount: widget.amount,
    );

    if (!mounted) return;

    if (success) {
      ShowToast().showNormalToast(
        msg: '✅ [Demo Mode] Payment successful - Access granted!',
      );
      Navigator.of(context).pop(true);
    } else {
      setState(() => _isProcessing = false);
      ShowToast().showNormalToast(msg: 'Payment failed. Please try again.');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Handle bar
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey[300],
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 24),

              // Google Pay logo
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.grey[300]!),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 24,
                      height: 24,
                      decoration: BoxDecoration(
                        color: Colors.blue,
                        shape: BoxShape.circle,
                      ),
                      child: const Center(
                        child: Text(
                          'G',
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    const Text(
                      'Google Pay',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),

              // Demo mode badge
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: Colors.amber[100],
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.amber[300]!),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.info_outline,
                      size: 16,
                      color: Colors.amber[900],
                    ),
                    const SizedBox(width: 4),
                    Text(
                      'Demo Mode - No actual charge',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.amber[900],
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),

              // Purchase details
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.grey[100],
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: Text(
                            widget.productName,
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        Text(
                          '${widget.currency.toUpperCase()} ${widget.amount.toStringAsFixed(2)}',
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                    const Divider(height: 24),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'Total',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Text(
                          '${widget.currency.toUpperCase()} ${widget.amount.toStringAsFixed(2)}',
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),

              // Payment button
              SizedBox(
                width: double.infinity,
                height: 56,
                child: ElevatedButton(
                  onPressed: _isProcessing ? null : _handlePayment,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF4285F4),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: _isProcessing
                      ? const SizedBox(
                          width: 24,
                          height: 24,
                          child: CircularProgressIndicator(
                            color: Colors.white,
                            strokeWidth: 2,
                          ),
                        )
                      : const Text(
                          'Pay with Google Pay',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                ),
              ),
              const SizedBox(height: 12),

              // Cancel button
              TextButton(
                onPressed: _isProcessing
                    ? null
                    : () => Navigator.of(context).pop(false),
                child: const Text('Cancel'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
