import 'package:cloud_firestore/cloud_firestore.dart';

class EventFeedbackModel {
  static String firebaseKey = 'event_feedback';

  final String id;
  final String eventId;
  final String? userId; // null if anonymous
  final int rating; // 1-5 stars
  final String? comment; // optional comment
  final DateTime timestamp;
  final bool isAnonymous;

  EventFeedbackModel({
    required this.id,
    required this.eventId,
    this.userId,
    required this.rating,
    this.comment,
    required this.timestamp,
    required this.isAnonymous,
  });

  factory EventFeedbackModel.fromFirestore(DocumentSnapshot doc) {
    Map<String, dynamic> data = doc.data() as Map<String, dynamic>;
    return EventFeedbackModel(
      id: doc.id,
      eventId: data['eventId'] ?? '',
      userId: data['userId'],
      rating: data['rating'] ?? 0,
      comment: data['comment'],
      timestamp: (data['timestamp'] as Timestamp).toDate(),
      isAnonymous: data['isAnonymous'] ?? false,
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'eventId': eventId,
      'userId': userId,
      'rating': rating,
      'comment': comment,
      'timestamp': Timestamp.fromDate(timestamp),
      'isAnonymous': isAnonymous,
    };
  }

  EventFeedbackModel copyWith({
    String? id,
    String? eventId,
    String? userId,
    int? rating,
    String? comment,
    DateTime? timestamp,
    bool? isAnonymous,
  }) {
    return EventFeedbackModel(
      id: id ?? this.id,
      eventId: eventId ?? this.eventId,
      userId: userId ?? this.userId,
      rating: rating ?? this.rating,
      comment: comment ?? this.comment,
      timestamp: timestamp ?? this.timestamp,
      isAnonymous: isAnonymous ?? this.isAnonymous,
    );
  }
}

class EventFeedbackAnalytics {
  final double averageRating;
  final int totalRatings;
  final Map<int, int> ratingDistribution; // rating -> count
  final String sentiment; // positive, neutral, negative
  final List<String> commentSummaries;
  final int anonymousCount;
  final int namedCount;

  EventFeedbackAnalytics({
    required this.averageRating,
    required this.totalRatings,
    required this.ratingDistribution,
    required this.sentiment,
    required this.commentSummaries,
    required this.anonymousCount,
    required this.namedCount,
  });

  factory EventFeedbackAnalytics.fromFirestore(Map<String, dynamic> data) {
    return EventFeedbackAnalytics(
      averageRating: (data['averageRating'] ?? 0.0).toDouble(),
      totalRatings: data['totalRatings'] ?? 0,
      ratingDistribution: Map<int, int>.from(data['ratingDistribution'] ?? {}),
      sentiment: data['sentiment'] ?? 'neutral',
      commentSummaries: List<String>.from(data['commentSummaries'] ?? []),
      anonymousCount: data['anonymousCount'] ?? 0,
      namedCount: data['namedCount'] ?? 0,
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'averageRating': averageRating,
      'totalRatings': totalRatings,
      'ratingDistribution': ratingDistribution,
      'sentiment': sentiment,
      'commentSummaries': commentSummaries,
      'anonymousCount': anonymousCount,
      'namedCount': namedCount,
    };
  }
}
