import 'package:attendus/Services/messaging_feed.dart';
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
  final _feed = MessagingFeed<ConversationModel>();
  StreamSubscription<User?>? _authSubscription;
  final TextEditingController _searchController = TextEditingController();
  final Map<String, Map<String, dynamic>> _userInfoCache = {};
  Set<String> _blockedUserIds = <String>{};

  @override
  void initState() {
    super.initState();
    _feed.addListener(_onFeedChanged);
    _authSubscription = _auth.authStateChanges().listen((_) {
      _userInfoCache.clear();
      _blockedUserIds.clear();
      _loadConversations();
    });
  }

  void _onFeedChanged() {
    if (!mounted) return;
    setState(() {
      _conversations = _feed.items;
      _isLoading = _feed.loading;
      _errorMessage = _feed.error;
    });
    _onSearchChanged(_searchController.text);
  }

  @override
  void dispose() {
    _authSubscription?.cancel();
    _feed.dispose();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadConversations() async {
    final user = _auth.currentUser;
    final uid = user != null && !user.isAnonymous ? user.uid : null;
    await _feed.bind(uid, () async {
      await _loadBlockedUsersSet(uid!);
      return _messagingHelper
          .getUserConversations(uid)
          .map(
            (conversations) => conversations
                .where(
                  (conversation) => !conversation.participantIds.any(
                    (id) => id != uid && _blockedUserIds.contains(id),
                  ),
                )
                .toList(),
          );
    });
  }

  Future<void> _loadBlockedUsersSet(String currentUserId) async {
    try {
      final snap = await FirebaseFirestore.instance
          .collection('Customers')
          .doc(currentUserId)
          .collection('blocks')
          .get();
      if (_auth.currentUser?.uid == currentUserId) {
        _blockedUserIds = snap.docs.map((d) => d.id).toSet();
      }
    } catch (e) {
      Logger.error('Failed to load blocked users set: $e');
      rethrow;
    }
  }

  Future<void> _retryLoading() => _loadConversations();

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
      return conversation.participantIds.firstWhere(
        (id) => id != currentUserId,
        orElse: () => '',
      );
    } catch (e) {
      Logger.error('Error getting other participant ID: $e');
      return '';
    }
  }

  Map<String, dynamic> _getOtherParticipantInfo(
    ConversationModel conversation,
  ) {
    try {
      if (conversation.isGroup) return {};
      final otherId = _getOtherParticipantId(conversation);
      final fromConv = conversation.participantInfo[otherId] ?? {};
      if (fromConv.isNotEmpty) {
        return {...Map<String, dynamic>.from(fromConv), 'uid': otherId};
      }
      // Fallback to cache
      final cached = _userInfoCache[otherId];
      if (cached != null) return cached;
      // Trigger async fetch (non-blocking)
      _prefetchUserInfo(otherId);
      return {'uid': otherId, 'name': 'User'};
    } catch (e) {
      Logger.error('Error getting other participant info: $e');
      return {};
    }
  }

  Future<void> _prefetchUserInfo(String userId) async {
    final currentAccount = _auth.currentUser?.uid;
    if (userId.isEmpty || _userInfoCache.containsKey(userId)) return;
    final helper = FirebaseFirestoreHelper();
    final user = await helper.getSingleCustomer(customerId: userId);
    if (user != null && mounted && _auth.currentUser?.uid == currentAccount) {
      setState(() {
        _userInfoCache[userId] = {
          'uid': user.uid,
          'name': user.name,
          'username': user.username,
          'profilePictureUrl': user.profilePictureUrl,
          'bio': user.bio,
        };
      });
    }
  }

  CustomerModel _convertToCustomerModel(Map<String, dynamic> participantInfo) {
    return CustomerModel.fromPublicProfile(participantInfo);
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

    if (_errorMessage != null && _conversations.isEmpty) {
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

    return Column(
      children: [
        if (_errorMessage != null)
          MaterialBanner(
            content: Text(_errorMessage!),
            actions: [
              TextButton(
                onPressed: _retryLoading,
                child: const Text('Try again'),
              ),
            ],
          ),
        Expanded(child: _buildConversationsList()),
      ],
    );
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
