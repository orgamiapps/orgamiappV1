import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:orgami/Models/MessageModel.dart';
import 'package:orgami/Firebase/FirebaseMessagingHelper.dart';
import 'package:orgami/Utils/cached_image.dart';
import 'package:orgami/Utils/Toast.dart';
import 'package:orgami/Utils/ThemeProvider.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';

class ChatScreen extends StatefulWidget {
  final String conversationId;
  final Map<String, dynamic> otherParticipantInfo;

  const ChatScreen({
    super.key,
    required this.conversationId,
    required this.otherParticipantInfo,
  });

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseMessagingHelper _messagingHelper = FirebaseMessagingHelper();
  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final FocusNode _focusNode = FocusNode();

  List<MessageModel> _messages = [];
  bool _isLoading = true;
  bool _isSending = false;
  String? _errorMessage;
  Set<String> _sendingMessageIds = {}; // Track messages being sent
  Set<String> _failedMessageIds = {}; // Track failed messages

  @override
  void initState() {
    super.initState();
    _ensureConversationExists();
    _loadMessages();
    _markMessagesAsRead();

    // Listen for focus changes to show/hide keyboard
    _focusNode.addListener(() {
      if (_focusNode.hasFocus) {
        _scrollToBottom();
      }
    });

    // Listen for text changes to update send button state
    _messageController.addListener(() {
      setState(() {});
    });
  }

  Future<void> _ensureConversationExists() async {
    try {
      final currentUser = _auth.currentUser;
      if (currentUser == null) return;

      final participants = widget.conversationId.split('_');
      final otherUserId = participants.firstWhere(
        (id) => id != currentUser.uid,
      );

      // Check if conversation exists
      final conversationId = await _messagingHelper.getConversationId(
        currentUser.uid,
        otherUserId,
      );

      if (conversationId == null) {
        print('🔧 Creating conversation ${widget.conversationId}');
        await _messagingHelper.createConversation(
          userId: currentUser.uid,
          otherUserId: otherUserId,
          otherUserInfo: widget.otherParticipantInfo,
        );
      }
    } catch (e) {
      print('❌ Error ensuring conversation exists: $e');
    }
  }

  Future<void> _sendTestMessage() async {
    try {
      final currentUser = _auth.currentUser;
      if (currentUser == null) return;

      final participants = widget.conversationId.split('_');
      final receiverId = participants.firstWhere((id) => id != currentUser.uid);

      print('🧪 Sending test message to $receiverId');

      await _messagingHelper.sendMessage(
        receiverId: receiverId,
        content: 'Test message at ${DateTime.now()}',
      );

      print('✅ Test message sent successfully');
      if (mounted) {
        ShowToast().showSnackBar('Test message sent!', context);
      }
    } catch (e) {
      print('❌ Error sending test message: $e');
      if (mounted) {
        ShowToast().showSnackBar('Error sending test message', context);
      }
    }
  }

  @override
  void dispose() {
    _messageController.dispose();
    _scrollController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  Future<void> _loadMessages() async {
    try {
      final currentUser = _auth.currentUser;
      if (currentUser == null) {
        setState(() {
          _isLoading = false;
          _errorMessage = 'Please log in to view messages';
        });
        return;
      }

      print('🔍 Loading messages for conversation: ${widget.conversationId}');
      print('🔍 Current user: ${currentUser.uid}');
      print('🔍 Other participant: ${widget.otherParticipantInfo}');

      _messagingHelper
          .getMessages(widget.conversationId)
          .listen(
            (messages) {
              print('✅ Received ${messages.length} messages');
              print(
                '📝 Messages: ${messages.map((m) => '${m.senderId}: ${m.content}').join(', ')}',
              );

              // Find optimistic messages that should be replaced by real messages
              final optimisticMessages = _messages
                  .where((msg) => _sendingMessageIds.contains(msg.id))
                  .toList();

              // Remove optimistic messages that have been replaced by real messages
              // (messages with same content and sender from the last 30 seconds)
              final now = DateTime.now();
              final recentMessages = messages
                  .where(
                    (msg) =>
                        msg.senderId == _auth.currentUser?.uid &&
                        now.difference(msg.timestamp).inSeconds < 30,
                  )
                  .toList();

              // Remove optimistic messages that match recent real messages
              final messagesToKeep = optimisticMessages.where((optimisticMsg) {
                return !recentMessages.any(
                  (realMsg) =>
                      realMsg.content == optimisticMsg.content &&
                      realMsg.senderId == optimisticMsg.senderId,
                );
              }).toList();

              setState(() {
                // Combine real messages with remaining optimistic messages
                _messages = [...messages, ...messagesToKeep];
                // Sort by timestamp to maintain correct order
                _messages.sort((a, b) => a.timestamp.compareTo(b.timestamp));
                _isLoading = false;
                _errorMessage = null;
              });

              // Scroll to bottom when new messages arrive
              WidgetsBinding.instance.addPostFrameCallback((_) {
                _scrollToBottom();
              });
            },
            onError: (error) {
              print('❌ Error loading messages: $error');
              // Check if this is a new conversation (no conversation document exists)
              if (error.toString().contains('permission-denied') ||
                  error.toString().contains('not-found')) {
                // This is likely a new conversation, show empty state instead of error
                setState(() {
                  _messages = [];
                  _isLoading = false;
                  _errorMessage = null;
                });
              } else {
                setState(() {
                  _isLoading = false;
                  _errorMessage = 'Failed to load messages. Please try again.';
                });
              }
            },
          );
    } catch (e) {
      print('❌ Exception in _loadMessages: $e');
      // Check if this is a new conversation
      if (e.toString().contains('permission-denied') ||
          e.toString().contains('not-found')) {
        setState(() {
          _messages = [];
          _isLoading = false;
          _errorMessage = null;
        });
      } else {
        setState(() {
          _isLoading = false;
          _errorMessage = 'An error occurred while loading messages';
        });
      }
    }
  }

  Future<void> _markMessagesAsRead() async {
    try {
      final currentUser = _auth.currentUser;
      if (currentUser == null) return;

      await _messagingHelper.markMessagesAsRead(
        widget.conversationId,
        currentUser.uid,
      );
    } catch (e) {
      print('Error marking messages as read: $e');
    }
  }

  Future<void> _sendMessage() async {
    final message = _messageController.text.trim();
    if (message.isEmpty) return;

    final currentUser = _auth.currentUser;
    if (currentUser == null) return;

    final participants = widget.conversationId.split('_');
    final receiverId = participants.firstWhere((id) => id != currentUser.uid);

    // Create optimistic message
    final optimisticMessage = MessageModel(
      id: 'temp_${DateTime.now().millisecondsSinceEpoch}',
      senderId: currentUser.uid,
      receiverId: receiverId,
      content: message,
      timestamp: DateTime.now(),
      isRead: false,
      messageType: 'text',
      mediaUrl: null,
      fileName: null,
    );

    // Optimistically add message to UI immediately
    setState(() {
      _messages.add(optimisticMessage);
      _isSending = true;
      _sendingMessageIds.add(optimisticMessage.id);
    });

    // Clear input and scroll to bottom immediately
    _messageController.clear();
    _scrollToBottom();

    try {
      print('📤 Sending message to $receiverId: $message');
      print('📤 Conversation ID: ${widget.conversationId}');

      // Send message to Firestore in background
      await _messagingHelper.sendMessage(
        receiverId: receiverId,
        content: message,
      );

      print('✅ Message sent successfully');

      // The optimistic message will be replaced by the real message from the stream
      // We don't need to remove it here as the stream listener will handle it
    } catch (e) {
      print('❌ Error sending message: $e');
      if (mounted) {
        ShowToast().showSnackBar('Error sending message', context);
      }

      // Mark the message as failed instead of removing it
      setState(() {
        _sendingMessageIds.remove(optimisticMessage.id);
        _failedMessageIds.add(optimisticMessage.id);
      });
    } finally {
      setState(() {
        _isSending = false;
      });
    }
  }

  void _scrollToBottom() {
    if (_scrollController.hasClients) {
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    }
  }

  bool _isCurrentUserMessage(MessageModel message) {
    final currentUser = _auth.currentUser;
    return currentUser?.uid == message.senderId;
  }

  bool _shouldShowDate(int index) {
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

    return currentDate != previousDate;
  }

  bool _shouldShowAvatar(int index) {
    if (index == _messages.length - 1) return true;

    final currentMessage = _messages[index];
    final nextMessage = _messages[index + 1];

    // Show avatar if next message is from different user or if there's a time gap
    if (_isCurrentUserMessage(currentMessage) !=
        _isCurrentUserMessage(nextMessage)) {
      return true;
    }

    // Show avatar if there's more than 5 minutes gap
    final timeDiff = nextMessage.timestamp.difference(currentMessage.timestamp);
    return timeDiff.inMinutes > 5;
  }

  @override
  Widget build(BuildContext context) {
    final themeProvider = Provider.of<ThemeProvider>(context);
    final isDark = themeProvider.isDarkMode;

    final otherName = widget.otherParticipantInfo['name'] ?? 'Unknown User';
    final otherProfilePictureUrl =
        widget.otherParticipantInfo['profilePictureUrl'];
    final otherUsername = widget.otherParticipantInfo['username'];

    return Scaffold(
      backgroundColor: isDark
          ? const Color(0xFF000000)
          : const Color(0xFFF2F2F7),
      appBar: AppBar(
        backgroundColor: isDark ? const Color(0xFF1C1C1E) : Colors.white,
        elevation: 0,
        shadowColor: Colors.transparent,
        leading: IconButton(
          icon: Icon(
            Icons.arrow_back_ios,
            color: isDark ? Colors.white : Colors.black,
            size: 20,
          ),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: isDark
                    ? const Color(0xFF2C2C2E)
                    : const Color(0xFFE5E5EA),
              ),
              child: otherProfilePictureUrl != null
                  ? ClipOval(
                      child: SafeNetworkImage(
                        imageUrl: otherProfilePictureUrl,
                        fit: BoxFit.cover,
                        placeholder: Icon(
                          Icons.person,
                          color: isDark ? Colors.white70 : Colors.black54,
                          size: 20,
                        ),
                        errorWidget: Icon(
                          Icons.person,
                          color: isDark ? Colors.white70 : Colors.black54,
                          size: 20,
                        ),
                      ),
                    )
                  : Icon(
                      Icons.person,
                      color: isDark ? Colors.white70 : Colors.black54,
                      size: 20,
                    ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    otherName,
                    style: TextStyle(
                      color: isDark ? Colors.white : Colors.black,
                      fontWeight: FontWeight.w600,
                      fontSize: 17,
                    ),
                  ),
                  if (otherUsername != null)
                    Text(
                      '@$otherUsername',
                      style: TextStyle(
                        color: isDark ? Colors.white60 : Colors.black54,
                        fontSize: 13,
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: Icon(
              Icons.bug_report,
              color: isDark ? Colors.white : Colors.black,
              size: 20,
            ),
            onPressed: () {
              _sendTestMessage();
            },
          ),
          IconButton(
            icon: Icon(
              Icons.more_vert,
              color: isDark ? Colors.white : Colors.black,
              size: 20,
            ),
            onPressed: () {
              // TODO: Show more options
            },
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(child: _buildBody()),
          _buildMessageInput(),
        ],
      ),
    );
  }

  Widget _buildBody() {
    final themeProvider = Provider.of<ThemeProvider>(context);
    final isDark = themeProvider.isDarkMode;

    if (_isLoading) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(
              color: isDark ? Colors.white : const Color(0xFF007AFF),
            ),
            const SizedBox(height: 16),
            Text(
              'Loading messages...',
              style: TextStyle(
                color: isDark ? Colors.white70 : Colors.black54,
                fontSize: 16,
              ),
            ),
          ],
        ),
      );
    }

    if (_errorMessage != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.error_outline,
              size: 80,
              color: isDark ? Colors.white38 : Colors.black38,
            ),
            const SizedBox(height: 16),
            Text(
              'Oops!',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w600,
                color: isDark ? Colors.white : Colors.black,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              _errorMessage!,
              style: TextStyle(
                fontSize: 16,
                color: isDark ? Colors.white70 : Colors.black54,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: () {
                setState(() {
                  _isLoading = true;
                  _errorMessage = null;
                });
                _loadMessages();
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF007AFF),
                padding: const EdgeInsets.symmetric(
                  horizontal: 32,
                  vertical: 12,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              child: const Text(
                'Try Again',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      );
    }

    if (_messages.isEmpty) {
      return _buildEmptyState();
    }

    return _buildMessagesList();
  }

  Widget _buildEmptyState() {
    final themeProvider = Provider.of<ThemeProvider>(context);
    final isDark = themeProvider.isDarkMode;
    final otherName = widget.otherParticipantInfo['name'] ?? 'this person';

    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                color: isDark
                    ? const Color(0xFF2C2C2E)
                    : const Color(0xFFE5E5EA),
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.chat_bubble_outline,
                size: 40,
                color: isDark ? Colors.white54 : Colors.black54,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'Start a conversation',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w600,
                color: isDark ? Colors.white : Colors.black,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'No messages yet with $otherName.\nSend your first message to begin chatting!',
              style: TextStyle(
                fontSize: 16,
                color: isDark ? Colors.white70 : Colors.black54,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: isDark
                    ? const Color(0xFF2C2C2E)
                    : const Color(0xFFF2F2F7),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.lightbulb_outline,
                    color: const Color(0xFF007AFF),
                    size: 20,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Tip: Type your message below and tap send',
                      style: TextStyle(
                        fontSize: 14,
                        color: isDark ? Colors.white70 : Colors.black54,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMessagesList() {
    return ListView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      itemCount: _messages.length,
      itemBuilder: (context, index) {
        final message = _messages[index];
        return Column(
          children: [
            if (_shouldShowDate(index)) _buildDateDivider(message.timestamp),
            _buildMessageBubble(message, index),
          ],
        );
      },
    );
  }

  Widget _buildDateDivider(DateTime date) {
    final themeProvider = Provider.of<ThemeProvider>(context);
    final isDark = themeProvider.isDarkMode;

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 16),
      child: Row(
        children: [
          Expanded(
            child: Divider(color: isDark ? Colors.white24 : Colors.black12),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Text(
              _formatDate(date),
              style: TextStyle(
                fontSize: 12,
                color: isDark ? Colors.white54 : Colors.black54,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          Expanded(
            child: Divider(color: isDark ? Colors.white24 : Colors.black12),
          ),
        ],
      ),
    );
  }

  String _formatDate(DateTime date) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = today.subtract(const Duration(days: 1));
    final messageDate = DateTime(date.year, date.month, date.day);

    if (messageDate == today) {
      return 'Today';
    } else if (messageDate == yesterday) {
      return 'Yesterday';
    } else {
      return DateFormat('MMM d, y').format(date);
    }
  }

  Widget _buildMessageBubble(MessageModel message, int index) {
    final themeProvider = Provider.of<ThemeProvider>(context);
    final isDark = themeProvider.isDarkMode;
    final isCurrentUser = _isCurrentUserMessage(message);
    final showAvatar = !isCurrentUser && _shouldShowAvatar(index);
    final isFailed = _failedMessageIds.contains(message.id);

    return Container(
      margin: EdgeInsets.only(
        bottom: 8,
        left: isCurrentUser ? 60 : 0,
        right: isCurrentUser ? 0 : 60,
      ),
      child: GestureDetector(
        onTap: isFailed && isCurrentUser ? () => _retryMessage(message) : null,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          mainAxisAlignment: isCurrentUser
              ? MainAxisAlignment.end
              : MainAxisAlignment.start,
          children: [
            if (!isCurrentUser && showAvatar) ...[
              Container(
                width: 32,
                height: 32,
                margin: const EdgeInsets.only(right: 8),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: isDark
                      ? const Color(0xFF2C2C2E)
                      : const Color(0xFFE5E5EA),
                ),
                child: widget.otherParticipantInfo['profilePictureUrl'] != null
                    ? ClipOval(
                        child: SafeNetworkImage(
                          imageUrl:
                              widget.otherParticipantInfo['profilePictureUrl'],
                          fit: BoxFit.cover,
                          placeholder: Icon(
                            Icons.person,
                            color: isDark ? Colors.white70 : Colors.black54,
                            size: 16,
                          ),
                          errorWidget: Icon(
                            Icons.person,
                            color: isDark ? Colors.white70 : Colors.black54,
                            size: 16,
                          ),
                        ),
                      )
                    : Icon(
                        Icons.person,
                        color: isDark ? Colors.white70 : Colors.black54,
                        size: 16,
                      ),
              ),
            ] else if (!isCurrentUser) ...[
              const SizedBox(width: 40), // Space for avatar
            ],
            Flexible(
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: isCurrentUser
                      ? const Color(0xFF007AFF)
                      : (isDark ? const Color(0xFF2C2C2E) : Colors.white),
                  borderRadius: BorderRadius.circular(20).copyWith(
                    bottomLeft: isCurrentUser
                        ? const Radius.circular(20)
                        : const Radius.circular(4),
                    bottomRight: isCurrentUser
                        ? const Radius.circular(4)
                        : const Radius.circular(20),
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: isDark
                          ? Colors.black12
                          : Colors.black.withValues(alpha: 0.08),
                      blurRadius: 2,
                      offset: const Offset(0, 1),
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      message.content,
                      style: TextStyle(
                        fontSize: 16,
                        color: isCurrentUser
                            ? Colors.white
                            : (isDark ? Colors.white : Colors.black),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          DateFormat('h:mm a').format(message.timestamp),
                          style: TextStyle(
                            fontSize: 11,
                            color: isCurrentUser
                                ? Colors.white70
                                : (isDark ? Colors.white54 : Colors.black54),
                          ),
                        ),
                        if (isCurrentUser) ...[
                          const SizedBox(width: 4),
                          if (_sendingMessageIds.contains(message.id)) ...[
                            SizedBox(
                              width: 14,
                              height: 14,
                              child: CircularProgressIndicator(
                                strokeWidth: 1.5,
                                valueColor: AlwaysStoppedAnimation<Color>(
                                  Colors.white54,
                                ),
                              ),
                            ),
                          ] else if (_failedMessageIds.contains(
                            message.id,
                          )) ...[
                            Icon(
                              Icons.error_outline,
                              size: 14,
                              color: Colors.red[300],
                            ),
                          ] else ...[
                            Icon(
                              message.isRead ? Icons.done_all : Icons.done,
                              size: 14,
                              color: message.isRead
                                  ? Colors.white70
                                  : Colors.white54,
                            ),
                          ],
                        ],
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMessageInput() {
    final themeProvider = Provider.of<ThemeProvider>(context);
    final isDark = themeProvider.isDarkMode;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1C1C1E) : Colors.white,
        border: Border(
          top: BorderSide(
            color: isDark
                ? Colors.white12
                : Colors.black.withValues(alpha: 0.08),
            width: 0.5,
          ),
        ),
      ),
      child: SafeArea(
        child: Row(
          children: [
            Expanded(
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
                decoration: BoxDecoration(
                  color: isDark
                      ? const Color(0xFF2C2C2E)
                      : const Color(0xFFF2F2F7),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: TextField(
                  controller: _messageController,
                  focusNode: _focusNode,
                  style: TextStyle(
                    color: isDark ? Colors.white : Colors.black,
                    fontSize: 16,
                  ),
                  decoration: InputDecoration(
                    hintText: 'iMessage',
                    hintStyle: TextStyle(
                      color: isDark ? Colors.white54 : Colors.black54,
                      fontSize: 16,
                    ),
                    border: InputBorder.none,
                    contentPadding: EdgeInsets.zero,
                  ),
                  maxLines: null,
                  textCapitalization: TextCapitalization.sentences,
                  onSubmitted: (_) => _sendMessage(),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: _messageController.text.trim().isNotEmpty
                    ? const Color(0xFF007AFF)
                    : (isDark
                          ? const Color(0xFF2C2C2E)
                          : const Color(0xFFF2F2F7)),
                borderRadius: BorderRadius.circular(20),
              ),
              child: IconButton(
                onPressed:
                    _messageController.text.trim().isNotEmpty && !_isSending
                    ? _sendMessage
                    : null,
                icon: _isSending
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          color: Colors.white,
                          strokeWidth: 2,
                        ),
                      )
                    : Icon(
                        Icons.send,
                        color: _messageController.text.trim().isNotEmpty
                            ? Colors.white
                            : (isDark ? Colors.white54 : Colors.black54),
                        size: 18,
                      ),
                padding: EdgeInsets.zero,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _retryMessage(MessageModel message) async {
    // Remove from failed messages
    setState(() {
      _failedMessageIds.remove(message.id);
      _sendingMessageIds.add(message.id);
    });

    try {
      final currentUser = _auth.currentUser;
      if (currentUser == null) return;

      final participants = widget.conversationId.split('_');
      final receiverId = participants.firstWhere((id) => id != currentUser.uid);

      await _messagingHelper.sendMessage(
        receiverId: receiverId,
        content: message.content,
      );

      // Remove the optimistic message - it will be replaced by the real message from stream
      setState(() {
        _sendingMessageIds.remove(message.id);
      });
    } catch (e) {
      print('❌ Error retrying message: $e');
      if (mounted) {
        ShowToast().showSnackBar('Error retrying message', context);
      }

      // Mark as failed again
      setState(() {
        _sendingMessageIds.remove(message.id);
        _failedMessageIds.add(message.id);
      });
    }
  }
}
