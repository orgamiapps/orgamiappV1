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
import 'package:attendus/screens/MyProfile/user_profile_screen.dart';

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
  final Map<String, double> _messageSwipeOffsets =
      {}; // Track individual message swipe positions

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

  Widget _buildMessageBubble(
    MessageModel message, {
    bool showDateHeader = false,
  }) {
    User? currentUser = _auth.currentUser;
    bool isMe = currentUser?.uid == message.senderId;
    final isGroup = _conversation?.isGroup == true;
    final senderName = isGroup
        ? (_conversation?.participantInfo[message.senderId]?['name'] ?? '')
        : '';
    final isLastMessage =
        _messages.isNotEmpty && _messages.last.id == message.id;
    final currentOffset = _messageSwipeOffsets[message.id] ?? 0.0;
    final isBeingDragged =
        currentOffset.abs() > 20; // Show timestamp while dragging

    return Column(
      children: [
        // Date header
        if (showDateHeader) _buildDateHeader(message.timestamp),

        GestureDetector(
      onTap: () {
            // Tap anywhere to reset any dragging states
            if (_messageSwipeOffsets.isNotEmpty) {
          setState(() {
                _messageSwipeOffsets.clear();
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
                      style: TextStyle(
                        fontSize: 12,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                        fontWeight: FontWeight.w500,
                      ),
                ),
              ),
            GestureDetector(
                  onHorizontalDragUpdate: (details) {
                  setState(() {
                      final currentOffset =
                          _messageSwipeOffsets[message.id] ?? 0.0;
                      double newOffset;

                      if (isMe) {
                        // For sent messages: swipe left to reveal timestamp
                        newOffset = (currentOffset + details.delta.dx).clamp(
                          -120.0,
                          0.0,
                        );
                      } else {
                        // For received messages: swipe right to reveal timestamp
                        newOffset = (currentOffset + details.delta.dx).clamp(
                          0.0,
                          120.0,
                        );
                      }

                      _messageSwipeOffsets[message.id] = newOffset;
                    });
                  },
                  onHorizontalDragEnd: (details) {
                    // Always return to normal state when drag ends
                    setState(() {
                      _messageSwipeOffsets[message.id] = 0.0;
                      if (_swipedMessageId == message.id) {
                        _swipedMessageId = null;
                      }
                    });
              },
              child: AnimatedContainer(
                    duration: const Duration(milliseconds: 250),
                    curve: Curves.easeOutCubic,
                transform: Matrix4.translationValues(
                      currentOffset,
                  0.0,
                  0.0,
                ),
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                        // Timestamp behind the message (only while dragging)
                        if (isBeingDragged)
                      Positioned(
                            right: isMe ? -90 : null,
                            left: isMe ? null : -90,
                        top: 0,
                        bottom: 0,
                        child: Container(
                              width: 80,
                          alignment: Alignment.center,
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Text(
                                    _formatTimeOnly(message.timestamp),
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: Theme.of(
                                        context,
                                      ).colorScheme.onSurfaceVariant,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                  Text(
                                    _formatDateOnly(message.timestamp),
                                    style: TextStyle(
                              fontSize: 10,
                                      color: Theme.of(context)
                                          .colorScheme
                                          .onSurfaceVariant
                                          .withValues(alpha: 0.7),
                            ),
                          ),
                                ],
                        ),
                      ),
                          ),
                        // Message bubble with enhanced iOS styling
                    Container(
                          margin: EdgeInsets.symmetric(
                            vertical: 1,
                            horizontal: isMe ? 12 : 8,
                      ),
                      padding: const EdgeInsets.symmetric(
                            vertical: 12,
                            horizontal: 16,
                          ),
                          constraints: BoxConstraints(
                            maxWidth: MediaQuery.of(context).size.width * 0.75,
                      ),
                      decoration: BoxDecoration(
                        color: isMe
                            ? Theme.of(context).colorScheme.primary
                                : Theme.of(
                                    context,
                                  ).colorScheme.surfaceContainerHighest,
                        borderRadius: BorderRadius.only(
                              topLeft: const Radius.circular(20),
                              topRight: const Radius.circular(20),
                              bottomLeft: Radius.circular(isMe ? 20 : 6),
                              bottomRight: Radius.circular(isMe ? 6 : 20),
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: Theme.of(
                                  context,
                                ).shadowColor.withValues(alpha: 0.1),
                                blurRadius: 2,
                                offset: const Offset(0, 1),
                              ),
                            ],
                      ),
                      child: Text(
                        message.content,
                        style: TextStyle(
                          color: isMe 
                              ? Theme.of(context).colorScheme.onPrimary 
                              : Theme.of(context).colorScheme.onSurface,
                          fontSize: 16,
                              height: 1.3,
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
                    padding: const EdgeInsets.only(right: 16, top: 4),
                child: Text(
                  'Delivered',
                  style: TextStyle(
                    fontSize: 11, 
                        color: Theme.of(
                          context,
                        ).colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
                  ),
                ),
              ),
          ],
        ),
      ),
        ),
      ],
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
      padding: const EdgeInsets.only(top: 8, bottom: 80),
      itemCount: _messages.length,
      itemBuilder: (context, index) {
        final message = _messages[index];
        final showDateHeader = _shouldShowDateHeader(index);
        return _buildMessageBubble(message, showDateHeader: showDateHeader);
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

  String _formatTimeOnly(DateTime dt) {
    return TimeOfDay.fromDateTime(dt).format(context);
  }

  String _formatDateOnly(DateTime dt) {
    final now = DateTime.now();
    final isToday =
        dt.year == now.year && dt.month == now.month && dt.day == now.day;
    final yesterday = now.subtract(const Duration(days: 1));
    final isYesterday =
        dt.year == yesterday.year &&
        dt.month == yesterday.month &&
        dt.day == yesterday.day;

    if (isToday) {
      return 'Today';
    } else if (isYesterday) {
      return 'Yesterday';
    } else {
      return '${dt.month}/${dt.day}/${dt.year.toString().substring(2)}';
    }
  }

  bool _shouldShowDateHeader(int index) {
    if (index == 0) return true;

    final currentMessage = _messages[index];
    final previousMessage = _messages[index - 1];

    final currentDate = DateTime(
      currentMessage.timestamp.year,
      currentMessage.timestamp.month,
      currentMessage.timestamp.day,
    );

    final previousDate = DateTime(
      previousMessage.timestamp.year,
      previousMessage.timestamp.month,
      previousMessage.timestamp.day,
    );

    return !currentDate.isAtSameMomentAs(previousDate);
  }

  Widget _buildDateHeader(DateTime timestamp) {
    final now = DateTime.now();
    final messageDate = DateTime(
      timestamp.year,
      timestamp.month,
      timestamp.day,
    );
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = today.subtract(const Duration(days: 1));

    String dateText;
    if (messageDate.isAtSameMomentAs(today)) {
      dateText = 'Today';
    } else if (messageDate.isAtSameMomentAs(yesterday)) {
      dateText = 'Yesterday';
    } else {
      // Format as "Monday, January 15" for recent dates
      final daysDifference = today.difference(messageDate).inDays;
      if (daysDifference <= 7) {
        dateText = _formatWeekdayDate(timestamp);
      } else {
        dateText = _formatFullDate(timestamp);
      }
    }

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 16),
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: Theme.of(
              context,
            ).colorScheme.surfaceContainerHighest.withValues(alpha: 0.8),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(
            dateText,
            style: TextStyle(
              fontSize: 13,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ),
    );
  }

  String _formatWeekdayDate(DateTime date) {
    const weekdays = [
      'Monday',
      'Tuesday',
      'Wednesday',
      'Thursday',
      'Friday',
      'Saturday',
      'Sunday',
    ];
    const months = [
      'January',
      'February',
      'March',
      'April',
      'May',
      'June',
      'July',
      'August',
      'September',
      'October',
      'November',
      'December',
    ];

    final weekday = weekdays[date.weekday - 1];
    final month = months[date.month - 1];
    return '$weekday, $month ${date.day}';
  }

  String _formatFullDate(DateTime date) {
    const months = [
      'January',
      'February',
      'March',
      'April',
      'May',
      'June',
      'July',
      'August',
      'September',
      'October',
      'November',
      'December',
    ];

    final month = months[date.month - 1];
    return '$month ${date.day}, ${date.year}';
  }

  void _showGroupMembersModal() {
    if (_conversation?.isGroup != true) return;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _buildGroupMembersModal(),
    );
  }

  Widget _buildGroupMembersModal() {
    final conversation = _conversation;
    if (conversation?.isGroup != true) return const SizedBox.shrink();

    final currentUserId = _auth.currentUser?.uid;
    final members = conversation!.participantIds
        .map(
          (id) => {
            'id': id,
            'info':
                conversation.participantInfo[id] ?? {'name': 'Unknown User'},
            'isCurrentUser': id == currentUserId,
          },
        )
        .toList();

    // Sort members: current user first, then alphabetically
    members.sort((a, b) {
      if (a['isCurrentUser'] == true) return -1;
      if (b['isCurrentUser'] == true) return 1;
      final nameA = (a['info'] as Map)['name'] ?? '';
      final nameB = (b['info'] as Map)['name'] ?? '';
      return nameA.toString().toLowerCase().compareTo(
        nameB.toString().toLowerCase(),
      );
    });

    return DraggableScrollableSheet(
      initialChildSize: 0.6,
      minChildSize: 0.3,
      maxChildSize: 0.9,
      builder: (context, scrollController) {
        return Container(
          decoration: BoxDecoration(
            color: Theme.of(context).scaffoldBackgroundColor,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
            boxShadow: [
              BoxShadow(
                color: Theme.of(context).shadowColor.withValues(alpha: 0.2),
                blurRadius: 10,
                offset: const Offset(0, -2),
              ),
            ],
          ),
          child: Column(
            children: [
              // Handle bar
              Container(
                margin: const EdgeInsets.only(top: 8, bottom: 16),
                height: 4,
                width: 36,
                decoration: BoxDecoration(
                  color: Theme.of(
                    context,
                  ).colorScheme.onSurfaceVariant.withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),

              // Header
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 8,
                ),
                child: Column(
                  children: [
                    CircleAvatar(
                      radius: 30,
                      backgroundColor: Theme.of(context).colorScheme.primary,
                      child: const Icon(
                        Icons.group,
                        color: Colors.white,
                        size: 30,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      conversation.groupName ?? 'Group',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w600,
                        color: Theme.of(context).colorScheme.onSurface,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${members.length} member${members.length != 1 ? 's' : ''}',
                      style: TextStyle(
                        fontSize: 14,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),

              const Divider(height: 32),

              // Members list
              Expanded(
                child: ListView.builder(
                  controller: scrollController,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  itemCount: members.length,
                  itemBuilder: (context, index) {
                    final member = members[index];
                    final memberInfo = member['info'] as Map<String, dynamic>;
                    final isCurrentUser = member['isCurrentUser'] as bool;

                    return _buildMemberTile(
                      memberInfo: memberInfo,
                      isCurrentUser: isCurrentUser,
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildMemberTile({
    required Map<String, dynamic> memberInfo,
    required bool isCurrentUser,
  }) {
    final name = memberInfo['name'] ?? 'Unknown User';
    final email = memberInfo['email'] ?? '';
    final username = memberInfo['username'];
    final profilePictureUrl = memberInfo['profilePictureUrl'];

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(12),
        border: isCurrentUser
            ? Border.all(
                color: Theme.of(
                  context,
                ).colorScheme.primary.withValues(alpha: 0.3),
                width: 1,
              )
            : null,
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        leading: CircleAvatar(
          radius: 24,
          backgroundImage: profilePictureUrl != null
              ? NetworkImage(profilePictureUrl)
              : null,
          backgroundColor: Theme.of(
            context,
          ).colorScheme.primary.withValues(alpha: 0.1),
          child: profilePictureUrl == null
              ? Text(
                  name.isNotEmpty ? name[0].toUpperCase() : '?',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                )
              : null,
        ),
        title: Row(
          children: [
            Expanded(
              child: Text(
                name,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                  color: Theme.of(context).colorScheme.onSurface,
                ),
              ),
            ),
            if (isCurrentUser)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.primary,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Text(
                  'You',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: Colors.white,
                  ),
                ),
              ),
          ],
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (username != null) ...[
              const SizedBox(height: 2),
              Text(
                '@$username',
                style: TextStyle(
                  fontSize: 14,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ],
            if (email.isNotEmpty) ...[
              const SizedBox(height: 2),
              Text(
                email,
                style: TextStyle(
                  fontSize: 12,
                  color: Theme.of(
                    context,
                  ).colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
                ),
              ),
            ],
          ],
        ),
        onTap: isCurrentUser
            ? null
            : () {
                Navigator.pop(context); // Close the modal first
                _navigateToUserProfile(memberInfo);
              },
      ),
    );
  }

  void _navigateToUserProfile(Map<String, dynamic> memberInfo) {
    final customerModel = CustomerModel(
      uid: memberInfo['uid'] ?? '',
      name: memberInfo['name'] ?? 'Unknown User',
      email: memberInfo['email'] ?? '',
      username: memberInfo['username'],
      profilePictureUrl: memberInfo['profilePictureUrl'],
      bio: memberInfo['bio'],
      phoneNumber: memberInfo['phoneNumber'],
      age: memberInfo['age'],
      gender: memberInfo['gender'],
      location: memberInfo['location'],
      occupation: memberInfo['occupation'],
      company: memberInfo['company'],
      website: memberInfo['website'],
      socialMediaLinks: memberInfo['socialMediaLinks'],
      isDiscoverable: memberInfo['isDiscoverable'] ?? true,
      favorites: List<String>.from(memberInfo['favorites'] ?? []),
      createdAt: memberInfo['createdAt'] != null
          ? DateTime.parse(memberInfo['createdAt'])
          : DateTime.now(),
    );

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => UserProfileScreen(
          user: customerModel,
          isOwnProfile: false,
        ),
      ),
    );
  }

  void _navigateToDirectMessageUserProfile(CustomerModel user) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => UserProfileScreen(
          user: user,
          isOwnProfile: false,
        ),
      ),
    );
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
      return GestureDetector(
        onTap: () => _showGroupMembersModal(),
        child: Row(
        children: [
          const CircleAvatar(child: Icon(Icons.group)),
          const SizedBox(width: 8),
          Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
              name,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
              overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    '${_conversation?.participantIds.length ?? 0} members',
                    style: TextStyle(
                      fontSize: 12,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ],
              ),
            ),
            Icon(
              Icons.chevron_right,
              size: 18,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ],
        ),
      );
    }
    final user = widget.otherParticipantInfo;
    if (user == null) return const SizedBox.shrink();
    return GestureDetector(
      onTap: () => _navigateToDirectMessageUserProfile(user),
      child: Row(
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
                Text(
                  user.name, 
                  style: const TextStyle(
                    fontSize: 16, 
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(
                  user.email,
                  style: TextStyle(
                    fontSize: 12, 
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          Icon(
            Icons.chevron_right,
            size: 18,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ],
      ),
    );
  }
}
