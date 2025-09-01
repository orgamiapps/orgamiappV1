import 'package:flutter/material.dart';
import 'package:flutter_stripe/flutter_stripe.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import 'package:attendus/models/ticket_payment_model.dart';
import 'package:attendus/models/ticket_model.dart';
import 'package:attendus/models/event_model.dart';
import 'package:attendus/Utils/logger.dart';

class TicketPaymentService {
  static final FirebaseFunctions _functions = FirebaseFunctions.instance;
  static final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  /// Create a payment intent for purchasing a ticket
  static Future<Map<String, dynamic>> createTicketPaymentIntent({
    required String eventId,
    required String ticketId,
    required double amount,
    required String customerUid,
    required String customerName,
    required String customerEmail,
    required String creatorUid,
    required String eventTitle,
  }) async {
    try {
      Logger.debug('Creating ticket payment intent for event: $eventId');

      final amountInCents = (amount * 100)
          .round(); // Convert to cents for Stripe

      final callable = _functions.httpsCallable('createTicketPaymentIntent');
      final result = await callable.call({
        'eventId': eventId,
        'ticketId': ticketId,
        'amount': amountInCents,
        'currency': 'usd',
        'customerUid': customerUid,
        'customerName': customerName,
        'customerEmail': customerEmail,
        'creatorUid': creatorUid,
        'eventTitle': eventTitle,
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
    try {
      Logger.debug('Initializing payment sheet for ticket');

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
    try {
      Logger.debug('Confirming ticket payment for ticket: $ticketId');

      final callable = _functions.httpsCallable('confirmTicketPayment');
      await callable.call({
        'paymentIntentId': paymentIntentId,
        'ticketId': ticketId,
        'eventId': eventId,
      });

      Logger.success('Ticket payment confirmed');
    } catch (e) {
      Logger.error('Failed to confirm ticket payment: $e', e);
      throw Exception('Failed to confirm payment: ${e.toString()}');
    }
  }

  /// Issue a paid ticket after successful payment
  static Future<TicketModel?> issuePaidTicket({
    required String eventId,
    required String customerUid,
    required String customerName,
    required EventModel eventModel,
    required String paymentIntentId,
  }) async {
    try {
      Logger.debug('Issuing paid ticket for event: $eventId');

      // Create ticket document
      final ticketId = _firestore.collection(TicketModel.firebaseKey).doc().id;
      final ticketCode = TicketModel.generateTicketCode();

      final ticket = TicketModel(
        id: ticketId,
        eventId: eventId,
        eventTitle: eventModel.title,
        eventImageUrl: eventModel.imageUrl,
        eventLocation: eventModel.location,
        eventDateTime: eventModel.selectedDateTime,
        customerUid: customerUid,
        customerName: customerName,
        ticketCode: ticketCode,
        issuedDateTime: DateTime.now(),
        price: eventModel.ticketPrice,
        isPaid: true,
        paymentIntentId: paymentIntentId,
        paidAt: DateTime.now(),
      );

      // Save ticket
      await _firestore
          .collection(TicketModel.firebaseKey)
          .doc(ticketId)
          .set(ticket.toJson());

      // Update event ticket count
      await _firestore.collection(EventModel.firebaseKey).doc(eventId).update({
        'issuedTickets': FieldValue.increment(1),
      });

      Logger.success('Paid ticket issued successfully');
      return ticket;
    } catch (e) {
      Logger.error('Failed to issue paid ticket: $e', e);
      return null;
    }
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
    try {
      Logger.debug('Confirming ticket upgrade for ticket: $ticketId');

      // Update ticket in Firestore
      await _firestore
          .collection(TicketModel.firebaseKey)
          .doc(ticketId)
          .update({
            'isSkipTheLine': true,
            'upgradedAt': DateTime.now(),
            'upgradePaymentIntentId': paymentIntentId,
          });

      Logger.success('Ticket upgraded to skip-the-line successfully');
    } catch (e) {
      Logger.error('Failed to confirm ticket upgrade: $e', e);
      throw Exception('Failed to confirm upgrade: ${e.toString()}');
    }
  }
}
