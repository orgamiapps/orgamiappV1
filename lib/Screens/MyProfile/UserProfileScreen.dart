import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:orgami/Models/CustomerModel.dart';
import 'package:orgami/Models/EventModel.dart';
import 'package:orgami/Utils/Colors.dart';
import 'package:orgami/Utils/dimensions.dart';
import 'package:orgami/Utils/cached_image.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:share_plus/share_plus.dart';
import 'package:orgami/Firebase/FirebaseFirestoreHelper.dart';
import 'package:orgami/Utils/Toast.dart';
import 'package:orgami/Screens/Events/Widget/SingleEventListViewItem.dart';
import 'package:orgami/Controller/CustomerController.dart';
import 'package:orgami/Screens/MyProfile/FollowersFollowingScreen.dart';

class UserProfileScreen extends StatefulWidget {
  final CustomerModel user;
  final bool isOwnProfile;

  const UserProfileScreen({
    super.key,
    required this.user,
    this.isOwnProfile = false,
  });

  @override
  State<UserProfileScreen> createState() => _UserProfileScreenState();
}

class _UserProfileScreenState extends State<UserProfileScreen>
    with TickerProviderStateMixin {
  late TabController _tabController;
  List<EventModel> _createdEvents = [];
  List<EventModel> _attendedEvents = [];
  bool _isLoading = true;
  bool _isFollowing = false;
  int _followersCount = 0;
  int _followingCount = 0;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _loadUserData();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadUserData() async {
    if (!mounted) return;

    setState(() => _isLoading = true);

    try {
      print('Loading user data for: ${widget.user.uid}');

      // Load user's created events
      List<EventModel> createdEvents = [];
      try {
        createdEvents = await FirebaseFirestoreHelper().getEventsCreatedByUser(
          widget.user.uid,
        );
        // Sort by most recent to oldest
        createdEvents.sort(
          (a, b) => b.eventGenerateTime.compareTo(a.eventGenerateTime),
        );
        print('Loaded ${createdEvents.length} created events');
      } catch (e) {
        print('Error loading created events: $e');
        createdEvents = [];
      }

      // Load user's attended events
      List<EventModel> attendedEvents = [];
      try {
        attendedEvents = await FirebaseFirestoreHelper()
            .getEventsAttendedByUser(widget.user.uid);
        // Sort by most recent to oldest
        attendedEvents.sort(
          (a, b) => b.eventGenerateTime.compareTo(a.eventGenerateTime),
        );
        print('Loaded ${attendedEvents.length} attended events');
      } catch (e) {
        print('Error loading attended events: $e');
        attendedEvents = [];
      }

      // Load follower/following counts
      int followersCount = 0;
      int followingCount = 0;
      try {
        followersCount = await FirebaseFirestoreHelper().getFollowersCount(
          userId: widget.user.uid,
        );
        followingCount = await FirebaseFirestoreHelper().getFollowingCount(
          userId: widget.user.uid,
        );
        print('Loaded followers: $followersCount, following: $followingCount');
      } catch (e) {
        print('Error loading follow counts: $e');
        followersCount = 0;
        followingCount = 0;
      }

      // Check if current user is following this user (only if not own profile)
      bool isFollowing = false;
      try {
        if (!widget.isOwnProfile && CustomerController.logeInCustomer != null) {
          isFollowing = await FirebaseFirestoreHelper().isFollowingUser(
            followerId: CustomerController.logeInCustomer!.uid,
            followingId: widget.user.uid,
          );
          print('Follow status: $isFollowing');
        }
      } catch (e) {
        print('Error checking follow status: $e');
        isFollowing = false;
      }

      if (mounted) {
        setState(() {
          _createdEvents = createdEvents;
          _attendedEvents = attendedEvents;
          _followersCount = followersCount;
          _followingCount = followingCount;
          _isFollowing = isFollowing;
          _isLoading = false;
        });
        print('User data loaded successfully');
      }
    } catch (e) {
      print('Error loading user data: $e');
      if (mounted) {
        setState(() {
          _isLoading = false;
          _createdEvents = [];
          _attendedEvents = [];
          _followersCount = 0;
          _followingCount = 0;
          _isFollowing = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    print('Building UserProfileScreen - isLoading: $_isLoading');

    if (_isLoading) {
      return Scaffold(
        backgroundColor: AppThemeColor.backGroundColor,
        body: SafeArea(
          child: Container(
            color: AppThemeColor.backGroundColor,
            child: const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  CircularProgressIndicator(color: AppThemeColor.darkBlueColor),
                  SizedBox(height: 16),
                  Text(
                    'Loading profile...',
                    style: TextStyle(
                      color: AppThemeColor.darkBlueColor,
                      fontSize: 16,
                      fontFamily: 'Roboto',
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: AppThemeColor.backGroundColor,
      body: SafeArea(
        child: Column(
          children: [
            _buildAppBar(),
            Expanded(
              child: Column(
                children: [
                  _buildProfileHeader(),
                  _buildStatsSection(),
                  _buildTabBar(),
                  Expanded(child: _buildTabContent()),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAppBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
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
          const Spacer(),
          if (!widget.isOwnProfile) ...[
            IconButton(
              icon: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.share_outlined,
                  color: AppThemeColor.pureWhiteColor,
                  size: 20,
                ),
              ),
              onPressed: () => _shareProfile(),
            ),
            IconButton(
              icon: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.more_vert,
                  color: AppThemeColor.pureWhiteColor,
                  size: 20,
                ),
              ),
              onPressed: () => _showProfileOptions(context),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildProfileHeader() {
    return Container(
      padding: const EdgeInsets.all(24),
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
      child: Column(
        children: [
          Row(
            children: [
              // Profile Image
              Container(
                width: 80,
                height: 80,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(40),
                  border: Border.all(
                    color: AppThemeColor.pureWhiteColor,
                    width: 3,
                  ),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(37),
                  child: widget.user.profilePictureUrl != null
                      ? SafeNetworkImage(
                          imageUrl: widget.user.profilePictureUrl!,
                          fit: BoxFit.cover,
                          placeholder: Container(
                            color: AppThemeColor.lightBlueColor,
                            child: const Icon(
                              Icons.person,
                              size: 40,
                              color: AppThemeColor.darkBlueColor,
                            ),
                          ),
                          errorWidget: Container(
                            color: AppThemeColor.lightBlueColor,
                            child: const Icon(
                              Icons.person,
                              size: 40,
                              color: AppThemeColor.darkBlueColor,
                            ),
                          ),
                        )
                      : Container(
                          color: AppThemeColor.lightBlueColor,
                          child: const Icon(
                            Icons.person,
                            size: 40,
                            color: AppThemeColor.darkBlueColor,
                          ),
                        ),
                ),
              ),
              const SizedBox(width: 16),
              // User Info
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.user.name,
                      style: const TextStyle(
                        color: AppThemeColor.pureWhiteColor,
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                        fontFamily: 'Roboto',
                      ),
                    ),
                    if (widget.user.username != null) ...[
                      const SizedBox(height: 4),
                      Text(
                        '@${widget.user.username}',
                        style: TextStyle(
                          color: AppThemeColor.pureWhiteColor.withValues(
                            alpha: 0.8,
                          ),
                          fontSize: 16,
                          fontFamily: 'Roboto',
                        ),
                      ),
                    ],
                    if (widget.user.bio != null &&
                        widget.user.bio!.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Text(
                        widget.user.bio!,
                        style: TextStyle(
                          color: AppThemeColor.pureWhiteColor.withValues(
                            alpha: 0.9,
                          ),
                          fontSize: 14,
                          fontFamily: 'Roboto',
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
          // Follow button for non-own profiles
          if (!widget.isOwnProfile) ...[
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: Container(
                    height: 48,
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [
                          AppThemeColor.darkBlueColor,
                          AppThemeColor.dullBlueColor,
                        ],
                      ),
                      borderRadius: BorderRadius.circular(
                        Dimensions.radiusLarge,
                      ),
                    ),
                    child: ElevatedButton(
                      onPressed: () => _toggleFollow(),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.transparent,
                        shadowColor: Colors.transparent,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(
                            Dimensions.radiusLarge,
                          ),
                        ),
                      ),
                      child: Text(
                        _isFollowing ? 'Following' : 'Follow',
                        style: const TextStyle(
                          color: AppThemeColor.pureWhiteColor,
                          fontSize: Dimensions.fontSizeDefault,
                          fontWeight: FontWeight.w600,
                          fontFamily: 'Roboto',
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Container(
                  height: 48,
                  width: 48,
                  decoration: BoxDecoration(
                    color: AppThemeColor.pureWhiteColor,
                    borderRadius: BorderRadius.circular(Dimensions.radiusLarge),
                    border: Border.all(color: AppThemeColor.borderColor),
                  ),
                  child: IconButton(
                    onPressed: () => _showMessageDialog(),
                    icon: const Icon(
                      Icons.message_outlined,
                      color: AppThemeColor.darkBlueColor,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildStatsSection() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      padding: const EdgeInsets.all(20),
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
      child: Row(
        children: [
          Expanded(
            child: GestureDetector(
              onTap: () => _showFollowersFollowing('followers'),
              child: Column(
                children: [
                  Text(
                    '$_followersCount',
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: AppThemeColor.darkBlueColor,
                      fontFamily: 'Roboto',
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Followers',
                    style: TextStyle(
                      fontSize: 12,
                      color: AppThemeColor.dullFontColor,
                      fontFamily: 'Roboto',
                    ),
                  ),
                ],
              ),
            ),
          ),
          Container(width: 1, height: 40, color: AppThemeColor.borderColor),
          Expanded(
            child: GestureDetector(
              onTap: () => _showFollowersFollowing('following'),
              child: Column(
                children: [
                  Text(
                    '$_followingCount',
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: AppThemeColor.darkBlueColor,
                      fontFamily: 'Roboto',
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Following',
                    style: TextStyle(
                      fontSize: 12,
                      color: AppThemeColor.dullFontColor,
                      fontFamily: 'Roboto',
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTabBar() {
    return Container(
      margin: const EdgeInsets.fromLTRB(24, 0, 24, 16),
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
      child: Row(
        children: [
          _buildTabButton(
            label: '${_createdEvents.length} Created Events',
            index: 0,
            icon: Icons.add_circle_outline,
          ),
          Container(width: 1, height: 40, color: AppThemeColor.borderColor),
          _buildTabButton(
            label: '${_attendedEvents.length} Attended',
            index: 1,
            icon: Icons.check_circle_outline,
          ),
        ],
      ),
    );
  }

  Widget _buildTabButton({
    required String label,
    required int index,
    required IconData icon,
  }) {
    final isSelected = _tabController.index == index;
    return Expanded(
      child: GestureDetector(
        onTap: () {
          if (_tabController.index != index) {
            setState(() {
              _tabController.animateTo(index);
            });
          }
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 300),
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
          decoration: BoxDecoration(
            color: isSelected
                ? AppThemeColor.darkBlueColor
                : Colors.transparent,
            borderRadius: BorderRadius.circular(Dimensions.radiusLarge),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                color: isSelected
                    ? AppThemeColor.pureWhiteColor
                    : AppThemeColor.dullIconColor,
                size: 18,
              ),
              const SizedBox(height: 4),
              Text(
                label,
                style: TextStyle(
                  color: isSelected
                      ? AppThemeColor.pureWhiteColor
                      : AppThemeColor.dullFontColor,
                  fontSize: 10,
                  fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                  fontFamily: 'Roboto',
                ),
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTabContent() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 24),
      child: TabBarView(
        controller: _tabController,
        children: [_buildCreatedEventsTab(), _buildAttendedEventsTab()],
      ),
    );
  }

  Widget _buildCreatedEventsTab() {
    print('Building created events tab with ${_createdEvents.length} events');

    if (_createdEvents.isEmpty) {
      return _buildEmptyState(
        'No Created Events',
        'This user hasn\'t created any events yet.',
        Icons.event_outlined,
      );
    }

    return ListView.builder(
      itemCount: _createdEvents.length,
      itemBuilder: (context, index) {
        final event = _createdEvents[index];
        return Container(
          margin: const EdgeInsets.only(bottom: 12),
          child: SingleEventListViewItem(eventModel: event),
        );
      },
    );
  }

  Widget _buildAttendedEventsTab() {
    print('Building attended events tab with ${_attendedEvents.length} events');

    if (_attendedEvents.isEmpty) {
      return _buildEmptyState(
        'No Attended Events',
        'This user hasn\'t attended any events yet.',
        Icons.check_circle_outline,
      );
    }

    return ListView.builder(
      itemCount: _attendedEvents.length,
      itemBuilder: (context, index) {
        final event = _attendedEvents[index];
        return Container(
          margin: const EdgeInsets.only(bottom: 12),
          child: SingleEventListViewItem(eventModel: event),
        );
      },
    );
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

  void _toggleFollow() async {
    if (CustomerController.logeInCustomer == null) {
      ShowToast().showNormalToast(msg: 'Please log in to follow users');
      return;
    }

    if (widget.isOwnProfile) {
      ShowToast().showNormalToast(msg: 'You cannot follow yourself');
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      if (_isFollowing) {
        await FirebaseFirestoreHelper().unfollowUser(
          followerId: CustomerController.logeInCustomer!.uid,
          followingId: widget.user.uid,
        );
        setState(() {
          _isFollowing = false;
          _followersCount--;
        });
        ShowToast().showNormalToast(msg: 'Unfollowed ${widget.user.name}');
      } else {
        await FirebaseFirestoreHelper().followUser(
          followerId: CustomerController.logeInCustomer!.uid,
          followingId: widget.user.uid,
        );
        setState(() {
          _isFollowing = true;
          _followersCount++;
        });
        ShowToast().showNormalToast(msg: 'Following ${widget.user.name}');
      }
    } catch (e) {
      print('Error toggling follow status: $e');
      if (e.toString().contains('permission-denied')) {
        ShowToast().showNormalToast(
          msg: 'Follow feature is not available yet. Coming soon!',
        );
      } else {
        ShowToast().showNormalToast(
          msg: 'Error updating follow status. Please try again.',
        );
      }
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  void _showMessageDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Send Message'),
        content: const Text('This feature will be available soon!'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  void _showFollowersFollowing(String initialTab) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) =>
            FollowersFollowingScreen(user: widget.user, initialTab: initialTab),
      ),
    ).then((selectedUser) {
      if (selectedUser != null && selectedUser is CustomerModel) {
        // Navigate to the selected user's profile
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (context) => UserProfileScreen(
              user: selectedUser,
              isOwnProfile:
                  selectedUser.uid == CustomerController.logeInCustomer?.uid,
            ),
          ),
        );
      }
    });
  }

  void _editProfile() {
    ShowToast().showNormalToast(msg: 'Edit profile feature coming soon!');
  }

  void _shareProfile() {
    SharePlus.instance.share(
      ShareParams(text: 'Check out ${widget.user.name}\'s profile on Orgami!'),
    );
  }

  void _showProfileOptions(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        decoration: const BoxDecoration(
          color: AppThemeColor.pureWhiteColor,
          borderRadius: BorderRadius.only(
            topLeft: Radius.circular(Dimensions.radiusLarge),
            topRight: Radius.circular(Dimensions.radiusLarge),
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              margin: const EdgeInsets.only(top: 12),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey[300],
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            ListTile(
              leading: const Icon(
                Icons.report_outlined,
                color: AppThemeColor.orangeColor,
              ),
              title: const Text('Report User'),
              onTap: () {
                Navigator.pop(context);
                _showReportDialog(context);
              },
            ),
            ListTile(
              leading: const Icon(
                Icons.block_outlined,
                color: AppThemeColor.orangeColor,
              ),
              title: const Text('Block User'),
              onTap: () {
                Navigator.pop(context);
                _showBlockDialog(context);
              },
            ),
            ListTile(
              leading: const Icon(
                Icons.copy_outlined,
                color: AppThemeColor.darkBlueColor,
              ),
              title: const Text('Copy Profile Link'),
              onTap: () {
                Navigator.pop(context);
                _copyProfileLink();
              },
            ),
            const SizedBox(height: Dimensions.spaceSizedDefault),
          ],
        ),
      ),
    );
  }

  void _showReportDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Report User'),
        content: const Text('Are you sure you want to report this user?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              ShowToast().showNormalToast(msg: 'User reported successfully');
            },
            child: const Text('Report'),
          ),
        ],
      ),
    );
  }

  void _showBlockDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Block User'),
        content: const Text('Are you sure you want to block this user?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              ShowToast().showNormalToast(msg: 'User blocked successfully');
            },
            child: const Text('Block'),
          ),
        ],
      ),
    );
  }

  void _copyProfileLink() {
    Clipboard.setData(
      ClipboardData(text: 'https://orgami.app/profile/${widget.user.uid}'),
    );
    ShowToast().showNormalToast(msg: 'Profile link copied to clipboard');
  }
}
