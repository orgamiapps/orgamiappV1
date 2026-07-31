import 'package:flutter/material.dart';
import 'package:attendus/Utils/logger.dart';
import 'package:attendus/Utils/toast.dart';

/// Launch-safe premium payment availability service.
///
/// Premium subscriptions unlock digital app functionality, so they must use
/// platform-compliant in-app purchase before App Store or Google Play release.
/// Until that production path is configured, this service blocks the old mock
/// purchase flow so review builds cannot grant paid access without charging.
class PaymentPlaceholderService {
  static final PaymentPlaceholderService _instance =
      PaymentPlaceholderService._internal();
  factory PaymentPlaceholderService() => _instance;
  PaymentPlaceholderService._internal();

  static const String paymentMode = 'unavailable';
  static bool get isPlaceholderMode => false;

  Future<bool> showApplePayPlaceholder({
    required BuildContext context,
    required String productName,
    required double amount,
    required String currency,
  }) async {
    return _showUnavailableNotice(productName: productName);
  }

  Future<bool> showGooglePayPlaceholder({
    required BuildContext context,
    required String productName,
    required double amount,
    required String currency,
  }) async {
    return _showUnavailableNotice(productName: productName);
  }

  Future<bool> processPlaceholderPayment({
    required String productName,
    required double amount,
  }) async {
    Logger.warning('Blocked mock premium payment processing for $productName');
    return false;
  }

  Future<bool> _showUnavailableNotice({required String productName}) async {
    Logger.warning(
      'Premium purchase requested before production IAP is configured: $productName',
    );
    ShowToast().showNormalToast(
      msg: 'Premium subscriptions are not available in this release yet.',
    );
    return false;
  }
}
