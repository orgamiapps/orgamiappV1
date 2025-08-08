import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:orgami/models/customer_model.dart';
import 'package:orgami/firebase/firebase_messaging_helper.dart';
import 'package:orgami/Utils/colors.dart';
import 'package:orgami/Utils/dimensions.dart';
import 'package:orgami/Utils/cached_image.dart';
import 'package:orgami/Screens/Messaging/chat_screen.dart';
import 'package:orgami/Utils/toast.dart';
import 'package:orgami/Utils/theme_provider.dart';
import 'package:provider/provider.dart';
import 'package:orgami/Utils/logger.dart';

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
      Logger.error('Error loading users: $e');
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

      final results = await _messagingHelper.searchUsers(
        query,
        currentUser.uid,
      );
      setState(() {
        _searchResults = results;
      });
    } catch (e) {
      Logger.error('Error searching users: $e');
    }
  }

  Future<void> _startConversation(CustomerModel user) async {
    try {
      final currentUser = _auth.currentUser;
      if (currentUser == null) return;

      // Create conversation ID (sorted to ensure consistency)
      final sortedIds = [currentUser.uid, user.uid]..sort();
      final conversationId = '${sortedIds[0]}_${sortedIds[1]}';

      // Check if conversation already exists
      final existingConversationId = await _messagingHelper.getConversationId(
        currentUser.uid,
        user.uid,
      );

      if (existingConversationId != null) {
        // Navigate to existing conversation
        if (!mounted) return;
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (context) => ChatScreen(
              conversationId: existingConversationId,
              otherParticipantInfo: CustomerModel(
                uid: user.uid,
                name: user.name,
                email: user.email,
                username: user.username,
                profilePictureUrl: user.profilePictureUrl,
                bio: user.bio,
                phoneNumber: user.phoneNumber,
                age: user.age,
                gender: user.gender,
                location: user.location,
                occupation: user.occupation,
                company: user.company,
                website: user.website,
                socialMediaLinks: user.socialMediaLinks,
                isDiscoverable: user.isDiscoverable,
                favorites: user.favorites,
                createdAt: user.createdAt,
              ),
            ),
          ),
        );
      } else {
        // Create new conversation and navigate
        if (!mounted) return;
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (context) => ChatScreen(
              conversationId: conversationId,
              otherParticipantInfo: CustomerModel(
                uid: user.uid,
                name: user.name,
                email: user.email,
                username: user.username,
                profilePictureUrl: user.profilePictureUrl,
                bio: user.bio,
                phoneNumber: user.phoneNumber,
                age: user.age,
                gender: user.gender,
                location: user.location,
                occupation: user.occupation,
                company: user.company,
                website: user.website,
                socialMediaLinks: user.socialMediaLinks,
                isDiscoverable: user.isDiscoverable,
                favorites: user.favorites,
                createdAt: user.createdAt,
              ),
            ),
          ),
        );
      }
    } catch (e) {
      Logger.error('Error starting conversation: $e');
      if (!mounted) return;
      ShowToast().showSnackBar('Error starting conversation', context);
    }
  }

  @override
  Widget build(BuildContext context) {
    final themeProvider = Provider.of<ThemeProvider>(context);
    final isDark = themeProvider.isDarkMode;
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        title: Text(
          'New Message',
          style: TextStyle(
            color: theme.appBarTheme.foregroundColor,
            fontWeight: FontWeight.bold,
            fontSize: 20,
          ),
        ),
        flexibleSpace: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: themeProvider.getGradientColors(context),
            ),
          ),
        ),
        iconTheme: IconThemeData(color: theme.appBarTheme.foregroundColor),
        elevation: 0,
      ),
      body: Column(
        children: [
          _buildSearchBar(),
          Expanded(
            child: _isLoading
                ? Center(
                    child: CircularProgressIndicator(
                      color: Theme.of(context).colorScheme.primary,
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
    final themeProvider = Provider.of<ThemeProvider>(context);
    final isDark = themeProvider.isDarkMode;
    final theme = Theme.of(context);

    return Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.symmetric(horizontal: 16),
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
      child: TextField(
        controller: _searchController,
        style: TextStyle(color: theme.textTheme.bodyLarge?.color),
        decoration: InputDecoration(
          hintText: 'Search users...',
          hintStyle: TextStyle(
            color: theme.textTheme.bodyMedium?.color,
            fontSize: 16,
          ),
          border: InputBorder.none,
          icon: Icon(Icons.search, color: theme.textTheme.bodyMedium?.color),
          suffixIcon: _searchController.text.isNotEmpty
              ? IconButton(
                  icon: Icon(
                    Icons.clear,
                    color: theme.textTheme.bodyMedium?.color,
                  ),
                  onPressed: () {
                    _searchController.clear();
                  },
                )
              : null,
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    final themeProvider = Provider.of<ThemeProvider>(context);
    final isDark = themeProvider.isDarkMode;
    final theme = Theme.of(context);

    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            _isSearching ? Icons.search_off : Icons.people_outline,
            size: 80,
            color: theme.textTheme.bodyMedium?.color?.withValues(alpha: 0.5),
          ),
          const SizedBox(height: 16),
          Text(
            _isSearching ? 'No users found' : 'No users available',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w600,
              color: isDark ? const Color(0xFF2C5A96) : const Color(0xFF667EEA),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            _isSearching
                ? 'Try a different search term'
                : 'There are no other users to message',
            style: TextStyle(
              fontSize: 16,
              color: theme.textTheme.bodyMedium?.color,
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
    final themeProvider = Provider.of<ThemeProvider>(context);
    final isDark = themeProvider.isDarkMode;
    final theme = Theme.of(context);

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
        leading: CircleAvatar(
          radius: 25,
          backgroundColor: isDark
              ? const Color(0xFF4A90E2)
              : AppThemeColor.lightBlueColor,
          child: user.profilePictureUrl != null
              ? ClipOval(
                  child: SafeNetworkImage(
                    imageUrl: user.profilePictureUrl!,
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
                  ),
                )
              : Icon(
                  Icons.person,
                  color: isDark
                      ? const Color(0xFF2C5A96)
                      : const Color(0xFF667EEA),
                ),
        ),
        title: Text(
          user.name,
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            color: theme.textTheme.titleMedium?.color,
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
                  color: theme.textTheme.bodyMedium?.color,
                ),
              ),
              const SizedBox(height: 4),
            ],
            if (user.bio != null && user.bio!.isNotEmpty) ...[
              Text(
                user.bio!,
                style: TextStyle(
                  fontSize: 14,
                  color: theme.textTheme.bodyMedium?.color,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ],
        ),
        trailing: IconButton(
          icon: Icon(
            Icons.message_outlined,
            color: isDark
                ? const Color(0xFF2C5A96)
                : AppThemeColor.darkBlueColor,
          ),
          onPressed: () => _startConversation(user),
        ),
        onTap: () => _startConversation(user),
      ),
    );
  }
}
