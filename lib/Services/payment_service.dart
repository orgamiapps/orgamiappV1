import 'package:flutter/material.dart';
import 'package:flutter_stripe/flutter_stripe.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:orgami/models/payment_model.dart';
import 'package:orgami/Utils/logger.dart';

class PaymentService {
  static final FirebaseFunctions _functions = FirebaseFunctions.instance;
  static final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  /// Initialize Stripe with publishable key
  static void initializeStripe(String publishableKey) {
    Stripe.publishableKey = publishableKey;
    Logger.debug('Stripe initialized with publishable key');
  }

  /// Create a payment intent for featuring an event
  static Future<Map<String, dynamic>> createPaymentIntent({
    required String eventId,
    required int durationDays,
    required String customerUid,
  }) async {
    try {
      Logger.debug('Creating payment intent for event: $eventId');

      // Calculate amount based on duration
      final amount = FeaturePaymentModel.getPriceForDays(durationDays);
      final amountInCents = (amount * 100)
          .round(); // Convert to cents for Stripe

      final callable = _functions.httpsCallable('createFeaturePaymentIntent');
      final result = await callable.call({
        'eventId': eventId,
        'durationDays': durationDays,
        'customerUid': customerUid,
        'amount': amountInCents,
        'currency': 'usd',
      });

      Logger.debug('Payment intent created successfully');
      return {
        'clientSecret': result.data['clientSecret'],
        'paymentIntentId': result.data['paymentIntentId'],
      };
    } catch (e) {
      Logger.error('Failed to create payment intent: $e', e);
      throw Exception('Failed to create payment: ${e.toString()}');
    }
  }

  /// Process payment using Stripe payment sheet
  static Future<bool> processPayment({
    required String clientSecret,
    required String eventId,
  }) async {
    try {
      Logger.debug('Initializing payment sheet');

      // Initialize payment sheet
      await Stripe.instance.initPaymentSheet(
        paymentSheetParameters: SetupPaymentSheetParameters(
          paymentIntentClientSecret: clientSecret,
          merchantDisplayName: 'Orgami',
          style: ThemeMode.system,
          googlePay: const PaymentSheetGooglePay(
            merchantCountryCode: 'US',
            testEnv: true, // Set to false for production
          ),
          applePay: const PaymentSheetApplePay(merchantCountryCode: 'US'),
          customFlow: false,
          returnURL: 'orgami://stripe-redirect',
          allowsDelayedPaymentMethods: false,
        ),
      );

      Logger.debug('Presenting payment sheet');
      // Present payment sheet
      await Stripe.instance.presentPaymentSheet();

      Logger.success('Payment successful');
      // If we reach here, payment was successful
      return true;
    } on StripeException catch (e) {
      Logger.error('Stripe error: ${e.error.localizedMessage}', e);
      if (e.error.code == FailureCode.Canceled) {
        Logger.debug('Payment cancelled by user');
      }
      return false;
    } catch (e) {
      Logger.error('Payment error: $e', e);
      return false;
    }
  }

  /// Confirm the feature payment after successful Stripe payment
  static Future<void> confirmFeaturePayment({
    required String paymentIntentId,
    required String eventId,
    required int durationDays,
    required bool untilEvent,
  }) async {
    try {
      Logger.debug('Confirming feature payment for event: $eventId');

      final callable = _functions.httpsCallable('confirmFeaturePayment');
      await callable.call({
        'paymentIntentId': paymentIntentId,
        'eventId': eventId,
        'durationDays': durationDays,
        'untilEvent': untilEvent,
      });

      Logger.success('Feature payment confirmed');
    } catch (e) {
      Logger.error('Failed to confirm feature payment: $e', e);
      throw Exception('Failed to confirm payment: ${e.toString()}');
    }
  }

  /// Get payment history for a user
  static Future<List<FeaturePaymentModel>> getPaymentHistory(
    String userId,
  ) async {
    try {
      final querySnapshot = await _firestore
          .collection(FeaturePaymentModel.firebaseKey)
          .where('customerUid', isEqualTo: userId)
          .orderBy('createdAt', descending: true)
          .get();

      return querySnapshot.docs
          .map((doc) => FeaturePaymentModel.fromJson(doc.data()))
          .toList();
    } catch (e) {
      Logger.error('Failed to fetch payment history: $e', e);
      return [];
    }
  }

  /// Check if an event has an active feature payment
  static Future<bool> hasActiveFeaturePayment(String eventId) async {
    try {
      final querySnapshot = await _firestore
          .collection(FeaturePaymentModel.firebaseKey)
          .where('eventId', isEqualTo: eventId)
          .where('status', isEqualTo: 'completed')
          .orderBy('createdAt', descending: true)
          .limit(1)
          .get();

      if (querySnapshot.docs.isEmpty) {
        return false;
      }

      // Check if the feature period is still active
      final payment = FeaturePaymentModel.fromJson(
        querySnapshot.docs.first.data(),
      );
      if (payment.completedAt != null) {
        final endDate = payment.completedAt!.add(
          Duration(days: payment.durationDays),
        );
        return endDate.isAfter(DateTime.now());
      }

      return false;
    } catch (e) {
      Logger.error('Failed to check feature payment status: $e', e);
      return false;
    }
  }
}
