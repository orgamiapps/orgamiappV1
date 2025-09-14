import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'dart:async';
import 'package:attendus/models/message_model.dart';
import 'package:attendus/models/customer_model.dart';
import 'package:attendus/firebase/firebase_messaging_helper.dart';
import 'package:attendus/Utils/toast.dart';
import 'package:attendus/firebase/firebase_firestore_helper.dart';
import 'package:attendus/widgets/app_scaffold_wrapper.dart';

class ChatScreen extends StatefulWidget {
  final String conversationId;
  final CustomerModel? otherParticipantInfo; // null for group

  const ChatScreen({
    super.key,
    required this.conversationId,
    this.otherParticipantInfo,
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
  StreamSubscription<List<MessageModel>>? _messagesSubscription;
  ConversationModel? _conversation;
  String? _swipedMessageId; // Track which message is currently swiped

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

      // Start listener ASAP so new messages appear instantly
      _listenForMessages();

      // Load conversation metadata and initial messages
      await _loadConversation();
      await _loadMessages();
    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ Error initializing chat: $e');
      }
    }
  }

  Future<void> _loadConversation() async {
    try {
      final doc = await _firestore
          .collection('Conversations')
          .doc(widget.conversationId)
          .get();
      if (doc.exists) {
        setState(() {
          _conversation = ConversationModel.fromFirestore(doc);
        });
      }
    } catch (e) {
      if (kDebugMode) debugPrint('❌ Error loading conversation: $e');
    }
  }

  Future<void> _loadMessages() async {
    try {
      User? currentUser = _auth.currentUser;
      if (currentUser == null) return;

      if (kDebugMode) {
        debugPrint(
          '🔍 Loading messages for conversation: ${widget.conversationId}',
        );
        debugPrint('🔍 Current user: ${currentUser.uid}');
        debugPrint('🔍 Conversation loaded: ${_conversation?.id}');
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

      _messagesSubscription = FirebaseMessagingHelper()
          .getMessages(widget.conversationId)
          .listen((newMessages) async {
            try {
              // Sort by timestamp (oldest first)
              newMessages.sort((a, b) => a.timestamp.compareTo(b.timestamp));

              // If group chat: hide messages from blocked users
              final isGroup = _conversation?.isGroup == true;
              if (isGroup) {
                try {
                  final blocksSnap = await _firestore
                      .collection('Customers')
                      .doc(currentUser.uid)
                      .collection('blocks')
                      .get();
                  final blocked = blocksSnap.docs.map((d) => d.id).toSet();
                  newMessages = newMessages
                      .where((m) => !blocked.contains(m.senderId))
                      .toList();
                } catch (_) {}
              }
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
              if (kDebugMode) debugPrint('❌ Listen error: $e');
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

      setState(() {
        _isSending = true;
      });

      if (kDebugMode) {
        debugPrint(
          '📤 Sending message to conversation ${widget.conversationId}: $message',
        );
        debugPrint('📤 Conversation ID: ${widget.conversationId}');
      }

      final isGroup = _conversation?.isGroup == true;

      // Optimistically add message to the list for instant feedback
      final provisional = MessageModel(
        id: 'local_${DateTime.now().millisecondsSinceEpoch}',
        senderId: currentUser.uid,
        receiverId: isGroup ? null : widget.otherParticipantInfo?.uid,
        conversationId: widget.conversationId,
        content: message,
        timestamp: DateTime.now(),
        isRead: false,
      );
      setState(() {
        _messages = [..._messages, provisional];
      });
      // Scroll to bottom immediately
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scrollController.hasClients) {
          _scrollController.animateTo(
            _scrollController.position.maxScrollExtent,
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOut,
          );
        }
      });

      // Persist to Firestore
      if (isGroup) {
        await FirebaseMessagingHelper().sendMessage(
          content: message,
          conversationId: widget.conversationId,
        );
      } else {
        final receiverId = widget.otherParticipantInfo!.uid;
        await FirebaseMessagingHelper().sendMessage(
          receiverId: receiverId,
          content: message,
          conversationId: widget.conversationId,
        );
      }

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
    final isGroup = _conversation?.isGroup == true;
    final senderName = isGroup
        ? (_conversation?.participantInfo[message.senderId]?['name'] ?? '')
        : '';
    final isLastMessage =
        _messages.isNotEmpty && _messages.last.id == message.id;
    final isSwipedOut = _swipedMessageId == message.id;

    return GestureDetector(
      onTap: () {
        // Tap anywhere to close swiped message
        if (_swipedMessageId != null) {
          setState(() {
            _swipedMessageId = null;
          });
        }
      },
      child: Align(
        alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
        child: Column(
          crossAxisAlignment: isMe
              ? CrossAxisAlignment.end
              : CrossAxisAlignment.start,
          children: [
            if (!isMe && isGroup && senderName.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(left: 12, bottom: 2),
                child: Text(
                  senderName,
                  style: const TextStyle(fontSize: 12, color: Colors.grey),
                ),
              ),
            GestureDetector(
              onHorizontalDragEnd: (details) {
                // Swipe left to reveal timestamp
                if (details.primaryVelocity! < -500) {
                  setState(() {
                    _swipedMessageId = isSwipedOut ? null : message.id;
                  });
                }
              },
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                curve: Curves.easeInOut,
                transform: Matrix4.translationValues(
                  isSwipedOut ? -80.0 : 0.0,
                  0.0,
                  0.0,
                ),
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    // Timestamp behind the message
                    if (isSwipedOut)
                      Positioned(
                        right: isMe ? -70 : null,
                        left: isMe ? null : -70,
                        top: 0,
                        bottom: 0,
                        child: Container(
                          width: 60,
                          alignment: Alignment.center,
                          child: Text(
                            _formatDetailedTimestamp(message.timestamp),
                            style: const TextStyle(
                              fontSize: 10,
                              color: Colors.grey,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ),
                      ),
                    // Message bubble
                    Container(
                      margin: const EdgeInsets.symmetric(
                        vertical: 2,
                        horizontal: 8,
                      ),
                      padding: const EdgeInsets.symmetric(
                        vertical: 10,
                        horizontal: 14,
                      ),
                      decoration: BoxDecoration(
                        color: isMe
                            ? Theme.of(context).colorScheme.primary
                            : Theme.of(context).colorScheme.surfaceContainerHighest,
                        borderRadius: BorderRadius.only(
                          topLeft: const Radius.circular(18),
                          topRight: const Radius.circular(18),
                          bottomLeft: Radius.circular(isMe ? 18 : 4),
                          bottomRight: Radius.circular(isMe ? 4 : 18),
                        ),
                      ),
                      child: Text(
                        message.content,
                        style: TextStyle(
                          color: isMe 
                              ? Theme.of(context).colorScheme.onPrimary 
                              : Theme.of(context).colorScheme.onSurface,
                          fontSize: 16,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            // Delivered status for the most recent sent message
            if (isMe && isLastMessage && !message.id.startsWith('local_'))
              Padding(
                padding: const EdgeInsets.only(right: 12, top: 2),
                child: Text(
                  'Delivered',
                  style: TextStyle(
                    fontSize: 11, 
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildMessageList() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_messages.isEmpty) {
      return Center(
        child: Text(
          'No messages yet. Start a conversation!',
          style: TextStyle(
            fontSize: 16, 
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
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
        color: Theme.of(context).cardColor,
        boxShadow: [
          BoxShadow(
            color: Theme.of(context).shadowColor.withValues(alpha: 0.3),
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

  String _formatDetailedTimestamp(DateTime dt) {
    final now = DateTime.now();
    final isToday =
        dt.year == now.year && dt.month == now.month && dt.day == now.day;
    final yesterday = now.subtract(const Duration(days: 1));
    final isYesterday =
        dt.year == yesterday.year &&
        dt.month == yesterday.month &&
        dt.day == yesterday.day;

    final timeStr = TimeOfDay.fromDateTime(dt).format(context);

    if (isToday) {
      return 'Today\n$timeStr';
    } else if (isYesterday) {
      return 'Yesterday\n$timeStr';
    } else {
      return '${dt.month}/${dt.day}/${dt.year}\n$timeStr';
    }
  }

  @override
  Widget build(BuildContext context) {
    return AppScaffoldWrapper(
      selectedBottomNavIndex: 2, // Messages tab
      appBar: AppBar(
        backgroundColor: Colors.white,
        foregroundColor: Colors.black87,
        iconTheme: const IconThemeData(color: Colors.black87),
        elevation: 0,
        scrolledUnderElevation: 0,
        surfaceTintColor: Colors.transparent,
        systemOverlayStyle: SystemUiOverlayStyle.dark,
        leading: IconButton(
          icon: const Icon(
            Icons.arrow_back_ios_new_rounded,
            color: Colors.black87,
          ),
          onPressed: () => Navigator.pop(context),
          tooltip: 'Back',
        ),
        titleTextStyle: const TextStyle(
          color: Colors.black87,
          fontSize: 18,
          fontWeight: FontWeight.w600,
        ),
        title: _buildAppBarTitle(),
        actions: [
          PopupMenuButton<String>(
            onSelected: _handleMenuAction,
            itemBuilder: (_) => [
              const PopupMenuItem(
                value: 'report_user',
                child: Text('Report User'),
              ),
              const PopupMenuItem(
                value: 'block_user',
                child: Text('Block User'),
              ),
              const PopupMenuItem(
                value: 'unblock_user',
                child: Text('Unblock User'),
              ),
            ],
          ),
        ],
        bottom: const PreferredSize(
          preferredSize: Size.fromHeight(1),
          child: Divider(height: 1, thickness: 1, color: Color(0xFFE5E7EB)),
        ),
      ),
      body: Column(
        children: [
          Expanded(child: _buildMessageList()),
          _buildMessageInput(),
        ],
      ),
    );
  }

  Future<void> _handleMenuAction(String value) async {
    final currentUser = _auth.currentUser;
    if (currentUser == null) return;
    final otherId = widget.otherParticipantInfo?.uid;

    try {
      switch (value) {
        case 'report_user':
          await FirebaseFirestoreHelper().submitUserReport(
            type: 'user',
            targetUserId: otherId,
            reason: 'inappropriate_content',
          );
          if (mounted) {
            ShowToast().showSnackBar('Report submitted. Thank you.', context);
          }
          break;
        case 'block_user':
          if (otherId != null && otherId.isNotEmpty) {
            await FirebaseFirestoreHelper().blockUser(
              blockerId: currentUser.uid,
              blockedUserId: otherId,
            );
            if (mounted) {
              ShowToast().showSnackBar('User blocked', context);
            }
          }
          break;
        case 'unblock_user':
          if (otherId != null && otherId.isNotEmpty) {
            await FirebaseFirestoreHelper().unblockUser(
              blockerId: currentUser.uid,
              blockedUserId: otherId,
            );
            if (mounted) {
              ShowToast().showSnackBar('User unblocked', context);
            }
          }
          break;
      }
    } catch (_) {}
  }

  Widget _buildAppBarTitle() {
    if (_conversation?.isGroup == true) {
      final name = _conversation?.groupName ?? 'Group';
      return Row(
        children: [
          const CircleAvatar(child: Icon(Icons.group)),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              name,
              style: const TextStyle(fontSize: 16),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      );
    }
    final user = widget.otherParticipantInfo;
    if (user == null) return const SizedBox.shrink();
    return Row(
      children: [
        CircleAvatar(
          backgroundImage: user.profilePictureUrl != null
              ? NetworkImage(user.profilePictureUrl!)
              : null,
          child: user.profilePictureUrl == null
              ? Text(user.name.isNotEmpty ? user.name[0].toUpperCase() : '?')
              : null,
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(user.name, style: const TextStyle(fontSize: 16)),
              Text(
                user.email,
                style: const TextStyle(fontSize: 12, color: Colors.grey),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
