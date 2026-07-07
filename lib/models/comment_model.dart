import 'package:cloud_firestore/cloud_firestore.dart';

class CommentModel {
  static String firebaseKey = 'Comments';

  String id;
  String eventId;
  String userId;
  String userName;
  String? userProfilePictureUrl;
  String comment;
  DateTime createdAt;

  CommentModel({
    required this.id,
    required this.eventId,
    required this.userId,
    required this.userName,
    this.userProfilePictureUrl,
    required this.comment,
    required this.createdAt,
  });

  factory CommentModel.fromFirestore(DocumentSnapshot snap) {
    Map d = snap.data() as Map<dynamic, dynamic>;
    return CommentModel(
      id: d['id'],
      eventId: d['eventId'],
      userId: d['userId'],
      userName: d['userName'],
      userProfilePictureUrl: d['userProfilePictureUrl'],
      comment: d['comment'],
      createdAt: (d['createdAt'] as Timestamp).toDate(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'eventId': eventId,
      'userId': userId,
      'userName': userName,
      'userProfilePictureUrl': userProfilePictureUrl,
      'comment': comment,
      'createdAt': Timestamp.fromDate(createdAt),
    };
  }
}
