import 'package:attendus/models/message_model.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'unread badges belong to the current account, not a shared legacy count',
    () {
      final snapshot = <String, dynamic>{
        'participantIds': ['a', 'b'],
        'unreadCount': 99,
        'unreadCounts': {'a': 2, 'b': 7},
        'readSequences': {'a': 3},
        'lastMessageTime': Timestamp.fromMillisecondsSinceEpoch(1000),
      };
      expect(
        ConversationModel.fromMap(
          'thread',
          snapshot,
          currentUserId: 'a',
        ).unreadCount,
        2,
      );
      expect(
        ConversationModel.fromMap(
          'thread',
          snapshot,
          currentUserId: 'b',
        ).unreadCount,
        7,
      );
      expect(
        ConversationModel.fromMap(
          'thread',
          snapshot,
          currentUserId: 'c',
        ).unreadCount,
        0,
      );
      expect(
        ConversationModel.fromMap('thread', snapshot).readSequences['a'],
        3,
      );
    },
  );

  test(
    'malformed records fail visibly instead of fabricating valid messages',
    () {
      expect(
        () => MessageModel.fromMap('thread', {'content': 42}),
        throwsA(isA<TypeError>()),
      );
      expect(
        () => ConversationModel.fromMap('thread', {
          'participantIds': [42],
        }),
        throwsA(isA<TypeError>()),
      );
    },
  );

  test('message sequence and canonical parent survive parsing', () {
    final message = MessageModel.fromMap('thread', {
      'senderId': 'a',
      'receiverId': 'b',
      'conversationId': 'legacy-thread',
      'content': 'hello',
      'sequence': 12,
      'timestamp': Timestamp.fromMillisecondsSinceEpoch(1000),
    });
    expect(message.conversationId, 'legacy-thread');
    expect(message.sequence, 12);
    expect(message.timestamp.millisecondsSinceEpoch, 1000);
  });
}
