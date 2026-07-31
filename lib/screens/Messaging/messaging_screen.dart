import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:attendus/models/message_model.dart';

import 'package:attendus/firebase/firebase_messaging_helper.dart';
import 'package:attendus/screens/Messaging/chat_screen.dart';
import 'package:attendus/screens/Messaging/new_message_screen.dart';
import 'package:intl/intl.dart';
import 'package:attendus/models/customer_model.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:attendus/Utils/logger.dart';
import 'package:attendus/firebase/firebase_firestore_helper.dart';
import 'package:attendus/widgets/attendus_design_system.dart';

class MessagingScreen extends StatefulWidget {
  final bool showShellHeader;

  const MessagingScreen({super.key, this.showShellHeader = true});

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
  StreamSubscription<List<ConversationModel>>? _conversationsSubscription;
  Timer? _timeoutTimer;
  final TextEditingController _searchController = TextEditingController();
  final Map<String, Map<String, dynamic>> _userInfoCache = {};
  Set<String> _blockedUserIds = <String>{};

  @override
  void initState() {
    super.initState();
    // Defer conversation loading to prevent blocking app startup
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _loadConversations();
      }
    });
  }

  @override
  void dispose() {
    // Cancel any active streams and timers
    _conversationsSubscription?.cancel();
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

      // Set up timeout timer (extend to allow index/backoff on slow networks)
      _timeoutTimer = Timer(const Duration(seconds: 20), () {
        if (_isLoading) {
          Logger.warning('Timeout loading conversations');
          setState(() {
            _isLoading = false;
            _errorMessage =
                'Request timed out. Please check your connection and try again.';
          });
        }
      });

      // Cancel any previous subscription before listening again
      _conversationsSubscription?.cancel();

      // Listen to the stream with proper error handling
      _conversationsSubscription = _conversationsStream!.listen(
        (conversations) {
          _timeoutTimer?.cancel(); // Cancel timeout on success
          Logger.info('Received ${conversations.length} conversations');
          // Filter out conversations with blocked users (1-1 only)
          final filtered =
              conversations.where((conv) {
                if (conv.isGroup) {
                  // hide group conversation if any member (other than current user) is blocked
                  return !_isGroupMemberBlocked(conv);
                }
                final otherId = _getOtherParticipantId(conv);
                return !_blockedUserIds.contains(otherId);
              }).toList()..sort(
                (a, b) => b.lastMessageTime.compareTo(a.lastMessageTime),
              );
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

  // Search is always visible now; clearing text resets the filtered list

  void _onSearchChanged(String query) {
    if (query.isEmpty) {
      setState(() {
        _filteredConversations = [..._conversations]
          ..sort((a, b) => b.lastMessageTime.compareTo(a.lastMessageTime));
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
    }).toList()..sort((a, b) => b.lastMessageTime.compareTo(a.lastMessageTime));

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
      appBar: widget.showShellHeader
          ? AppBar(
              systemOverlayStyle: SystemUiOverlayStyle.dark,
              title: const Text('Messages'),
              actions: [
                IconButton(
                  icon: const Icon(Icons.add_comment_rounded),
                  tooltip: 'New message',
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => const NewMessageScreen(),
                      ),
                    );
                  },
                ),
              ],
            )
          : null,
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 900),
          child: Column(
            children: [
              _buildSearchBar(),
              Expanded(child: _buildBody()),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const AttendUsLoadingState(label: 'Loading conversations...');
    }

    if (_errorMessage != null) {
      return Center(
        child: AttendUsEmptyState(
          icon: Icons.cloud_off_outlined,
          title: 'Messages unavailable',
          message: _errorMessage!,
          action: AttendUsButton.primary(
            label: 'Try again',
            icon: Icons.refresh,
            onPressed: _retryLoading,
          ),
        ),
      );
    }

    if (_filteredConversations.isEmpty) {
      return _buildEmptyState();
    }

    return _buildConversationsList();
  }

  Widget _buildEmptyState() {
    final isSearching = _searchController.text.isNotEmpty;

    return Center(
      child: AttendUsEmptyState(
        icon: isSearching ? Icons.search_off : Icons.mark_chat_unread_outlined,
        title: isSearching ? 'No conversations found' : 'No messages yet',
        message: isSearching
            ? 'Try a different name, username, or message keyword.'
            : 'Start a direct message or create a group conversation.',
        action: isSearching
            ? null
            : AttendUsButton.primary(
                label: 'New message',
                icon: Icons.add_comment_outlined,
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => const NewMessageScreen(),
                    ),
                  );
                },
              ),
      ),
    );
  }

  Widget _buildSearchBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
      child: AttendUsSearchField(
        controller: _searchController,
        onChanged: _onSearchChanged,
        hintText: 'Search conversations',
      ),
    );
  }

  Widget _buildConversationsList() {
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
      itemCount: _filteredConversations.length,
      separatorBuilder: (_, index) => const SizedBox(height: 10),
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

    final subtitleParts = <String>[
      if (!isGroup && subtitleUsername != null && subtitleUsername.isNotEmpty)
        '@$subtitleUsername',
      _buildLastMessagePreview(conversation),
      DateFormat('MMM d, h:mm a').format(conversation.lastMessageTime),
    ];

    return AttendUsListTile(
      selected: hasUnread,
      leading: isGroup
          ? _buildGroupAvatar(conversation)
          : AttendUsAvatar(imageUrl: profilePictureUrl, name: name, size: 48),
      title: name,
      subtitle: subtitleParts.join(' • '),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (hasUnread) ...[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: theme.colorScheme.primary,
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(
                conversation.unreadCount > 99
                    ? '99+'
                    : conversation.unreadCount.toString(),
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.onPrimary,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            const SizedBox(width: 8),
          ],
          Icon(Icons.chevron_right, color: theme.colorScheme.onSurfaceVariant),
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
    );
  }

  // Build stacked avatars for a group (show up to 3)
  Widget _buildGroupAvatar(ConversationModel conversation) {
    final List<String> memberIds = conversation.participantIds;
    final currentUserId = _auth.currentUser?.uid;
    final others = memberIds
        .where((id) => id != currentUserId)
        .take(3)
        .toList();

    if (others.isEmpty) {
      return AttendUsAvatar(
        name: conversation.groupName ?? 'Group',
        fallbackIcon: Icons.groups_outlined,
        size: 48,
        tone: AttendUsStatusTone.success,
      );
    }

    return SizedBox(
      width: 60,
      height: 42,
      child: Stack(
        children: [
          for (var i = 0; i < others.length; i++)
            Positioned(
              left: i * 16.0,
              child: Container(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: Theme.of(context).colorScheme.surface,
                    width: 2,
                  ),
                ),
                child: AttendUsAvatar(
                  imageUrl: conversation
                      .participantInfo[others[i]]?['profilePictureUrl'],
                  name: conversation.participantInfo[others[i]]?['name'],
                  size: 38,
                  tone: AttendUsStatusTone.success,
                ),
              ),
            ),
        ],
      ),
    );
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
