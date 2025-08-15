import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:orgami/models/message_model.dart';
import 'package:provider/provider.dart';

import 'package:orgami/firebase/firebase_messaging_helper.dart';
import 'package:orgami/Utils/colors.dart';
import 'package:orgami/Utils/dimensions.dart';
import 'package:orgami/Utils/cached_image.dart';
import 'package:orgami/Utils/theme_provider.dart';
import 'package:orgami/screens/Messaging/chat_screen.dart';
import 'package:orgami/screens/Messaging/new_message_screen.dart';
import 'package:intl/intl.dart';
import 'package:orgami/models/customer_model.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:orgami/Utils/logger.dart';
import 'package:orgami/firebase/firebase_firestore_helper.dart';

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
  final Map<String, Map<String, dynamic>> _userInfoCache = {};
  Set<String> _blockedUserIds = <String>{};

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
        Logger.error('No authenticated user found');
        setState(() {
          _isLoading = false;
          _errorMessage = 'Please log in to view messages';
        });
        return;
      }

      Logger.info('Loading conversations for user: ${user.uid}');

      // Load blocked users set first
      await _loadBlockedUsersSet(user.uid);

      // Create the stream
      _conversationsStream = _messagingHelper.getUserConversations(user.uid);

      // Set up timeout timer
      _timeoutTimer = Timer(const Duration(seconds: 10), () {
        if (_isLoading) {
          Logger.warning('Timeout loading conversations');
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
          Logger.info('Received ${conversations.length} conversations');
          // Filter out conversations with blocked users (1-1 only)
          final filtered = conversations.where((conv) {
            if (conv.isGroup) {
              // hide group conversation if any member (other than current user) is blocked
              return !_isGroupMemberBlocked(conv);
            }
            final otherId = _getOtherParticipantId(conv);
            return !_blockedUserIds.contains(otherId);
          }).toList();
          setState(() {
            _conversations = filtered;
            _filteredConversations = filtered;
            _isLoading = false;
            _errorMessage = null;
          });
        },
        onError: (error) {
          _timeoutTimer?.cancel(); // Cancel timeout on error
          Logger.error('Error loading conversations: $error');
          setState(() {
            _isLoading = false;
            _errorMessage = 'Failed to load messages. Please try again.';
          });
        },
      );
    } catch (e) {
      Logger.error('Exception in _loadConversations: $e');
      setState(() {
        _isLoading = false;
        _errorMessage = 'An error occurred while loading messages';
      });
    }
  }

  Future<void> _loadBlockedUsersSet(String currentUserId) async {
    try {
      final snap = await FirebaseFirestore.instance
          .collection('Customers')
          .doc(currentUserId)
          .collection('blocks')
          .get();
      _blockedUserIds = snap.docs.map((d) => d.id).toSet();
    } catch (e) {
      Logger.error('Failed to load blocked users set: $e');
      _blockedUserIds = <String>{};
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
      if (conversation.isGroup) return '';
      final p1 = conversation.participant1Id;
      final p2 = conversation.participant2Id;
      if (p1 == null || p2 == null) return '';
      return p1 == currentUserId ? p2 : p1;
    } catch (e) {
      Logger.error('Error getting other participant ID: $e');
      return '';
    }
  }

  bool _isGroupMemberBlocked(ConversationModel conversation) {
    // Returns true if any other participant (besides current user) is blocked
    final currentUserId = _auth.currentUser?.uid;
    if (currentUserId == null) return false;
    for (final uid in conversation.participantIds) {
      if (uid != currentUserId && _blockedUserIds.contains(uid)) {
        return true;
      }
    }
    return false;
  }

  Map<String, dynamic> _getOtherParticipantInfo(
    ConversationModel conversation,
  ) {
    try {
      if (conversation.isGroup) return {};
      final otherId = _getOtherParticipantId(conversation);
      final fromConv = conversation.participantInfo[otherId] ?? {};
      if (fromConv.isNotEmpty) return fromConv;
      // Fallback to cache
      final cached = _userInfoCache[otherId];
      if (cached != null) return cached;
      // Trigger async fetch (non-blocking)
      _prefetchUserInfo(otherId);
      return {};
    } catch (e) {
      Logger.error('Error getting other participant info: $e');
      return {};
    }
  }

  Future<void> _prefetchUserInfo(String userId) async {
    if (userId.isEmpty || _userInfoCache.containsKey(userId)) return;
    final helper = FirebaseFirestoreHelper();
    final user = await helper.getSingleCustomer(customerId: userId);
    if (user != null && mounted) {
      setState(() {
        _userInfoCache[userId] = {
          'uid': user.uid,
          'name': user.name,
          'email': user.email,
          'username': user.username,
          'profilePictureUrl': user.profilePictureUrl,
          'bio': user.bio,
        };
      });
    }
  }

  CustomerModel _convertToCustomerModel(Map<String, dynamic> participantInfo) {
    return CustomerModel(
      uid: participantInfo['uid'] ?? '',
      name: participantInfo['name'] ?? 'Unknown User',
      email: participantInfo['email'] ?? '',
      username: participantInfo['username'],
      profilePictureUrl: participantInfo['profilePictureUrl'],
      bio: participantInfo['bio'],
      phoneNumber: participantInfo['phoneNumber'],
      age: participantInfo['age'],
      gender: participantInfo['gender'],
      location: participantInfo['location'],
      occupation: participantInfo['occupation'],
      company: participantInfo['company'],
      website: participantInfo['website'],
      socialMediaLinks: participantInfo['socialMediaLinks'],
      isDiscoverable: participantInfo['isDiscoverable'] ?? true,
      favorites: List<String>.from(participantInfo['favorites'] ?? []),
      createdAt: participantInfo['createdAt'] != null
          ? (participantInfo['createdAt'] as Timestamp).toDate()
          : DateTime.now(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        backgroundColor: Colors.white,
        foregroundColor: Colors.black87,
        titleTextStyle: const TextStyle(
          color: Colors.black87,
          fontSize: 22,
          fontWeight: FontWeight.w600,
        ),
        elevation: 0,
        scrolledUnderElevation: 0,
        surfaceTintColor: Colors.transparent,
        systemOverlayStyle: SystemUiOverlayStyle.dark,
        title: const Text('Messages'),
        actions: [
          IconButton(
            icon: Icon(_isSearching ? Icons.close : Icons.search),
            onPressed: _toggleSearch,
          ),
        ],
        bottom: const PreferredSize(
          preferredSize: Size.fromHeight(1),
          child: Divider(height: 1, thickness: 1, color: Color(0xFFE5E7EB)),
        ),
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
        backgroundColor: Theme.of(context).colorScheme.primary,
        child: Icon(
          Icons.message,
          color: Theme.of(context).colorScheme.onPrimary,
        ),
      ),
    );
  }

  Widget _buildBody() {
    final themeProvider = Provider.of<ThemeProvider>(context);
    final isDark = themeProvider.isDarkMode;
    final theme = Theme.of(context);

    if (_isLoading) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(
              color: isDark ? const Color(0xFF2C5A96) : const Color(0xFF667EEA),
            ),
            const SizedBox(height: 16),
            Text(
              'Loading messages...',
              style: TextStyle(
                color: theme.textTheme.bodyMedium?.color,
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
              color: theme.textTheme.bodyMedium?.color?.withValues(alpha: 0.5),
            ),
            const SizedBox(height: 16),
            Text(
              'Oops!',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w600,
                color: isDark
                    ? const Color(0xFF2C5A96)
                    : const Color(0xFF667EEA),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              _errorMessage!,
              style: TextStyle(
                fontSize: 16,
                color: theme.textTheme.bodyMedium?.color,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: _retryLoading,
              style: ElevatedButton.styleFrom(
                backgroundColor: isDark
                    ? const Color(0xFF2C5A96)
                    : const Color(0xFF667EEA),
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
    final themeProvider = Provider.of<ThemeProvider>(context);
    final isDark = themeProvider.isDarkMode;
    final theme = Theme.of(context);
    final isSearching = _isSearching && _searchController.text.isNotEmpty;

    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            isSearching ? Icons.search_off : Icons.message_outlined,
            size: 80,
            color: theme.textTheme.bodyMedium?.color?.withValues(alpha: 0.5),
          ),
          const SizedBox(height: 16),
          Text(
            isSearching ? 'No conversations found' : 'No messages yet',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w600,
              color: isDark ? const Color(0xFF2C5A96) : const Color(0xFF667EEA),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            isSearching
                ? 'Try adjusting your search terms or start a new conversation'
                : 'Start a conversation with other users',
            style: TextStyle(
              fontSize: 16,
              color: theme.textTheme.bodyMedium?.color,
            ),
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
                backgroundColor: isDark
                    ? const Color(0xFF2C5A96)
                    : const Color(0xFF667EEA),
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
    final themeProvider = Provider.of<ThemeProvider>(context);
    final isDark = themeProvider.isDarkMode;
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.cardColor,
        boxShadow: [
          BoxShadow(
            color: isDark
                ? Colors.black.withValues(alpha: 0.3)
                : Colors.black.withValues(alpha: 0.05),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: TextField(
        controller: _searchController,
        onChanged: _onSearchChanged,
        style: TextStyle(color: theme.textTheme.bodyLarge?.color),
        decoration: InputDecoration(
          hintText: 'Search conversations...',
          hintStyle: TextStyle(color: theme.textTheme.bodyMedium?.color),
          prefixIcon: Icon(
            Icons.search,
            color: theme.textTheme.bodyMedium?.color,
          ),
          suffixIcon: _searchController.text.isNotEmpty
              ? IconButton(
                  icon: Icon(
                    Icons.clear,
                    color: theme.textTheme.bodyMedium?.color,
                  ),
                  onPressed: () {
                    _searchController.clear();
                    _onSearchChanged('');
                  },
                )
              : null,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(Dimensions.radiusLarge),
            borderSide: BorderSide(
              color: isDark
                  ? const Color(0xFF4A90E2)
                  : AppThemeColor.lightBlueColor,
            ),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(Dimensions.radiusLarge),
            borderSide: BorderSide(
              color: isDark ? const Color(0xFF2C5A96) : const Color(0xFF667EEA),
              width: 2,
            ),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(Dimensions.radiusLarge),
            borderSide: BorderSide(
              color: isDark
                  ? const Color(0xFF4A90E2)
                  : AppThemeColor.lightBlueColor,
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
    final themeProvider = Provider.of<ThemeProvider>(context);
    final isDark = themeProvider.isDarkMode;
    final theme = Theme.of(context);

    final bool isGroup = conversation.isGroup;
    final hasUnread = conversation.unreadCount > 0;
    String name;
    String? subtitleUsername;
    String? profilePictureUrl;
    if (isGroup) {
      name = conversation.groupName ?? 'Group';
      subtitleUsername = null;
      profilePictureUrl = conversation.groupAvatarUrl;
    } else {
      name = otherParticipantInfo['name'] ?? 'Unknown User';
      profilePictureUrl = otherParticipantInfo['profilePictureUrl'];
      subtitleUsername = otherParticipantInfo['username'];
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: theme.cardColor,
        borderRadius: BorderRadius.circular(Dimensions.radiusLarge),
        boxShadow: [
          BoxShadow(
            color: isDark
                ? Colors.black.withValues(alpha: 0.3)
                : Colors.black.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.all(16),
        leading: isGroup
            ? _buildGroupAvatar(conversation)
            : ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: Container(
                  width: 48,
                  height: 48,
                  color: isDark
                      ? const Color(0xFF4A90E2)
                      : AppThemeColor.lightBlueColor,
                  child: profilePictureUrl != null
                      ? SafeNetworkImage(
                          imageUrl: profilePictureUrl,
                          fit: BoxFit.cover,
                          placeholder: Icon(
                            Icons.person,
                            color: isDark
                                ? const Color(0xFF2C5A96)
                                : const Color(0xFF667EEA),
                          ),
                          errorWidget: Icon(
                            Icons.person,
                            color: isDark
                                ? const Color(0xFF2C5A96)
                                : const Color(0xFF667EEA),
                          ),
                        )
                      : Icon(
                          Icons.person,
                          color: isDark
                              ? const Color(0xFF2C5A96)
                              : const Color(0xFF667EEA),
                        ),
                ),
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
                      ? (isDark
                            ? const Color(0xFF2C5A96)
                            : const Color(0xFF667EEA))
                      : theme.textTheme.titleMedium?.color,
                ),
              ),
            ),
            if (hasUnread)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: isDark
                      ? const Color(0xFF2C5A96)
                      : const Color(0xFF667EEA),
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
            if (!isGroup && subtitleUsername != null) ...[
              Text(
                '@$subtitleUsername',
                style: TextStyle(
                  fontSize: 14,
                  color: theme.textTheme.bodyMedium?.color,
                ),
              ),
              const SizedBox(height: 4),
            ],
            Text(
              _buildLastMessagePreview(conversation),
              style: TextStyle(
                fontSize: 14,
                color: hasUnread
                    ? (isDark
                          ? const Color(0xFF2C5A96)
                          : const Color(0xFF667EEA))
                    : theme.textTheme.bodyMedium?.color,
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
                color: theme.textTheme.bodyMedium?.color,
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
                otherParticipantInfo: conversation.isGroup
                    ? null
                    : _convertToCustomerModel(otherParticipantInfo),
              ),
            ),
          );
        },
      ),
    );
  }

  // Build stacked avatars for a group (show up to 3)
  Widget _buildGroupAvatar(ConversationModel conversation) {
    final themeProvider = Provider.of<ThemeProvider>(context, listen: false);
    final isDark = themeProvider.isDarkMode;
    final List<String> memberIds = conversation.participantIds;
    final currentUserId = _auth.currentUser?.uid;
    final others = memberIds
        .where((id) => id != currentUserId)
        .take(3)
        .toList();

    List<Widget> circles = [];
    for (int i = 0; i < others.length; i++) {
      final uid = others[i];
      final info = conversation.participantInfo[uid] ?? {};
      final url = info['profilePictureUrl'];
      circles.add(
        Positioned(
          left: i * 18.0,
          child: CircleAvatar(
            radius: 16,
            backgroundColor: isDark
                ? const Color(0xFF4A90E2)
                : AppThemeColor.lightBlueColor,
            child: url != null
                ? ClipOval(
                    child: SafeNetworkImage(
                      imageUrl: url,
                      fit: BoxFit.cover,
                      placeholder: const Icon(Icons.person, size: 14),
                      errorWidget: const Icon(Icons.person, size: 14),
                    ),
                  )
                : const Icon(Icons.person, size: 14),
          ),
        ),
      );
    }

    return SizedBox(width: 56, height: 32, child: Stack(children: circles));
  }

  String _buildLastMessagePreview(ConversationModel conversation) {
    if (conversation.isGroup) {
      final senderId = conversation.lastMessageSenderId;
      if (senderId != null && conversation.participantInfo[senderId] != null) {
        final name =
            conversation.participantInfo[senderId]['name'] ?? 'Someone';
        return '$name: ${conversation.lastMessage}';
      }
    }
    return conversation.lastMessage;
  }
}
