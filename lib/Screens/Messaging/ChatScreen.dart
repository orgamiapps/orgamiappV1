import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:orgami/Models/MessageModel.dart';
import 'package:orgami/Firebase/FirebaseMessagingHelper.dart';
import 'package:orgami/Utils/Colors.dart';

import 'package:orgami/Utils/cached_image.dart';
import 'package:orgami/Utils/Toast.dart';
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

  List<MessageModel> _messages = [];
  bool _isLoading = true;
  bool _isSending = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _loadMessages();
    _markMessagesAsRead();
  }

  @override
  void dispose() {
    _messageController.dispose();
    _scrollController.dispose();
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

      _messagingHelper
          .getMessages(widget.conversationId)
          .listen(
            (messages) {
              print('✅ Received ${messages.length} messages');
              setState(() {
                _messages = messages;
                _isLoading = false;
                _errorMessage = null;
              });

              // Scroll to bottom when new messages arrive
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (_scrollController.hasClients) {
                  _scrollController.animateTo(
                    _scrollController.position.maxScrollExtent,
                    duration: const Duration(milliseconds: 300),
                    curve: Curves.easeOut,
                  );
                }
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

    setState(() {
      _isSending = true;
    });

    try {
      final currentUser = _auth.currentUser;
      if (currentUser == null) return;

      final participants = widget.conversationId.split('_');
      final receiverId = participants.firstWhere((id) => id != currentUser.uid);

      await _messagingHelper.sendMessage(
        receiverId: receiverId,
        content: message,
      );

      _messageController.clear();
    } catch (e) {
      print('Error sending message: $e');
      ShowToast().showSnackBar('Error sending message', context);
    } finally {
      setState(() {
        _isSending = false;
      });
    }
  }

  bool _isCurrentUserMessage(MessageModel message) {
    final currentUser = _auth.currentUser;
    return currentUser?.uid == message.senderId;
  }

  @override
  Widget build(BuildContext context) {
    final otherName = widget.otherParticipantInfo['name'] ?? 'Unknown User';
    final otherProfilePictureUrl =
        widget.otherParticipantInfo['profilePictureUrl'];
    final otherUsername = widget.otherParticipantInfo['username'];

    return Scaffold(
      backgroundColor: AppThemeColor.backGroundColor,
      appBar: AppBar(
        title: Row(
          children: [
            CircleAvatar(
              radius: 18,
              backgroundColor: AppThemeColor.lightBlueColor,
              child: otherProfilePictureUrl != null
                  ? ClipOval(
                      child: SafeNetworkImage(
                        imageUrl: otherProfilePictureUrl,
                        fit: BoxFit.cover,
                        placeholder: const Icon(
                          Icons.person,
                          color: AppThemeColor.darkBlueColor,
                          size: 18,
                        ),
                        errorWidget: const Icon(
                          Icons.person,
                          color: AppThemeColor.darkBlueColor,
                          size: 18,
                        ),
                      ),
                    )
                  : const Icon(
                      Icons.person,
                      color: AppThemeColor.darkBlueColor,
                      size: 18,
                    ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    otherName,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                  if (otherUsername != null)
                    Text(
                      '@$otherUsername',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.8),
                        fontSize: 12,
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
        flexibleSpace: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                AppThemeColor.darkBlueColor,
                AppThemeColor.dullBlueColor,
                Color(0xFF4A90E2),
              ],
            ),
          ),
        ),
        iconTheme: const IconThemeData(color: Colors.white),
        elevation: 0,
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
    if (_isLoading) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(color: AppThemeColor.darkBlueColor),
            SizedBox(height: 16),
            Text(
              'Loading messages...',
              style: TextStyle(
                color: AppThemeColor.dullFontColor,
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
              color: AppThemeColor.dullFontColor.withValues(alpha: 0.5),
            ),
            const SizedBox(height: 16),
            Text(
              'Oops!',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w600,
                color: AppThemeColor.darkBlueColor,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              _errorMessage!,
              style: TextStyle(
                fontSize: 16,
                color: AppThemeColor.dullFontColor,
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
                backgroundColor: AppThemeColor.darkBlueColor,
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
    final otherName = widget.otherParticipantInfo['name'] ?? 'this person';

    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.chat_bubble_outline,
              size: 80,
              color: AppThemeColor.dullFontColor.withValues(alpha: 0.5),
            ),
            const SizedBox(height: 16),
            Text(
              'Start a conversation',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w600,
                color: AppThemeColor.darkBlueColor,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'No messages yet with $otherName.\nSend your first message to begin chatting!',
              style: TextStyle(fontSize: 16, color: AppThemeColor.dullFontColor),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppThemeColor.lightBlueColor.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: AppThemeColor.lightBlueColor.withValues(alpha: 0.3),
                  width: 1,
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.lightbulb_outline,
                    color: AppThemeColor.darkBlueColor,
                    size: 20,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Tip: Type your message below and tap send',
                      style: TextStyle(
                        fontSize: 14,
                        color: AppThemeColor.darkBlueColor,
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
      padding: const EdgeInsets.all(16),
      itemCount: _messages.length,
      itemBuilder: (context, index) {
        final message = _messages[index];
        return _buildMessageBubble(message);
      },
    );
  }

  Widget _buildMessageBubble(MessageModel message) {
    final isCurrentUser = _isCurrentUserMessage(message);

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      child: Row(
        mainAxisAlignment: isCurrentUser
            ? MainAxisAlignment.end
            : MainAxisAlignment.start,
        children: [
          if (!isCurrentUser) ...[
            CircleAvatar(
              radius: 16,
              backgroundColor: AppThemeColor.lightBlueColor,
              child: widget.otherParticipantInfo['profilePictureUrl'] != null
                  ? ClipOval(
                      child: SafeNetworkImage(
                        imageUrl:
                            widget.otherParticipantInfo['profilePictureUrl'],
                        fit: BoxFit.cover,
                        placeholder: const Icon(
                          Icons.person,
                          color: AppThemeColor.darkBlueColor,
                          size: 16,
                        ),
                        errorWidget: const Icon(
                          Icons.person,
                          color: AppThemeColor.darkBlueColor,
                          size: 16,
                        ),
                      ),
                    )
                  : const Icon(
                      Icons.person,
                      color: AppThemeColor.darkBlueColor,
                      size: 16,
                    ),
            ),
            const SizedBox(width: 8),
          ],
          Flexible(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: isCurrentUser
                    ? AppThemeColor.darkBlueColor
                    : Colors.white,
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.05),
                    blurRadius: 5,
                    offset: const Offset(0, 2),
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
                      color: isCurrentUser ? Colors.white : Colors.black87,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    DateFormat('h:mm a').format(message.timestamp),
                    style: TextStyle(
                      fontSize: 12,
                      color: isCurrentUser
                          ? Colors.white.withValues(alpha: 0.7)
                          : AppThemeColor.dullFontColor,
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (isCurrentUser) ...[
            const SizedBox(width: 8),
            Icon(
              message.isRead ? Icons.done_all : Icons.done,
              size: 16,
              color: message.isRead
                  ? Colors.white
                  : Colors.white.withValues(alpha: 0.7),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildMessageInput() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: Row(
        children: [
          Expanded(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: AppThemeColor.backGroundColor,
                borderRadius: BorderRadius.circular(25),
                border: Border.all(color: AppThemeColor.borderColor),
              ),
              child: TextField(
                controller: _messageController,
                decoration: InputDecoration(
                  hintText: 'Type a message...',
                  hintStyle: TextStyle(
                    color: AppThemeColor.dullFontColor,
                    fontSize: 16,
                  ),
                  border: InputBorder.none,
                ),
                style: const TextStyle(fontSize: 16),
                maxLines: null,
                textCapitalization: TextCapitalization.sentences,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Container(
            decoration: BoxDecoration(
              color: AppThemeColor.darkBlueColor,
              borderRadius: BorderRadius.circular(25),
            ),
            child: IconButton(
              onPressed: _isSending ? null : _sendMessage,
              icon: _isSending
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        color: Colors.white,
                        strokeWidth: 2,
                      ),
                    )
                  : const Icon(Icons.send, color: Colors.white),
            ),
          ),
        ],
      ),
    );
  }
}
