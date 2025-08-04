import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:orgami/Models/CustomerModel.dart';
import 'package:orgami/Firebase/FirebaseMessagingHelper.dart';
import 'package:orgami/Utils/Colors.dart';
import 'package:orgami/Utils/dimensions.dart';
import 'package:orgami/Utils/cached_image.dart';
import 'package:orgami/Screens/Messaging/ChatScreen.dart';
import 'package:orgami/Utils/Toast.dart';

class NewMessageScreen extends StatefulWidget {
  const NewMessageScreen({super.key});

  @override
  State<NewMessageScreen> createState() => _NewMessageScreenState();
}

class _NewMessageScreenState extends State<NewMessageScreen> {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseMessagingHelper _messagingHelper = FirebaseMessagingHelper();
  final TextEditingController _searchController = TextEditingController();
  
  List<CustomerModel> _searchResults = [];
  List<CustomerModel> _allUsers = [];
  bool _isLoading = false;
  bool _isSearching = false;

  @override
  void initState() {
    super.initState();
    _loadAllUsers();
    _searchController.addListener(_onSearchChanged);
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadAllUsers() async {
    setState(() {
      _isLoading = true;
    });

    try {
      final currentUser = _auth.currentUser;
      if (currentUser == null) return;

      final users = await _messagingHelper.searchUsers('', currentUser.uid);
      setState(() {
        _allUsers = users;
        _searchResults = users;
        _isLoading = false;
      });
    } catch (e) {
      print('Error loading users: $e');
      setState(() {
        _isLoading = false;
      });
    }
  }

  void _onSearchChanged() {
    final query = _searchController.text.trim();
    setState(() {
      _isSearching = query.isNotEmpty;
    });

    if (query.isEmpty) {
      setState(() {
        _searchResults = _allUsers;
      });
    } else {
      _performSearch(query);
    }
  }

  Future<void> _performSearch(String query) async {
    try {
      final currentUser = _auth.currentUser;
      if (currentUser == null) return;

      final results = await _messagingHelper.searchUsers(query, currentUser.uid);
      setState(() {
        _searchResults = results;
      });
    } catch (e) {
      print('Error searching users: $e');
    }
  }

  Future<void> _startConversation(CustomerModel user) async {
    try {
      final currentUser = _auth.currentUser;
      if (currentUser == null) return;

      // Check if conversation already exists
      final conversationId = await _messagingHelper.getConversationId(
        currentUser.uid,
        user.uid,
      );

      if (conversationId != null) {
        // Navigate to existing conversation
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (context) => ChatScreen(
              conversationId: conversationId,
              otherParticipantInfo: {
                'name': user.name,
                'profilePictureUrl': user.profilePictureUrl,
                'username': user.username,
              },
            ),
          ),
        );
      } else {
        // Create new conversation and navigate
        final conversationId = '${currentUser.uid}_${user.uid}';
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (context) => ChatScreen(
              conversationId: conversationId,
              otherParticipantInfo: {
                'name': user.name,
                'profilePictureUrl': user.profilePictureUrl,
                'username': user.username,
              },
            ),
          ),
        );
      }
    } catch (e) {
      print('Error starting conversation: $e');
      ShowToast().showSnackBar('Error starting conversation', context);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppThemeColor.backGroundColor,
      appBar: AppBar(
        title: const Text(
          'New Message',
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
      ),
      body: Column(
        children: [
          _buildSearchBar(),
          Expanded(
            child: _isLoading
                ? const Center(
                    child: CircularProgressIndicator(
                      color: AppThemeColor.darkBlueColor,
                    ),
                  )
                : _searchResults.isEmpty
                    ? _buildEmptyState()
                    : _buildUsersList(),
          ),
        ],
      ),
    );
  }

  Widget _buildSearchBar() {
    return Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.symmetric(horizontal: 16),
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
      child: TextField(
        controller: _searchController,
        decoration: InputDecoration(
          hintText: 'Search users...',
          hintStyle: TextStyle(
            color: AppThemeColor.dullFontColor,
            fontSize: 16,
          ),
          border: InputBorder.none,
          icon: Icon(
            Icons.search,
            color: AppThemeColor.dullFontColor,
          ),
          suffixIcon: _searchController.text.isNotEmpty
              ? IconButton(
                  icon: Icon(
                    Icons.clear,
                    color: AppThemeColor.dullFontColor,
                  ),
                  onPressed: () {
                    _searchController.clear();
                  },
                )
              : null,
        ),
        style: const TextStyle(fontSize: 16),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            _isSearching ? Icons.search_off : Icons.people_outline,
            size: 80,
            color: AppThemeColor.dullFontColor.withValues(alpha: 0.5),
          ),
          const SizedBox(height: 16),
          Text(
            _isSearching ? 'No users found' : 'No users available',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w600,
              color: AppThemeColor.darkBlueColor,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            _isSearching
                ? 'Try a different search term'
                : 'There are no other users to message',
            style: TextStyle(
              fontSize: 16,
              color: AppThemeColor.dullFontColor,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildUsersList() {
    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      itemCount: _searchResults.length,
      itemBuilder: (context, index) {
        final user = _searchResults[index];
        return _buildUserTile(user);
      },
    );
  }

  Widget _buildUserTile(CustomerModel user) {
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
          child: user.profilePictureUrl != null
              ? ClipOval(
                  child: SafeNetworkImage(
                    imageUrl: user.profilePictureUrl!,
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
              : const Icon(
                  Icons.person,
                  color: AppThemeColor.darkBlueColor,
                ),
        ),
        title: Text(
          user.name,
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            color: Colors.black87,
          ),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (user.username != null) ...[
              Text(
                '@${user.username}',
                style: TextStyle(
                  fontSize: 14,
                  color: AppThemeColor.dullFontColor,
                ),
              ),
              const SizedBox(height: 4),
            ],
            if (user.bio != null && user.bio!.isNotEmpty) ...[
              Text(
                user.bio!,
                style: TextStyle(
                  fontSize: 14,
                  color: AppThemeColor.dullFontColor,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ],
        ),
        trailing: IconButton(
          icon: const Icon(
            Icons.message_outlined,
            color: AppThemeColor.darkBlueColor,
          ),
          onPressed: () => _startConversation(user),
        ),
        onTap: () => _startConversation(user),
      ),
    );
  }
} 