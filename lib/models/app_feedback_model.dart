import 'package:cloud_firestore/cloud_firestore.dart';

class AppFeedbackModel {
  static String firebaseKey = 'app_feedback';

  final String id;
  final String? userId; // null if anonymous
  final int rating; // 1-5 stars
  final String? comment; // optional comment
  final DateTime timestamp;
  final bool isAnonymous;
  final String? name;
  final String? email;
  final String? contactNumber;

  AppFeedbackModel({
    required this.id,
    this.userId,
    required this.rating,
    this.comment,
    required this.timestamp,
    required this.isAnonymous,
    this.name,
    this.email,
    this.contactNumber,
  });

  factory AppFeedbackModel.fromFirestore(DocumentSnapshot doc) {
    Map<String, dynamic> data = doc.data() as Map<String, dynamic>;
    return AppFeedbackModel(
      id: doc.id,
      userId: data['userId'],
      rating: data['rating'] ?? 0,
      comment: data['comment'],
      timestamp: (data['timestamp'] as Timestamp).toDate(),
      isAnonymous: data['isAnonymous'] ?? false,
      name: data['name'],
      email: data['email'],
      contactNumber: data['contactNumber'],
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'userId': userId,
      'rating': rating,
      'comment': comment,
      'timestamp': Timestamp.fromDate(timestamp),
      'isAnonymous': isAnonymous,
      'name': name,
      'email': email,
      'contactNumber': contactNumber,
    };
  }

  AppFeedbackModel copyWith({
    String? id,
    String? userId,
    int? rating,
    String? comment,
    DateTime? timestamp,
    bool? isAnonymous,
    String? name,
    String? email,
    String? contactNumber,
  }) {
    return AppFeedbackModel(
      id: id ?? this.id,
      userId: userId ?? this.userId,
      rating: rating ?? this.rating,
      comment: comment ?? this.comment,
      timestamp: timestamp ?? this.timestamp,
      isAnonymous: isAnonymous ?? this.isAnonymous,
      name: name ?? this.name,
      email: email ?? this.email,
      contactNumber: contactNumber ?? this.contactNumber,
    );
  }
}
