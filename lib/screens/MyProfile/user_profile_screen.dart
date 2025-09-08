import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:attendus/models/customer_model.dart';
import 'package:attendus/models/event_model.dart';
import 'package:attendus/Utils/colors.dart';
import 'package:attendus/Utils/dimensions.dart';
import 'package:attendus/Utils/cached_image.dart';
import 'package:attendus/Utils/responsive_helper.dart';
import 'package:attendus/firebase/firebase_storage_helper.dart';
import 'package:share_plus/share_plus.dart';
import 'package:attendus/firebase/firebase_firestore_helper.dart';
import 'package:attendus/Utils/toast.dart';
import 'package:attendus/screens/Events/Widget/single_event_list_view_item.dart';
import 'package:attendus/controller/customer_controller.dart';
import 'package:attendus/screens/MyProfile/followers_following_screen.dart';
import 'package:attendus/screens/Messaging/chat_screen.dart';
import 'package:attendus/firebase/firebase_messaging_helper.dart';
import 'package:attendus/widgets/app_scaffold_wrapper.dart';

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
          _isFollowing = isFollowing;
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
      return AppScaffoldWrapper(
        selectedBottomNavIndex: 3, // Profile tab
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

    return AppScaffoldWrapper(
      selectedBottomNavIndex: 3, // Profile tab
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
    final responsivePadding = ResponsiveHelper.getResponsivePadding(context);
    final buttonSize = ResponsiveHelper.getResponsiveIconSize(context, phone: 36, tablet: 44, desktop: 48);
    final iconSize = ResponsiveHelper.getResponsiveIconSize(context, phone: 18, tablet: 22, desktop: 24);
    
    return Container(
      width: double.infinity,
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: Color(0xFFE5E7EB), width: 1)),
      ),
      padding: EdgeInsets.fromLTRB(
        responsivePadding.left, 
        ResponsiveHelper.getResponsiveSpacing(context, phone: 8, tablet: 12, desktop: 16), 
        responsivePadding.right, 
        ResponsiveHelper.getResponsiveSpacing(context, phone: 12, tablet: 16, desktop: 20)
      ),
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
                      width: buttonSize,
                      height: buttonSize,
                      decoration: BoxDecoration(
                        color: const Color(0xFFF3F4F6),
                        borderRadius: BorderRadius.circular(buttonSize / 2),
                      ),
                      child: Icon(
                        Icons.arrow_back,
                        color: Colors.black87,
                        size: iconSize,
                      ),
                    ),
                  ),
                  const Spacer(),
                  if (widget.isOwnProfile)
                    GestureDetector(
                      onTap: _showEditProfileModal,
                      child: Container(
                        width: buttonSize,
                        height: buttonSize,
                        decoration: BoxDecoration(
                          color: const Color(0xFFF3F4F6),
                          borderRadius: BorderRadius.circular(buttonSize / 2),
                        ),
                        child: Icon(
                          Icons.edit,
                          color: Colors.black87,
                          size: iconSize,
                        ),
                      ),
                    )
                  else ...[
                    Container(
                      width: buttonSize,
                      height: buttonSize,
                      decoration: BoxDecoration(
                        color: const Color(0xFFF3F4F6),
                        borderRadius: BorderRadius.circular(buttonSize / 2),
                      ),
                      child: IconButton(
                        icon: Icon(CupertinoIcons.share, size: iconSize),
                        color: Colors.black87,
                        onPressed: _shareProfile,
                        padding: EdgeInsets.zero,
                      ),
                    ),
                    SizedBox(width: ResponsiveHelper.getResponsiveSpacing(context, phone: 8, tablet: 12, desktop: 16)),
                    Container(
                      width: buttonSize,
                      height: buttonSize,
                      decoration: BoxDecoration(
                        color: const Color(0xFFF3F4F6),
                        borderRadius: BorderRadius.circular(buttonSize / 2),
                      ),
                      child: IconButton(
                        icon: Icon(Icons.more_vert, size: iconSize),
                        color: Colors.black87,
                        onPressed: () => _showProfileOptions(context),
                        padding: EdgeInsets.zero,
                      ),
                    ),
                  ],
                ],
              ),
              SizedBox(height: ResponsiveHelper.getResponsiveSpacing(context, phone: 8, tablet: 12, desktop: 16)),
              // Responsive profile row
              _buildResponsiveProfileRow(),
              // Add Follow and Message buttons for other users' profiles
              if (!widget.isOwnProfile &&
                  CustomerController.logeInCustomer != null &&
                  widget.user.uid !=
                      CustomerController.logeInCustomer!.uid) ...[
                SizedBox(height: ResponsiveHelper.getResponsiveSpacing(context, phone: 12, tablet: 16, desktop: 20)),
                _buildActionButtons(),
              ],
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildResponsiveProfileRow() {
    final avatarSize = ResponsiveHelper.getResponsiveAvatarSize(context, phone: 60, tablet: 80, desktop: 100);
    final nameSize = ResponsiveHelper.getResponsiveFontSize(context, phone: 22, tablet: 26, desktop: 30);
    final usernameSize = ResponsiveHelper.getResponsiveFontSize(context, phone: 16, tablet: 18, desktop: 20);
    final bioSize = ResponsiveHelper.getResponsiveFontSize(context, phone: 14, tablet: 16, desktop: 18);
    final spacing = ResponsiveHelper.getResponsiveSpacing(context, phone: 16, tablet: 20, desktop: 24);
    
    return Row(
      children: [
        // Avatar
        Container(
          width: avatarSize,
          height: avatarSize,
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
            child: (widget.user.profilePictureUrl != null &&
                    widget.user.profilePictureUrl!.isNotEmpty)
                ? SafeNetworkImage(
                    imageUrl: widget.user.profilePictureUrl!,
                    fit: BoxFit.cover,
                    errorWidget: Icon(
                      Icons.person,
                      color: const Color(0xFF64748B),
                      size: avatarSize * 0.5,
                    ),
                  )
                : Icon(
                    Icons.person, 
                    color: const Color(0xFF64748B),
                    size: avatarSize * 0.5,
                  ),
          ),
        ),
        SizedBox(width: spacing),
        // Name + username + tagline
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                widget.user.name,
                style: TextStyle(
                  color: const Color(0xFF1A1A1A),
                  fontSize: nameSize,
                  fontWeight: FontWeight.w600,
                  fontFamily: 'Roboto',
                ),
              ),
              if (widget.user.username != null &&
                  widget.user.username!.isNotEmpty) ...[
                SizedBox(height: ResponsiveHelper.getResponsiveSpacing(context, phone: 4, tablet: 6, desktop: 8)),
                Container(
                  padding: EdgeInsets.symmetric(
                    horizontal: ResponsiveHelper.getResponsiveSpacing(context, phone: 8, tablet: 10, desktop: 12),
                    vertical: ResponsiveHelper.getResponsiveSpacing(context, phone: 4, tablet: 6, desktop: 8),
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF3F4F6),
                    borderRadius: BorderRadius.circular(
                      ResponsiveHelper.getResponsiveBorderRadius(context, phone: 12, tablet: 14, desktop: 16)
                    ),
                    border: Border.all(
                      color: const Color(0xFFE5E7EB),
                      width: 1,
                    ),
                  ),
                  child: Text(
                    '@${widget.user.username}',
                    style: TextStyle(
                      color: const Color(0xFF1F2937),
                      fontWeight: FontWeight.w500,
                      fontSize: usernameSize,
                      fontFamily: 'Roboto',
                    ),
                  ),
                ),
              ],
              if (widget.user.bio != null &&
                  widget.user.bio!.isNotEmpty) ...[
                SizedBox(height: ResponsiveHelper.getResponsiveSpacing(context, phone: 2, tablet: 4, desktop: 6)),
                Text(
                  widget.user.bio!,
                  style: TextStyle(
                    color: const Color(0xFF6B7280),
                    fontWeight: FontWeight.w400,
                    fontSize: bioSize,
                    fontFamily: 'Roboto',
                  ),
                  maxLines: context.isPhone ? 2 : 3,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ],
          ),
        ),
      ],
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

  Widget _buildActionButtons() {
    final buttonHeight = ResponsiveHelper.getResponsiveButtonHeight(context, phone: 36, tablet: 44, desktop: 48);
    final fontSize = ResponsiveHelper.getResponsiveFontSize(context, phone: 14, tablet: 16, desktop: 18);
    final borderRadius = ResponsiveHelper.getResponsiveBorderRadius(context, phone: 18, tablet: 22, desktop: 24);
    final horizontalPadding = ResponsiveHelper.getResponsivePadding(context).horizontal;
    final spacing = ResponsiveHelper.getResponsiveSpacing(context, phone: 8, tablet: 12, desktop: 16);
    
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: horizontalPadding),
      child: ResponsiveHelper.buildResponsiveLayout(
        context: context,
        phone: Row(
          children: [
            // Follow/Following button
            Expanded(
              child: GestureDetector(
                onTap: _toggleFollow,
                child: Container(
                  height: buttonHeight,
                  decoration: BoxDecoration(
                    color: _isFollowing
                        ? AppThemeColor.pureWhiteColor
                        : AppThemeColor.darkBlueColor,
                    borderRadius: BorderRadius.circular(borderRadius),
                    border: _isFollowing
                        ? Border.all(color: AppThemeColor.darkBlueColor, width: 1)
                        : null,
                  ),
                  child: Center(
                    child: Text(
                      _isFollowing ? 'Following' : 'Follow',
                      style: TextStyle(
                        color: _isFollowing
                            ? AppThemeColor.darkBlueColor
                            : AppThemeColor.pureWhiteColor,
                        fontSize: fontSize,
                        fontWeight: FontWeight.w600,
                        fontFamily: 'Roboto',
                      ),
                    ),
                  ),
                ),
              ),
            ),
            SizedBox(width: spacing),
            // Message button
            Expanded(
              child: GestureDetector(
                onTap: _sendMessage,
                child: Container(
                  height: buttonHeight,
                  decoration: BoxDecoration(
                    color: const Color(0xFFF3F4F6),
                    borderRadius: BorderRadius.circular(borderRadius),
                    border: Border.all(color: const Color(0xFFE5E7EB), width: 1),
                  ),
                  child: Center(
                    child: Text(
                      'Message',
                      style: TextStyle(
                        color: const Color(0xFF1F2937),
                        fontSize: fontSize,
                        fontWeight: FontWeight.w600,
                        fontFamily: 'Roboto',
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
        tablet: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Follow/Following button
            SizedBox(
              width: ResponsiveHelper.getResponsiveWidth(context, tabletPercent: 0.3),
              child: GestureDetector(
                onTap: _toggleFollow,
                child: Container(
                  height: buttonHeight,
                  decoration: BoxDecoration(
                    color: _isFollowing
                        ? AppThemeColor.pureWhiteColor
                        : AppThemeColor.darkBlueColor,
                    borderRadius: BorderRadius.circular(borderRadius),
                    border: _isFollowing
                        ? Border.all(color: AppThemeColor.darkBlueColor, width: 1)
                        : null,
                  ),
                  child: Center(
                    child: Text(
                      _isFollowing ? 'Following' : 'Follow',
                      style: TextStyle(
                        color: _isFollowing
                            ? AppThemeColor.darkBlueColor
                            : AppThemeColor.pureWhiteColor,
                        fontSize: fontSize,
                        fontWeight: FontWeight.w600,
                        fontFamily: 'Roboto',
                      ),
                    ),
                  ),
                ),
              ),
            ),
            SizedBox(width: spacing),
            // Message button
            SizedBox(
              width: ResponsiveHelper.getResponsiveWidth(context, tabletPercent: 0.3),
              child: GestureDetector(
                onTap: _sendMessage,
                child: Container(
                  height: buttonHeight,
                  decoration: BoxDecoration(
                    color: const Color(0xFFF3F4F6),
                    borderRadius: BorderRadius.circular(borderRadius),
                    border: Border.all(color: const Color(0xFFE5E7EB), width: 1),
                  ),
                  child: Center(
                    child: Text(
                      'Message',
                      style: TextStyle(
                        color: const Color(0xFF1F2937),
                        fontSize: fontSize,
                        fontWeight: FontWeight.w600,
                        fontFamily: 'Roboto',
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
        desktop: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Follow/Following button
            SizedBox(
              width: ResponsiveHelper.getResponsiveWidth(context, desktopPercent: 0.2),
              child: GestureDetector(
                onTap: _toggleFollow,
                child: Container(
                  height: buttonHeight,
                  decoration: BoxDecoration(
                    color: _isFollowing
                        ? AppThemeColor.pureWhiteColor
                        : AppThemeColor.darkBlueColor,
                    borderRadius: BorderRadius.circular(borderRadius),
                    border: _isFollowing
                        ? Border.all(color: AppThemeColor.darkBlueColor, width: 1)
                        : null,
                  ),
                  child: Center(
                    child: Text(
                      _isFollowing ? 'Following' : 'Follow',
                      style: TextStyle(
                        color: _isFollowing
                            ? AppThemeColor.darkBlueColor
                            : AppThemeColor.pureWhiteColor,
                        fontSize: fontSize,
                        fontWeight: FontWeight.w600,
                        fontFamily: 'Roboto',
                      ),
                    ),
                  ),
                ),
              ),
            ),
            SizedBox(width: spacing),
            // Message button
            SizedBox(
              width: ResponsiveHelper.getResponsiveWidth(context, desktopPercent: 0.2),
              child: GestureDetector(
                onTap: _sendMessage,
                child: Container(
                  height: buttonHeight,
                  decoration: BoxDecoration(
                    color: const Color(0xFFF3F4F6),
                    borderRadius: BorderRadius.circular(borderRadius),
                    border: Border.all(color: const Color(0xFFE5E7EB), width: 1),
                  ),
                  child: Center(
                    child: Text(
                      'Message',
                      style: TextStyle(
                        color: const Color(0xFF1F2937),
                        fontSize: fontSize,
                        fontWeight: FontWeight.w600,
                        fontFamily: 'Roboto',
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _toggleFollow() async {
    if (CustomerController.logeInCustomer == null) {
      ShowToast().showNormalToast(msg: 'Please log in to follow users');
      return;
    }

    if (widget.user.uid == CustomerController.logeInCustomer!.uid) {
      ShowToast().showNormalToast(msg: 'You cannot follow yourself');
      return;
    }

    setState(() {
      _isFollowing = !_isFollowing;
      // Update followers count immediately for better UX
      if (_isFollowing) {
        _followersCount++;
      } else {
        _followersCount = _followersCount > 0 ? _followersCount - 1 : 0;
      }
    });

    try {
      if (_isFollowing) {
        await FirebaseFirestoreHelper().followUser(
          followerId: CustomerController.logeInCustomer!.uid,
          followingId: widget.user.uid,
        );
        ShowToast().showNormalToast(msg: 'Following ${widget.user.name}');
      } else {
        await FirebaseFirestoreHelper().unfollowUser(
          followerId: CustomerController.logeInCustomer!.uid,
          followingId: widget.user.uid,
        );
        ShowToast().showNormalToast(msg: 'Unfollowed ${widget.user.name}');
      }

      // Reload data to get accurate counts
      _loadUserData();
    } catch (e) {
      debugPrint('Error toggling follow status: $e');
      // Revert the state change on error
      setState(() {
        _isFollowing = !_isFollowing;
        if (_isFollowing) {
          _followersCount++;
        } else {
          _followersCount = _followersCount > 0 ? _followersCount - 1 : 0;
        }
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

  void _sendMessage() async {
    if (CustomerController.logeInCustomer == null) {
      ShowToast().showNormalToast(msg: 'Please log in to send messages');
      return;
    }

    // Create conversation ID (sorted to ensure consistency)
    final currentUserId = CustomerController.logeInCustomer!.uid;
    final sortedIds = [currentUserId, widget.user.uid]..sort();
    final conversationId = '${sortedIds[0]}_${sortedIds[1]}';

    // Check if conversation already exists
    final messagingHelper = FirebaseMessagingHelper();
    final existingConversationId = await messagingHelper.getConversationId(
      currentUserId,
      widget.user.uid,
    );

    if (!mounted) return;

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => ChatScreen(
          conversationId: existingConversationId ?? conversationId,
          otherParticipantInfo: widget.user,
        ),
      ),
    );
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
    final margin = ResponsiveHelper.getResponsiveMargin(context, phone: 24, tablet: 32, desktop: 48);
    final padding = ResponsiveHelper.getResponsivePadding(context, phone: 16, tablet: 20, desktop: 24);
    final borderRadius = ResponsiveHelper.getResponsiveBorderRadius(context);
    final numberFontSize = ResponsiveHelper.getResponsiveFontSize(context, phone: 16, tablet: 20, desktop: 24);
    final labelFontSize = ResponsiveHelper.getResponsiveFontSize(context, phone: 11, tablet: 13, desktop: 15);
    final dividerHeight = ResponsiveHelper.getResponsiveSpacing(context, phone: 30, tablet: 35, desktop: 40);
    
    return Container(
      constraints: BoxConstraints(
        maxWidth: ResponsiveHelper.getMaxContentWidth(context),
      ),
      margin: EdgeInsets.symmetric(horizontal: margin.horizontal, vertical: margin.vertical),
      padding: EdgeInsets.symmetric(horizontal: padding.horizontal, vertical: padding.vertical),
      decoration: BoxDecoration(
        color: AppThemeColor.pureWhiteColor,
        borderRadius: BorderRadius.circular(borderRadius),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: ResponsiveHelper.getResponsiveElevation(context, phone: 10, tablet: 12, desktop: 16),
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
                    style: TextStyle(
                      fontSize: numberFontSize,
                      fontWeight: FontWeight.bold,
                      color: AppThemeColor.darkBlueColor,
                      fontFamily: 'Roboto',
                    ),
                  ),
                  SizedBox(height: ResponsiveHelper.getResponsiveSpacing(context, phone: 2, tablet: 4, desktop: 6)),
                  Text(
                    'Followers',
                    style: TextStyle(
                      fontSize: labelFontSize,
                      color: AppThemeColor.dullFontColor,
                      fontFamily: 'Roboto',
                    ),
                  ),
                ],
              ),
            ),
          ),
          Container(width: 1, height: dividerHeight, color: AppThemeColor.borderColor),
          Expanded(
            child: GestureDetector(
              onTap: () => _showFollowersFollowing('following'),
              child: Column(
                children: [
                  Text(
                    '$_followingCount',
                    style: TextStyle(
                      fontSize: numberFontSize,
                      fontWeight: FontWeight.bold,
                      color: AppThemeColor.darkBlueColor,
                      fontFamily: 'Roboto',
                    ),
                  ),
                  SizedBox(height: ResponsiveHelper.getResponsiveSpacing(context, phone: 2, tablet: 4, desktop: 6)),
                  Text(
                    'Following',
                    style: TextStyle(
                      fontSize: labelFontSize,
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
    final margin = ResponsiveHelper.getResponsiveMargin(context, phone: 24, tablet: 32, desktop: 48);
    final borderRadius = ResponsiveHelper.getResponsiveBorderRadius(context);
    final dividerHeight = ResponsiveHelper.getResponsiveSpacing(context, phone: 40, tablet: 48, desktop: 56);
    
    return Container(
      constraints: BoxConstraints(
        maxWidth: ResponsiveHelper.getMaxContentWidth(context),
      ),
      margin: EdgeInsets.fromLTRB(margin.horizontal, 0, margin.horizontal, margin.vertical),
      decoration: BoxDecoration(
        color: AppThemeColor.pureWhiteColor,
        borderRadius: BorderRadius.circular(borderRadius),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: ResponsiveHelper.getResponsiveElevation(context, phone: 10, tablet: 12, desktop: 16),
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: ResponsiveHelper.buildResponsiveLayout(
        context: context,
        phone: Row(
          children: [
            _buildTabButton(
              label: 'Created (${_createdEvents.length})',
              index: 0,
            ),
            Container(width: 1, height: dividerHeight, color: AppThemeColor.borderColor),
            _buildTabButton(
              label: 'Attended (${_attendedEvents.length})',
              index: 1,
            ),
          ],
        ),
        tablet: Row(
          children: [
            _buildTabButton(
              label: 'Created Events (${_createdEvents.length})',
              index: 0,
            ),
            Container(width: 1, height: dividerHeight, color: AppThemeColor.borderColor),
            _buildTabButton(
              label: 'Attended Events (${_attendedEvents.length})',
              index: 1,
            ),
          ],
        ),
        desktop: Row(
          children: [
            _buildTabButton(
              label: 'Created Events (${_createdEvents.length})',
              index: 0,
            ),
            Container(width: 1, height: dividerHeight, color: AppThemeColor.borderColor),
            _buildTabButton(
              label: 'Attended Events (${_attendedEvents.length})',
              index: 1,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTabContent() {
    final margin = ResponsiveHelper.getResponsiveMargin(context, phone: 24, tablet: 32, desktop: 48);
    
    return Container(
      constraints: BoxConstraints(
        maxWidth: ResponsiveHelper.getMaxContentWidth(context),
      ),
      margin: EdgeInsets.symmetric(horizontal: margin.horizontal),
      child: _tabController.index == 0
          ? _buildCreatedEventsTab()
          : _buildAttendedEventsTab(),
    );
  }

  Widget _buildTabButton({required String label, required int index}) {
    final isSelected = _tabController.index == index;
    final fontSize = ResponsiveHelper.getResponsiveFontSize(context, phone: 14, tablet: 16, desktop: 18);
    final verticalPadding = ResponsiveHelper.getResponsiveSpacing(context, phone: 12, tablet: 16, desktop: 20);
    final borderRadius = ResponsiveHelper.getResponsiveBorderRadius(context);
    
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
          padding: EdgeInsets.symmetric(vertical: verticalPadding),
          decoration: BoxDecoration(
            color: isSelected
                ? AppThemeColor.darkBlueColor
                : Colors.transparent,
            borderRadius: BorderRadius.circular(borderRadius),
          ),
          child: Text(
            label,
            style: TextStyle(
              color: isSelected
                  ? AppThemeColor.pureWhiteColor
                  : AppThemeColor.dullFontColor,
              fontSize: fontSize,
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

    final spacing = ResponsiveHelper.getResponsiveSpacing(context, phone: 12, tablet: 16, desktop: 20);
    
    return ResponsiveHelper.buildResponsiveLayout(
      context: context,
      phone: ListView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        itemCount: _createdEvents.length,
        itemBuilder: (context, index) {
          final event = _createdEvents[index];
          return Container(
            margin: EdgeInsets.only(bottom: spacing),
            child: SingleEventListViewItem(eventModel: event),
          );
        },
      ),
      tablet: GridView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        gridDelegate: ResponsiveHelper.getResponsiveGridDelegate(
          context,
          childAspectRatio: 1.2,
        ),
        itemCount: _createdEvents.length,
        itemBuilder: (context, index) {
          final event = _createdEvents[index];
          return SingleEventListViewItem(eventModel: event);
        },
      ),
      desktop: GridView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        gridDelegate: ResponsiveHelper.getResponsiveGridDelegate(
          context,
          childAspectRatio: 1.1,
        ),
        itemCount: _createdEvents.length,
        itemBuilder: (context, index) {
          final event = _createdEvents[index];
          return SingleEventListViewItem(eventModel: event);
        },
      ),
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

    final spacing = ResponsiveHelper.getResponsiveSpacing(context, phone: 12, tablet: 16, desktop: 20);
    
    return ResponsiveHelper.buildResponsiveLayout(
      context: context,
      phone: ListView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        itemCount: _attendedEvents.length,
        itemBuilder: (context, index) {
          final event = _attendedEvents[index];
          return Container(
            margin: EdgeInsets.only(bottom: spacing),
            child: SingleEventListViewItem(eventModel: event),
          );
        },
      ),
      tablet: GridView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        gridDelegate: ResponsiveHelper.getResponsiveGridDelegate(
          context,
          childAspectRatio: 1.2,
        ),
        itemCount: _attendedEvents.length,
        itemBuilder: (context, index) {
          final event = _attendedEvents[index];
          return SingleEventListViewItem(eventModel: event);
        },
      ),
      desktop: GridView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        gridDelegate: ResponsiveHelper.getResponsiveGridDelegate(
          context,
          childAspectRatio: 1.1,
        ),
        itemCount: _attendedEvents.length,
        itemBuilder: (context, index) {
          final event = _attendedEvents[index];
          return SingleEventListViewItem(eventModel: event);
        },
      ),
    );
  }

  Widget _buildEmptyState(String title, String message, IconData icon) {
    final padding = ResponsiveHelper.getResponsivePadding(context, phone: 40, tablet: 48, desktop: 56);
    final borderRadius = ResponsiveHelper.getResponsiveBorderRadius(context);
    final iconSize = ResponsiveHelper.getResponsiveIconSize(context, phone: 64, tablet: 80, desktop: 96);
    final titleSize = ResponsiveHelper.getResponsiveFontSize(context, phone: 16, tablet: 20, desktop: 24);
    final messageSize = ResponsiveHelper.getResponsiveFontSize(context, phone: 14, tablet: 16, desktop: 18);
    final spacing = ResponsiveHelper.getResponsiveSpacing(context, phone: 24, tablet: 32, desktop: 40);
    
    return Container(
      padding: EdgeInsets.all(padding.left),
      decoration: BoxDecoration(
        color: AppThemeColor.pureWhiteColor,
        borderRadius: BorderRadius.circular(borderRadius),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: ResponsiveHelper.getResponsiveElevation(context, phone: 10, tablet: 12, desktop: 16),
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: iconSize, color: AppThemeColor.dullIconColor),
          SizedBox(height: spacing),
          Text(
            title,
            style: TextStyle(
              fontSize: titleSize,
              fontWeight: FontWeight.bold,
              color: AppThemeColor.darkBlueColor,
              fontFamily: 'Roboto',
            ),
            textAlign: TextAlign.center,
          ),
          SizedBox(height: ResponsiveHelper.getResponsiveSpacing(context, phone: 8, tablet: 12, desktop: 16)),
          Text(
            message,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: messageSize,
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

  // Removed _startMessage as the stats section message shortcut was removed

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
      ShareParams(
        text: 'Check out ${widget.user.name}\'s profile on AttendUs!',
      ),
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

    if (context.isDesktop) {
      _showEditProfileDialog(nameController, usernameController, bioController);
    } else {
      _showEditProfileBottomSheet(nameController, usernameController, bioController);
    }
  }

  void _showEditProfileBottomSheet(TextEditingController nameController, TextEditingController usernameController, TextEditingController bioController) {
    final borderRadius = ResponsiveHelper.getResponsiveBorderRadius(context);
    final padding = ResponsiveHelper.getResponsivePadding(context);
    
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return DraggableScrollableSheet(
          expand: false,
          initialChildSize: context.isTablet ? 0.75 : 0.85,
          minChildSize: 0.5,
          maxChildSize: 0.95,
          builder: (context, scrollCtlr) {
            return Container(
              decoration: BoxDecoration(
                color: AppThemeColor.pureWhiteColor,
                borderRadius: BorderRadius.only(
                  topLeft: Radius.circular(borderRadius),
                  topRight: Radius.circular(borderRadius),
                ),
              ),
              child: SingleChildScrollView(
                controller: scrollCtlr,
                padding: EdgeInsets.only(
                  left: padding.left,
                  right: padding.right,
                  top: padding.top,
                  bottom: MediaQuery.of(context).viewInsets.bottom + padding.bottom,
                ),
                child: _buildEditProfileContent(nameController, usernameController, bioController),
              ),
            );
          },
        );
      },
    );
  }

  void _showEditProfileDialog(TextEditingController nameController, TextEditingController usernameController, TextEditingController bioController) {
    final dialogWidth = ResponsiveHelper.getResponsiveDialogWidth(context);
    
    showDialog(
      context: context,
      builder: (context) {
        return Dialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(
              ResponsiveHelper.getResponsiveBorderRadius(context)
            ),
          ),
          child: Container(
            width: dialogWidth,
            constraints: const BoxConstraints(maxHeight: 700),
            padding: ResponsiveHelper.getResponsivePadding(context),
            child: SingleChildScrollView(
              child: _buildEditProfileContent(nameController, usernameController, bioController),
            ),
          ),
        );
      },
    );
  }

  Widget _buildEditProfileContent(TextEditingController nameController, TextEditingController usernameController, TextEditingController bioController) {
    final titleSize = ResponsiveHelper.getResponsiveFontSize(context, phone: 20, tablet: 24, desktop: 28);
    final spacing = ResponsiveHelper.getResponsiveSpacing(context, phone: 16, tablet: 20, desktop: 24);
    final buttonHeight = ResponsiveHelper.getResponsiveButtonHeight(context, phone: 48, tablet: 52, desktop: 56);
    final borderRadius = ResponsiveHelper.getResponsiveBorderRadius(context);
    
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (!context.isDesktop) Center(
          child: Container(
            width: 40,
            height: 4,
            margin: EdgeInsets.only(bottom: spacing),
            decoration: BoxDecoration(
              color: Colors.grey[300],
              borderRadius: BorderRadius.circular(2),
            ),
          ),
        ),
        Text(
          'Edit Profile',
          style: TextStyle(
            fontSize: titleSize,
            fontWeight: FontWeight.w700,
            color: AppThemeColor.darkBlueColor,
          ),
        ),
        SizedBox(height: spacing),
        // Modern media section with live previews
        _EditMediaSection(
          bannerUrl: widget.user.bannerUrl,
          avatarUrl: widget.user.profilePictureUrl,
          onChangeBanner: _pickAndUploadBanner,
          onChangeAvatar: _pickAndUploadAvatar,
        ),
        SizedBox(height: spacing),
        TextField(
          controller: nameController,
          style: TextStyle(
            fontSize: ResponsiveHelper.getResponsiveFontSize(context, phone: 16, tablet: 18, desktop: 20),
          ),
          decoration: InputDecoration(
            labelText: 'Full Name',
            prefixIcon: Icon(
              Icons.person_outline,
              size: ResponsiveHelper.getResponsiveIconSize(context, phone: 24, tablet: 28, desktop: 32),
            ),
          ),
        ),
        SizedBox(height: ResponsiveHelper.getResponsiveSpacing(context, phone: 12, tablet: 16, desktop: 20)),
        TextField(
          controller: usernameController,
          style: TextStyle(
            fontSize: ResponsiveHelper.getResponsiveFontSize(context, phone: 16, tablet: 18, desktop: 20),
          ),
          decoration: InputDecoration(
            labelText: 'Username',
            prefixIcon: Icon(
              Icons.alternate_email,
              size: ResponsiveHelper.getResponsiveIconSize(context, phone: 24, tablet: 28, desktop: 32),
            ),
            hintText: 'yourname',
          ),
        ),
        SizedBox(height: ResponsiveHelper.getResponsiveSpacing(context, phone: 12, tablet: 16, desktop: 20)),
        TextField(
          controller: bioController,
          maxLines: context.isPhone ? 4 : 5,
          style: TextStyle(
            fontSize: ResponsiveHelper.getResponsiveFontSize(context, phone: 16, tablet: 18, desktop: 20),
          ),
          decoration: InputDecoration(
            labelText: 'Bio',
            alignLabelWithHint: true,
            prefixIcon: Icon(
              Icons.info_outline,
              size: ResponsiveHelper.getResponsiveIconSize(context, phone: 24, tablet: 28, desktop: 32),
            ),
          ),
        ),
        SizedBox(height: spacing * 1.5),
        SizedBox(
          width: double.infinity,
          height: buttonHeight,
          child: ElevatedButton(
            onPressed: () => _saveProfileChanges(nameController, usernameController, bioController),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppThemeColor.darkBlueColor,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(borderRadius),
              ),
            ),
            child: Text(
              'Save Changes',
              style: TextStyle(
                fontSize: ResponsiveHelper.getResponsiveFontSize(context, phone: 16, tablet: 18, desktop: 20),
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _saveProfileChanges(TextEditingController nameController, TextEditingController usernameController, TextEditingController bioController) async {
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
    final bannerHeight = ResponsiveHelper.getResponsiveHeight(context, phonePercent: 0.15, tabletPercent: 0.18, desktopPercent: 0.2);
    final borderRadius = ResponsiveHelper.getResponsiveBorderRadius(context);
    final avatarRadius = ResponsiveHelper.getResponsiveAvatarSize(context, phone: 32, tablet: 40, desktop: 48);
    final iconSize = ResponsiveHelper.getResponsiveIconSize(context, phone: 16, tablet: 20, desktop: 24);
    final buttonPadding = ResponsiveHelper.getResponsivePadding(context, phone: 12, tablet: 16, desktop: 20);
    final spacing = ResponsiveHelper.getResponsiveSpacing(context, phone: 12, tablet: 16, desktop: 20);
    final fontSize = ResponsiveHelper.getResponsiveFontSize(context, phone: 14, tablet: 16, desktop: 18);
    
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Banner preview
        Stack(
          children: [
            Container(
              height: bannerHeight.clamp(120.0, 200.0),
              decoration: BoxDecoration(
                color: const Color(0xFFF1F5F9),
                borderRadius: BorderRadius.circular(borderRadius),
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
                  ? Center(
                      child: Icon(
                        Icons.wallpaper, 
                        color: const Color(0xFF94A3B8),
                        size: ResponsiveHelper.getResponsiveIconSize(context, phone: 32, tablet: 40, desktop: 48),
                      ),
                    )
                  : null,
            ),
            Positioned(
              right: ResponsiveHelper.getResponsiveSpacing(context, phone: 8, tablet: 12, desktop: 16),
              bottom: ResponsiveHelper.getResponsiveSpacing(context, phone: 8, tablet: 12, desktop: 16),
              child: FilledButton.icon(
                onPressed: onChangeBanner,
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFF667EEA),
                  padding: EdgeInsets.symmetric(
                    horizontal: buttonPadding.horizontal,
                    vertical: buttonPadding.vertical,
                  ),
                ),
                icon: Icon(Icons.edit, size: iconSize),
                label: Text(
                  context.isPhone ? 'Change' : 'Change banner',
                  style: TextStyle(fontSize: fontSize),
                ),
              ),
            ),
          ],
        ),
        SizedBox(height: spacing),
        Row(
          children: [
            // Avatar preview
            Stack(
              children: [
                CircleAvatar(
                  radius: avatarRadius,
                  backgroundColor: const Color(0xFFE5E7EB),
                  backgroundImage: (avatarUrl != null && avatarUrl!.isNotEmpty)
                      ? NetworkImage(avatarUrl!)
                      : null,
                  child: (avatarUrl == null || avatarUrl!.isEmpty)
                      ? Icon(
                          Icons.person, 
                          color: const Color(0xFF64748B),
                          size: avatarRadius * 1.2,
                        )
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
                        borderRadius: BorderRadius.circular(avatarRadius / 2),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.1),
                            blurRadius: 6,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      padding: EdgeInsets.all(ResponsiveHelper.getResponsiveSpacing(context, phone: 6, tablet: 8, desktop: 10)),
                      child: Icon(
                        Icons.camera_alt,
                        size: ResponsiveHelper.getResponsiveIconSize(context, phone: 14, tablet: 16, desktop: 18),
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
              ],
            ),
            SizedBox(width: spacing),
            TextButton(
              onPressed: onChangeAvatar,
              child: Text(
                'Change profile photo',
                style: TextStyle(fontSize: fontSize),
              ),
            ),
          ],
        ),
      ],
    );
  }
}
