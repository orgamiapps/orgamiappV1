import 'package:flutter/material.dart';
import 'package:orgami/controller/customer_controller.dart';
import 'package:orgami/models/customer_model.dart';
import 'package:orgami/firebase/firebase_firestore_helper.dart';
import 'package:orgami/models/event_model.dart';
import 'package:orgami/Utils/colors.dart';
import 'package:orgami/Screens/Events/Widget/single_event_list_view_item.dart';
import 'package:orgami/Utils/toast.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:shimmer/shimmer.dart';
import 'package:orgami/Screens/MyProfile/my_tickets_screen.dart';
import 'package:orgami/Screens/MyProfile/user_profile_screen.dart';
import 'package:orgami/Screens/MyProfile/badge_screen.dart';
import 'package:orgami/Screens/MyProfile/Widgets/professional_badge_widget.dart';
import 'package:orgami/models/badge_model.dart';
import 'package:orgami/Services/badge_service.dart';
import 'package:orgami/Screens/Home/account_details_screen.dart';

// Enum for sort options
enum SortOption {
  none,
  dateAddedAsc,
  dateAddedDesc,
  titleAsc,
  titleDesc,
  eventDateAsc,
  eventDateDesc,
}

class MyProfileScreen extends StatefulWidget {
  const MyProfileScreen({super.key});

  @override
  State<MyProfileScreen> createState() => _MyProfileScreenState();
}

class _MyProfileScreenState extends State<MyProfileScreen>
    with TickerProviderStateMixin {
  List<EventModel> createdEvents = [];
  List<EventModel> attendedEvents = [];
  List<EventModel> savedEvents = [];
  bool isLoading = true;
  int selectedTab = 1; // 1 = Created, 2 = Attended, 3 = Saved
  bool isDiscoverable = true; // User discoverability setting

  // Badge related fields
  UserBadgeModel? _userBadge;
  bool _isBadgeLoading = false;
  final BadgeService _badgeService = BadgeService();

  // Selection state
  bool isSelectionMode = false;
  Set<String> selectedEventIds = <String>{};

  // Filter/Sort state
  SortOption currentSortOption = SortOption.none;
  List<String> selectedCategories = [];
  final List<String> _allCategories = ['Educational', 'Professional', 'Other'];

  // Animation controllers
  late AnimationController _fadeController;
  late Animation<double> _fadeAnimation;
  late AnimationController _slideController;
  late Animation<Offset> _slideAnimation;

  @override
  void initState() {
    super.initState();
    _initializeAnimations();
    _loadProfileData();
  }

  void _initializeAnimations() {
    _fadeController = AnimationController(
      duration: const Duration(milliseconds: 800),
      vsync: this,
    );
    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _fadeController, curve: Curves.easeInOut),
    );

    _slideController = AnimationController(
      duration: const Duration(milliseconds: 600),
      vsync: this,
    );
    _slideAnimation =
        Tween<Offset>(begin: const Offset(0, 0.3), end: Offset.zero).animate(
          CurvedAnimation(parent: _slideController, curve: Curves.easeOutCubic),
        );

    _fadeController.forward();
    _slideController.forward();
  }

  @override
  void dispose() {
    _fadeController.dispose();
    _slideController.dispose();
    super.dispose();
  }

  Future<void> _refreshSavedEvents() async {
    try {
      // Check if user is logged in
      if (CustomerController.logeInCustomer == null) {
        return;
      }

      // Fetch only saved events
      final saved = await FirebaseFirestoreHelper().getFavoritedEvents(
        userId: CustomerController.logeInCustomer!.uid,
      );
      debugPrint('Updated saved events count: ${saved.length}');

      if (mounted) {
        setState(() {
          savedEvents = saved;
        });
      }
    } catch (e) {
      debugPrint('Error refreshing saved events: $e');
    }
  }

  Future<void> _loadProfileData() async {
    setState(() {
      isLoading = true;
    });

    try {
      // Check if user is logged in
      if (CustomerController.logeInCustomer == null) {
        debugPrint('User not logged in');
        setState(() {
          isLoading = false;
        });
        ShowToast().showNormalToast(msg: 'Please log in to view your profile');
        return;
      }

      debugPrint(
        'Loading profile data for user: ${CustomerController.logeInCustomer!.uid}',
      );

      // Fetch events created by user
      final created = await FirebaseFirestoreHelper().getEventsCreatedByUser(
        CustomerController.logeInCustomer!.uid,
      );
      debugPrint('Created events count: ${created.length}');

      // Fetch events attended by user
      final attended = await FirebaseFirestoreHelper().getEventsAttendedByUser(
        CustomerController.logeInCustomer!.uid,
      );
      debugPrint('Attended events count: ${attended.length}');

      // Fetch saved events
      final saved = await FirebaseFirestoreHelper().getFavoritedEvents(
        userId: CustomerController.logeInCustomer!.uid,
      );
      debugPrint('Saved events count: ${saved.length}');

      // Load user badge
      await _loadUserBadge();

      if (mounted) {
        setState(() {
          createdEvents = created;
          attendedEvents = attended;
          savedEvents = saved;
          isDiscoverable =
              CustomerController.logeInCustomer?.isDiscoverable ?? true;
          isLoading = false;
        });
        debugPrint('Profile data loaded successfully');
      }
    } catch (e) {
      debugPrint('Error loading profile data: $e');
      if (mounted) {
        setState(() {
          isLoading = false;
        });
        ShowToast().showNormalToast(
          msg: 'Failed to load profile data: ${e.toString()}',
        );
      }
    }
  }

  // Bio section and related state removed to avoid duplication with UserProfileScreen

  // Badge related methods
  Future<void> _loadUserBadge() async {
    try {
      final userId = CustomerController.logeInCustomer?.uid;
      if (userId == null) return;

      setState(() {
        _isBadgeLoading = true;
      });

      final badge = await _badgeService.getOrGenerateBadge(userId);

      if (mounted) {
        setState(() {
          _userBadge = badge;
          _isBadgeLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Error loading user badge: $e');
      if (mounted) {
        setState(() {
          _isBadgeLoading = false;
        });
      }
    }
  }

  void _navigateToBadgeScreen() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => BadgeScreen(
          userId: CustomerController.logeInCustomer?.uid,
          isOwnBadge: true,
        ),
      ),
    );
  }

  // Selection methods
  void _toggleSelectionMode() {
    setState(() {
      isSelectionMode = !isSelectionMode;
      if (!isSelectionMode) {
        selectedEventIds.clear();
      }
    });
  }

  void _toggleEventSelection(String eventId) {
    setState(() {
      if (selectedEventIds.contains(eventId)) {
        selectedEventIds.remove(eventId);
      } else {
        selectedEventIds.add(eventId);
      }
    });
  }

  void _toggleSelectAll(List<EventModel> events) {
    setState(() {
      if (selectedEventIds.length == events.length) {
        // If all are selected, deselect all
        selectedEventIds.clear();
      } else {
        // Select all
        selectedEventIds = events.map((e) => e.id).toSet();
      }
    });
  }

  Future<void> _deleteSelectedEvents() async {
    if (selectedEventIds.isEmpty) {
      ShowToast().showNormalToast(msg: 'Please select events to delete');
      return;
    }

    // Show confirmation dialog
    final bool? confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text(
          'Delete Events',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            fontFamily: 'Roboto',
          ),
        ),
        content: Text(
          'Are you sure you want to delete ${selectedEventIds.length} selected event${selectedEventIds.length == 1 ? '' : 's'}? This action cannot be undone.',
          style: const TextStyle(fontSize: 16, fontFamily: 'Roboto'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text(
              'Cancel',
              style: TextStyle(
                color: Color(0xFF6B7280),
                fontWeight: FontWeight.w600,
                fontFamily: 'Roboto',
              ),
            ),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFEF4444),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            child: const Text(
              'Delete',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w600,
                fontFamily: 'Roboto',
              ),
            ),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    setState(() {
      isLoading = true;
    });

    try {
      // Delete events from Firebase
      for (String eventId in selectedEventIds) {
        await FirebaseFirestoreHelper().deleteEvent(eventId);
      }

      if (mounted) {
        setState(() {
          selectedEventIds.clear();
          isSelectionMode = false;
          isLoading = false;
        });
        ShowToast().showNormalToast(
          msg:
              '${selectedEventIds.length} event${selectedEventIds.length == 1 ? '' : 's'} deleted successfully',
        );
        // Reload profile data to refresh the lists
        _loadProfileData();
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          isLoading = false;
        });
        ShowToast().showNormalToast(msg: 'Failed to delete events: $e');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = CustomerController.logeInCustomer;
    return Scaffold(
      backgroundColor: const Color(0xFFFAFBFC),
      body: SafeArea(
        child: isLoading
            ? _buildLoadingState()
            : FadeTransition(
                opacity: _fadeAnimation,
                child: SlideTransition(
                  position: _slideAnimation,
                  child: _buildProfileContent(user),
                ),
              ),
      ),
    );
  }

  Widget _buildLoadingState() {
    return SingleChildScrollView(
      child: Column(
        children: [
          _buildShimmerProfileHeader(),
          const SizedBox(height: 24),
          _buildShimmerTabs(),
          const SizedBox(height: 16),
          _buildShimmerEventList(),
        ],
      ),
    );
  }

  Widget _buildShimmerProfileHeader() {
    return Shimmer.fromColors(
      baseColor: Colors.grey[300]!,
      highlightColor: Colors.grey[100]!,
      child: Container(
        margin: const EdgeInsets.all(20),
        child: Row(
          children: [
            Container(
              width: 60,
              height: 60,
              decoration: const BoxDecoration(
                color: Colors.white,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 150,
                    height: 20,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Container(
                    width: 200,
                    height: 14,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(7),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildShimmerTabs() {
    return Shimmer.fromColors(
      baseColor: Colors.grey[300]!,
      highlightColor: Colors.grey[100]!,
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 20),
        child: Row(
          children: [
            Expanded(
              child: Container(
                height: 48,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Container(
                height: 48,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildShimmerEventList() {
    return Shimmer.fromColors(
      baseColor: Colors.grey[300]!,
      highlightColor: Colors.grey[100]!,
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 20),
        child: Column(
          children: List.generate(
            3,
            (index) => Container(
              margin: const EdgeInsets.only(bottom: 12),
              height: 120,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildProfileContent(CustomerModel? user) {
    return RefreshIndicator(
      onRefresh: _loadProfileData,
      color: const Color(0xFF667EEA),
      child: CustomScrollView(
        slivers: [
          // Back Button and Profile Header
          SliverToBoxAdapter(child: _buildProfileHeader(user)),
          // Badge Section
          SliverToBoxAdapter(child: _buildBadgeSection()),
          // Discoverability Section
          SliverToBoxAdapter(child: _buildDiscoverabilitySection()),
          // My Tickets Section
          SliverToBoxAdapter(child: _buildMyTicketsSection()),
          // Tab Bar
          SliverToBoxAdapter(child: _buildTabBar()),
          // Tab Content
          SliverToBoxAdapter(child: _buildTabContent()),
        ],
      ),
    );
  }

  Widget _buildProfileHeader(CustomerModel? user) {
    return Container(
      width: double.infinity,
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF667EEA), Color(0xFF764BA2)],
        ),
      ),
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
      child: Column(
        children: [
          // Back Button and Header Row
          Row(
            children: [
              GestureDetector(
                onTap: () {
                  if (isSelectionMode) {
                    setState(() {
                      isSelectionMode = false;
                      selectedEventIds.clear();
                    });
                  } else {
                    Navigator.of(context).pop();
                  }
                },
                child: Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(18),
                  ),
                  child: Icon(
                    isSelectionMode ? Icons.close : Icons.arrow_back,
                    color: Colors.white,
                    size: 18,
                  ),
                ),
              ),
              const Spacer(),
              Text(
                isSelectionMode ? '${selectedEventIds.length} selected' : '',
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                  fontSize: 16,
                  fontFamily: 'Roboto',
                ),
              ),
              // Account Details (Edit) button
              GestureDetector(
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (context) => const AccountDetailsScreen(),
                    ),
                  );
                },
                child: Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(18),
                  ),
                  child: const Icon(
                    Icons.edit,
                    color: Colors.white,
                    size: 18,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Compact Profile Section - Horizontal Layout
          Row(
            children: [
              // Profile Picture
              Stack(
                children: [
                  Container(
                    width: 60,
                    height: 60,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white, width: 3),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.15),
                          blurRadius: 12,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: ClipOval(
                      child: user?.profilePictureUrl != null
                          ? Image.network(
                              user!.profilePictureUrl!,
                              fit: BoxFit.cover,
                              errorBuilder: (context, error, stackTrace) {
                                return _buildDefaultProfilePicture();
                              },
                            )
                          : _buildDefaultProfilePicture(),
                    ),
                  ),
                  Positioned(
                    bottom: 0,
                    right: 0,
                    child: Container(
                      width: 24,
                      height: 24,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.1),
                            blurRadius: 4,
                            offset: const Offset(0, 1),
                          ),
                        ],
                      ),
                      child: const Icon(
                        Icons.camera_alt,
                        color: Color(0xFF667EEA),
                        size: 12,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(width: 16),

              // User Info - Vertical Stack
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      user?.name ?? 'User',
                      style: const TextStyle(
                        color: AppThemeColor.pureWhiteColor,
                        fontSize: 24,
                        fontWeight: FontWeight.w600,
                        fontFamily: 'Roboto',
                      ),
                    ),
                    if (user?.username != null &&
                        user!.username!.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      GestureDetector(
                        onTap: () {
                          // Navigate to public profile view
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => UserProfileScreen(
                                user: user,
                                isOwnProfile: true,
                              ),
                            ),
                          );
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.2),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: Colors.white.withValues(alpha: 0.3),
                              width: 1,
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                '@${user.username}',
                                style: TextStyle(
                                  color: Colors.white.withValues(alpha: 0.9),
                                  fontWeight: FontWeight.w500,
                                  fontSize: 16,
                                  fontFamily: 'Roboto',
                                ),
                              ),
                              const SizedBox(width: 4),
                              Icon(
                                Icons.open_in_new,
                                color: Colors.white.withValues(alpha: 0.7),
                                size: 14,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                    const SizedBox(height: 2),
                    Text(
                      'Welcome to your profile',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.8),
                        fontWeight: FontWeight.w400,
                        fontSize: 14,
                        fontFamily: 'Roboto',
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildDefaultProfilePicture() {
    return Container(
      color: const Color(0xFFE1E5E9),
      child: const Icon(Icons.person, size: 30, color: Color(0xFF9CA3AF)),
    );
  }

  // _buildBioSection removed

  Widget _buildBadgeSection() {
    if (_isBadgeLoading) {
      return Container(
        margin: const EdgeInsets.fromLTRB(24, 0, 24, 24),
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              spreadRadius: 0,
              blurRadius: 20,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: const Center(
          child: CircularProgressIndicator(
            valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF667EEA)),
          ),
        ),
      );
    }

    if (_userBadge == null) {
      return const SizedBox(); // Don't show anything if badge failed to load
    }

    return Container(
      margin: const EdgeInsets.fromLTRB(24, 0, 24, 24),
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            spreadRadius: 0,
            blurRadius: 20,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Icon(
                    Icons.military_tech,
                    color: const Color(0xFF667EEA),
                    size: 18,
                  ),
                  const SizedBox(width: 8),
                  const Text(
                    'My Badge',
                    style: TextStyle(
                      color: Color(0xFF1A1A1A),
                      fontWeight: FontWeight.w600,
                      fontSize: 16,
                      fontFamily: 'Roboto',
                    ),
                  ),
                ],
              ),
              GestureDetector(
                onTap: _navigateToBadgeScreen,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFF667EEA).withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text(
                        'View Full Badge',
                        style: TextStyle(
                          color: Color(0xFF667EEA),
                          fontWeight: FontWeight.w600,
                          fontSize: 12,
                          fontFamily: 'Roboto',
                        ),
                      ),
                      const SizedBox(width: 4),
                      const Icon(
                        Icons.arrow_forward_ios,
                        color: Color(0xFF667EEA),
                        size: 12,
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Center(
            child: GestureDetector(
              onTap: _navigateToBadgeScreen,
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final availableWidth = constraints.maxWidth;
                  final badgeWidth = availableWidth.clamp(260.0, 360.0);
                  final badgeHeight = badgeWidth * (180 / 280);
                  return ProfessionalBadgeWidget(
                    badge: _userBadge!,
                    width: badgeWidth,
                    height: badgeHeight,
                    showActions: false,
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDiscoverabilitySection() {
    return Container(
      margin: const EdgeInsets.fromLTRB(24, 0, 24, 24),
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            spreadRadius: 0,
            blurRadius: 20,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.visibility, color: const Color(0xFF667EEA), size: 18),
              const SizedBox(width: 8),
              const Text(
                'Privacy Settings',
                style: TextStyle(
                  color: Color(0xFF1A1A1A),
                  fontWeight: FontWeight.w600,
                  fontSize: 16,
                  fontFamily: 'Roboto',
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Profile Discoverability',
                      style: TextStyle(
                        color: Color(0xFF1A1A1A),
                        fontWeight: FontWeight.w500,
                        fontSize: 14,
                        fontFamily: 'Roboto',
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      isDiscoverable
                          ? 'Your profile can be found in user searches'
                          : 'Your profile is hidden from user searches',
                      style: TextStyle(
                        color: const Color(0xFF6B7280),
                        fontSize: 12,
                        fontFamily: 'Roboto',
                      ),
                    ),
                  ],
                ),
              ),
              Switch(
                value: isDiscoverable,
                onChanged: (value) {
                  setState(() {
                    isDiscoverable = value;
                  });
                  _updateDiscoverability(value);
                },
                activeColor: const Color(0xFF667EEA),
                activeTrackColor: const Color(
                  0xFF667EEA,
                ).withValues(alpha: 0.3),
                inactiveThumbColor: const Color(0xFF9CA3AF),
                inactiveTrackColor: const Color(0xFFE1E5E9),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _updateDiscoverability(bool value) async {
    try {
      final user = CustomerController.logeInCustomer;
      if (user != null) {
        await FirebaseFirestoreHelper().updateUserDiscoverability(
          userId: user.uid,
          isDiscoverable: value,
        );
        ShowToast().showNormalToast(
          msg: value
              ? 'Profile is now discoverable'
              : 'Profile is now hidden from searches',
        );
      }
    } catch (e) {
      ShowToast().showNormalToast(msg: 'Failed to update privacy settings: $e');
      // Revert the state if update failed
      setState(() {
        isDiscoverable = !value;
      });
    }
  }

  Widget _buildMyTicketsSection() {
    return Container(
      margin: const EdgeInsets.fromLTRB(24, 0, 24, 24),
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            spreadRadius: 0,
            blurRadius: 20,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // My Tickets button
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFFFF9800).withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: const Color(0xFFFF9800).withValues(alpha: 0.3),
              ),
            ),
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => const MyTicketsScreen(),
                    ),
                  );
                },
                child: Row(
                  children: [
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: const Color(0xFFFF9800).withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(
                        Icons.confirmation_number,
                        color: Color(0xFFFF9800),
                        size: 20,
                      ),
                    ),
                    const SizedBox(width: 12),
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'My Tickets',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                              color: Color(0xFF1A1A1A),
                              fontFamily: 'Roboto',
                            ),
                          ),
                          SizedBox(height: 2),
                          Text(
                            'View and manage your event tickets',
                            style: TextStyle(
                              fontSize: 12,
                              color: Color(0xFF6B7280),
                              fontFamily: 'Roboto',
                            ),
                          ),
                        ],
                      ),
                    ),
                    const Icon(
                      Icons.arrow_forward_ios,
                      color: Color(0xFFFF9800),
                      size: 16,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTabBar() {
    return Container(
      margin: const EdgeInsets.fromLTRB(24, 0, 24, 24),
      child: Column(
        children: [
          // Title and Action buttons row
          Row(
            children: [
              // Events title
              const Text(
                'Events',
                style: TextStyle(
                  color: Color(0xFF1A1A1A),
                  fontWeight: FontWeight.w600,
                  fontSize: 18,
                  fontFamily: 'Roboto',
                ),
              ),
              const Spacer(),
              // Action buttons
              _buildActionButton(
                icon: Icons.tune,
                label: 'Filter/Sort',
                onTap: _showFilterSortModal,
                isActive:
                    selectedCategories.isNotEmpty ||
                    currentSortOption != SortOption.none,
              ),
              const SizedBox(width: 8),
              _buildActionButton(
                icon: Icons.checklist,
                label: 'Select',
                onTap: _toggleSelectionMode,
                isActive: isSelectionMode,
              ),
            ],
          ),
          const SizedBox(height: 12),
          // Tab bar
          Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.05),
                  spreadRadius: 0,
                  blurRadius: 20,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Row(
              children: [
                _buildTabButton(label: 'Created', index: 1),
                Container(width: 1, height: 40, color: const Color(0xFFE1E5E9)),
                _buildTabButton(label: 'Attended', index: 2),
                Container(width: 1, height: 40, color: const Color(0xFFE1E5E9)),
                _buildTabButton(label: 'Saved', index: 3),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActionButton({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    required bool isActive,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
        decoration: BoxDecoration(
          color: isActive
              ? const Color(0xFF667EEA).withValues(alpha: 0.1)
              : Colors.white,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isActive ? const Color(0xFF667EEA) : const Color(0xFFE1E5E9),
            width: 1,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              spreadRadius: 0,
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              color: isActive
                  ? const Color(0xFF667EEA)
                  : const Color(0xFF9CA3AF),
              size: 16,
            ),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                color: isActive
                    ? const Color(0xFF667EEA)
                    : const Color(0xFF9CA3AF),
                fontSize: 12,
                fontWeight: isActive ? FontWeight.w600 : FontWeight.normal,
                fontFamily: 'Roboto',
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTabButton({required String label, required int index}) {
    bool isSelected = selectedTab == index;
    int eventCount;
    if (index == 1) {
      eventCount = createdEvents.length;
    } else if (index == 2) {
      eventCount = attendedEvents.length;
    } else {
      eventCount = savedEvents.length;
    }

    return Expanded(
      child: GestureDetector(
        onTap: () {
          setState(() {
            selectedTab = index;
          });
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 300),
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            color: isSelected ? const Color(0xFF667EEA) : Colors.transparent,
            borderRadius: BorderRadius.circular(20),
          ),
          child: Text(
            '$label ($eventCount)',
            style: TextStyle(
              color: isSelected ? Colors.white : const Color(0xFF9CA3AF),
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

  Widget _buildTabContent() {
    final events = selectedTab == 1
        ? createdEvents
        : selectedTab == 2
        ? attendedEvents
        : savedEvents;
    final emptyMessage = selectedTab == 1
        ? 'You haven\'t created any events yet'
        : selectedTab == 2
        ? 'You haven\'t attended any events yet'
        : 'You haven\'t saved any events yet';
    final emptyIcon = selectedTab == 1
        ? FontAwesomeIcons.plus
        : selectedTab == 2
        ? FontAwesomeIcons.calendarCheck
        : FontAwesomeIcons.bookmark;

    debugPrint('Building tab content - Selected tab: $selectedTab');
    debugPrint('Created events: ${createdEvents.length}');
    debugPrint('Attended events: ${attendedEvents.length}');
    debugPrint('Current events to show: ${events.length}');

    // Apply category filtering
    List<EventModel> filteredEvents = List<EventModel>.from(events);
    if (selectedCategories.isNotEmpty) {
      filteredEvents = filteredEvents
          .where(
            (event) => event.categories.any(
              (category) => selectedCategories.contains(category),
            ),
          )
          .toList();
    }

    // Apply sorting
    final sortedEvents = _sortEvents(filteredEvents);

    return Container(
      margin: const EdgeInsets.fromLTRB(24, 0, 24, 24),
      child: sortedEvents.isEmpty
          ? _buildEmptyState(emptyMessage, emptyIcon)
          : Column(
              children: [
                // Selection mode controls
                if (isSelectionMode)
                  Container(
                    margin: const EdgeInsets.only(bottom: 16),
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.05),
                          spreadRadius: 0,
                          blurRadius: 10,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: Column(
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                '${selectedEventIds.length} of ${sortedEvents.length} selected',
                                style: const TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                  color: Color(0xFF1A1A1A),
                                  fontFamily: 'Roboto',
                                ),
                              ),
                            ),
                            TextButton(
                              onPressed: () => _toggleSelectAll(sortedEvents),
                              child: Text(
                                selectedEventIds.length == sortedEvents.length
                                    ? 'Deselect All'
                                    : 'Select All',
                                style: const TextStyle(
                                  color: Color(0xFF667EEA),
                                  fontWeight: FontWeight.w600,
                                  fontFamily: 'Roboto',
                                ),
                              ),
                            ),
                          ],
                        ),
                        if (selectedEventIds.isNotEmpty) ...[
                          const SizedBox(height: 12),
                          SizedBox(
                            width: double.infinity,
                            child: ElevatedButton.icon(
                              onPressed: _deleteSelectedEvents,
                              icon: const Icon(Icons.delete, size: 18),
                              label: Text(
                                'Delete ${selectedEventIds.length} Event${selectedEventIds.length == 1 ? '' : 's'}',
                              ),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFFEF4444),
                                foregroundColor: Colors.white,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                padding: const EdgeInsets.symmetric(
                                  vertical: 12,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                // Events list
                ListView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: sortedEvents.length,
                  itemBuilder: (context, index) {
                    debugPrint('Building event item at index: $index');
                    return Container(
                      margin: const EdgeInsets.only(bottom: 12),
                      child: _buildSelectableEventItem(sortedEvents[index]),
                    );
                  },
                ),
              ],
            ),
    );
  }

  Widget _buildEmptyState(String message, IconData icon) {
    return Container(
      padding: const EdgeInsets.all(40),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            spreadRadius: 0,
            blurRadius: 20,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: [
          Icon(icon, size: 64, color: const Color(0xFF9CA3AF)),
          const SizedBox(height: 16),
          Text(
            message,
            style: const TextStyle(
              fontSize: 18,
              color: Color(0xFF1A1A1A),
              fontWeight: FontWeight.w600,
              fontFamily: 'Roboto',
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          Text(
            selectedTab == 1
                ? 'Start creating amazing events!'
                : 'Join events to see them here',
            style: const TextStyle(
              fontSize: 14,
              color: Color(0xFF9CA3AF),
              fontFamily: 'Roboto',
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          ElevatedButton(
            onPressed: _loadProfileData,
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF667EEA),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            ),
            child: const Text(
              'Retry',
              style: TextStyle(
                fontWeight: FontWeight.w600,
                fontSize: 14,
                fontFamily: 'Roboto',
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSelectableEventItem(EventModel event) {
    final bool isSelected = selectedEventIds.contains(event.id);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () {
          if (isSelectionMode) {
            _toggleEventSelection(event.id);
          } else {
            // Navigate to event details
            // You can add navigation here if needed
          }
        },
        onLongPress: () {
          if (!isSelectionMode) {
            setState(() {
              isSelectionMode = true;
              selectedEventIds.add(event.id);
            });
          }
        },
        child: Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: isSelectionMode && isSelected
                ? Border.all(color: const Color(0xFF667EEA), width: 2)
                : null,
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.05),
                spreadRadius: 0,
                blurRadius: 10,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Stack(
            children: [
              SingleEventListViewItem(
                eventModel: event,
                disableTap: isSelectionMode,
                onFavoriteChanged: _refreshSavedEvents,
              ),
              // Selection checkbox overlay
              if (isSelectionMode)
                Positioned(
                  top: 12,
                  right: 12,
                  child: Container(
                    width: 24,
                    height: 24,
                    decoration: BoxDecoration(
                      color: isSelected
                          ? const Color(0xFF667EEA)
                          : Colors.white.withValues(alpha: 0.9),
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: isSelected
                            ? const Color(0xFF667EEA)
                            : const Color(0xFF9CA3AF),
                        width: 2,
                      ),
                    ),
                    child: isSelected
                        ? const Icon(Icons.check, color: Colors.white, size: 16)
                        : null,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  // Sort events based on current sort option
  List<EventModel> _sortEvents(List<EventModel> events) {
    switch (currentSortOption) {
      case SortOption.none:
        // Default sorting based on tab context
        if (selectedTab == 1) {
          // Created events - sort by creation date (most recent first)
          events.sort(
            (a, b) => b.eventGenerateTime.compareTo(a.eventGenerateTime),
          );
        } else if (selectedTab == 2) {
          // Attended events - sort by event date (most recent first)
          events.sort(
            (a, b) => b.selectedDateTime.compareTo(a.selectedDateTime),
          );
        } else {
          // Favorited events - sort by event date (most recent first)
          events.sort(
            (a, b) => b.selectedDateTime.compareTo(a.selectedDateTime),
          );
        }
        break;
      case SortOption.dateAddedAsc:
        events.sort(
          (a, b) => a.eventGenerateTime.compareTo(b.eventGenerateTime),
        );
        break;
      case SortOption.dateAddedDesc:
        events.sort(
          (a, b) => b.eventGenerateTime.compareTo(a.eventGenerateTime),
        );
        break;
      case SortOption.titleAsc:
        events.sort(
          (a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()),
        );
        break;
      case SortOption.titleDesc:
        events.sort(
          (a, b) => b.title.toLowerCase().compareTo(a.title.toLowerCase()),
        );
        break;
      case SortOption.eventDateAsc:
        events.sort((a, b) => a.selectedDateTime.compareTo(b.selectedDateTime));
        break;
      case SortOption.eventDateDesc:
        events.sort((a, b) => b.selectedDateTime.compareTo(a.selectedDateTime));
        break;
    }
    return events;
  }

  // Show filter/sort modal
  void _showFilterSortModal() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => _FilterSortModal(
        selectedCategories: selectedCategories,
        currentSortOption: currentSortOption,
        allCategories: _allCategories,
        selectedTab: selectedTab,
        onCategoriesChanged: (categories) {
          setState(() {
            selectedCategories = categories;
          });
        },
        onSortOptionChanged: (sortOption) {
          setState(() {
            currentSortOption = sortOption;
          });
        },
      ),
    );
  }
}

// Filter/Sort Modal Widget
class _FilterSortModal extends StatefulWidget {
  final List<String> selectedCategories;
  final SortOption currentSortOption;
  final List<String> allCategories;
  final Function(List<String>) onCategoriesChanged;
  final Function(SortOption) onSortOptionChanged;
  final int selectedTab;

  const _FilterSortModal({
    required this.selectedCategories,
    required this.currentSortOption,
    required this.allCategories,
    required this.onCategoriesChanged,
    required this.onSortOptionChanged,
    required this.selectedTab,
  });

  @override
  State<_FilterSortModal> createState() => _FilterSortModalState();
}

class _FilterSortModalState extends State<_FilterSortModal> {
  late List<String> _selectedCategories;
  late SortOption _currentSortOption;

  @override
  void initState() {
    super.initState();
    _selectedCategories = List.from(widget.selectedCategories);
    _currentSortOption = widget.currentSortOption;
  }

  void _updateCategories(List<String> categories) {
    setState(() {
      _selectedCategories = categories;
    });
    widget.onCategoriesChanged(categories);
  }

  void _updateSortOption(SortOption sortOption) {
    setState(() {
      _currentSortOption = sortOption;
    });
    widget.onSortOptionChanged(sortOption);
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(24),
          topRight: Radius.circular(24),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Handle bar
          Container(
            margin: const EdgeInsets.only(top: 12),
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.grey[300],
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          // Header
          Padding(
            padding: const EdgeInsets.all(24),
            child: Row(
              children: [
                const Icon(Icons.tune, color: Color(0xFF667EEA), size: 24),
                const SizedBox(width: 12),
                const Text(
                  'Filter/Sort Events',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    fontFamily: 'Roboto',
                  ),
                ),
                const Spacer(),
                GestureDetector(
                  onTap: () => Navigator.pop(context),
                  child: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.grey[100],
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(Icons.close, size: 20),
                  ),
                ),
              ],
            ),
          ),
          // Content
          Flexible(
            child: ListView(
              shrinkWrap: true,
              padding: const EdgeInsets.symmetric(horizontal: 24),
              children: [
                // Active filters summary
                if (_selectedCategories.isNotEmpty ||
                    _currentSortOption != SortOption.none)
                  _buildActiveFiltersSummary(),
                if (_selectedCategories.isNotEmpty ||
                    _currentSortOption != SortOption.none)
                  const SizedBox(height: 16),
                // Categories Section
                _buildCategoriesSection(),
                const Divider(height: 32),
                // Sort Section
                _buildSortSection(),
                const SizedBox(height: 24),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // Build active filters summary
  Widget _buildActiveFiltersSummary() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF667EEA).withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: const Color(0xFF667EEA).withValues(alpha: 0.3),
          width: 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.filter_list, color: const Color(0xFF667EEA), size: 16),
              const SizedBox(width: 8),
              Text(
                'Active Filters',
                style: TextStyle(
                  color: const Color(0xFF667EEA),
                  fontWeight: FontWeight.w600,
                  fontSize: 14,
                  fontFamily: 'Roboto',
                ),
              ),
            ],
          ),
          if (_selectedCategories.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              'Categories: ${_selectedCategories.join(', ')}',
              style: TextStyle(
                color: const Color(0xFF667EEA),
                fontSize: 12,
                fontFamily: 'Roboto',
              ),
            ),
          ],
          if (_currentSortOption != SortOption.none) ...[
            const SizedBox(height: 4),
            Text(
              'Sort: ${_getSortOptionText(_currentSortOption)}',
              style: TextStyle(
                color: const Color(0xFF667EEA),
                fontSize: 12,
                fontFamily: 'Roboto',
              ),
            ),
          ],
        ],
      ),
    );
  }

  // Build categories section
  Widget _buildCategoriesSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.category, color: const Color(0xFF667EEA), size: 20),
            const SizedBox(width: 8),
            const Text(
              'Filter by Category',
              style: TextStyle(
                color: Color(0xFF1A1A1A),
                fontWeight: FontWeight.w600,
                fontSize: 18,
                fontFamily: 'Roboto',
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            ...widget.allCategories.map((category) {
              final isSelected = _selectedCategories.contains(category);
              return _buildCategoryChip(
                label: category,
                icon: _getCategoryIcon(category),
                isSelected: isSelected,
                onSelected: (selected) {
                  List<String> newCategories = List.from(_selectedCategories);
                  if (selected) {
                    newCategories.add(category);
                  } else {
                    newCategories.remove(category);
                  }
                  _updateCategories(newCategories);
                },
                color: const Color(0xFF667EEA),
              );
            }),
            if (_selectedCategories.isNotEmpty)
              _buildCategoryChip(
                label: 'Clear All',
                icon: Icons.clear,
                isSelected: false,
                onSelected: (_) {
                  _updateCategories([]);
                },
                color: const Color(0xFFE53E3E),
              ),
          ],
        ),
      ],
    );
  }

  // Build category chip
  Widget _buildCategoryChip({
    required String label,
    required IconData icon,
    required bool isSelected,
    required Function(bool) onSelected,
    required Color color,
  }) {
    return FilterChip(
      label: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: isSelected ? Colors.white : color),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              color: isSelected ? Colors.white : const Color(0xFF1A1A1A),
              fontWeight: FontWeight.w500,
              fontSize: 14,
              fontFamily: 'Roboto',
            ),
          ),
        ],
      ),
      selected: isSelected,
      onSelected: onSelected,
      backgroundColor: Colors.white,
      selectedColor: color,
      side: BorderSide(
        color: isSelected ? color : const Color(0xFFE1E5E9),
        width: 1.5,
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
    );
  }

  // Build sort section
  Widget _buildSortSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.sort, color: const Color(0xFF667EEA), size: 20),
            const SizedBox(width: 8),
            const Text(
              'Sort by',
              style: TextStyle(
                color: Color(0xFF1A1A1A),
                fontWeight: FontWeight.w600,
                fontSize: 18,
                fontFamily: 'Roboto',
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        // Default (No Sorting)
        _buildSortOptionGroup('Default', [SortOption.none]),
        const SizedBox(height: 16),
        // Date Added section
        _buildSortOptionGroup('Date Added', [
          SortOption.dateAddedDesc,
          SortOption.dateAddedAsc,
        ]),
        const SizedBox(height: 16),
        // Title section
        _buildSortOptionGroup('Title', [
          SortOption.titleAsc,
          SortOption.titleDesc,
        ]),
        const SizedBox(height: 16),
        // Event Date section
        _buildSortOptionGroup('Event Date', [
          SortOption.eventDateDesc,
          SortOption.eventDateAsc,
        ]),
      ],
    );
  }

  // Build sort option group
  Widget _buildSortOptionGroup(String title, List<SortOption> options) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Text(
            title,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: Colors.grey[600],
              fontFamily: 'Roboto',
            ),
          ),
        ),
        ...options.map((option) {
          bool isSelected = _currentSortOption == option;
          return GestureDetector(
            onTap: () {
              _updateSortOption(option);
            },
            child: Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: isSelected
                    ? const Color(0xFF667EEA).withValues(alpha: 0.1)
                    : Colors.grey[50],
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: isSelected
                      ? const Color(0xFF667EEA)
                      : Colors.grey[200]!,
                  width: 1,
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    _getSortOptionIcon(option),
                    color: isSelected
                        ? const Color(0xFF667EEA)
                        : Colors.grey[600],
                    size: 20,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      _getSortOptionText(option),
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: isSelected
                            ? FontWeight.w600
                            : FontWeight.w500,
                        color: isSelected
                            ? const Color(0xFF1A1A1A)
                            : Colors.grey[700],
                        fontFamily: 'Roboto',
                      ),
                    ),
                  ),
                  if (isSelected)
                    const Icon(
                      Icons.check_circle,
                      color: Color(0xFF667EEA),
                      size: 20,
                    ),
                ],
              ),
            ),
          );
        }),
      ],
    );
  }

  IconData _getCategoryIcon(String category) {
    switch (category) {
      case 'Educational':
        return Icons.school;
      case 'Professional':
        return Icons.work;
      case 'Other':
        return Icons.more_horiz;
      default:
        return Icons.category;
    }
  }

  // Get sort option display text
  String _getSortOptionText(SortOption option) {
    switch (option) {
      case SortOption.none:
        if (widget.selectedTab == 1) {
          return 'Most Recent Created';
        } else if (widget.selectedTab == 2) {
          return 'Most Recent Attended';
        } else {
          return 'Most Recent Favorited';
        }
      case SortOption.dateAddedAsc:
        return 'Date Added (Oldest First)';
      case SortOption.dateAddedDesc:
        return 'Date Added (Newest First)';
      case SortOption.titleAsc:
        return 'Title (A-Z)';
      case SortOption.titleDesc:
        return 'Title (Z-A)';
      case SortOption.eventDateAsc:
        return 'Event Date (Earliest First)';
      case SortOption.eventDateDesc:
        return 'Event Date (Latest First)';
    }
  }

  // Get sort option icon
  IconData _getSortOptionIcon(SortOption option) {
    switch (option) {
      case SortOption.none:
        return Icons.sort;
      case SortOption.dateAddedAsc:
      case SortOption.dateAddedDesc:
        return Icons.schedule;
      case SortOption.titleAsc:
      case SortOption.titleDesc:
        return Icons.sort_by_alpha;
      case SortOption.eventDateAsc:
      case SortOption.eventDateDesc:
        return Icons.event;
    }
  }
}
