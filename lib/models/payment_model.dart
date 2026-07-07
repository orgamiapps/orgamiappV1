import 'package:cloud_firestore/cloud_firestore.dart';

class FeaturePaymentModel {
  final String id;
  final String eventId;
  final String customerUid;
  final int durationDays;
  final double amount;
  final String currency;
  final String paymentIntentId;
  final String status; // 'pending', 'completed', 'failed', 'refunded'
  final DateTime createdAt;
  final DateTime? completedAt;

  static String firebaseKey = 'FeaturePayments';

  // Pricing tiers (in dollars)
  static const Map<int, double> pricingTiers = {
    3: 3.00,   // $3.00 for 3 days
    7: 5.00,   // $5.00 for 7 days
    14: 8.00,  // $8.00 for 14 days
  };

  FeaturePaymentModel({
    required this.id,
    required this.eventId,
    required this.customerUid,
    required this.durationDays,
    required this.amount,
    required this.currency,
    required this.paymentIntentId,
    required this.status,
    required this.createdAt,
    this.completedAt,
  });

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'eventId': eventId,
      'customerUid': customerUid,
      'durationDays': durationDays,
      'amount': amount,
      'currency': currency,
      'paymentIntentId': paymentIntentId,
      'status': status,
      'createdAt': createdAt,
      'completedAt': completedAt,
    };
  }

  factory FeaturePaymentModel.fromJson(Map<String, dynamic> json) {
    return FeaturePaymentModel(
      id: json['id'] ?? '',
      eventId: json['eventId'] ?? '',
      customerUid: json['customerUid'] ?? '',
      durationDays: json['durationDays'] ?? 0,
      amount: (json['amount'] ?? 0).toDouble(),
      currency: json['currency'] ?? 'usd',
      paymentIntentId: json['paymentIntentId'] ?? '',
      status: json['status'] ?? 'pending',
      createdAt: json['createdAt'] is Timestamp 
          ? (json['createdAt'] as Timestamp).toDate()
          : DateTime.now(),
      completedAt: json['completedAt'] != null 
          ? (json['completedAt'] is Timestamp 
              ? (json['completedAt'] as Timestamp).toDate()
              : json['completedAt'] as DateTime)
          : null,
    );
  }

  static double getPriceForDays(int days) {
    // For "until event" option, calculate based on actual days
    if (!pricingTiers.containsKey(days)) {
      // Use the closest tier
      if (days <= 3) return pricingTiers[3]!;
      if (days <= 7) return pricingTiers[7]!;
      return pricingTiers[14]!;
    }
    return pricingTiers[days]!;
  }

  static int getPricingTierForDays(int days) {
    if (days <= 3) return 3;
    if (days <= 7) return 7;
    return 14;
  }
}
