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
  int sequence;
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
    this.sequence = 0,
    this.messageType = 'text',
    this.mediaUrl,
    this.fileName,
    this.replyToMessageId,
    this.readByUserIds,
  });

  factory MessageModel.fromFirestore(DocumentSnapshot snap) {
    return MessageModel.fromMap(
      snap.id,
      Map<String, dynamic>.from(snap.data() as Map),
    );
  }

  factory MessageModel.fromMap(String id, Map<String, dynamic> d) {
    return MessageModel(
      id: id,
      senderId: d['senderId'],
      receiverId: d['receiverId'],
      conversationId: d['conversationId'] ?? _inferConversationId(d),
      content: d['content'],
      timestamp: d['timestamp'] != null
          ? (d['timestamp'] as Timestamp).toDate()
          : DateTime.fromMillisecondsSinceEpoch(0),
      isRead: d['isRead'] ?? false,
      sequence: d['sequence'] ?? 0,
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
  Map<String, int> readSequences;

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
    this.readSequences = const {},
  });

  factory ConversationModel.fromFirestore(
    DocumentSnapshot snap, {
    String? currentUserId,
  }) {
    return ConversationModel.fromMap(
      snap.id,
      Map<String, dynamic>.from(snap.data() as Map),
      currentUserId: currentUserId,
    );
  }

  factory ConversationModel.fromMap(
    String id,
    Map<String, dynamic> d, {
    String? currentUserId,
  }) {
    return ConversationModel(
      id: id,
      participant1Id: d['participant1Id'],
      participant2Id: d['participant2Id'],
      participantIds: d['participantIds'] != null
          ? List<String>.from(d['participantIds'])
          : _buildParticipantIdsFallback(d),
      lastMessage: d['lastMessage'] ?? '',
      lastMessageTime: d['lastMessageTime'] != null
          ? (d['lastMessageTime'] as Timestamp).toDate()
          : DateTime.fromMillisecondsSinceEpoch(0),
      unreadCount: currentUserId == null
          ? 0
          : (d['unreadCounts']?[currentUserId] ?? 0),
      readSequences: Map<String, int>.from(d['readSequences'] ?? {}),
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
