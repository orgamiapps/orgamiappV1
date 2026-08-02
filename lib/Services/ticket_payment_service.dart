import 'package:flutter/material.dart';
import 'package:flutter_stripe/flutter_stripe.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import 'package:attendus/models/ticket_payment_model.dart';
import 'package:attendus/models/ticket_model.dart';
import 'package:attendus/models/event_model.dart';
import 'package:attendus/Utils/logger.dart';
import 'package:attendus/config/safety_flags.dart';

class TicketPaymentService {
  static final FirebaseFunctions _functions = FirebaseFunctions.instance;
  static final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  /// Create a payment intent for purchasing a ticket
  static Future<Map<String, dynamic>> createTicketPaymentIntent({
    required String eventId,
    String ticketTypeId = 'general',
  }) async {
    if (!SafetyFlags.paidCheckoutEnabled) {
      throw StateError(SafetyFlags.paymentMaintenanceMessage);
    }
    try {
      Logger.debug('Creating ticket payment intent for event: $eventId');

      final callable = _functions.httpsCallable('createTicketPaymentIntent');
      final result = await callable.call({
        'eventId': eventId,
        'ticketTypeId': ticketTypeId,
      });

      Logger.debug('Ticket payment intent created successfully');
      return {
        'clientSecret': result.data['clientSecret'],
        'paymentIntentId': result.data['paymentIntentId'],
      };
    } catch (e) {
      Logger.error('Failed to create ticket payment intent: $e', e);
      throw Exception('Failed to create payment: ${e.toString()}');
    }
  }

  /// Process ticket payment using Stripe payment sheet
  static Future<bool> processTicketPayment({
    required String clientSecret,
    required String eventTitle,
  }) async {
    if (!SafetyFlags.paidCheckoutEnabled) return false;
    try {
      Logger.debug('Initializing payment sheet for ticket');

      // Initialize payment sheet
      await Stripe.instance.initPaymentSheet(
        paymentSheetParameters: SetupPaymentSheetParameters(
          paymentIntentClientSecret: clientSecret,
          merchantDisplayName: 'Attendus',
          style: ThemeMode.system,
          googlePay: const PaymentSheetGooglePay(
            merchantCountryCode: 'US',
            testEnv: false,
          ),
          applePay: const PaymentSheetApplePay(merchantCountryCode: 'US'),
          customFlow: false,
          returnURL: 'attendus://callback',
          allowsDelayedPaymentMethods: false,
        ),
      );

      Logger.debug('Presenting payment sheet');
      // Present payment sheet
      await Stripe.instance.presentPaymentSheet();

      Logger.success('Ticket payment successful');
      // If we reach here, payment was successful
      return true;
    } on StripeException catch (e) {
      Logger.error('Stripe error: ${e.error.localizedMessage}', e);
      if (e.error.code == FailureCode.Canceled) {
        Logger.debug('Payment cancelled by user');
      }
      return false;
    } catch (e) {
      Logger.error('Ticket payment error: $e', e);
      return false;
    }
  }

  /// Confirm the ticket payment after successful Stripe payment
  static Future<void> confirmTicketPayment({
    required String paymentIntentId,
    required String ticketId,
    required String eventId,
  }) async {
    throw UnsupportedError(
      'Client payment confirmation is disabled. Payment status is webhook-owned.',
    );
  }

  /// Issue a paid ticket after successful payment
  static Future<TicketModel?> issuePaidTicket({
    required String eventId,
    required String customerUid,
    required String customerName,
    required EventModel eventModel,
    required String paymentIntentId,
  }) async {
    Logger.warning(
      'Blocked client-side paid ticket issuance for payment $paymentIntentId',
    );
    return null;
  }

  /// Get payment history for tickets purchased by a user
  static Future<List<TicketPaymentModel>> getTicketPaymentHistory(
    String userId,
  ) async {
    try {
      final querySnapshot = await _firestore
          .collection(TicketPaymentModel.firebaseKey)
          .where('customerUid', isEqualTo: userId)
          .where('status', isEqualTo: 'completed')
          .orderBy('createdAt', descending: true)
          .get();

      return querySnapshot.docs
          .map((doc) => TicketPaymentModel.fromJson(doc.data()))
          .toList();
    } catch (e) {
      Logger.error('Failed to fetch ticket payment history: $e', e);
      return [];
    }
  }

  /// Get revenue from ticket sales for an event creator
  static Future<Map<String, dynamic>> getTicketRevenue(
    String creatorUid,
  ) async {
    try {
      final querySnapshot = await _firestore
          .collection(TicketPaymentModel.firebaseKey)
          .where('creatorUid', isEqualTo: creatorUid)
          .where('status', isEqualTo: 'completed')
          .get();

      double totalRevenue = 0;
      int totalTicketsSold = 0;

      for (var doc in querySnapshot.docs) {
        final payment = TicketPaymentModel.fromJson(doc.data());
        totalRevenue += payment.amount;
        totalTicketsSold++;
      }

      return {
        'totalRevenue': totalRevenue,
        'totalTicketsSold': totalTicketsSold,
      };
    } catch (e) {
      Logger.error('Failed to fetch ticket revenue: $e', e);
      return {'totalRevenue': 0.0, 'totalTicketsSold': 0};
    }
  }

  /// Get revenue for a specific event
  static Future<Map<String, dynamic>> getEventTicketRevenue(
    String eventId,
  ) async {
    try {
      final querySnapshot = await _firestore
          .collection(TicketPaymentModel.firebaseKey)
          .where('eventId', isEqualTo: eventId)
          .where('status', isEqualTo: 'completed')
          .get();

      double totalRevenue = 0;
      int totalTicketsSold = 0;

      for (var doc in querySnapshot.docs) {
        final payment = TicketPaymentModel.fromJson(doc.data());
        totalRevenue += payment.amount;
        totalTicketsSold++;
      }

      return {
        'totalRevenue': totalRevenue,
        'totalTicketsSold': totalTicketsSold,
      };
    } catch (e) {
      Logger.error('Failed to fetch event ticket revenue: $e', e);
      return {'totalRevenue': 0.0, 'totalTicketsSold': 0};
    }
  }

  /// Create a payment intent for upgrading a ticket to skip-the-line
  static Future<Map<String, dynamic>> createTicketUpgradePaymentIntent({
    required String ticketId,
    required double originalPrice,
    required double upgradePrice,
    required String customerUid,
    required String customerName,
    required String customerEmail,
    required String eventTitle,
  }) async {
    if (!SafetyFlags.paidCheckoutEnabled) {
      throw StateError(SafetyFlags.paymentMaintenanceMessage);
    }
    try {
      Logger.debug(
        'Creating ticket upgrade payment intent for ticket: $ticketId',
      );

      // Use the upgrade price configured by the event creator
      final upgradeAmount = upgradePrice;
      final amountInCents = (upgradeAmount * 100).round();

      final callable = _functions.httpsCallable(
        'createTicketUpgradePaymentIntent',
      );
      final result = await callable.call({
        'ticketId': ticketId,
        'amount': amountInCents,
        'currency': 'usd',
        'customerUid': customerUid,
        'customerName': customerName,
        'customerEmail': customerEmail,
        'eventTitle': eventTitle,
      });

      Logger.debug('Ticket upgrade payment intent created successfully');
      return {
        'clientSecret': result.data['clientSecret'],
        'paymentIntentId': result.data['paymentIntentId'],
        'upgradeAmount': upgradeAmount,
      };
    } catch (e) {
      Logger.error('Failed to create ticket upgrade payment intent: $e', e);
      throw Exception('Failed to create upgrade payment: ${e.toString()}');
    }
  }

  /// Process ticket upgrade payment
  static Future<bool> processTicketUpgrade({
    required String clientSecret,
    required String eventTitle,
    required double upgradeAmount,
  }) async {
    try {
      Logger.debug('Initializing payment sheet for ticket upgrade');

      // Initialize payment sheet
      await Stripe.instance.initPaymentSheet(
        paymentSheetParameters: SetupPaymentSheetParameters(
          paymentIntentClientSecret: clientSecret,
          merchantDisplayName: 'Attendus',
          style: ThemeMode.system,
          googlePay: const PaymentSheetGooglePay(
            merchantCountryCode: 'US',
            testEnv: false,
          ),
          applePay: const PaymentSheetApplePay(merchantCountryCode: 'US'),
          customFlow: false,
          returnURL: 'attendus://callback',
          allowsDelayedPaymentMethods: false,
        ),
      );

      Logger.debug('Presenting payment sheet for upgrade');
      // Present payment sheet
      await Stripe.instance.presentPaymentSheet();

      Logger.success('Ticket upgrade payment successful');
      return true;
    } on StripeException catch (e) {
      Logger.error('Stripe error: ${e.error.localizedMessage}', e);
      if (e.error.code == FailureCode.Canceled) {
        Logger.debug('Upgrade payment cancelled by user');
      }
      return false;
    } catch (e) {
      Logger.error('Ticket upgrade payment error: $e', e);
      return false;
    }
  }

  /// Confirm ticket upgrade after successful payment
  static Future<void> confirmTicketUpgrade({
    required String ticketId,
    required String paymentIntentId,
  }) async {
    throw UnsupportedError(
      'Client ticket upgrades are disabled. Upgrade status is webhook-owned.',
    );
  }
}
