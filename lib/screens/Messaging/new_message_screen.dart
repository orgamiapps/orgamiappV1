import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';

import 'package:flutter/services.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:attendus/models/customer_model.dart';
import 'package:attendus/firebase/firebase_messaging_helper.dart';
import 'package:attendus/Utils/colors.dart';
import 'package:attendus/Utils/dimensions.dart';
import 'package:attendus/Utils/cached_image.dart';
import 'package:attendus/screens/Messaging/chat_screen.dart';
import 'package:attendus/Utils/toast.dart';
import 'package:attendus/Utils/theme_provider.dart';
import 'package:provider/provider.dart';
import 'package:attendus/Utils/logger.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:attendus/firebase/organization_helper.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shimmer/shimmer.dart';
// intl not used here; keep code lean
import 'package:share_plus/share_plus.dart';
import 'package:attendus/screens/MyProfile/user_profile_screen.dart';
import 'package:attendus/screens/Groups/groups_screen.dart';
import 'package:attendus/widgets/app_scaffold_wrapper.dart';

class NewMessageScreen extends StatefulWidget {
  const NewMessageScreen({super.key});

  @override
  State<NewMessageScreen> createState() => _NewMessageScreenState();
}

class _NewMessageScreenState extends State<NewMessageScreen>
    with TickerProviderStateMixin, AutomaticKeepAliveClientMixin {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseMessagingHelper _messagingHelper = FirebaseMessagingHelper();
  final TextEditingController _searchController = TextEditingController();
  final TextEditingController _groupNameController = TextEditingController();

  List<CustomerModel> _searchResults = [];
  List<CustomerModel> _allUsers = [];
  bool _isLoading = false;
  bool _isSearching = false;
  bool _isSearchInFlight = false;
  bool _searchFailed = false;
  bool _groupMode = false;
  final Set<String> _selectedUserIds = {};
  Set<String> _blockedUserIds = <String>{};
  List<Map<String, String>> _myOrgs = [];
  bool _isLoadingOrgs = false;
  TabController? _groupTabController;
  int _groupTabIndex = 0;
  String? _selectedOrgId;
  String? _selectedOrgName;
  final ScrollController _listController = ScrollController();
  int _listLimit = 30;
  bool _isNavigating = false;
  Timer? _searchDebounce;
  List<String> _recentSearches = [];
  String _lastSearchQuery = '';
  final double _testTextScale = 1.0; // debug-only a11y testing

  static const String _prefsKeyMode = 'new_message_last_mode';
  static const String _prefsKeyRecent = 'new_message_recent_searches';

  @override
  void initState() {
    super.initState();
    // Clear all state to ensure clean start
    _searchController.clear();
    _selectedUserIds.clear();
    _recentSearches.clear();
    _restorePrefs();
    _loadAllUsers();
    _searchController.addListener(_onSearchChanged);
    _loadMyOrganizations();
    _groupTabController = TabController(length: 2, vsync: this);
    _groupTabController!.addListener(() {
      if (!mounted) return;
      setState(() {
        _groupTabIndex = _groupTabController!.index;
      });
    });
    _listController.addListener(_onListScroll);
  }

  @override
  void dispose() {
    // Clear recent searches from storage when leaving the screen
    _clearRecentSearches();
    _searchController.dispose();
    _groupNameController.dispose();
    _groupTabController?.dispose();
    _listController.dispose();
    _searchDebounce?.cancel();
    super.dispose();
  }

  Future<void> _clearRecentSearches() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_prefsKeyRecent);
    } catch (_) {}
  }

  @override
  bool get wantKeepAlive => true;

  Future<void> _restorePrefs() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final lastMode = prefs.getBool(_prefsKeyMode);
      // Don't restore recent searches - start with a clean slate each time
      // This prevents confusion with old search terms appearing as selections
      if (!mounted) return;
      setState(() {
        _groupMode = lastMode ?? false;
        _recentSearches = <String>[]; // Always start with empty recent searches
      });
    } catch (_) {}
  }

  Future<void> _persistMode(bool group) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_prefsKeyMode, group);
    } catch (_) {}
  }

  Future<void> _addRecentSearch(String term) async {
    // Recent searches are disabled to prevent confusion with selected users
    // We no longer persist or display recent searches
    return;
  }

  Future<void> _loadMyOrganizations() async {
    try {
      setState(() {
        _isLoadingOrgs = true;
      });
      final helper = OrganizationHelper();
      final orgs = await helper.getUserOrganizationsLite();
      if (!mounted) return;
      setState(() {
        _myOrgs = orgs;
        _isLoadingOrgs = false;
      });
    } catch (e) {
      Logger.error('Error loading organizations: $e');
      if (!mounted) return;
      setState(() {
        _isLoadingOrgs = false;
        _myOrgs = [];
      });
    }
  }

  Future<void> _loadAllUsers() async {
    setState(() {
      _isLoading = true;
    });

    try {
      final currentUser = _auth.currentUser;
      if (currentUser == null) return;

      // load blocked set
      try {
        final bs = await FirebaseFirestore.instance
            .collection('Customers')
            .doc(currentUser.uid)
            .collection('blocks')
            .get();
        _blockedUserIds = bs.docs.map((d) => d.id).toSet();
      } catch (_) {}

      final users = await _messagingHelper.searchUsers('', currentUser.uid);
      // filter out blocked users from selectable list
      final filtered = users
          .where((u) => !_blockedUserIds.contains(u.uid))
          .toList();
      setState(() {
        _allUsers = filtered;
        _searchResults = filtered;
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

    _searchDebounce?.cancel();
    if (query.isEmpty) {
      setState(() {
        _searchResults = _allUsers;
        _isSearchInFlight = false;
      });
      return;
    }
    setState(() {
      _isSearchInFlight = true;
      _searchFailed = false;
    });
    _searchDebounce = Timer(const Duration(milliseconds: 300), () {
      _performSearch(query);
    });
  }

  Future<void> _performSearch(String query) async {
    try {
      final User? currentUser = _auth.currentUser;
      if (currentUser == null) return;

      final List<CustomerModel> results = await _messagingHelper.searchUsers(
        query,
        currentUser.uid,
      );
      // Support @username prefix filter locally
      final q = query.startsWith('@') ? query.substring(1) : query;
      final filtered = results
          .where((u) => !_blockedUserIds.contains(u.uid))
          .where((u) {
            if (query.startsWith('@')) {
              final uname = (u.username ?? '').toLowerCase();
              return uname.contains(q.toLowerCase());
            }
            return true;
          })
          .toList();
      if (!mounted) return;
      setState(() {
        _searchResults = filtered;
        _isSearchInFlight = false;
        _searchFailed = false;
      });
      _lastSearchQuery = query;
      _addRecentSearch(query);
    } catch (e) {
      Logger.error('Error searching users: $e');
      if (!mounted) return;
      setState(() {
        _isSearchInFlight = false;
        _searchFailed = true;
      });
      ShowToast().showSnackBar(_t('searchFailedToast'), context);
    }
  }

  Future<void> _startConversation(CustomerModel user) async {
    if (_isNavigating) return;
    try {
      setState(() => _isNavigating = true);
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
        await Navigator.pushReplacement(
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
        await Navigator.pushReplacement(
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
    } finally {
      if (mounted) setState(() => _isNavigating = false);
    }
  }

  Future<void> _createGroupAndOpenChat() async {
    try {
      final currentUser = _auth.currentUser;
      if (currentUser == null) return;
      final participants = {currentUser.uid, ..._selectedUserIds}.toList();
      if (participants.length < 3) {
        ShowToast().showSnackBar(
          'Select at least 2 people for a group',
          context,
        );
        return;
      }

      // Ask for a name just-in-time in a bottom sheet
      final name = await _promptForGroupName(context);
      final groupName = name?.trim() ?? '';

      final conv = await _messagingHelper.createGroupConversation(
        groupName: groupName.isEmpty ? null : groupName,
        participantIds: participants,
      );
      if (conv == null) {
        if (mounted) {
          ShowToast().showSnackBar('Failed to create group', context);
        }
        return;
      }
      HapticFeedback.mediumImpact();
      if (mounted) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (context) => ChatScreen(conversationId: conv.id),
          ),
        );
      }
    } catch (e) {
      Logger.error('Error creating group: $e');
      if (!mounted) return;
      ShowToast().showSnackBar('Error creating group', context);
    }
  }

  Future<String?> _promptForGroupName(BuildContext context) async {
    final controller = TextEditingController();
    return showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(context).viewInsets.bottom,
          ),
          child: Container(
            decoration: BoxDecoration(
              color: Theme.of(context).cardColor,
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(16),
                topRight: Radius.circular(16),
              ),
            ),
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.grey[300],
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                const Text(
                  'Name your group',
                  style: TextStyle(fontWeight: FontWeight.w600, fontSize: 16),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: controller,
                  textInputAction: TextInputAction.done,
                  decoration: const InputDecoration(
                    hintText: 'Add a name (optional) 🛸✨',
                    border: OutlineInputBorder(),
                  ),
                  onSubmitted: (v) => Navigator.pop(context, controller.text),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    TextButton(
                      onPressed: () => Navigator.pop(context, ''),
                      child: const Text('Skip'),
                    ),
                    const Spacer(),
                    FilledButton(
                      onPressed: () => Navigator.pop(context, controller.text),
                      child: const Text('Create'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _createGroupFromOrganization(
    String organizationId,
    String organizationName,
  ) async {
    try {
      final currentUser = _auth.currentUser;
      if (currentUser == null) return;

      final membersSnap = await FirebaseFirestore.instance
          .collection('Organizations')
          .doc(organizationId)
          .collection('Members')
          .where('status', isEqualTo: 'approved')
          .limit(500)
          .get();

      final Set<String> participantIds = <String>{};
      for (final d in membersSnap.docs) {
        final data = d.data();
        final String? fromField = (data['userId'] as String?);
        final String fallback = d.id; // legacy docs
        final String resolved = (fromField != null && fromField.isNotEmpty)
            ? fromField
            : fallback;
        if (resolved.isNotEmpty) participantIds.add(resolved);
      }

      if (participantIds.length < 3) {
        if (mounted) {
          ShowToast().showSnackBar(
            'Group must have at least 3 members',
            context,
          );
        }
        return;
      }

      final conv = await _messagingHelper.createGroupConversation(
        groupName: organizationName.isEmpty ? null : organizationName,
        participantIds: participantIds.toList()..sort(),
      );
      if (conv == null) {
        if (mounted) {
          ShowToast().showSnackBar('Failed to create group', context);
        }
        return;
      }

      if (!mounted) return;
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (context) => ChatScreen(conversationId: conv.id),
        ),
      );
    } catch (e) {
      Logger.error('Error creating org group: $e');
      if (!mounted) return;
      ShowToast().showSnackBar('Error creating group', context);
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final theme = Theme.of(context);

    final scaffold = AppScaffoldWrapper(
      selectedBottomNavIndex: 2, // Messages tab
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        backgroundColor: Colors.white,
        foregroundColor: Colors.black87,
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
          fontSize: 22,
          fontWeight: FontWeight.w600,
        ),
        elevation: 0,
        scrolledUnderElevation: 0,
        surfaceTintColor: Colors.transparent,
        title: Row(
          children: [
            Icon(
              _groupMode ? Icons.group_rounded : Icons.person_rounded,
              color: Colors.black87,
              size: 24,
            ),
            const SizedBox(width: 8),
            Text(_groupMode ? _t('newGroupMessage') : _t('newMessage')),
          ],
        ),
        bottom: const PreferredSize(
          preferredSize: Size.fromHeight(1),
          child: Divider(height: 1, thickness: 1, color: Color(0xFFE5E7EB)),
        ),
      ),
      bottomNavigationBar: _buildCreateGroupBar(),
      body: Column(
        children: [
          _buildModeToggle(),
          if (_groupMode) ...[
            _buildGroupTabs(),
            Expanded(child: _buildGroupTabContent()),
          ] else ...[
            _buildSearchBar(),
            Expanded(
              child: _isLoading
                  ? _buildShimmerList()
                  : _searchResults.isEmpty
                  ? _buildEmptyState()
                  : _buildUsersList(),
            ),
          ],
        ],
      ),
    );

    if (kDebugMode) {
      final mq = MediaQuery.of(context);
      return MediaQuery(
        data: mq.copyWith(textScaler: TextScaler.linear(_testTextScale)),
        child: scaffold,
      );
    }
    return scaffold;
  }

  Widget _buildModeToggle() {
    final themeProvider = Provider.of<ThemeProvider>(context);
    final isDark = themeProvider.isDarkMode;

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      height: 54,
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: isDark ? Colors.grey[900] : Colors.grey[100],
        borderRadius: BorderRadius.circular(30),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Stack(
        children: [
          // Animated sliding background indicator
          AnimatedAlign(
            alignment: _groupMode
                ? Alignment.centerRight
                : Alignment.centerLeft,
            duration: const Duration(milliseconds: 250),
            curve: Curves.easeInOut,
            child: Container(
              width: MediaQuery.of(context).size.width / 2 - 24,
              height: 46,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: isDark
                      ? [const Color(0xFF2C5A96), const Color(0xFF4A90E2)]
                      : [const Color(0xFF667EEA), const Color(0xFF764BA2)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(26),
                boxShadow: [
                  BoxShadow(
                    color:
                        (isDark
                                ? const Color(0xFF2C5A96)
                                : const Color(0xFF667EEA))
                            .withValues(alpha: 0.3),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
            ),
          ),
          // Tab buttons
          Row(
            children: [
              // Direct Tab
              Expanded(
                child: GestureDetector(
                  onTap: () {
                    if (_groupMode) {
                      HapticFeedback.lightImpact();
                      setState(() {
                        _groupMode = false;
                        // Clear recent searches when switching modes
                        _recentSearches.clear();
                      });
                      _persistMode(false);
                    }
                  },
                  child: Container(
                    height: 46,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(26),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.person_rounded,
                          size: 20,
                          color: !_groupMode
                              ? Colors.white
                              : (isDark ? Colors.grey[400] : Colors.grey[700]),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          'Direct',
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: !_groupMode
                                ? FontWeight.w700
                                : FontWeight.w500,
                            color: !_groupMode
                                ? Colors.white
                                : (isDark
                                      ? Colors.grey[400]
                                      : Colors.grey[700]),
                            letterSpacing: !_groupMode ? 0.3 : 0,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              // Group Tab
              Expanded(
                child: GestureDetector(
                  onTap: () {
                    if (!_groupMode) {
                      HapticFeedback.lightImpact();
                      setState(() {
                        _groupMode = true;
                        // Clear recent searches when entering group mode
                        _recentSearches.clear();
                      });
                      _persistMode(true);
                    }
                  },
                  child: Container(
                    height: 46,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(26),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.group_rounded,
                          size: 20,
                          color: _groupMode
                              ? Colors.white
                              : (isDark ? Colors.grey[400] : Colors.grey[700]),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          'Group',
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: _groupMode
                                ? FontWeight.w700
                                : FontWeight.w500,
                            color: _groupMode
                                ? Colors.white
                                : (isDark
                                      ? Colors.grey[400]
                                      : Colors.grey[700]),
                            letterSpacing: _groupMode ? 0.3 : 0,
                          ),
                        ),
                        // Show selected count badge when in group mode
                        if (_groupMode && _selectedUserIds.isNotEmpty)
                          AnimatedContainer(
                            duration: const Duration(milliseconds: 200),
                            margin: const EdgeInsets.only(left: 6),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.9),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Text(
                              '${_selectedUserIds.length}',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                color: isDark
                                    ? const Color(0xFF2C5A96)
                                    : const Color(0xFF667EEA),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildGroupTabs() {
    final themeProvider = Provider.of<ThemeProvider>(context);
    final isDark = themeProvider.isDarkMode;
    final theme = Theme.of(context);

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 8),
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
      child: TabBar(
        controller: _groupTabController,
        indicatorColor: Theme.of(context).colorScheme.primary,
        labelColor: Theme.of(context).colorScheme.primary,
        unselectedLabelColor: theme.textTheme.bodyMedium?.color,
        tabs: const [
          Tab(text: 'Users'),
          Tab(text: 'Your Groups'),
        ],
      ),
    );
  }

  Widget _buildGroupTabContent() {
    if (_groupTabIndex == 1) {
      return _buildGroupsTab();
    }
    // Users tab content
    return Column(
      children: [
        _buildSearchBar(),
        if (_selectedUserIds.isNotEmpty) _buildSelectedChips(),
        if (_searchFailed) _buildRetryBar(),
        Expanded(
          child: _isLoading
              ? _buildShimmerList()
              : _searchResults.isEmpty
              ? _buildEmptyState()
              : _buildUsersList(),
        ),
      ],
    );
  }

  Widget _buildGroupsTab() {
    final themeProvider = Provider.of<ThemeProvider>(context);
    final isDark = themeProvider.isDarkMode;
    final theme = Theme.of(context);

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      padding: const EdgeInsets.all(12),
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
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.groups_outlined,
                color: isDark
                    ? const Color(0xFF2C5A96)
                    : AppThemeColor.darkBlueColor,
              ),
              const SizedBox(width: 8),
              Text(
                _t('yourGroups'),
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: theme.textTheme.titleMedium?.color,
                ),
              ),
              const Spacer(),
              IconButton(
                icon: const Icon(Icons.info_outline),
                color: theme.textTheme.bodyMedium?.color,
                onPressed: () => _showOrgInfo(context),
                tooltip: _t('info'),
              ),
              IconButton(
                icon: const Icon(Icons.refresh),
                color: theme.textTheme.bodyMedium?.color,
                onPressed: _loadMyOrganizations,
                tooltip: _t('refresh'),
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (_isLoadingOrgs)
            const Center(
              child: Padding(
                padding: EdgeInsets.symmetric(vertical: 8),
                child: SizedBox(
                  height: 24,
                  width: 24,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            )
          else if (_myOrgs.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text(
                'You have no groups yet.',
                style: TextStyle(color: theme.textTheme.bodyMedium?.color),
              ),
            )
          else
            Expanded(
              child: ListView.separated(
                padding: EdgeInsets.zero,
                itemCount: _myOrgs.length,
                separatorBuilder: (_, index) => const SizedBox(height: 8),
                itemBuilder: (context, index) {
                  final org = _myOrgs[index];
                  final orgId = org['id'] ?? '';
                  final orgName = org['name'] ?? 'Group';
                  final logoUrl = (org['logoUrl'] ?? '').toString();
                  final selected = _selectedOrgId == orgId;
                  return Container(
                    decoration: BoxDecoration(
                      color: theme.scaffoldBackgroundColor,
                      borderRadius: BorderRadius.circular(
                        Dimensions.radiusLarge,
                      ),
                      border: Border.all(
                        color: selected
                            ? (isDark
                                  ? const Color(0xFF2C5A96)
                                  : AppThemeColor.darkBlueColor)
                            : (isDark
                                  ? const Color(0xFF2C5A96)
                                  : AppThemeColor.lightBlueColor),
                        width: selected ? 1.0 : 0.5,
                      ),
                    ),
                    child: ListTile(
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 6,
                      ),
                      leading: _buildOrgAvatar(logoUrl, isDark),
                      title: Text(
                        orgName,
                        style: TextStyle(
                          color: theme.textTheme.titleMedium?.color,
                        ),
                      ),
                      subtitle:
                          FutureBuilder<QuerySnapshot<Map<String, dynamic>>>(
                            future: FirebaseFirestore.instance
                                .collection('Organizations')
                                .doc(orgId)
                                .collection('Members')
                                .where('status', isEqualTo: 'approved')
                                .get(),
                            builder: (context, snap) {
                              final count = snap.data?.docs.length ?? 0;
                              return Text(
                                count == 0
                                    ? _t('noMembers')
                                    : _t('members', {'count': '$count'}),
                                style: TextStyle(
                                  color: theme.textTheme.bodyMedium?.color,
                                ),
                              );
                            },
                          ),
                      trailing: Radio<String>(
                        value: orgId,
                        groupValue: _selectedOrgId,
                        onChanged: (val) {
                          setState(() {
                            _selectedOrgId = val;
                            _selectedOrgName = orgName;
                          });
                        },
                      ),
                      onTap: () {
                        setState(() {
                          if (_selectedOrgId == orgId) {
                            _selectedOrgId = null;
                            _selectedOrgName = null;
                          } else {
                            _selectedOrgId = orgId;
                            _selectedOrgName = orgName;
                          }
                        });
                      },
                    ),
                  );
                },
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildOrgAvatar(String logoUrl, bool isDark) {
    final bgColor = isDark
        ? const Color(0xFF4A90E2)
        : AppThemeColor.lightBlueColor;
    if (logoUrl.isEmpty) {
      return CircleAvatar(
        backgroundColor: bgColor,
        child: const Icon(Icons.group, color: Colors.white),
      );
    }
    return CircleAvatar(
      backgroundColor: bgColor,
      foregroundImage: NetworkImage(logoUrl),
      onForegroundImageError: (_, __) {},
      child: const Icon(Icons.group, color: Colors.white),
    );
  }

  void _showOrgInfo(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        decoration: BoxDecoration(
          color: Theme.of(context).cardColor,
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(16),
            topRight: Radius.circular(16),
          ),
        ),
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 8),
            Text(
              _t('aboutGroups'),
              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 16),
            ),
            const SizedBox(height: 8),
            Text(_t('orgGroupExplainer')),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
  }

  // (Removed) _buildOrganizationsSection replaced by tabbed UI

  // Legacy inline group header removed in favor of bottom sticky bar

  Widget _buildSearchBar() {
    final themeProvider = Provider.of<ThemeProvider>(context);
    final isDark = themeProvider.isDarkMode;
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
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
          child: Column(
            children: [
              Semantics(
                textField: true,
                label: _t('searchUsers'),
                hint: _t('searchUsersHint'),
                child: TextField(
                  controller: _searchController,
                  style: TextStyle(color: theme.textTheme.bodyLarge?.color),
                  decoration: InputDecoration(
                    hintText: _t('searchUsers'),
                    hintStyle: TextStyle(
                      color: theme.textTheme.bodyMedium?.color,
                    ),
                    prefixIcon: Icon(
                      Icons.search,
                      color: theme.textTheme.bodyMedium?.color,
                    ),
                    suffixIcon: _searchController.text.isNotEmpty
                        ? Semantics(
                            button: true,
                            label: _t('clearSearch'),
                            child: IconButton(
                              icon: Icon(
                                Icons.clear,
                                color: theme.textTheme.bodyMedium?.color,
                              ),
                              onPressed: () {
                                _searchController.clear();
                              },
                            ),
                          )
                        : null,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(
                        Dimensions.radiusLarge,
                      ),
                      borderSide: BorderSide(
                        color: isDark
                            ? const Color(0xFF4A90E2)
                            : AppThemeColor.lightBlueColor,
                      ),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(
                        Dimensions.radiusLarge,
                      ),
                      borderSide: BorderSide(
                        color: isDark
                            ? const Color(0xFF2C5A96)
                            : const Color(0xFF667EEA),
                        width: 2,
                      ),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(
                        Dimensions.radiusLarge,
                      ),
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
              ),
              if (_isSearchInFlight)
                const Padding(
                  padding: EdgeInsets.only(top: 8),
                  child: LinearProgressIndicator(minHeight: 2),
                ),
            ],
          ),
        ),
        // Only show recent searches in direct message mode, not in group mode
        // This prevents confusion between recent searches and selected users
        if (_recentSearches.isNotEmpty && !_groupMode)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Wrap(
              spacing: 8,
              runSpacing: 4,
              children: _recentSearches
                  .map(
                    (s) => Semantics(
                      label: _t('recentSearch', {'term': s}),
                      button: true,
                      child: InputChip(
                        label: Text(s),
                        onPressed: () {
                          _searchController.text = s;
                          _onSearchChanged();
                        },
                        onDeleted: () async {
                          final prefs = await SharedPreferences.getInstance();
                          final list =
                              prefs.getStringList(_prefsKeyRecent) ??
                              <String>[];
                          list.remove(s);
                          await prefs.setStringList(_prefsKeyRecent, list);
                          if (!mounted) return;
                          setState(() => _recentSearches = list);
                        },
                      ),
                    ),
                  )
                  .toList(),
            ),
          ),
      ],
    );
  }

  Widget _buildRetryBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: Semantics(
        container: true,
        label: _t('searchFailedMsg'),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: Colors.red.withValues(alpha: 0.06),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.red.withValues(alpha: 0.25)),
          ),
          child: Row(
            children: [
              const Icon(Icons.error_outline, color: Colors.red),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  _t('searchFailedMsg'),
                  style: const TextStyle(color: Colors.red),
                ),
              ),
              Semantics(
                button: true,
                label: _t('retry'),
                child: TextButton(
                  onPressed: () {
                    if (_lastSearchQuery.isNotEmpty) {
                      setState(() => _isSearchInFlight = true);
                      _performSearch(_lastSearchQuery);
                    }
                  },
                  child: Text(_t('retry')),
                ),
              ),
            ],
          ),
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
            _isSearching ? _t('noUsersFound') : _t('noUsersAvailable'),
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w600,
              color: isDark ? const Color(0xFF2C5A96) : const Color(0xFF667EEA),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            _isSearching ? _t('tryDifferentSearch') : _t('noUsersToMessage'),
            style: TextStyle(
              fontSize: 16,
              color: theme.textTheme.bodyMedium?.color,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            children: [
              OutlinedButton(
                onPressed: _inviteFriends,
                child: Text(_t('inviteFriends')),
              ),
              OutlinedButton(
                onPressed: _discoverPeople,
                child: Text(_t('discoverPeople')),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildUsersList() {
    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      controller: _listController,
      itemCount:
          (_searchResults.length > _listLimit
              ? _listLimit
              : _searchResults.length) +
          1,
      itemBuilder: (context, index) {
        if (index >=
            (_searchResults.length > _listLimit
                ? _listLimit
                : _searchResults.length)) {
          return (_searchResults.length > _listLimit)
              ? const Padding(
                  padding: EdgeInsets.symmetric(vertical: 12),
                  child: Center(
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                )
              : const SizedBox.shrink();
        }
        final user = _searchResults[index];
        return _buildUserTile(user);
      },
    );
  }

  Widget _buildUserTile(CustomerModel user) {
    final themeProvider = Provider.of<ThemeProvider>(context);
    final isDark = themeProvider.isDarkMode;
    final theme = Theme.of(context);
    final bool isSelected = _selectedUserIds.contains(user.uid);

    return Semantics(
      label: _groupMode
          ? 'Select ${user.name}'
          : 'Start conversation with ${user.name}',
      button: true,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        decoration: BoxDecoration(
          color: theme.cardColor,
          borderRadius: BorderRadius.circular(Dimensions.radiusLarge),
          border: Border.all(
            color: _groupMode && isSelected
                ? (isDark ? const Color(0xFF2C5A96) : const Color(0xFF667EEA))
                : Colors.transparent,
            width: _groupMode && isSelected ? 1.2 : 0.0,
          ),
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
          leading: ClipRRect(
            borderRadius: BorderRadius.circular(20),
            child: Container(
              width: 56,
              height: 56,
              color: isDark
                  ? const Color(0xFF4A90E2)
                  : AppThemeColor.lightBlueColor,
              child:
                  (user.profilePictureUrl != null &&
                      user.profilePictureUrl!.isNotEmpty)
                  ? SafeNetworkImage(
                      imageUrl: user.profilePictureUrl!,
                      fit: BoxFit.cover,
                      placeholder: Icon(
                        Icons.person,
                        color: isDark
                            ? const Color(0xFF2C5A96)
                            : const Color(0xFF667EEA),
                      ),
                      errorWidget: _buildAvatarFallback(user, isDark),
                    )
                  : _buildAvatarFallback(user, isDark),
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
              if (user.username != null && user.username!.isNotEmpty) ...[
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
          trailing: _groupMode
              ? Checkbox(
                  value: isSelected,
                  onChanged: (checked) {
                    setState(() {
                      if (checked == true) {
                        _selectedUserIds.add(user.uid);
                      } else {
                        _selectedUserIds.remove(user.uid);
                      }
                    });
                    HapticFeedback.selectionClick();
                  },
                )
              : Icon(
                  Icons.chevron_right,
                  color: theme.textTheme.bodyMedium?.color,
                ),
          onTap: _groupMode
              ? () {
                  setState(() {
                    if (_selectedUserIds.contains(user.uid)) {
                      _selectedUserIds.remove(user.uid);
                    } else {
                      _selectedUserIds.add(user.uid);
                    }
                  });
                  HapticFeedback.selectionClick();
                }
              : () => _startConversation(user),
          onLongPress: () => _showUserActions(user),
        ),
      ),
    );
  }

  Widget _buildAvatarFallback(CustomerModel user, bool isDark) {
    final initial = (user.name.isNotEmpty ? user.name[0] : '?').toUpperCase();
    final bg = _colorFromString(user.uid);
    return Container(
      color: bg,
      alignment: Alignment.center,
      child: Text(
        initial,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 20,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  Color _colorFromString(String input) {
    final hash = input.codeUnits.fold<int>(0, (prev, el) => prev + el);
    final r = (hash & 0xFF0000) >> 16;
    final g = (hash & 0x00FF00) >> 8;
    final b = (hash & 0x0000FF);
    return Color.fromARGB(
      255,
      (r + 60) % 256,
      (g + 120) % 256,
      (b + 180) % 256,
    );
  }

  void _onListScroll() {
    if (!_listController.hasClients) return;
    final position = _listController.position;
    if (position.pixels > position.maxScrollExtent - 200) {
      if (_listLimit < _searchResults.length) {
        setState(
          () => _listLimit = (_listLimit + 30).clamp(0, _searchResults.length),
        );
      }
    }
  }

  Widget _buildSelectedChips() {
    final selected = _allUsers
        .where((u) => _selectedUserIds.contains(u.uid))
        .toList();
    if (selected.isEmpty) return const SizedBox.shrink();
    return SizedBox(
      height: 48,
      child: ListView.separated(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        scrollDirection: Axis.horizontal,
        itemCount: selected.length,
        separatorBuilder: (_, index) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final u = selected[index];
          return Semantics(
            label: _t('selectedUserChip', {'name': u.name}),
            hint: _t('removeSelectedHint'),
            button: true,
            child: InputChip(
              label: Text(u.name, overflow: TextOverflow.ellipsis),
              onDeleted: () {
                setState(() => _selectedUserIds.remove(u.uid));
              },
            ),
          );
        },
      ),
    );
  }

  Widget? _buildCreateGroupBar() {
    if (!_groupMode) return null;
    final onUsersTab = _groupTabIndex == 0;
    final canCreateFromUsers = onUsersTab && _selectedUserIds.length >= 2;
    final canCreateFromOrg =
        !onUsersTab && _selectedOrgId != null && _selectedOrgId!.isNotEmpty;
    if (!canCreateFromUsers && !canCreateFromOrg) return null;
    return SafeArea(
      child: Semantics(
        label: onUsersTab ? _t('createWithSelected') : _t('createFromOrg'),
        button: true,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: BoxDecoration(
            color: Theme.of(context).cardColor,
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.05),
                blurRadius: 8,
                offset: const Offset(0, -2),
              ),
            ],
          ),
          child: Row(
            children: [
              if (onUsersTab) ...[
                CircleAvatar(
                  radius: 14,
                  backgroundColor: Theme.of(
                    context,
                  ).colorScheme.primary.withValues(alpha: 0.15),
                  child: Text(
                    '${_selectedUserIds.length}',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.primary,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(child: Text(_t('createWithSelected'))),
                FilledButton(
                  onPressed: _createGroupAndOpenChat,
                  child: Text(_t('createGroup')),
                ),
              ] else ...[
                const Icon(Icons.group_outlined),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    _selectedOrgName == null || _selectedOrgName!.isEmpty
                        ? _t('createFromOrg')
                        : 'Create group from "${_selectedOrgName!}"',
                  ),
                ),
                FilledButton(
                  onPressed: () {
                    if (_selectedOrgId != null && _selectedOrgId!.isNotEmpty) {
                      _createGroupFromOrganization(
                        _selectedOrgId!,
                        _selectedOrgName ?? 'Group',
                      );
                    }
                  },
                  child: Text(_t('createGroup')),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildShimmerList() {
    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      itemCount: 6,
      itemBuilder: (_, index) => Container(
        margin: const EdgeInsets.only(bottom: 12),
        child: Shimmer.fromColors(
          baseColor: Colors.grey.shade300,
          highlightColor: Colors.grey.shade100,
          child: Container(
            height: 80,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(Dimensions.radiusLarge),
            ),
          ),
        ),
      ),
    );
  }

  void _showUserActions(CustomerModel user) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        decoration: BoxDecoration(
          color: Theme.of(context).cardColor,
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(16),
            topRight: Radius.circular(16),
          ),
        ),
        child: SafeArea(
          top: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.person_outline),
                title: Text(_t('viewProfile')),
                onTap: () {
                  Navigator.pop(context);
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) =>
                          UserProfileScreen(user: user, isOwnProfile: false),
                    ),
                  );
                },
              ),
              ListTile(
                leading: const Icon(Icons.message_outlined),
                title: Text(_t('message')),
                onTap: () {
                  Navigator.pop(context);
                  _startConversation(user);
                },
              ),
              ListTile(
                leading: const Icon(
                  Icons.report_outlined,
                  color: Colors.orange,
                ),
                title: Text(_t('reportOrBlock')),
                onTap: () {
                  Navigator.pop(context);
                  ShowToast().showNormalToast(msg: 'Reported');
                },
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }

  // Simple localization shim; replace with your app's localization later
  String _t(String key, [Map<String, String>? vars]) {
    final m = <String, String>{
      'newMessage': 'New Message',
      'newGroupMessage': 'New Group Message',
      'yourGroups': 'Your Groups',
      'info': 'Info',
      'refresh': 'Refresh',
      'noMembers': 'No members',
      'members': '${vars?['count'] ?? '{count}'} members',
      'noUsersFound': 'No users found',
      'noUsersAvailable': 'No users available',
      'tryDifferentSearch': 'Try a different search term',
      'noUsersToMessage': 'There are no other users to message',
      'inviteFriends': 'Invite friends',
      'discoverPeople': 'Discover people',
      'aboutGroups': 'About groups',
      'orgGroupExplainer':
          'Selecting a group here will create a group conversation with all approved members of that organization.',
      'viewProfile': 'View profile',
      'message': 'Message',
      'reportOrBlock': 'Report / Block',
      'createWithSelected': 'Create group with selected users',
      'createGroup': 'Create group',
      'createFromOrg': 'Create group from selected organization',
      'searchFailedToast': 'Search failed. Try again.',
      'searchFailedMsg': 'Search failed. Please try again.',
      'retry': 'Retry',
      'messageType': 'Message type',
      'searchUsers': 'Search users...',
      'searchUsersHint': 'Type a name or @username',
      'clearSearch': 'Clear search',
      'recentSearch': 'Recent search: {term}',
      'selectedUserChip': 'Selected: {name}',
      'removeSelectedHint': 'Double tap to remove',
      'a11yScaleFabTooltip': 'Toggle text scale for accessibility testing',
      'a11yScaleFabLabel': 'Change text scale to {scale}',
    };
    String value = m[key] ?? key;
    if (vars != null) {
      vars.forEach((k, v) => value = value.replaceAll('{$k}', v));
    }
    return value;
  }

  void _inviteFriends() {
    SharePlus.instance.share(
      ShareParams(text: 'Join me on AttendUs to chat and collaborate!'),
    );
  }

  void _discoverPeople() {
    try {
      Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const GroupsScreen()),
      );
    } catch (_) {
      ShowToast().showNormalToast(msg: 'Discover coming soon');
    }
  }
}
