import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:attendus/Utils/logger.dart';
import 'package:intl/intl.dart';
import 'package:attendus/models/subscription_model.dart';
import 'package:attendus/Services/stripe_service.dart';

/// Service for managing user premium subscriptions
class SubscriptionService extends ChangeNotifier {
  static final SubscriptionService _instance = SubscriptionService._internal();
  factory SubscriptionService() => _instance;
  SubscriptionService._internal();

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final StripeService _stripeService = StripeService();

  SubscriptionModel? _currentSubscription;
  bool _isLoading = false;

  SubscriptionModel? get currentSubscription => _currentSubscription;
  bool get isLoading => _isLoading;
  bool get hasPremium => _currentSubscription?.isActive ?? false;

  /// Initialize subscription service and load user's subscription
  Future<void> initialize() async {
    if (_auth.currentUser == null) return;

    try {
      // Only notify if state actually changes
      if (!_isLoading) {
        _isLoading = true;
        notifyListeners();
      }

      await _loadUserSubscription();

      // Automatically migrate old $20 prices to $5
      if (_currentSubscription?.priceAmount == 2000) {
        Logger.info('Migrating subscription price from \$20 to \$5');
        await updateSubscriptionPrice();
      }
    } catch (e) {
      Logger.error('Failed to initialize subscription service', e);
    } finally {
      if (_isLoading) {
        _isLoading = false;
        notifyListeners();
      }
    }
  }

  /// Load user's current subscription from Firestore
  Future<void> _loadUserSubscription() async {
    final userId = _auth.currentUser?.uid;
    if (userId == null) {
      _currentSubscription = null;
      notifyListeners();
      return;
    }

    try {
      final doc = await _firestore
          .collection('subscriptions')
          .doc(userId)
          .get();

      final oldSubscription = _currentSubscription;
      
      if (doc.exists) {
        _currentSubscription = SubscriptionModel.fromFirestore(doc);
        Logger.info(
          'Loaded subscription: ${_currentSubscription?.status} (isActive: ${_currentSubscription?.isActive})',
        );
      } else {
        _currentSubscription = null;
        Logger.info('No subscription found for user');
      }
      
      // Notify listeners if subscription state changed
      if (oldSubscription?.isActive != _currentSubscription?.isActive) {
        notifyListeners();
      }
    } catch (e) {
      Logger.error('Error loading user subscription', e);
      _currentSubscription = null;
      notifyListeners();
    }
  }

  /// Create a new premium subscription
  Future<bool> createPremiumSubscription({
    String? planId,
    bool withTrial = false,
  }) async {
    final userId = _auth.currentUser?.uid;
    if (userId == null) return false;

    try {
      if (!_isLoading) {
        _isLoading = true;
        notifyListeners();
      }

      // Determine subscription parameters based on plan
      final selectedPlanId = planId ?? 'premium_monthly';
      int billingDays;
      int priceAmount;
      String interval;

      switch (selectedPlanId) {
        case 'premium_6month':
          billingDays = 180;
          priceAmount = 10000; // $100.00 in cents
          interval = '6months';
          break;
        case 'premium_yearly':
          billingDays = 365;
          priceAmount = 17500; // $175.00 in cents
          interval = 'year';
          break;
        default:
          billingDays = 30;
          priceAmount = 2000; // $20.00 in cents
          interval = 'month';
      }

      final subscription = SubscriptionModel(
        id: userId,
        userId: userId,
        planId: selectedPlanId,
        status: 'active',
        priceAmount: priceAmount,
        currency: 'USD',
        interval: interval,
        currentPeriodStart: DateTime.now(),
        currentPeriodEnd: DateTime.now().add(Duration(days: billingDays)),
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
        isTrial: withTrial,
        trialEndsAt: withTrial
            ? DateTime.now().add(const Duration(days: 30))
            : null,
      );

      await _firestore
          .collection('subscriptions')
          .doc(userId)
          .set(subscription.toMap());

      _currentSubscription = subscription;
      Logger.success('Premium subscription created successfully');

      if (_isLoading) {
        _isLoading = false;
      }
      notifyListeners();
      return true;
    } catch (e) {
      Logger.error('Error creating premium subscription', e);
      if (_isLoading) {
        _isLoading = false;
        notifyListeners();
      }
      return false;
    }
  }

  /// Cancel current subscription
  Future<bool> cancelSubscription() async {
    final userId = _auth.currentUser?.uid;
    if (userId == null || _currentSubscription == null) return false;

    try {
      if (!_isLoading) {
        _isLoading = true;
        notifyListeners();
      }

      // Update subscription status to cancelled
      final updatedSubscription = _currentSubscription!.copyWith(
        status: 'cancelled',
        cancelledAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

      await _firestore
          .collection('subscriptions')
          .doc(userId)
          .update(updatedSubscription.toMap());

      _currentSubscription = updatedSubscription;
      Logger.info('Subscription cancelled successfully');

      if (_isLoading) {
        _isLoading = false;
      }
      notifyListeners();
      return true;
    } catch (e) {
      Logger.error('Error cancelling subscription', e);
      if (_isLoading) {
        _isLoading = false;
        notifyListeners();
      }
      return false;
    }
  }

  /// Reactivate a cancelled subscription
  Future<bool> reactivateSubscription() async {
    final userId = _auth.currentUser?.uid;
    if (userId == null || _currentSubscription == null) return false;

    try {
      if (!_isLoading) {
        _isLoading = true;
        notifyListeners();
      }

      // Update subscription status to active
      final updatedSubscription = _currentSubscription!.copyWith(
        status: 'active',
        cancelledAt: null,
        updatedAt: DateTime.now(),
        // Extend the period
        currentPeriodEnd: DateTime.now().add(const Duration(days: 30)),
      );

      await _firestore
          .collection('subscriptions')
          .doc(userId)
          .update(updatedSubscription.toMap());

      _currentSubscription = updatedSubscription;
      Logger.success('Subscription reactivated successfully');

      if (_isLoading) {
        _isLoading = false;
      }
      notifyListeners();
      return true;
    } catch (e) {
      Logger.error('Error reactivating subscription', e);
      if (_isLoading) {
        _isLoading = false;
        notifyListeners();
      }
      return false;
    }
  }

  /// Check if user can create events (has premium subscription)
  bool canCreateEvents() {
    return hasPremium;
  }

  /// Get subscription status text for UI
  String getSubscriptionStatusText() {
    if (_currentSubscription == null) {
      return 'No active subscription';
    }

    switch (_currentSubscription!.status) {
      case 'active':
        if (_currentSubscription!.isTrial) {
          return 'Premium (Trial)';
        }
        return 'Premium Active';
      case 'cancelled':
        return 'Premium (Cancelled)';
      case 'past_due':
        return 'Premium (Payment Due)';
      case 'incomplete':
        return 'Premium (Incomplete)';
      default:
        return 'Premium';
    }
  }

  /// Get next billing date
  String? getNextBillingDate() {
    if (_currentSubscription?.isActive != true) return null;

    final date = _currentSubscription!.currentPeriodEnd;
    return DateFormat('MM/dd/yyyy').format(date);
  }

  /// Refresh subscription data
  Future<void> refresh() async {
    try {
      final oldHasPremium = hasPremium;
      await _loadUserSubscription();
      
      // Force notify listeners if premium status changed
      if (oldHasPremium != hasPremium) {
        Logger.info(
          'Subscription status changed from $oldHasPremium to $hasPremium',
        );
        notifyListeners();
      }
    } catch (e) {
      Logger.error('Error refreshing subscription', e);
    }
  }

  /// Clear subscription data (for logout)
  void clear() {
    _currentSubscription = null;
    _isLoading = false;
    notifyListeners();
  }

  /// Prepare Stripe payment for subscription
  /// This method sets up the structure for future Stripe integration
  Future<Map<String, dynamic>?> prepareStripePayment({
    required String planId,
    required String priceId,
  }) async {
    try {
      final userId = _auth.currentUser?.uid;
      final userEmail = _auth.currentUser?.email;

      if (userId == null || userEmail == null) {
        Logger.error('User not authenticated');
        return null;
      }

      // Initialize Stripe if not already done
      if (!_stripeService.isInitialized) {
        await _stripeService.initialize();
      }

      // Create or get Stripe customer
      final customer = await _stripeService.createCustomer(
        email: userEmail,
        name: _auth.currentUser?.displayName,
        metadata: {'firebase_uid': userId},
      );

      if (customer == null) {
        Logger.error('Failed to create Stripe customer');
        return null;
      }

      // Create subscription
      final subscription = await _stripeService.createSubscription(
        customerId: customer['id'],
        priceId: priceId,
        metadata: {'firebase_uid': userId, 'plan_id': planId},
      );

      if (subscription == null) {
        Logger.error('Failed to create Stripe subscription');
        return null;
      }

      return {
        'client_secret':
            subscription['latest_invoice']['payment_intent']['client_secret'],
        'subscription_id': subscription['id'],
        'customer_id': customer['id'],
      };
    } catch (e) {
      Logger.error('Error preparing Stripe payment', e);
      return null;
    }
  }

  /// Handle successful payment (to be called after Stripe payment)
  Future<bool> handleSuccessfulPayment({
    required String subscriptionId,
    required String customerId,
    required String priceId,
  }) async {
    try {
      final userId = _auth.currentUser?.uid;
      if (userId == null) return false;

      // Create subscription record in Firestore
      final subscription = SubscriptionModel(
        id: userId,
        userId: userId,
        planId: 'premium_monthly',
        status: 'active',
        priceAmount: 500, // $5.00 in cents
        currency: 'USD',
        interval: 'month',
        currentPeriodStart: DateTime.now(),
        currentPeriodEnd: DateTime.now().add(const Duration(days: 30)),
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
        stripeSubscriptionId: subscriptionId,
        stripeCustomerId: customerId,
      );

      await _firestore
          .collection('subscriptions')
          .doc(userId)
          .set(subscription.toMap());

      _currentSubscription = subscription;
      Logger.success('Subscription created successfully');

      notifyListeners();
      return true;
    } catch (e) {
      Logger.error('Error handling successful payment', e);
      return false;
    }
  }

  /// Process real Stripe payment (for future use)
  Future<bool> processStripePayment({required String planId}) async {
    try {
      _isLoading = true;
      notifyListeners();

      // Get the appropriate price ID
      final priceId = _stripeService.getPriceId(planId);

      // Prepare payment
      final paymentData = await prepareStripePayment(
        planId: planId,
        priceId: priceId,
      );

      if (paymentData == null) {
        return false;
      }

      // Initialize payment sheet
      final initialized = await _stripeService.initPaymentSheet(
        clientSecret: paymentData['client_secret'],
        customerId: paymentData['customer_id'],
      );

      if (!initialized) {
        return false;
      }

      // Present payment sheet
      final paymentSuccess = await _stripeService.presentPaymentSheet(
        clientSecret: paymentData['client_secret'],
      );

      if (paymentSuccess) {
        // Handle successful payment
        return await handleSuccessfulPayment(
          subscriptionId: paymentData['subscription_id'],
          customerId: paymentData['customer_id'],
          priceId: priceId,
        );
      }

      return false;
    } catch (e) {
      Logger.error('Error processing Stripe payment', e);
      return false;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Update existing subscription price (for migration purposes)
  /// This method updates the price from $20 to $5 for existing subscriptions
  Future<bool> updateSubscriptionPrice() async {
    final userId = _auth.currentUser?.uid;
    if (userId == null || _currentSubscription == null) return false;

    try {
      // Only update if the price is currently $20 (2000 cents)
      if (_currentSubscription!.priceAmount != 2000) {
        Logger.info(
          'Subscription price is already correct: ${_currentSubscription!.formattedPrice}',
        );
        return true;
      }

      await _firestore.collection('subscriptions').doc(userId).update({
        'priceAmount': 500, // Update to $5.00
        'updatedAt': Timestamp.now(),
      });

      // Reload the subscription to reflect the change
      await _loadUserSubscription();

      Logger.success('Updated subscription price from \$20.00 to \$5.00');
      notifyListeners();
      return true;
    } catch (e) {
      Logger.error('Error updating subscription price', e);
      return false;
    }
  }

  /// Schedule a plan change to take effect after current period ends
  Future<bool> schedulePlanChange(String newPlanId) async {
    final userId = _auth.currentUser?.uid;
    if (userId == null || _currentSubscription == null) return false;

    try {
      if (!_isLoading) {
        _isLoading = true;
        notifyListeners();
      }

      // Prevent scheduling the same plan
      if (_currentSubscription!.planId == newPlanId) {
        Logger.info('Cannot schedule change to the same plan');
        return false;
      }

      // Calculate when the scheduled plan should start (at end of current period)
      final scheduledStartDate = _currentSubscription!.currentPeriodEnd;

      await _firestore.collection('subscriptions').doc(userId).update({
        'scheduledPlanId': newPlanId,
        'scheduledPlanStartDate': Timestamp.fromDate(scheduledStartDate),
        'updatedAt': Timestamp.now(),
      });

      // Reload the subscription to reflect the change
      await _loadUserSubscription();

      Logger.success('Plan change scheduled successfully');

      if (_isLoading) {
        _isLoading = false;
      }
      notifyListeners();
      return true;
    } catch (e) {
      Logger.error('Error scheduling plan change', e);
      if (_isLoading) {
        _isLoading = false;
        notifyListeners();
      }
      return false;
    }
  }

  /// Cancel a scheduled plan change
  Future<bool> cancelScheduledPlanChange() async {
    final userId = _auth.currentUser?.uid;
    if (userId == null || _currentSubscription == null) return false;

    try {
      if (!_isLoading) {
        _isLoading = true;
        notifyListeners();
      }

      await _firestore.collection('subscriptions').doc(userId).update({
        'scheduledPlanId': null,
        'scheduledPlanStartDate': null,
        'updatedAt': Timestamp.now(),
      });

      // Reload the subscription to reflect the change
      await _loadUserSubscription();

      Logger.success('Scheduled plan change cancelled');

      if (_isLoading) {
        _isLoading = false;
      }
      notifyListeners();
      return true;
    } catch (e) {
      Logger.error('Error cancelling scheduled plan change', e);
      if (_isLoading) {
        _isLoading = false;
        notifyListeners();
      }
      return false;
    }
  }

  /// Apply scheduled plan change (called when current period ends)
  /// This should be called by a cloud function or scheduled task
  Future<bool> applyScheduledPlanChange() async {
    final userId = _auth.currentUser?.uid;
    if (userId == null || _currentSubscription == null) return false;

    try {
      // Check if there's a scheduled plan change
      if (!_currentSubscription!.hasScheduledPlanChange) {
        Logger.info('No scheduled plan change to apply');
        return false;
      }

      final scheduledPlanId = _currentSubscription!.scheduledPlanId!;
      final scheduledStartDate = _currentSubscription!.scheduledPlanStartDate!;

      // Only apply if the scheduled start date has passed
      if (DateTime.now().isBefore(scheduledStartDate)) {
        Logger.info('Scheduled plan change date has not arrived yet');
        return false;
      }

      // Determine new subscription parameters
      int billingDays;
      int priceAmount;
      String interval;

      switch (scheduledPlanId) {
        case 'premium_6month':
          billingDays = 180;
          priceAmount = 10000; // $100.00 in cents
          interval = '6months';
          break;
        case 'premium_yearly':
          billingDays = 365;
          priceAmount = 17500; // $175.00 in cents
          interval = 'year';
          break;
        default:
          billingDays = 30;
          priceAmount = 2000; // $20.00 in cents
          interval = 'month';
      }

      // Update subscription with new plan
      await _firestore.collection('subscriptions').doc(userId).update({
        'planId': scheduledPlanId,
        'priceAmount': priceAmount,
        'interval': interval,
        'currentPeriodStart': Timestamp.fromDate(scheduledStartDate),
        'currentPeriodEnd':
            Timestamp.fromDate(scheduledStartDate.add(Duration(days: billingDays))),
        'scheduledPlanId': null,
        'scheduledPlanStartDate': null,
        'updatedAt': Timestamp.now(),
      });

      // Reload the subscription
      await _loadUserSubscription();

      Logger.success('Scheduled plan change applied successfully');
      notifyListeners();
      return true;
    } catch (e) {
      Logger.error('Error applying scheduled plan change', e);
      return false;
    }
  }
}
