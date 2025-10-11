import 'package:cloud_firestore/cloud_firestore.dart';

/// Subscription tier enum
enum SubscriptionTier {
  free,
  basic,
  premium;

  String get displayName {
    switch (this) {
      case SubscriptionTier.free:
        return 'Free';
      case SubscriptionTier.basic:
        return 'Basic';
      case SubscriptionTier.premium:
        return 'Premium';
    }
  }

  String get value {
    switch (this) {
      case SubscriptionTier.free:
        return 'free';
      case SubscriptionTier.basic:
        return 'basic';
      case SubscriptionTier.premium:
        return 'premium';
    }
  }

  static SubscriptionTier fromString(String? value) {
    switch (value?.toLowerCase()) {
      case 'basic':
        return SubscriptionTier.basic;
      case 'premium':
        return SubscriptionTier.premium;
      default:
        return SubscriptionTier.free;
    }
  }
}

class SubscriptionModel {
  final String id;
  final String userId;
  final String planId; // e.g., 'basic_monthly', 'premium_yearly'
  final String status; // 'active', 'cancelled', 'past_due', 'incomplete'
  final int priceAmount; // Price in cents (e.g., 500 = $5.00)
  final String currency; // 'USD', 'EUR', etc.
  final String interval; // 'month', 'year'
  final DateTime currentPeriodStart;
  final DateTime currentPeriodEnd;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? cancelledAt;
  final String? stripeSubscriptionId;
  final String? stripeCustomerId;
  final bool isTrial;
  final DateTime? trialEndsAt;
  final String? scheduledPlanId; // Plan ID to switch to after current period
  final DateTime? scheduledPlanStartDate; // When the scheduled plan starts
  final String tier; // 'free', 'basic', 'premium'
  final int eventsCreatedThisMonth; // For Basic tier monthly limit tracking
  final DateTime? currentMonthStart; // Track when current month started

  SubscriptionModel({
    required this.id,
    required this.userId,
    required this.planId,
    required this.status,
    required this.priceAmount,
    required this.currency,
    required this.interval,
    required this.currentPeriodStart,
    required this.currentPeriodEnd,
    required this.createdAt,
    required this.updatedAt,
    this.cancelledAt,
    this.stripeSubscriptionId,
    this.stripeCustomerId,
    this.isTrial = false,
    this.trialEndsAt,
    this.scheduledPlanId,
    this.scheduledPlanStartDate,
    this.tier = 'free',
    this.eventsCreatedThisMonth = 0,
    this.currentMonthStart,
  });

  /// Check if subscription is currently active
  bool get isActive {
    if (status != 'active') return false;

    final now = DateTime.now();

    // If it's a trial, check trial end date
    if (isTrial && trialEndsAt != null) {
      return now.isBefore(trialEndsAt!);
    }

    // Check if current period is still valid
    return now.isBefore(currentPeriodEnd);
  }

  /// Get formatted price string
  String get formattedPrice {
    final price = priceAmount / 100; // Convert cents to dollars
    return '\$${price.toStringAsFixed(2)}';
  }

  /// Get subscription tier
  SubscriptionTier get subscriptionTier => SubscriptionTier.fromString(tier);

  /// Get plan display name
  String get planDisplayName {
    final tierName = subscriptionTier.displayName;
    switch (planId) {
      case 'basic_monthly':
      case 'premium_monthly':
        return '$tierName Monthly';
      case 'basic_6month':
      case 'premium_6month':
        return '$tierName 6-Month';
      case 'basic_yearly':
      case 'premium_yearly':
        return '$tierName Annual';
      default:
        return tierName;
    }
  }

  /// Get billing interval display text
  String get intervalDisplayText {
    switch (planId) {
      case 'basic_monthly':
      case 'premium_monthly':
        return 'month';
      case 'basic_6month':
      case 'premium_6month':
        return '6 months';
      case 'basic_yearly':
      case 'premium_yearly':
        return 'year';
      default:
        return interval;
    }
  }

  /// Get savings percentage compared to monthly plan
  String? get savingsPercentage {
    switch (planId) {
      case 'basic_6month':
        return '17%'; // $25 vs $30 (6 months at $5)
      case 'basic_yearly':
        return '33%'; // $40 vs $60 (12 months at $5)
      case 'premium_6month':
        return '17%'; // $100 vs $120 (6 months at $20)
      case 'premium_yearly':
        return '27%'; // $175 vs $240 (12 months at $20)
      default:
        return null;
    }
  }

  /// Check if user can access analytics (Premium only)
  bool canAccessAnalytics() {
    return isActive && subscriptionTier == SubscriptionTier.premium;
  }

  /// Check if user can create groups (Premium only)
  bool canCreateGroups() {
    return isActive && subscriptionTier == SubscriptionTier.premium;
  }

  /// Check if user has unlimited events
  bool hasUnlimitedEvents() {
    return isActive && subscriptionTier == SubscriptionTier.premium;
  }

  /// Get monthly event limit (0 = unlimited, null = no access)
  int? get monthlyEventLimit {
    if (!isActive) return null;
    if (subscriptionTier == SubscriptionTier.premium) return 0; // Unlimited
    if (subscriptionTier == SubscriptionTier.basic) return 5;
    return null; // Free tier
  }

  /// Get remaining events this month for Basic tier
  int? get remainingEventsThisMonth {
    if (subscriptionTier != SubscriptionTier.basic) return null;
    final limit = monthlyEventLimit ?? 0;
    return (limit - eventsCreatedThisMonth).clamp(0, limit);
  }

  /// Check if monthly limit needs reset
  bool needsMonthlyReset() {
    if (subscriptionTier != SubscriptionTier.basic) return false;
    if (currentMonthStart == null) return true;

    final now = DateTime.now();
    final monthStart = currentMonthStart!;

    // Check if we're in a new month
    return now.year > monthStart.year ||
        (now.year == monthStart.year && now.month > monthStart.month);
  }

  /// Check if this is a popular/recommended plan
  bool get isRecommended {
    return planId == 'premium_6month';
  }

  /// Check if a plan change is scheduled
  bool get hasScheduledPlanChange {
    return scheduledPlanId != null && scheduledPlanStartDate != null;
  }

  /// Get scheduled plan display name
  String? get scheduledPlanDisplayName {
    if (scheduledPlanId == null) return null;
    switch (scheduledPlanId) {
      case 'premium_monthly':
        return 'Premium Monthly';
      case 'premium_6month':
        return 'Premium 6-Month';
      case 'premium_yearly':
        return 'Premium Annual';
      default:
        return 'Premium';
    }
  }

  /// Create from Firestore document
  factory SubscriptionModel.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;

    return SubscriptionModel(
      id: doc.id,
      userId: data['userId'] ?? '',
      planId: data['planId'] ?? '',
      status: data['status'] ?? '',
      priceAmount: data['priceAmount'] ?? 0,
      currency: data['currency'] ?? 'USD',
      interval: data['interval'] ?? 'month',
      currentPeriodStart: _parseTimestamp(data['currentPeriodStart']),
      currentPeriodEnd: _parseTimestamp(data['currentPeriodEnd']),
      createdAt: _parseTimestamp(data['createdAt']),
      updatedAt: _parseTimestamp(data['updatedAt']),
      cancelledAt: data['cancelledAt'] != null
          ? _parseTimestamp(data['cancelledAt'])
          : null,
      stripeSubscriptionId: data['stripeSubscriptionId'],
      stripeCustomerId: data['stripeCustomerId'],
      isTrial: data['isTrial'] ?? false,
      trialEndsAt: data['trialEndsAt'] != null
          ? _parseTimestamp(data['trialEndsAt'])
          : null,
      scheduledPlanId: data['scheduledPlanId'],
      scheduledPlanStartDate: data['scheduledPlanStartDate'] != null
          ? _parseTimestamp(data['scheduledPlanStartDate'])
          : null,
      tier: data['tier'] ?? _inferTierFromPlanId(data['planId']),
      eventsCreatedThisMonth: data['eventsCreatedThisMonth'] ?? 0,
      currentMonthStart: data['currentMonthStart'] != null
          ? _parseTimestamp(data['currentMonthStart'])
          : null,
    );
  }

  /// Infer tier from legacy plan IDs
  static String _inferTierFromPlanId(String? planId) {
    if (planId == null) return 'free';
    if (planId.startsWith('basic_')) return 'basic';
    if (planId.startsWith('premium_')) return 'premium';
    // Legacy: assume premium for old 'premium_*' plans
    return 'premium';
  }

  /// Convert to map for Firestore
  Map<String, dynamic> toMap() {
    return {
      'userId': userId,
      'planId': planId,
      'status': status,
      'priceAmount': priceAmount,
      'currency': currency,
      'interval': interval,
      'currentPeriodStart': Timestamp.fromDate(currentPeriodStart),
      'currentPeriodEnd': Timestamp.fromDate(currentPeriodEnd),
      'createdAt': Timestamp.fromDate(createdAt),
      'updatedAt': Timestamp.fromDate(updatedAt),
      'cancelledAt': cancelledAt != null
          ? Timestamp.fromDate(cancelledAt!)
          : null,
      'stripeSubscriptionId': stripeSubscriptionId,
      'stripeCustomerId': stripeCustomerId,
      'isTrial': isTrial,
      'trialEndsAt': trialEndsAt != null
          ? Timestamp.fromDate(trialEndsAt!)
          : null,
      'scheduledPlanId': scheduledPlanId,
      'scheduledPlanStartDate': scheduledPlanStartDate != null
          ? Timestamp.fromDate(scheduledPlanStartDate!)
          : null,
      'tier': tier,
      'eventsCreatedThisMonth': eventsCreatedThisMonth,
      'currentMonthStart': currentMonthStart != null
          ? Timestamp.fromDate(currentMonthStart!)
          : null,
    };
  }

  /// Create a copy with updated fields
  SubscriptionModel copyWith({
    String? id,
    String? userId,
    String? planId,
    String? status,
    int? priceAmount,
    String? currency,
    String? interval,
    DateTime? currentPeriodStart,
    DateTime? currentPeriodEnd,
    DateTime? createdAt,
    DateTime? updatedAt,
    DateTime? cancelledAt,
    String? stripeSubscriptionId,
    String? stripeCustomerId,
    bool? isTrial,
    DateTime? trialEndsAt,
    String? scheduledPlanId,
    DateTime? scheduledPlanStartDate,
    String? tier,
    int? eventsCreatedThisMonth,
    DateTime? currentMonthStart,
  }) {
    return SubscriptionModel(
      id: id ?? this.id,
      userId: userId ?? this.userId,
      planId: planId ?? this.planId,
      status: status ?? this.status,
      priceAmount: priceAmount ?? this.priceAmount,
      currency: currency ?? this.currency,
      interval: interval ?? this.interval,
      currentPeriodStart: currentPeriodStart ?? this.currentPeriodStart,
      currentPeriodEnd: currentPeriodEnd ?? this.currentPeriodEnd,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      cancelledAt: cancelledAt,
      stripeSubscriptionId: stripeSubscriptionId ?? this.stripeSubscriptionId,
      stripeCustomerId: stripeCustomerId ?? this.stripeCustomerId,
      isTrial: isTrial ?? this.isTrial,
      trialEndsAt: trialEndsAt,
      scheduledPlanId: scheduledPlanId,
      scheduledPlanStartDate: scheduledPlanStartDate,
      tier: tier ?? this.tier,
      eventsCreatedThisMonth: eventsCreatedThisMonth ?? this.eventsCreatedThisMonth,
      currentMonthStart: currentMonthStart,
    );
  }

  /// Parse timestamp from Firestore
  static DateTime _parseTimestamp(dynamic timestamp) {
    if (timestamp is Timestamp) {
      return timestamp.toDate();
    } else if (timestamp is DateTime) {
      return timestamp;
    } else if (timestamp is String) {
      return DateTime.tryParse(timestamp) ?? DateTime.now();
    } else {
      return DateTime.now();
    }
  }

  @override
  String toString() {
    return 'SubscriptionModel(id: $id, userId: $userId, planId: $planId, status: $status, isActive: $isActive)';
  }
}
