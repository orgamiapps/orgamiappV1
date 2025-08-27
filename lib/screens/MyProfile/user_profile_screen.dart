import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:orgami/models/customer_model.dart';
import 'package:orgami/models/event_model.dart';
import 'package:orgami/Utils/colors.dart';
import 'package:orgami/Utils/dimensions.dart';
import 'package:orgami/Utils/cached_image.dart';
import 'package:orgami/firebase/firebase_storage_helper.dart';
import 'package:share_plus/share_plus.dart';
import 'package:orgami/firebase/firebase_firestore_helper.dart';
import 'package:orgami/Utils/toast.dart';
import 'package:orgami/screens/Events/Widget/single_event_list_view_item.dart';
import 'package:orgami/controller/customer_controller.dart';
import 'package:orgami/screens/MyProfile/followers_following_screen.dart';
import 'package:orgami/screens/Messaging/new_message_screen.dart';

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
  // Follow state removed from header; we won't track it here to avoid unused field.
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
      debugPrint('Loading user data for: ${widget.user.uid}');

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
        debugPrint('Loaded ${createdEvents.length} created events');
      } catch (e) {
        debugPrint('Error loading created events: $e');
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
        debugPrint('Loaded ${attendedEvents.length} attended events');
      } catch (e) {
        debugPrint('Error loading attended events: $e');
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
        debugPrint(
          'Loaded followers: $followersCount, following: $followingCount',
        );
      } catch (e) {
        debugPrint('Error loading follow counts: $e');
        followersCount = 0;
        followingCount = 0;
      }

      // Check if current user is following this user (only if not own profile or same user)
      bool isFollowing = false;
      try {
        final currentUserId = CustomerController.logeInCustomer?.uid;
        if (currentUserId != null && currentUserId != widget.user.uid) {
          isFollowing = await FirebaseFirestoreHelper().isFollowingUser(
            followerId: currentUserId,
            followingId: widget.user.uid,
          );
          debugPrint('Follow status: $isFollowing');
        }
      } catch (e) {
        debugPrint('Error checking follow status: $e');
        isFollowing = false;
      }

      if (mounted) {
        setState(() {
          _createdEvents = createdEvents;
          _attendedEvents = attendedEvents;
          _followersCount = followersCount;
          _followingCount = followingCount;
          _isLoading = false;
        });
        debugPrint('User data loaded successfully');
      }
    } catch (e) {
      debugPrint('Error loading user data: $e');
      if (mounted) {
        setState(() {
          _isLoading = false;
          _createdEvents = [];
          _attendedEvents = [];
          _followersCount = 0;
          _followingCount = 0;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    debugPrint('Building UserProfileScreen - isLoading: $_isLoading');

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
      backgroundColor: const Color(0xFFFAFBFC),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _loadUserData,
          color: AppThemeColor.darkBlueColor,
          child: CustomScrollView(
            slivers: [
              // Profile Header (styled like MyProfileScreen)
              SliverToBoxAdapter(child: _buildProfileHeaderUser()),
              // Stats Section
              SliverToBoxAdapter(child: _buildStatsSection()),
              // Tab Bar
              SliverToBoxAdapter(child: _buildTabBar()),
              // Tab Content
              SliverToBoxAdapter(child: _buildTabContent()),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildProfileHeaderUser() {
    return Container(
      width: double.infinity,
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: Color(0xFFE5E7EB), width: 1)),
      ),
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
      child: Stack(
        children: [
          Column(
            children: [
              Row(
                children: [
                  // Back button
                  GestureDetector(
                    onTap: () => Navigator.of(context).maybePop(),
                    child: Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: const Color(0xFFF3F4F6),
                        borderRadius: BorderRadius.circular(18),
                      ),
                      child: const Icon(
                        Icons.arrow_back,
                        color: Colors.black87,
                        size: 18,
                      ),
                    ),
                  ),
                  const Spacer(),
                  if (widget.isOwnProfile)
                    GestureDetector(
                      onTap: _showEditProfileModal,
                      child: Container(
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(
                          color: const Color(0xFFF3F4F6),
                          borderRadius: BorderRadius.circular(18),
                        ),
                        child: const Icon(
                          Icons.edit,
                          color: Colors.black87,
                          size: 18,
                        ),
                      ),
                    )
                  else ...[
                    Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: const Color(0xFFF3F4F6),
                        borderRadius: BorderRadius.circular(18),
                      ),
                      child: IconButton(
                        icon: const Icon(CupertinoIcons.share, size: 18),
                        color: Colors.black87,
                        onPressed: _shareProfile,
                        padding: EdgeInsets.zero,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: const Color(0xFFF3F4F6),
                        borderRadius: BorderRadius.circular(18),
                      ),
                      child: IconButton(
                        icon: const Icon(Icons.more_vert, size: 18),
                        color: Colors.black87,
                        onPressed: () => _showProfileOptions(context),
                        padding: EdgeInsets.zero,
                      ),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 8),
              // Compact profile row
              Row(
                children: [
                  // Avatar
                  Container(
                    width: 60,
                    height: 60,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: const Color(0xFFE5E7EB),
                        width: 1,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.06),
                          blurRadius: 8,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: ClipOval(
                      child:
                          (widget.user.profilePictureUrl != null &&
                              widget.user.profilePictureUrl!.isNotEmpty)
                          ? SafeNetworkImage(
                              imageUrl: widget.user.profilePictureUrl!,
                              fit: BoxFit.cover,
                              errorWidget: const Icon(
                                Icons.person,
                                color: Color(0xFF64748B),
                              ),
                            )
                          : const Icon(Icons.person, color: Color(0xFF64748B)),
                    ),
                  ),
                  const SizedBox(width: 16),
                  // Name + username + tagline
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.user.name,
                          style: const TextStyle(
                            color: Color(0xFF1A1A1A),
                            fontSize: 22,
                            fontWeight: FontWeight.w600,
                            fontFamily: 'Roboto',
                          ),
                        ),
                        if (widget.user.username != null &&
                            widget.user.username!.isNotEmpty) ...[
                          const SizedBox(height: 4),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: const Color(0xFFF3F4F6),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: const Color(0xFFE5E7EB),
                                width: 1,
                              ),
                            ),
                            child: Text(
                              '@${widget.user.username}',
                              style: const TextStyle(
                                color: Color(0xFF1F2937),
                                fontWeight: FontWeight.w500,
                                fontSize: 16,
                                fontFamily: 'Roboto',
                              ),
                            ),
                          ),
                        ],
                        if (widget.user.bio != null &&
                            widget.user.bio!.isNotEmpty) ...[
                          const SizedBox(height: 2),
                          Text(
                            widget.user.bio!,
                            style: const TextStyle(
                              color: Color(0xFF6B7280),
                              fontWeight: FontWeight.w400,
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
            ],
          ),
        ],
      ),
    );
  }

  // Banner upload
  Future<void> _pickAndUploadBanner() async {
    try {
      final file = await FirebaseStorageHelper.pickImageFromGallery();
      if (file == null) return;
      final url = await FirebaseStorageHelper.uploadUserBanner(
        userId: widget.user.uid,
        imageFile: file,
      );
      if (url == null) return;
      await FirebaseFirestoreHelper().updateCustomerProfile(
        customerId: widget.user.uid,
        bannerUrl: url,
      );
      setState(() {
        widget.user.bannerUrl = url;
      });
      ShowToast().showNormalToast(msg: 'Banner updated');
    } catch (_) {}
  }

  // Avatar upload
  Future<void> _pickAndUploadAvatar() async {
    try {
      final file = await FirebaseStorageHelper.pickImageFromGallery();
      if (file == null) return;
      final url = await FirebaseStorageHelper.uploadProfilePicture(
        widget.user.uid,
        file,
      );
      if (url == null) return;
      await FirebaseFirestoreHelper().updateCustomerProfile(
        customerId: widget.user.uid,
        profilePictureUrl: url,
      );
      setState(() {
        widget.user.profilePictureUrl = url;
      });
      ShowToast().showNormalToast(msg: 'Profile photo updated');
    } catch (_) {}
  }

  Widget _buildStatsSection() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
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
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: AppThemeColor.darkBlueColor,
                      fontFamily: 'Roboto',
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Followers',
                    style: TextStyle(
                      fontSize: 11,
                      color: AppThemeColor.dullFontColor,
                      fontFamily: 'Roboto',
                    ),
                  ),
                ],
              ),
            ),
          ),
          Container(width: 1, height: 30, color: AppThemeColor.borderColor),
          Expanded(
            child: GestureDetector(
              onTap: () => _showFollowersFollowing('following'),
              child: Column(
                children: [
                  Text(
                    '$_followingCount',
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: AppThemeColor.darkBlueColor,
                      fontFamily: 'Roboto',
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Following',
                    style: TextStyle(
                      fontSize: 11,
                      color: AppThemeColor.dullFontColor,
                      fontFamily: 'Roboto',
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (!widget.isOwnProfile) ...[
            Container(width: 1, height: 30, color: AppThemeColor.borderColor),
            GestureDetector(
              onTap: () => _startMessage(),
              child: Column(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: AppThemeColor.darkBlueColor,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(
                      Icons.message_outlined,
                      color: Colors.white,
                      size: 16,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Message',
                    style: TextStyle(
                      fontSize: 11,
                      color: AppThemeColor.dullFontColor,
                      fontFamily: 'Roboto',
                    ),
                  ),
                ],
              ),
            ),
          ],
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
            label: 'Created Events (${_createdEvents.length})',
            index: 0,
          ),
          Container(width: 1, height: 40, color: AppThemeColor.borderColor),
          _buildTabButton(
            label: 'Attended (${_attendedEvents.length})',
            index: 1,
          ),
        ],
      ),
    );
  }

  Widget _buildTabContent() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 24),
      child: _tabController.index == 0
          ? _buildCreatedEventsTab()
          : _buildAttendedEventsTab(),
    );
  }

  Widget _buildTabButton({required String label, required int index}) {
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
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            color: isSelected
                ? AppThemeColor.darkBlueColor
                : Colors.transparent,
            borderRadius: BorderRadius.circular(Dimensions.radiusLarge),
          ),
          child: Text(
            label,
            style: TextStyle(
              color: isSelected
                  ? AppThemeColor.pureWhiteColor
                  : AppThemeColor.dullFontColor,
              fontSize: 14,
              fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
              fontFamily: 'Roboto',
            ),
            textAlign: TextAlign.center,
          ),
        ),
      ),
    );
  }

  Widget _buildCreatedEventsTab() {
    debugPrint(
      'Building created events tab with ${_createdEvents.length} events',
    );

    if (_createdEvents.isEmpty) {
      return _buildEmptyState(
        'No Created Events',
        'This user hasn\'t created any events yet.',
        Icons.event_outlined,
      );
    }

    return ListView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
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
    debugPrint(
      'Building attended events tab with ${_attendedEvents.length} events',
    );

    if (_attendedEvents.isEmpty) {
      return _buildEmptyState(
        'No Attended Events',
        'This user hasn\'t attended any events yet.',
        Icons.check_circle_outline,
      );
    }

    return ListView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
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

  // Follow action UI moved out; function removed

  // Removed unused _showMessageDialog

  void _startMessage() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => NewMessageScreen()),
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
        if (!mounted) return;
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

  void _showEditProfileModal() {
    final nameController = TextEditingController(text: widget.user.name);
    final usernameController = TextEditingController(
      text: widget.user.username ?? '',
    );
    final bioController = TextEditingController(text: widget.user.bio ?? '');

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.85,
          minChildSize: 0.5,
          maxChildSize: 0.95,
          builder: (context, scrollCtlr) {
            return Container(
              decoration: const BoxDecoration(
                color: AppThemeColor.pureWhiteColor,
                borderRadius: BorderRadius.only(
                  topLeft: Radius.circular(Dimensions.radiusLarge),
                  topRight: Radius.circular(Dimensions.radiusLarge),
                ),
              ),
              child: SingleChildScrollView(
                controller: scrollCtlr,
                padding: EdgeInsets.only(
                  left: 24,
                  right: 24,
                  top: 16,
                  bottom: MediaQuery.of(context).viewInsets.bottom + 24,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Center(
                      child: Container(
                        width: 40,
                        height: 4,
                        margin: const EdgeInsets.only(bottom: 16),
                        decoration: BoxDecoration(
                          color: Colors.grey[300],
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                    const Text(
                      'Edit Profile',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                        color: AppThemeColor.darkBlueColor,
                      ),
                    ),
                    const SizedBox(height: 16),
                    // Modern media section with live previews
                    _EditMediaSection(
                      bannerUrl: widget.user.bannerUrl,
                      avatarUrl: widget.user.profilePictureUrl,
                      onChangeBanner: _pickAndUploadBanner,
                      onChangeAvatar: _pickAndUploadAvatar,
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: nameController,
                      decoration: const InputDecoration(
                        labelText: 'Full Name',
                        prefixIcon: Icon(Icons.person_outline),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: usernameController,
                      decoration: const InputDecoration(
                        labelText: 'Username',
                        prefixIcon: Icon(Icons.alternate_email),
                        hintText: 'yourname',
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: bioController,
                      maxLines: 4,
                      decoration: const InputDecoration(
                        labelText: 'Bio',
                        alignLabelWithHint: true,
                        prefixIcon: Icon(Icons.info_outline),
                      ),
                    ),
                    const SizedBox(height: 24),
                    SizedBox(
                      width: double.infinity,
                      height: 48,
                      child: ElevatedButton(
                        onPressed: () async {
                          final current = CustomerController.logeInCustomer;
                          if (current == null) {
                            Navigator.pop(context);
                            return;
                          }

                          // Save name and bio immediately
                          await FirebaseFirestoreHelper().updateCustomerProfile(
                            customerId: current.uid,
                            name: nameController.text.trim(),
                            bio: bioController.text.trim(),
                          );

                          // Save username if changed and not empty
                          final newUsername = usernameController.text.trim();
                          if (newUsername.isNotEmpty &&
                              newUsername != (widget.user.username ?? '')) {
                            await FirebaseFirestoreHelper().updateUsername(
                              userId: current.uid,
                              newUsername: newUsername,
                            );
                          }

                          // Update local model so UI reflects immediately
                          setState(() {
                            widget.user.name = nameController.text.trim();
                            widget.user.bio = bioController.text.trim();
                            widget.user.username = newUsername.isEmpty
                                ? null
                                : newUsername;
                          });

                          if (mounted) {
                            Navigator.pop(context);
                            ShowToast().showNormalToast(
                              msg: 'Profile updated successfully',
                            );
                          }
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppThemeColor.darkBlueColor,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(
                              Dimensions.radiusLarge,
                            ),
                          ),
                        ),
                        child: const Text('Save Changes'),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }
}

class _EditMediaSection extends StatelessWidget {
  final String? bannerUrl;
  final String? avatarUrl;
  final VoidCallback onChangeBanner;
  final VoidCallback onChangeAvatar;

  const _EditMediaSection({
    required this.bannerUrl,
    required this.avatarUrl,
    required this.onChangeBanner,
    required this.onChangeAvatar,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Banner preview
        Stack(
          children: [
            Container(
              height: 120,
              decoration: BoxDecoration(
                color: const Color(0xFFF1F5F9),
                borderRadius: BorderRadius.circular(12),
                image: (bannerUrl != null && bannerUrl!.isNotEmpty)
                    ? DecorationImage(
                        image: NetworkImage(bannerUrl!),
                        fit: BoxFit.cover,
                        colorFilter: ColorFilter.mode(
                          Colors.black.withValues(alpha: 0.15),
                          BlendMode.darken,
                        ),
                      )
                    : null,
              ),
              child: (bannerUrl == null || bannerUrl!.isEmpty)
                  ? const Center(
                      child: Icon(Icons.wallpaper, color: Color(0xFF94A3B8)),
                    )
                  : null,
            ),
            Positioned(
              right: 8,
              bottom: 8,
              child: FilledButton.icon(
                onPressed: onChangeBanner,
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFF667EEA),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                ),
                icon: const Icon(Icons.edit, size: 16),
                label: const Text('Change banner'),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            // Avatar preview
            Stack(
              children: [
                CircleAvatar(
                  radius: 32,
                  backgroundColor: const Color(0xFFE5E7EB),
                  backgroundImage: (avatarUrl != null && avatarUrl!.isNotEmpty)
                      ? NetworkImage(avatarUrl!)
                      : null,
                  child: (avatarUrl == null || avatarUrl!.isEmpty)
                      ? const Icon(Icons.person, color: Color(0xFF64748B))
                      : null,
                ),
                Positioned(
                  right: 0,
                  bottom: 0,
                  child: InkWell(
                    onTap: onChangeAvatar,
                    child: Container(
                      decoration: BoxDecoration(
                        color: const Color(0xFF667EEA),
                        borderRadius: BorderRadius.circular(16),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.1),
                            blurRadius: 6,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      padding: const EdgeInsets.all(6),
                      child: const Icon(
                        Icons.camera_alt,
                        size: 14,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(width: 12),
            TextButton(
              onPressed: onChangeAvatar,
              child: const Text('Change profile photo'),
            ),
          ],
        ),
      ],
    );
  }
}
