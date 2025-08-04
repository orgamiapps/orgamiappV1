import 'dart:async';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:orgami/Models/MessageModel.dart';

import 'package:orgami/Firebase/FirebaseMessagingHelper.dart';
import 'package:orgami/Utils/Colors.dart';
import 'package:orgami/Utils/dimensions.dart';
import 'package:orgami/Utils/cached_image.dart';
import 'package:orgami/Screens/Messaging/ChatScreen.dart';
import 'package:orgami/Screens/Messaging/NewMessageScreen.dart';
import 'package:intl/intl.dart';

class MessagingScreen extends StatefulWidget {
  const MessagingScreen({super.key});

  @override
  State<MessagingScreen> createState() => _MessagingScreenState();
}

class _MessagingScreenState extends State<MessagingScreen> {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseMessagingHelper _messagingHelper = FirebaseMessagingHelper();
  List<ConversationModel> _conversations = [];
  List<ConversationModel> _filteredConversations = [];
  bool _isLoading = true;
  String? _errorMessage;
  Stream<List<ConversationModel>>? _conversationsStream;
  Timer? _timeoutTimer;
  final TextEditingController _searchController = TextEditingController();
  bool _isSearching = false;

  @override
  void initState() {
    super.initState();
    _loadConversations();
  }

  @override
  void dispose() {
    // Cancel any active streams and timers
    _conversationsStream = null;
    _timeoutTimer?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadConversations() async {
    try {
      final user = _auth.currentUser;
      if (user == null) {
        print('❌ No authenticated user found');
        setState(() {
          _isLoading = false;
          _errorMessage = 'Please log in to view messages';
        });
        return;
      }

      print('🔍 Loading conversations for user: ${user.uid}');

      // Create the stream
      _conversationsStream = _messagingHelper.getUserConversations(user.uid);

      // Set up timeout timer
      _timeoutTimer = Timer(const Duration(seconds: 10), () {
        if (_isLoading) {
          print('⏰ Timeout loading conversations');
          setState(() {
            _isLoading = false;
            _errorMessage =
                'Request timed out. Please check your connection and try again.';
          });
        }
      });

      // Listen to the stream with proper error handling
      _conversationsStream!.listen(
        (conversations) {
          _timeoutTimer?.cancel(); // Cancel timeout on success
          print('✅ Received ${conversations.length} conversations');
          setState(() {
            _conversations = conversations;
            _filteredConversations = conversations;
            _isLoading = false;
            _errorMessage = null;
          });
        },
        onError: (error) {
          _timeoutTimer?.cancel(); // Cancel timeout on error
          print('❌ Error loading conversations: $error');
          setState(() {
            _isLoading = false;
            _errorMessage = 'Failed to load messages. Please try again.';
          });
        },
      );
    } catch (e) {
      print('❌ Exception in _loadConversations: $e');
      setState(() {
        _isLoading = false;
        _errorMessage = 'An error occurred while loading messages';
      });
    }
  }

  Future<void> _retryLoading() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });
    await _loadConversations();
  }

  void _toggleSearch() {
    setState(() {
      _isSearching = !_isSearching;
      if (!_isSearching) {
        _searchController.clear();
        _filteredConversations = _conversations;
      }
    });
  }

  void _onSearchChanged(String query) {
    if (query.isEmpty) {
      setState(() {
        _filteredConversations = _conversations;
      });
      return;
    }

    final lowercaseQuery = query.toLowerCase();
    final filtered = _conversations.where((conversation) {
      final otherParticipantInfo = _getOtherParticipantInfo(conversation);
      final name = otherParticipantInfo['name']?.toString().toLowerCase() ?? '';
      final username =
          otherParticipantInfo['username']?.toString().toLowerCase() ?? '';
      final lastMessage = conversation.lastMessage.toLowerCase();

      return name.contains(lowercaseQuery) ||
          username.contains(lowercaseQuery) ||
          lastMessage.contains(lowercaseQuery);
    }).toList();

    setState(() {
      _filteredConversations = filtered;
    });
  }

  String _getOtherParticipantId(ConversationModel conversation) {
    final currentUserId = _auth.currentUser?.uid;
    if (currentUserId == null) return '';

    try {
      return conversation.participant1Id == currentUserId
          ? conversation.participant2Id
          : conversation.participant1Id;
    } catch (e) {
      print('❌ Error getting other participant ID: $e');
      return '';
    }
  }

  Map<String, dynamic> _getOtherParticipantInfo(
    ConversationModel conversation,
  ) {
    try {
      final otherId = _getOtherParticipantId(conversation);
      return conversation.participantInfo[otherId] ?? {};
    } catch (e) {
      print('❌ Error getting other participant info: $e');
      return {};
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppThemeColor.backGroundColor,
      appBar: AppBar(
        title: const Text(
          'Messages',
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
            fontSize: 20,
          ),
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
        actions: [
          IconButton(
            icon: Icon(_isSearching ? Icons.close : Icons.search),
            onPressed: _isSearching ? _toggleSearch : _toggleSearch,
          ),
        ],
      ),
      body: Column(
        children: [
          if (_isSearching) _buildSearchBar(),
          Expanded(child: _buildBody()),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (context) => const NewMessageScreen()),
          );
        },
        backgroundColor: AppThemeColor.darkBlueColor,
        child: const Icon(Icons.message, color: Colors.white),
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
              onPressed: _retryLoading,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppThemeColor.darkBlueColor,
                padding: const EdgeInsets.symmetric(
                  horizontal: 32,
                  vertical: 12,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(Dimensions.radiusLarge),
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

    if (_filteredConversations.isEmpty) {
      return _buildEmptyState();
    }

    return _buildConversationsList();
  }

  Widget _buildEmptyState() {
    final isSearching = _isSearching && _searchController.text.isNotEmpty;

    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            isSearching ? Icons.search_off : Icons.message_outlined,
            size: 80,
            color: AppThemeColor.dullFontColor.withValues(alpha: 0.5),
          ),
          const SizedBox(height: 16),
          Text(
            isSearching ? 'No conversations found' : 'No messages yet',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w600,
              color: AppThemeColor.darkBlueColor,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            isSearching
                ? 'Try adjusting your search terms or start a new conversation'
                : 'Start a conversation with other users',
            style: TextStyle(fontSize: 16, color: AppThemeColor.dullFontColor),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 24),
          if (!isSearching)
            ElevatedButton(
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const NewMessageScreen(),
                  ),
                );
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: AppThemeColor.darkBlueColor,
                padding: const EdgeInsets.symmetric(
                  horizontal: 32,
                  vertical: 12,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(Dimensions.radiusLarge),
                ),
              ),
              child: const Text(
                'Start Messaging',
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

  Widget _buildSearchBar() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: TextField(
        controller: _searchController,
        onChanged: _onSearchChanged,
        decoration: InputDecoration(
          hintText: 'Search conversations...',
          prefixIcon: const Icon(
            Icons.search,
            color: AppThemeColor.dullFontColor,
          ),
          suffixIcon: _searchController.text.isNotEmpty
              ? IconButton(
                  icon: const Icon(
                    Icons.clear,
                    color: AppThemeColor.dullFontColor,
                  ),
                  onPressed: () {
                    _searchController.clear();
                    _onSearchChanged('');
                  },
                )
              : null,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(Dimensions.radiusLarge),
            borderSide: BorderSide(color: AppThemeColor.lightBlueColor),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(Dimensions.radiusLarge),
            borderSide: BorderSide(
              color: AppThemeColor.darkBlueColor,
              width: 2,
            ),
          ),
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 12,
          ),
        ),
      ),
    );
  }

  Widget _buildConversationsList() {
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _filteredConversations.length,
      itemBuilder: (context, index) {
        final conversation = _filteredConversations[index];
        final otherParticipantInfo = _getOtherParticipantInfo(conversation);

        return _buildConversationTile(conversation, otherParticipantInfo);
      },
    );
  }

  Widget _buildConversationTile(
    ConversationModel conversation,
    Map<String, dynamic> otherParticipantInfo,
  ) {
    final name = otherParticipantInfo['name'] ?? 'Unknown User';
    final profilePictureUrl = otherParticipantInfo['profilePictureUrl'];
    final username = otherParticipantInfo['username'];
    final hasUnread = conversation.unreadCount > 0;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(Dimensions.radiusLarge),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.all(16),
        leading: CircleAvatar(
          radius: 25,
          backgroundColor: AppThemeColor.lightBlueColor,
          child: profilePictureUrl != null
              ? ClipOval(
                  child: SafeNetworkImage(
                    imageUrl: profilePictureUrl,
                    fit: BoxFit.cover,
                    placeholder: const Icon(
                      Icons.person,
                      color: AppThemeColor.darkBlueColor,
                    ),
                    errorWidget: const Icon(
                      Icons.person,
                      color: AppThemeColor.darkBlueColor,
                    ),
                  ),
                )
              : const Icon(Icons.person, color: AppThemeColor.darkBlueColor),
        ),
        title: Row(
          children: [
            Expanded(
              child: Text(
                name,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: hasUnread ? FontWeight.w600 : FontWeight.w500,
                  color: hasUnread
                      ? AppThemeColor.darkBlueColor
                      : Colors.black87,
                ),
              ),
            ),
            if (hasUnread)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: AppThemeColor.darkBlueColor,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  conversation.unreadCount.toString(),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
          ],
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (username != null) ...[
              Text(
                '@$username',
                style: TextStyle(
                  fontSize: 14,
                  color: AppThemeColor.dullFontColor,
                ),
              ),
              const SizedBox(height: 4),
            ],
            Text(
              conversation.lastMessage,
              style: TextStyle(
                fontSize: 14,
                color: hasUnread
                    ? AppThemeColor.darkBlueColor
                    : AppThemeColor.dullFontColor,
                fontWeight: hasUnread ? FontWeight.w500 : FontWeight.normal,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 4),
            Text(
              DateFormat('MMM d, h:mm a').format(conversation.lastMessageTime),
              style: TextStyle(
                fontSize: 12,
                color: AppThemeColor.dullFontColor,
              ),
            ),
          ],
        ),
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => ChatScreen(
                conversationId: conversation.id,
                otherParticipantInfo: otherParticipantInfo,
              ),
            ),
          );
        },
      ),
    );
  }
}
