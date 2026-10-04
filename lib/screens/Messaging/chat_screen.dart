import 'package:attendus/Services/messaging_feed.dart';
import 'package:attendus/Services/conversation_redirect.dart';
import 'package:attendus/Utils/logger.dart';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/services.dart';
import 'dart:async';
import 'package:attendus/models/message_model.dart';
import 'package:attendus/models/customer_model.dart';
import 'package:attendus/firebase/firebase_messaging_helper.dart';
import 'package:attendus/Utils/toast.dart';
import 'package:attendus/firebase/firebase_firestore_helper.dart';
import 'package:attendus/widgets/app_scaffold_wrapper.dart';
import 'package:attendus/screens/MyProfile/user_profile_screen.dart';
import 'package:attendus/widgets/attendus_design_system.dart';

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
  final _feed = MessagingFeed<MessageModel>();
  StreamSubscription<User?>? _authSubscription;
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>?
  _conversationSubscription;
  String? _messageError;
  String? _pendingRequestId;
  String? _pendingContent;
  String? _lastReadId;
  String? _accountUid;
  int _chatGeneration = 0;
  String? _resolvedConversationId;
  bool _conversationMoving = false;
  ConversationModel? _conversation;
  String? _swipedMessageId; // Track which message is currently swiped
  final Map<String, double> _messageSwipeOffsets =
      {}; // Track individual message swipe positions

  CustomerModel? get _otherParticipant {
    if (_conversation?.isGroup == true) return null;
    if (widget.otherParticipantInfo != null &&
        _conversation?.participantIds.contains(
              widget.otherParticipantInfo!.uid,
            ) ==
            true) {
      return widget.otherParticipantInfo;
    }
    final others = _conversation?.participantIds.where(
      (id) => id != _auth.currentUser?.uid,
    );
    if (others == null || others.isEmpty) return null;
    final id = others.first;
    final info = _conversation?.participantInfo[id] ?? <String, dynamic>{};
    return CustomerModel(
      uid: id,
      name: info['name'] ?? 'User',
      email: '',
      username: info['username'],
      profilePictureUrl: info['profilePictureUrl'],
      createdAt: DateTime.fromMillisecondsSinceEpoch(0),
    );
  }

  @override
  void initState() {
    super.initState();
    _feed.addListener(_onMessagesChanged);
    _authSubscription = _auth.authStateChanges().listen((user) {
      if (_accountUid != user?.uid) {
        _messageController.clear();
        _pendingRequestId = null;
        _pendingContent = null;
        _lastReadId = null;
        _conversation = null;
      }
      _accountUid = user?.uid;
      _initializeChat();
    });
  }

  @override
  void dispose() {
    _chatGeneration++;
    _messageController.dispose();
    _scrollController.dispose();
    _feed.dispose();
    _authSubscription?.cancel();
    _conversationSubscription?.cancel();
    super.dispose();
  }

  Future<void> _initializeChat() async {
    final generation = ++_chatGeneration;
    final user = _auth.currentUser;
    final uid = user != null && !user.isAnonymous ? user.uid : null;
    _conversationSubscription?.cancel();
    _resolvedConversationId = null;
    _conversationMoving = false;
    _conversation = null;
    _lastReadId = null;
    await _feed.bind(uid, () async {
      final doc = await resolveConversationRedirect(
        widget.conversationId,
        load: (id) => _firestore.collection('Conversations').doc(id).get(),
        redirect: (doc) => doc.data()?['redirectConversationId'] as String?,
      );
      if (!doc.exists) throw StateError('Conversation is unavailable');
      final conversation = ConversationModel.fromFirestore(
        doc,
        currentUserId: uid,
      );
      final blocks = await _firestore
          .collection('Customers')
          .doc(uid)
          .collection('blocks')
          .get();
      final blocked = blocks.docs.map((doc) => doc.id).toSet();
      if (!mounted ||
          generation != _chatGeneration ||
          _auth.currentUser?.uid != uid) {
        return const Stream<List<MessageModel>>.empty();
      }
      _conversation = conversation;
      _resolvedConversationId = doc.id;
      _conversationMoving = doc.data()?['migrationState'] == 'moving';
      _conversationSubscription = doc.reference.snapshots().listen(
        (snapshot) {
          if (!mounted ||
              generation != _chatGeneration ||
              _auth.currentUser?.uid != uid ||
              !snapshot.exists) {
            return;
          }
          if (snapshot.data()?['redirectConversationId'] != null ||
              (snapshot.data()?['migrationState'] == 'moving') !=
                  _conversationMoving) {
            unawaited(_initializeChat());
            return;
          }
          setState(
            () => _conversation = ConversationModel.fromFirestore(
              snapshot,
              currentUserId: uid,
            ),
          );
        },
        onError: (Object error) {
          if (mounted &&
              generation == _chatGeneration &&
              _auth.currentUser?.uid == uid) {
            setState(() => _messageError = messagingErrorMessage(error));
          }
        },
      );
      if (_conversationMoving) {
        throw FirebaseException(
          plugin: 'cloud_firestore',
          code: 'failed-precondition',
          message: 'Conversation migration is in progress',
        );
      }
      return FirebaseMessagingHelper()
          .getMessages(doc.id)
          .map(
            (messages) => messages
                .where((message) => !blocked.contains(message.senderId))
                .toList(),
          );
    }, clearItems: true);
  }

  void _onMessagesChanged() {
    if (!mounted) return;
    setState(() {
      _messages = _feed.items;
      _isLoading = _feed.loading;
      _messageError = _feed.error;
    });
    if (_messages.isEmpty || _messageError != null) return;
    final boundary = _messages.last.id;
    final uid = _auth.currentUser?.uid;
    if (uid == null || boundary == _lastReadId) return;
    // Mark only the snapshot rendered in this frame, never later arrivals.
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted ||
          _auth.currentUser?.uid != uid ||
          boundary == _lastReadId ||
          ModalRoute.of(context)?.isCurrent != true) {
        return;
      }
      if (_scrollController.hasClients) {
        _scrollController.jumpTo(_scrollController.position.maxScrollExtent);
        await WidgetsBinding.instance.endOfFrame;
      }
      if (!mounted ||
          _auth.currentUser?.uid != uid ||
          ModalRoute.of(context)?.isCurrent != true) {
        return;
      }
      _lastReadId = boundary;
      try {
        await FirebaseMessagingHelper().markMessagesAsRead(
          _resolvedConversationId ?? widget.conversationId,
          uid,
          lastMessageId: boundary,
        );
      } catch (error) {
        _lastReadId = null;
        Logger.error(
          'messaging_mark_read: ${error is FirebaseException ? error.code : error.runtimeType}',
        );
      }
    });
  }

  Future<void> _sendMessage() async {
    if (_isSending ||
        _conversationMoving ||
        _resolvedConversationId == null ||
        _messageController.text.trim().isEmpty) {
      return;
    }
    final uid = _auth.currentUser?.uid;
    if (uid == null) return;
    final content = _messageController.text.trim();
    if (content.length > 4000) {
      ShowToast().showSnackBar(
        'Messages can contain up to 4000 characters',
        context,
      );
      return;
    }
    if (_pendingContent != content) {
      _pendingContent = content;
      _pendingRequestId = _firestore.collection('Messages').doc().id;
    }
    setState(() => _isSending = true);
    try {
      await FirebaseMessagingHelper().sendMessage(
        content: content,
        conversationId: _resolvedConversationId!,
        requestId: _pendingRequestId,
      );
      if (!mounted || _auth.currentUser?.uid != uid) return;
      if (_messageController.text.trim() == content) _messageController.clear();
      _pendingContent = null;
      _pendingRequestId = null;
    } catch (error) {
      if (mounted && _auth.currentUser?.uid == uid) {
        ShowToast().showSnackBar(
          'Message not confirmed. Your text is still here; try again.',
          context,
        );
      }
      Logger.error(
        'messaging_send: ${error is FirebaseException ? error.code : error.runtimeType}',
      );
    } finally {
      if (mounted) setState(() => _isSending = false);
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
                      (_conversation?.participantIds
                                      .where((id) => id != currentUser?.uid)
                                      .every(
                                        (id) =>
                                            (_conversation?.readSequences[id] ??
                                                0) >=
                                            message.sequence,
                                      ) ==
                                  true &&
                              message.sequence > 0)
                          ? 'Read'
                          : 'Delivered',
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
      return const AttendUsLoadingState(label: 'Loading conversation...');
    }

    if (_messageError != null && _messages.isEmpty) {
      return Center(
        child: AttendUsEmptyState(
          icon: Icons.cloud_off_outlined,
          title: 'Messages unavailable',
          message: _messageError!,
          action: AttendUsButton.primary(
            label: 'Try again',
            icon: Icons.refresh,
            onPressed: _initializeChat,
          ),
        ),
      );
    }
    if (_messages.isEmpty) {
      return Center(
        child: AttendUsEmptyState(
          icon: Icons.chat_bubble_outline,
          title: 'No messages yet',
          message: 'Send the first message to start this conversation.',
        ),
      );
    }

    return Column(
      children: [
        if (_messageError != null)
          MaterialBanner(
            content: Text(_messageError!),
            actions: [
              TextButton(
                onPressed: _initializeChat,
                child: const Text('Try again'),
              ),
            ],
          ),
        Expanded(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 980),
              child: ListView.builder(
                controller: _scrollController,
                padding: EdgeInsets.only(
                  left: 12,
                  right: 12,
                  top: 10,
                  bottom: MediaQuery.of(context).padding.bottom + 96,
                ),
                itemCount: _messages.length,
                itemBuilder: (context, index) {
                  final message = _messages[index];
                  final showDateHeader = _shouldShowDateHeader(index);
                  return _buildMessageBubble(
                    message,
                    showDateHeader: showDateHeader,
                  );
                },
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildMessageInput() {
    final theme = Theme.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        border: Border(
          top: BorderSide(color: theme.colorScheme.outlineVariant),
        ),
      ),
      child: SafeArea(
        top: false,
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 980),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(
                    child: TextField(
                      controller: _messageController,
                      decoration: const InputDecoration(
                        hintText: 'Write a message',
                        prefixIcon: Icon(Icons.chat_bubble_outline),
                      ),
                      minLines: 1,
                      maxLines: 5,
                      textCapitalization: TextCapitalization.sentences,
                      onSubmitted: (_) => _isSending ? null : _sendMessage(),
                    ),
                  ),
                  const SizedBox(width: 10),
                  FilledButton(
                    onPressed: _isSending ? null : _sendMessage,
                    style: FilledButton.styleFrom(
                      minimumSize: const Size(48, 48),
                      padding: const EdgeInsets.symmetric(horizontal: 14),
                    ),
                    child: _isSending
                        ? const SizedBox.square(
                            dimension: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.send_rounded),
                  ),
                ],
              ),
            ),
          ),
        ),
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
                  padding: EdgeInsets.only(
                    left: 16,
                    right: 16,
                    bottom: MediaQuery.of(context).padding.bottom + 16,
                  ),
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
    final customerModel = CustomerModel.fromPublicProfile(memberInfo);

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) =>
            UserProfileScreen(user: customerModel, isOwnProfile: false),
      ),
    );
  }

  void _navigateToDirectMessageUserProfile(CustomerModel user) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) =>
            UserProfileScreen(user: user, isOwnProfile: false),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AppScaffoldWrapper(
      selectedBottomNavIndex: 2, // Messages tab
      appBar: AppBar(
        systemOverlayStyle: SystemUiOverlayStyle.dark,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded),
          onPressed: () => Navigator.pop(context),
          tooltip: 'Back',
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
    final otherId = _otherParticipant?.uid;

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
            AttendUsAvatar(
              imageUrl: _conversation?.groupAvatarUrl,
              name: name,
              fallbackIcon: Icons.groups_outlined,
              size: 40,
              tone: AttendUsStatusTone.success,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    name,
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    '${_conversation?.participantIds.length ?? 0} members',
                    style: TextStyle(
                      fontSize: 12,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                    overflow: TextOverflow.ellipsis,
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
    final user = _otherParticipant;
    if (user == null) return const SizedBox.shrink();
    return GestureDetector(
      onTap: () => _navigateToDirectMessageUserProfile(user),
      child: Row(
        children: [
          AttendUsAvatar(
            imageUrl: user.profilePictureUrl,
            name: user.name,
            size: 40,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  user.name,
                  style: Theme.of(
                    context,
                  ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
                  overflow: TextOverflow.ellipsis,
                ),
                if (user.username?.isNotEmpty == true)
                  Text(
                    '@${user.username}',
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
