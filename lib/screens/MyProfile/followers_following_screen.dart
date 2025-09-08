import 'package:flutter/material.dart';
import 'package:attendus/models/customer_model.dart';
import 'package:attendus/Utils/colors.dart';
import 'package:attendus/Utils/dimensions.dart';
import 'package:attendus/Utils/cached_image.dart';
import 'package:attendus/firebase/firebase_firestore_helper.dart';
import 'package:attendus/Utils/toast.dart';
import 'package:attendus/controller/customer_controller.dart';
import 'package:attendus/widgets/app_scaffold_wrapper.dart';

class FollowersFollowingScreen extends StatefulWidget {
  final CustomerModel user;
  final String initialTab; // 'followers' or 'following'

  const FollowersFollowingScreen({
    super.key,
    required this.user,
    this.initialTab = 'followers',
  });

  @override
  State<FollowersFollowingScreen> createState() =>
      _FollowersFollowingScreenState();
}

class _FollowersFollowingScreenState extends State<FollowersFollowingScreen>
    with TickerProviderStateMixin {
  late TabController _tabController;
  List<CustomerModel> _followers = [];
  List<CustomerModel> _following = [];
  List<CustomerModel> _filteredFollowers = [];
  List<CustomerModel> _filteredFollowing = [];
  bool _isLoadingFollowers = true;
  bool _isLoadingFollowing = true;
  int _followersCount = 0;
  int _followingCount = 0;

  // Search functionality
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  // Follow status tracking
  final Map<String, bool> _followStatus = {};

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);

    // Set initial tab
    if (widget.initialTab == 'following') {
      _tabController.index = 1;
    }

    _loadData();

    // Listen to search changes
    _searchController.addListener(_onSearchChanged);
  }

  @override
  void dispose() {
    _tabController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  void _onSearchChanged() {
    setState(() {
      _searchQuery = _searchController.text.toLowerCase();
      _filterUsers();
    });
  }

  void _filterUsers() {
    if (_searchQuery.isEmpty) {
      _filteredFollowers = List.from(_followers);
      _filteredFollowing = List.from(_following);
    } else {
      _filteredFollowers = _followers.where((user) {
        return user.name.toLowerCase().contains(_searchQuery) ||
            (user.username?.toLowerCase().contains(_searchQuery) ?? false) ||
            (user.bio?.toLowerCase().contains(_searchQuery) ?? false);
      }).toList();

      _filteredFollowing = _following.where((user) {
        return user.name.toLowerCase().contains(_searchQuery) ||
            (user.username?.toLowerCase().contains(_searchQuery) ?? false) ||
            (user.bio?.toLowerCase().contains(_searchQuery) ?? false);
      }).toList();
    }
  }

  Future<void> _loadData() async {
    await Future.wait([_loadFollowers(), _loadFollowing()]);
  }

  Future<void> _loadFollowers() async {
    try {
      final followerIds = await FirebaseFirestoreHelper().getFollowersList(
        userId: widget.user.uid,
      );

      final followers = await FirebaseFirestoreHelper().getUsersByIds(
        userIds: followerIds,
      );

      if (mounted) {
        setState(() {
          _followers = followers;
          _filteredFollowers = List.from(followers);
          _followersCount = followers.length;
          _isLoadingFollowers = false;
        });
        _loadFollowStatuses(followers);
      }
    } catch (e) {
      debugPrint('Error loading followers: $e');
      if (mounted) {
        setState(() {
          _isLoadingFollowers = false;
        });
      }
    }
  }

  Future<void> _loadFollowing() async {
    try {
      final followingIds = await FirebaseFirestoreHelper().getFollowingList(
        userId: widget.user.uid,
      );

      final following = await FirebaseFirestoreHelper().getUsersByIds(
        userIds: followingIds,
      );

      if (mounted) {
        setState(() {
          _following = following;
          _filteredFollowing = List.from(following);
          _followingCount = following.length;
          _isLoadingFollowing = false;
        });
        _loadFollowStatuses(following);
      }
    } catch (e) {
      debugPrint('Error loading following: $e');
      if (mounted) {
        setState(() {
          _isLoadingFollowing = false;
        });
      }
    }
  }

  Future<void> _loadFollowStatuses(List<CustomerModel> users) async {
    if (CustomerController.logeInCustomer == null) return;

    try {
      for (final user in users) {
        if (user.uid != CustomerController.logeInCustomer!.uid) {
          final isFollowing = await FirebaseFirestoreHelper().isFollowingUser(
            followerId: CustomerController.logeInCustomer!.uid,
            followingId: user.uid,
          );
          setState(() {
            _followStatus[user.uid] = isFollowing;
          });
        }
      }
    } catch (e) {
      debugPrint('Error loading follow statuses: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return AppScaffoldWrapper(
      selectedBottomNavIndex: 3, // Profile tab
      backgroundColor: AppThemeColor.backGroundColor,
      body: SafeArea(
        child: Column(
          children: [
            _buildAppBar(),
            _buildTabBar(),
            _buildSearchBar(),
            Expanded(child: _buildTabContent()),
          ],
        ),
      ),
    );
  }

  Widget _buildAppBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
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
      child: Row(
        children: [
          IconButton(
            icon: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(
                Icons.arrow_back_ios_new,
                color: AppThemeColor.pureWhiteColor,
                size: 20,
              ),
            ),
            onPressed: () => Navigator.pop(context),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.user.name,
                  style: const TextStyle(
                    color: AppThemeColor.pureWhiteColor,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    fontFamily: 'Roboto',
                  ),
                ),
                Text(
                  'Followers & Following',
                  style: TextStyle(
                    color: AppThemeColor.pureWhiteColor.withValues(alpha: 0.8),
                    fontSize: 14,
                    fontFamily: 'Roboto',
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTabBar() {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      decoration: BoxDecoration(
        color: AppThemeColor.pureWhiteColor,
        borderRadius: BorderRadius.circular(Dimensions.radiusLarge),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: TabBar(
        controller: _tabController,
        indicator: BoxDecoration(
          borderRadius: BorderRadius.circular(Dimensions.radiusLarge),
          color: AppThemeColor.darkBlueColor,
        ),
        indicatorSize: TabBarIndicatorSize.tab,
        labelColor: AppThemeColor.pureWhiteColor,
        unselectedLabelColor: AppThemeColor.dullFontColor,
        labelStyle: const TextStyle(
          fontWeight: FontWeight.w600,
          fontSize: 14,
          fontFamily: 'Roboto',
        ),
        unselectedLabelStyle: const TextStyle(
          fontWeight: FontWeight.normal,
          fontSize: 14,
          fontFamily: 'Roboto',
        ),
        dividerColor: Colors.transparent,
        tabs: [
          Tab(text: '$_followersCount Followers'),
          Tab(text: '$_followingCount Following'),
        ],
      ),
    );
  }

  Widget _buildSearchBar() {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      decoration: BoxDecoration(
        color: AppThemeColor.pureWhiteColor,
        borderRadius: BorderRadius.circular(Dimensions.radiusLarge),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 8,
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
            fontSize: 14,
            fontFamily: 'Roboto',
          ),
          prefixIcon: Icon(
            Icons.search,
            color: AppThemeColor.dullIconColor,
            size: 20,
          ),
          suffixIcon: _searchQuery.isNotEmpty
              ? IconButton(
                  icon: Icon(
                    Icons.clear,
                    color: AppThemeColor.dullIconColor,
                    size: 20,
                  ),
                  onPressed: () {
                    _searchController.clear();
                  },
                )
              : null,
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 12,
          ),
        ),
        style: const TextStyle(
          fontSize: 14,
          fontFamily: 'Roboto',
          color: AppThemeColor.darkBlueColor,
        ),
      ),
    );
  }

  Widget _buildTabContent() {
    return TabBarView(
      controller: _tabController,
      children: [_buildFollowersTab(), _buildFollowingTab()],
    );
  }

  Widget _buildFollowersTab() {
    if (_isLoadingFollowers) {
      return const Center(
        child: CircularProgressIndicator(color: AppThemeColor.darkBlueColor),
      );
    }

    if (_filteredFollowers.isEmpty) {
      return _buildEmptyState(
        _searchQuery.isNotEmpty ? 'No Results Found' : 'No Followers Yet',
        _searchQuery.isNotEmpty
            ? 'Try adjusting your search terms.'
            : 'When people follow ${widget.user.name}, they\'ll appear here.',
        _searchQuery.isNotEmpty ? Icons.search_off : Icons.people_outline,
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      itemCount: _filteredFollowers.length,
      itemBuilder: (context, index) {
        final follower = _filteredFollowers[index];
        return _buildUserTile(follower);
      },
    );
  }

  Widget _buildFollowingTab() {
    if (_isLoadingFollowing) {
      return const Center(
        child: CircularProgressIndicator(color: AppThemeColor.darkBlueColor),
      );
    }

    if (_filteredFollowing.isEmpty) {
      return _buildEmptyState(
        _searchQuery.isNotEmpty ? 'No Results Found' : 'Not Following Anyone',
        _searchQuery.isNotEmpty
            ? 'Try adjusting your search terms.'
            : 'When ${widget.user.name} follows people, they\'ll appear here.',
        _searchQuery.isNotEmpty ? Icons.search_off : Icons.person_add_outlined,
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      itemCount: _filteredFollowing.length,
      itemBuilder: (context, index) {
        final following = _filteredFollowing[index];
        return _buildUserTile(following);
      },
    );
  }

  Widget _buildUserTile(CustomerModel user) {
    final isCurrentUser = user.uid == CustomerController.logeInCustomer?.uid;
    final isFollowing = _followStatus[user.uid] ?? false;

    return GestureDetector(
      onTap: () => _navigateToUserProfile(user),
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppThemeColor.pureWhiteColor,
          borderRadius: BorderRadius.circular(Dimensions.radiusLarge),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          children: [
            // Profile Image
            Container(
              width: 50,
              height: 50,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(25),
                border: Border.all(color: AppThemeColor.borderColor),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(25),
                child: user.profilePictureUrl != null
                    ? SafeNetworkImage(
                        imageUrl: user.profilePictureUrl!,
                        fit: BoxFit.cover,
                        placeholder: Container(
                          color: AppThemeColor.lightBlueColor,
                          child: const Icon(
                            Icons.person,
                            size: 25,
                            color: AppThemeColor.darkBlueColor,
                          ),
                        ),
                        errorWidget: Container(
                          color: AppThemeColor.lightBlueColor,
                          child: const Icon(
                            Icons.person,
                            size: 25,
                            color: AppThemeColor.darkBlueColor,
                          ),
                        ),
                      )
                    : Container(
                        color: AppThemeColor.lightBlueColor,
                        child: const Icon(
                          Icons.person,
                          size: 25,
                          color: AppThemeColor.darkBlueColor,
                        ),
                      ),
              ),
            ),
            const SizedBox(width: 12),
            // User Info
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    user.name,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: AppThemeColor.darkBlueColor,
                      fontFamily: 'Roboto',
                    ),
                  ),
                  if (user.username != null && user.username!.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      '@${user.username}',
                      style: TextStyle(
                        fontSize: 14,
                        color: AppThemeColor.dullFontColor,
                        fontFamily: 'Roboto',
                      ),
                    ),
                  ],
                  if (user.bio != null && user.bio!.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      user.bio!,
                      style: TextStyle(
                        fontSize: 12,
                        color: AppThemeColor.dullFontColor,
                        fontFamily: 'Roboto',
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ],
              ),
            ),
            // Follow Button
            if (!isCurrentUser) ...[
              const SizedBox(width: 8),
              _buildFollowButton(user, isFollowing),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildFollowButton(CustomerModel user, bool isFollowing) {
    return Container(
      height: 32,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: isFollowing
            ? AppThemeColor.pureWhiteColor
            : AppThemeColor.darkBlueColor,
        borderRadius: BorderRadius.circular(16),
        border: isFollowing
            ? Border.all(color: AppThemeColor.darkBlueColor)
            : null,
      ),
      child: TextButton(
        onPressed: () => _toggleFollow(user),
        style: TextButton.styleFrom(
          padding: EdgeInsets.zero,
          minimumSize: Size.zero,
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
        child: Text(
          isFollowing ? 'Following' : 'Follow',
          style: TextStyle(
            color: isFollowing
                ? AppThemeColor.darkBlueColor
                : AppThemeColor.pureWhiteColor,
            fontSize: 12,
            fontWeight: FontWeight.w600,
            fontFamily: 'Roboto',
          ),
        ),
      ),
    );
  }

  Future<void> _toggleFollow(CustomerModel user) async {
    if (CustomerController.logeInCustomer == null) {
      ShowToast().showNormalToast(msg: 'Please log in to follow users');
      return;
    }

    if (user.uid == CustomerController.logeInCustomer!.uid) {
      ShowToast().showNormalToast(msg: 'You cannot follow yourself');
      return;
    }

    final currentStatus = _followStatus[user.uid] ?? false;

    setState(() {
      _followStatus[user.uid] = !currentStatus;
    });

    try {
      if (currentStatus) {
        await FirebaseFirestoreHelper().unfollowUser(
          followerId: CustomerController.logeInCustomer!.uid,
          followingId: user.uid,
        );
        ShowToast().showNormalToast(msg: 'Unfollowed ${user.name}');
      } else {
        await FirebaseFirestoreHelper().followUser(
          followerId: CustomerController.logeInCustomer!.uid,
          followingId: user.uid,
        );
        ShowToast().showNormalToast(msg: 'Following ${user.name}');
      }
    } catch (e) {
      debugPrint('Error toggling follow status: $e');
      // Revert the state change on error
      setState(() {
        _followStatus[user.uid] = currentStatus;
      });

      if (e.toString().contains('permission-denied')) {
        ShowToast().showNormalToast(
          msg: 'Follow feature is not available yet. Coming soon!',
        );
      } else {
        ShowToast().showNormalToast(
          msg: 'Error updating follow status. Please try again.',
        );
      }
    }
  }

  Widget _buildEmptyState(String title, String message, IconData icon) {
    return Container(
      padding: const EdgeInsets.all(40),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 64, color: AppThemeColor.dullIconColor),
          const SizedBox(height: 24),
          Text(
            title,
            style: const TextStyle(
              fontSize: Dimensions.fontSizeLarge,
              fontWeight: FontWeight.bold,
              color: AppThemeColor.darkBlueColor,
              fontFamily: 'Roboto',
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          Text(
            message,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: Dimensions.fontSizeDefault,
              color: AppThemeColor.dullFontColor,
              fontFamily: 'Roboto',
            ),
          ),
        ],
      ),
    );
  }

  void _navigateToUserProfile(CustomerModel user) {
    Navigator.pop(context, user);
  }
}
