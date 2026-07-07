import 'package:cloud_firestore/cloud_firestore.dart';

class TicketPaymentModel {
  static String firebaseKey = 'TicketPayments';

  String id;
  String eventId;
  String eventTitle;
  String ticketId;
  String customerUid;
  String customerName;
  String customerEmail;
  String creatorUid; // Event creator who receives the payment
  double amount;
  String currency;
  String paymentIntentId;
  String status; // 'pending', 'processing', 'completed', 'failed', 'refunded'
  DateTime createdAt;
  DateTime? completedAt;
  Map<String, dynamic>? metadata;

  TicketPaymentModel({
    required this.id,
    required this.eventId,
    required this.eventTitle,
    required this.ticketId,
    required this.customerUid,
    required this.customerName,
    required this.customerEmail,
    required this.creatorUid,
    required this.amount,
    required this.currency,
    required this.paymentIntentId,
    required this.status,
    required this.createdAt,
    this.completedAt,
    this.metadata,
  });

  factory TicketPaymentModel.fromJson(Map<String, dynamic> json) {
    return TicketPaymentModel(
      id: json['id'],
      eventId: json['eventId'],
      eventTitle: json['eventTitle'],
      ticketId: json['ticketId'],
      customerUid: json['customerUid'],
      customerName: json['customerName'],
      customerEmail: json['customerEmail'],
      creatorUid: json['creatorUid'],
      amount: (json['amount'] as num).toDouble(),
      currency: json['currency'] ?? 'usd',
      paymentIntentId: json['paymentIntentId'],
      status: json['status'],
      createdAt: (json['createdAt'] as Timestamp).toDate(),
      completedAt: json['completedAt'] != null
          ? (json['completedAt'] as Timestamp).toDate()
          : null,
      metadata: json['metadata'],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'eventId': eventId,
      'eventTitle': eventTitle,
      'ticketId': ticketId,
      'customerUid': customerUid,
      'customerName': customerName,
      'customerEmail': customerEmail,
      'creatorUid': creatorUid,
      'amount': amount,
      'currency': currency,
      'paymentIntentId': paymentIntentId,
      'status': status,
      'createdAt': createdAt,
      'completedAt': completedAt,
      'metadata': metadata,
    };
  }
}
