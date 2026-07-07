import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:attendus/Utils/logger.dart';
import 'package:attendus/Services/subscription_service.dart';
import 'package:attendus/models/subscription_model.dart';

/// Service for managing creation limits for free users
/// Free users can create up to 5 events and 5 groups
/// Premium users have unlimited creation
class CreationLimitService extends ChangeNotifier {
  static final CreationLimitService _instance = CreationLimitService._internal();
  factory CreationLimitService() => _instance;
  CreationLimitService._internal();

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final SubscriptionService _subscriptionService = SubscriptionService();

  // Free tier limits
  static const int freeEventLimit = 5;
  static const int freeGroupLimit = 5;

  int _eventsCreated = 0;
  int _groupsCreated = 0;
  bool _isLoading = false;

  int get eventsCreated => _eventsCreated;
  int get groupsCreated => _groupsCreated;
  bool get isLoading => _isLoading;

  // Computed properties for remaining creations
  int get eventsRemaining {
    if (_subscriptionService.hasPremium) return -1; // -1 indicates unlimited
    return (freeEventLimit - _eventsCreated).clamp(0, freeEventLimit);
  }

  int get groupsRemaining {
    if (_subscriptionService.hasPremium) return -1; // -1 indicates unlimited
    return (freeGroupLimit - _groupsCreated).clamp(0, freeGroupLimit);
  }

  // Check if user can create more events
  bool get canCreateEvent {
    // Premium: unlimited
    if (_subscriptionService.hasUnlimitedEvents()) return true;
    
    // Basic: check monthly limit (handled by subscription service)
    if (_subscriptionService.currentTier == SubscriptionTier.basic) {
      final remaining = _subscriptionService.getRemainingEvents();
      return remaining != null && remaining > 0;
    }
    
    // Free: check lifetime limit
    return _eventsCreated < freeEventLimit;
  }

  // Check if user can create more groups
  bool get canCreateGroup {
    // Premium: unlimited
    if (_subscriptionService.canCreateGroups()) return true;
    
    // Basic and Free: no group creation
    return false;
  }

  // Check if user is approaching limit (1 remaining)
  bool get isApproachingEventLimit {
    if (_subscriptionService.hasPremium) return false;
    return eventsRemaining == 1;
  }

  bool get isApproachingGroupLimit {
    if (_subscriptionService.hasPremium) return false;
    return groupsRemaining == 1;
  }

  /// Initialize the service and load user's creation counts
  Future<void> initialize() async {
    final userId = _auth.currentUser?.uid;
    if (userId == null) return;

    try {
      _isLoading = true;
      // CRITICAL FIX: Defer notifyListeners to prevent setState during build
      WidgetsBinding.instance.addPostFrameCallback((_) {
        notifyListeners();
      });

      await _loadCreationCounts();
    } catch (e) {
      Logger.error('Failed to initialize creation limit service', e);
    } finally {
      _isLoading = false;
      // CRITICAL FIX: Defer notifyListeners to prevent setState during build
      WidgetsBinding.instance.addPostFrameCallback((_) {
        notifyListeners();
      });
    }
  }

  /// Load user's creation counts from Firestore
  Future<void> _loadCreationCounts() async {
    final userId = _auth.currentUser?.uid;
    if (userId == null) return;

    try {
      final doc = await _firestore
          .collection('Customers')
          .doc(userId)
          .get();

      if (doc.exists) {
        final data = doc.data()!;
        _eventsCreated = data['eventsCreated'] ?? 0;
        _groupsCreated = data['groupsCreated'] ?? 0;
        Logger.info('Loaded creation counts: Events=$_eventsCreated, Groups=$_groupsCreated');
      }
    } catch (e) {
      Logger.error('Error loading creation counts', e);
    }
  }

  /// Get event limit description text for UI
  String getEventLimitText() {
    final tier = _subscriptionService.currentTier;
    
    switch (tier) {
      case SubscriptionTier.premium:
        return 'Unlimited events';
      case SubscriptionTier.basic:
        final remaining = _subscriptionService.getRemainingEvents();
        if (remaining == null) return 'No events available';
        return '$remaining of 5 events remaining this month';
      case SubscriptionTier.free:
        return '$eventsRemaining of $freeEventLimit lifetime events remaining';
    }
  }

  /// Increment event creation count
  Future<bool> incrementEventCount() async {
    final userId = _auth.currentUser?.uid;
    if (userId == null) return false;

    // Premium users don't need to track counts
    if (_subscriptionService.hasUnlimitedEvents()) {
      Logger.info('Premium user - skipping event count increment');
      return true;
    }

    // Basic users: increment monthly count in subscription service
    if (_subscriptionService.currentTier == SubscriptionTier.basic) {
      Logger.info('Basic user - incrementing monthly event count');
      return await _subscriptionService.incrementMonthlyEventCount();
    }

    // Free users: check lifetime limit
    if (!canCreateEvent) {
      Logger.warning('Event creation limit reached');
      return false;
    }

    try {
      await _firestore
          .collection('Customers')
          .doc(userId)
          .update({
        'eventsCreated': FieldValue.increment(1),
      });

      _eventsCreated++;
      notifyListeners();
      
      Logger.success('Event count incremented to $_eventsCreated');
      return true;
    } catch (e) {
      Logger.error('Error incrementing event count', e);
      return false;
    }
  }

  /// Increment group creation count
  Future<bool> incrementGroupCount() async {
    final userId = _auth.currentUser?.uid;
    if (userId == null) return false;

    // Only Premium users can create groups
    if (!_subscriptionService.canCreateGroups()) {
      Logger.warning('Group creation requires Premium subscription');
      return false;
    }

    // Premium users don't need to track counts
    Logger.info('Premium user - group creation allowed');
    return true;
  }

  /// Decrement event count (when an event is deleted)
  Future<void> decrementEventCount() async {
    final userId = _auth.currentUser?.uid;
    if (userId == null) return;

    // Premium users don't track counts
    if (_subscriptionService.hasPremium) return;

    if (_eventsCreated <= 0) return;

    try {
      await _firestore
          .collection('Customers')
          .doc(userId)
          .update({
        'eventsCreated': FieldValue.increment(-1),
      });

      _eventsCreated = (_eventsCreated - 1).clamp(0, freeEventLimit);
      notifyListeners();
      
      Logger.info('Event count decremented to $_eventsCreated');
    } catch (e) {
      Logger.error('Error decrementing event count', e);
    }
  }

  /// Decrement group count (when a group is deleted)
  Future<void> decrementGroupCount() async {
    final userId = _auth.currentUser?.uid;
    if (userId == null) return;

    // Premium users don't track counts
    if (_subscriptionService.hasPremium) return;

    if (_groupsCreated <= 0) return;

    try {
      await _firestore
          .collection('Customers')
          .doc(userId)
          .update({
        'groupsCreated': FieldValue.increment(-1),
      });

      _groupsCreated = (_groupsCreated - 1).clamp(0, freeGroupLimit);
      notifyListeners();
      
      Logger.info('Group count decremented to $_groupsCreated');
    } catch (e) {
      Logger.error('Error decrementing group count', e);
    }
  }

  /// Reset counts (typically not needed as premium users aren't tracked)
  Future<void> resetCounts() async {
    final userId = _auth.currentUser?.uid;
    if (userId == null) return;

    try {
      await _firestore
          .collection('Customers')
          .doc(userId)
          .update({
        'eventsCreated': 0,
        'groupsCreated': 0,
      });

      _eventsCreated = 0;
      _groupsCreated = 0;
      notifyListeners();
      
      Logger.info('Creation counts reset');
    } catch (e) {
      Logger.error('Error resetting counts', e);
    }
  }

  /// Get formatted limit status text
  String getEventLimitStatus() {
    if (_subscriptionService.hasPremium) {
      return 'Unlimited';
    }
    return '$_eventsCreated / $freeEventLimit';
  }

  String getGroupLimitStatus() {
    if (_subscriptionService.hasPremium) {
      return 'Unlimited';
    }
    return '$_groupsCreated / $freeGroupLimit';
  }

  /// Get progress percentage (0.0 to 1.0)
  double getEventProgress() {
    if (_subscriptionService.hasPremium) return 0.0;
    return (_eventsCreated / freeEventLimit).clamp(0.0, 1.0);
  }

  double getGroupProgress() {
    if (_subscriptionService.hasPremium) return 0.0;
    return (_groupsCreated / freeGroupLimit).clamp(0.0, 1.0);
  }
}

