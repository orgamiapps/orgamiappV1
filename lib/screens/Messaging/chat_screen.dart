import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'dart:async';
import 'package:orgami/models/message_model.dart';
import 'package:orgami/models/customer_model.dart';
import 'package:orgami/firebase/firebase_messaging_helper.dart';
import 'package:orgami/Utils/toast.dart';

class ChatScreen extends StatefulWidget {
  final String conversationId;
  final CustomerModel otherParticipantInfo;

  const ChatScreen({
    super.key,
    required this.conversationId,
    required this.otherParticipantInfo,
  });

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  List<MessageModel> _messages = [];
  bool _isLoading = true;
  bool _isSending = false;
  StreamSubscription<QuerySnapshot>? _messagesSubscription;

  @override
  void initState() {
    super.initState();
    _initializeChat();
  }

  @override
  void dispose() {
    _messageController.dispose();
    _scrollController.dispose();
    _messagesSubscription?.cancel();
    super.dispose();
  }

  Future<void> _initializeChat() async {
    try {
      User? currentUser = _auth.currentUser;
      if (currentUser == null) return;

      if (kDebugMode) {
        debugPrint('🔧 Creating conversation ${widget.conversationId}');
      }

      // Load messages
      await _loadMessages();

      // Listen for new messages
      _listenForMessages();
    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ Error initializing chat: $e');
      }
    }
  }

  Future<void> _loadMessages() async {
    try {
      User? currentUser = _auth.currentUser;
      if (currentUser == null) return;

      if (kDebugMode) {
        debugPrint(
          '🧪 Sending test message to ${widget.otherParticipantInfo.uid}',
        );
      }

      // For testing purposes, send a test message
      try {
        await FirebaseMessagingHelper().sendMessage(
          receiverId: widget.otherParticipantInfo.uid,
          content: 'Test message from ${currentUser.displayName}',
        );

        if (kDebugMode) {
          debugPrint('✅ Test message sent successfully');
        }
      } catch (e) {
        if (kDebugMode) {
          debugPrint('❌ Error sending test message: $e');
        }
      }

      if (kDebugMode) {
        debugPrint(
          '🔍 Loading messages for conversation: ${widget.conversationId}',
        );
        debugPrint('🔍 Current user: ${currentUser.uid}');
        debugPrint('🔍 Other participant: ${widget.otherParticipantInfo}');
      }

      // Get messages from Firestore
      Stream<List<MessageModel>> messagesStream = FirebaseMessagingHelper()
          .getMessages(widget.conversationId);

      // Listen to the stream and get the first value
      List<MessageModel> messages = await messagesStream.first;

      if (mounted) {
        setState(() {
          _messages = messages;
          _isLoading = false;
        });

        if (kDebugMode) {
          debugPrint('✅ Received ${messages.length} messages');
          debugPrint('📱 Messages loaded successfully');
        }

        // Mark messages as read
        await FirebaseMessagingHelper().markMessagesAsRead(
          widget.conversationId,
          currentUser.uid,
        );

        // Scroll to bottom
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (_scrollController.hasClients) {
            _scrollController.animateTo(
              _scrollController.position.maxScrollExtent,
              duration: const Duration(milliseconds: 300),
              curve: Curves.easeOut,
            );
          }
        });
      }
    } catch (error) {
      if (kDebugMode) {
        debugPrint('❌ Error loading messages: $error');
      }
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  void _listenForMessages() {
    try {
      User? currentUser = _auth.currentUser;
      if (currentUser == null) return;

      _messagesSubscription = _firestore
          .collection('messages')
          .where('conversationId', isEqualTo: widget.conversationId)
          .orderBy('timestamp', descending: true)
          .limit(50)
          .snapshots()
          .listen((snapshot) {
            try {
              List<MessageModel> newMessages = [];
              for (DocumentSnapshot doc in snapshot.docs) {
                try {
                  MessageModel message = MessageModel.fromFirestore(doc);
                  newMessages.add(message);
                } catch (e) {
                  if (kDebugMode) {
                    debugPrint('❌ Exception in _loadMessages: $e');
                  }
                }
              }

              // Sort by timestamp (oldest first)
              newMessages.sort((a, b) => a.timestamp.compareTo(b.timestamp));

              if (mounted) {
                setState(() {
                  _messages = newMessages;
                });

                // Mark messages as read
                FirebaseMessagingHelper().markMessagesAsRead(
                  widget.conversationId,
                  currentUser.uid,
                );

                // Scroll to bottom for new messages
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (_scrollController.hasClients) {
                    _scrollController.animateTo(
                      _scrollController.position.maxScrollExtent,
                      duration: const Duration(milliseconds: 300),
                      curve: Curves.easeOut,
                    );
                  }
                });
              }
            } catch (e) {
              if (kDebugMode) {
                debugPrint('❌ Exception in _loadMessages: $e');
              }
            }
          });
    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ Error loading messages: $e');
      }
    }
  }

  Future<void> _sendMessage() async {
    if (_messageController.text.trim().isEmpty) return;

    try {
      User? currentUser = _auth.currentUser;
      if (currentUser == null) return;

      String message = _messageController.text.trim();
      String receiverId = widget.otherParticipantInfo.uid;

      setState(() {
        _isSending = true;
      });

      if (kDebugMode) {
        debugPrint('📤 Sending message to $receiverId: $message');
        debugPrint('📤 Conversation ID: ${widget.conversationId}');
      }

      // Send message
      await FirebaseMessagingHelper().sendMessage(
        receiverId: receiverId,
        content: message,
      );

      if (kDebugMode) {
        debugPrint('✅ Message sent successfully');
      }

      // Clear text field
      _messageController.clear();

      setState(() {
        _isSending = false;
      });
    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ Error sending message: $e');
      }

      setState(() {
        _isSending = false;
      });

      if (mounted) {
        ShowToast().showSnackBar('Failed to send message', context);
      }
    }
  }

  Widget _buildMessageBubble(MessageModel message) {
    User? currentUser = _auth.currentUser;
    bool isMe = currentUser?.uid == message.senderId;

    return Align(
      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 16),
        decoration: BoxDecoration(
          color: isMe ? Colors.blue : Colors.grey[300],
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(
          message.content,
          style: TextStyle(
            color: isMe ? Colors.white : Colors.black,
            fontSize: 16,
          ),
        ),
      ),
    );
  }

  Widget _buildMessageList() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_messages.isEmpty) {
      return const Center(
        child: Text(
          'No messages yet. Start a conversation!',
          style: TextStyle(fontSize: 16, color: Colors.grey),
        ),
      );
    }

    return ListView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.only(bottom: 80),
      itemCount: _messages.length,
      itemBuilder: (context, index) {
        return _buildMessageBubble(_messages[index]);
      },
    );
  }

  Widget _buildMessageInput() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withValues(alpha: 0.3),
            blurRadius: 5,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _messageController,
              decoration: const InputDecoration(
                hintText: 'Type a message...',
                border: OutlineInputBorder(),
              ),
              maxLines: null,
              textCapitalization: TextCapitalization.sentences,
            ),
          ),
          const SizedBox(width: 8),
          IconButton(
            onPressed: _isSending ? null : _sendMessage,
            icon: _isSending
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.send),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            CircleAvatar(
              backgroundImage:
                  widget.otherParticipantInfo.profilePictureUrl != null
                  ? NetworkImage(widget.otherParticipantInfo.profilePictureUrl!)
                  : null,
              child: widget.otherParticipantInfo.profilePictureUrl == null
                  ? Text(
                      widget.otherParticipantInfo.name.isNotEmpty
                          ? widget.otherParticipantInfo.name[0].toUpperCase()
                          : '?',
                    )
                  : null,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.otherParticipantInfo.name,
                    style: const TextStyle(fontSize: 16),
                  ),
                  Text(
                    widget.otherParticipantInfo.email,
                    style: const TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.more_vert),
            onPressed: () {
              // Show more options
            },
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(child: _buildMessageList()),
          _buildMessageInput(),
        ],
      ),
    );
  }
}
