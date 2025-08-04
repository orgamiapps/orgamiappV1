import 'package:cloud_firestore/cloud_firestore.dart';

class MessageModel {
  static String firebaseKey = 'Messages';
  String id;
  String senderId;
  String receiverId;
  String content;
  DateTime timestamp;
  bool isRead;
  String? messageType; // 'text', 'image', 'file'
  String? mediaUrl;
  String? fileName;

  MessageModel({
    required this.id,
    required this.senderId,
    required this.receiverId,
    required this.content,
    required this.timestamp,
    this.isRead = false,
    this.messageType = 'text',
    this.mediaUrl,
    this.fileName,
  });

  factory MessageModel.fromFirestore(DocumentSnapshot snap) {
    Map d = snap.data() as Map<dynamic, dynamic>;
    return MessageModel(
      id: snap.id,
      senderId: d['senderId'],
      receiverId: d['receiverId'],
      content: d['content'],
      timestamp: (d['timestamp'] as Timestamp).toDate(),
      isRead: d['isRead'] ?? false,
      messageType: d['messageType'] ?? 'text',
      mediaUrl: d['mediaUrl'],
      fileName: d['fileName'],
    );
  }

  static Map<String, dynamic> getMap(MessageModel message) {
    return {
      'senderId': message.senderId,
      'receiverId': message.receiverId,
      'content': message.content,
      'timestamp': message.timestamp,
      'isRead': message.isRead,
      'messageType': message.messageType,
      'mediaUrl': message.mediaUrl,
      'fileName': message.fileName,
    };
  }
}

class ConversationModel {
  String id;
  String participant1Id;
  String participant2Id;
  String lastMessage;
  DateTime lastMessageTime;
  int unreadCount;
  Map<String, dynamic> participantInfo;

  ConversationModel({
    required this.id,
    required this.participant1Id,
    required this.participant2Id,
    required this.lastMessage,
    required this.lastMessageTime,
    this.unreadCount = 0,
    required this.participantInfo,
  });

  factory ConversationModel.fromFirestore(DocumentSnapshot snap) {
    Map d = snap.data() as Map<dynamic, dynamic>;
    return ConversationModel(
      id: snap.id,
      participant1Id: d['participant1Id'] ?? '',
      participant2Id: d['participant2Id'] ?? '',
      lastMessage: d['lastMessage'] ?? '',
      lastMessageTime: d['lastMessageTime'] != null
          ? (d['lastMessageTime'] as Timestamp).toDate()
          : DateTime.now(),
      unreadCount: d['unreadCount'] ?? 0,
      participantInfo: d['participantInfo'] ?? {},
    );
  }

  static Map<String, dynamic> getMap(ConversationModel conversation) {
    return {
      'participant1Id': conversation.participant1Id,
      'participant2Id': conversation.participant2Id,
      'lastMessage': conversation.lastMessage,
      'lastMessageTime': conversation.lastMessageTime,
      'unreadCount': conversation.unreadCount,
      'participantInfo': conversation.participantInfo,
    };
  }
}
