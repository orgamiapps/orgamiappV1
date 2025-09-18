import 'package:cloud_firestore/cloud_firestore.dart';

class SubscriptionModel {
  final String id;
  final String userId;
  final String planId; // e.g., 'premium_monthly', 'premium_yearly'
  final String status; // 'active', 'cancelled', 'past_due', 'incomplete'
  final int priceAmount; // Price in cents (e.g., 2000 = $20.00)
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

  /// Get plan display name
  String get planDisplayName {
    switch (planId) {
      case 'premium_monthly':
        return 'Premium Monthly';
      case 'premium_yearly':
        return 'Premium Yearly';
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
    );
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
      'cancelledAt': cancelledAt != null ? Timestamp.fromDate(cancelledAt!) : null,
      'stripeSubscriptionId': stripeSubscriptionId,
      'stripeCustomerId': stripeCustomerId,
      'isTrial': isTrial,
      'trialEndsAt': trialEndsAt != null ? Timestamp.fromDate(trialEndsAt!) : null,
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