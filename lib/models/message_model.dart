import 'package:cloud_firestore/cloud_firestore.dart';

class MessageModel {
  static String firebaseKey = 'Messages';
  String id;
  String senderId;
  String? receiverId; // optional for group messages
  String conversationId; // supports both 1-1 and group
  String content;
  DateTime timestamp;
  bool isRead;
  String? messageType; // 'text', 'image', 'file'
  String? mediaUrl;
  String? fileName;
  String? replyToMessageId;
  List<String>? readByUserIds; // for group read receipts

  MessageModel({
    required this.id,
    required this.senderId,
    this.receiverId,
    required this.conversationId,
    required this.content,
    required this.timestamp,
    this.isRead = false,
    this.messageType = 'text',
    this.mediaUrl,
    this.fileName,
    this.replyToMessageId,
    this.readByUserIds,
  });

  factory MessageModel.fromFirestore(DocumentSnapshot snap) {
    Map d = snap.data() as Map<dynamic, dynamic>;
    return MessageModel(
      id: snap.id,
      senderId: d['senderId'],
      receiverId: d['receiverId'],
      conversationId: d['conversationId'] ?? _inferConversationId(d),
      content: d['content'],
      timestamp: d['timestamp'] != null 
          ? (d['timestamp'] as Timestamp).toDate() 
          : DateTime.now(),
      isRead: d['isRead'] ?? false,
      messageType: d['messageType'] ?? 'text',
      mediaUrl: d['mediaUrl'],
      fileName: d['fileName'],
      replyToMessageId: d['replyToMessageId'],
      readByUserIds: d['readByUserIds'] != null
          ? List<String>.from(d['readByUserIds'])
          : null,
    );
  }

  static Map<String, dynamic> getMap(MessageModel message) {
    return {
      'senderId': message.senderId,
      'receiverId': message.receiverId,
      'conversationId': message.conversationId,
      'content': message.content,
      'timestamp': message.timestamp,
      'isRead': message.isRead,
      'messageType': message.messageType,
      'mediaUrl': message.mediaUrl,
      'fileName': message.fileName,
      'replyToMessageId': message.replyToMessageId,
      'readByUserIds': message.readByUserIds,
    };
  }

  // Backward-compatibility helper for older 1-1 messages without conversationId
  static String _inferConversationId(Map<dynamic, dynamic> d) {
    final sender = d['senderId'];
    final receiver = d['receiverId'];
    if (sender is String && receiver is String) {
      final ids = [sender, receiver]..sort();
      return '${ids[0]}_${ids[1]}';
    }
    return 'unknown_conversation';
  }
}

class ConversationModel {
  String id;
  // Legacy 1-1 fields (kept for compatibility)
  String? participant1Id;
  String? participant2Id;
  // New unified participants list
  List<String> participantIds;
  String lastMessage;
  DateTime lastMessageTime;
  int unreadCount;
  Map<String, dynamic> participantInfo;
  // Group fields
  bool isGroup;
  String? groupName;
  String? groupAvatarUrl;
  String? lastMessageSenderId;

  ConversationModel({
    required this.id,
    this.participant1Id,
    this.participant2Id,
    required this.participantIds,
    required this.lastMessage,
    required this.lastMessageTime,
    this.unreadCount = 0,
    required this.participantInfo,
    this.isGroup = false,
    this.groupName,
    this.groupAvatarUrl,
    this.lastMessageSenderId,
  });

  factory ConversationModel.fromFirestore(DocumentSnapshot snap) {
    Map d = snap.data() as Map<dynamic, dynamic>;
    return ConversationModel(
      id: snap.id,
      participant1Id: d['participant1Id'],
      participant2Id: d['participant2Id'],
      participantIds: d['participantIds'] != null
          ? List<String>.from(d['participantIds'])
          : _buildParticipantIdsFallback(d),
      lastMessage: d['lastMessage'] ?? '',
      lastMessageTime: d['lastMessageTime'] != null
          ? (d['lastMessageTime'] as Timestamp).toDate()
          : DateTime.now(),
      unreadCount: d['unreadCount'] ?? 0,
      participantInfo: d['participantInfo'] ?? {},
      isGroup: d['isGroup'] ?? false,
      groupName: d['groupName'],
      groupAvatarUrl: d['groupAvatarUrl'],
      lastMessageSenderId: d['lastMessageSenderId'],
    );
  }

  static Map<String, dynamic> getMap(ConversationModel conversation) {
    return {
      'participant1Id': conversation.participant1Id,
      'participant2Id': conversation.participant2Id,
      'participantIds': conversation.participantIds,
      'lastMessage': conversation.lastMessage,
      'lastMessageTime': conversation.lastMessageTime,
      'unreadCount': conversation.unreadCount,
      'participantInfo': conversation.participantInfo,
      'isGroup': conversation.isGroup,
      'groupName': conversation.groupName,
      'groupAvatarUrl': conversation.groupAvatarUrl,
      'lastMessageSenderId': conversation.lastMessageSenderId,
    };
  }

  static List<String> _buildParticipantIdsFallback(Map<dynamic, dynamic> d) {
    final p1 = d['participant1Id'];
    final p2 = d['participant2Id'];
    List<String> ids = [];
    if (p1 is String && p1.isNotEmpty) ids.add(p1);
    if (p2 is String && p2.isNotEmpty) ids.add(p2);
    return ids;
  }
}
