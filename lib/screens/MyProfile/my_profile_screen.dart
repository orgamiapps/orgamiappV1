import 'package:flutter/material.dart';
import 'package:attendus/controller/customer_controller.dart';
import 'package:attendus/models/customer_model.dart';
import 'package:attendus/firebase/firebase_firestore_helper.dart';
import 'package:attendus/models/event_model.dart';
import 'package:attendus/screens/Events/Widget/single_event_list_view_item.dart';
import 'package:attendus/Utils/cached_image.dart';
import 'package:attendus/Utils/toast.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:shimmer/shimmer.dart';
import 'package:attendus/screens/MyProfile/my_tickets_screen.dart';
import 'package:attendus/screens/MyProfile/user_profile_screen.dart';
import 'package:attendus/screens/MyProfile/Widgets/professional_badge_widget.dart';
import 'package:attendus/models/badge_model.dart';
import 'package:attendus/Services/badge_service.dart';
import 'package:attendus/screens/Home/account_details_screen_v2.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:attendus/Utils/profile_diagnostics.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

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
  final bool showBackButton;

  const MyProfileScreen({super.key, this.showBackButton = true});

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

  // Pagination state for each tab
  Map<int, DocumentSnapshot?> _lastDocuments = {};
  Map<int, bool> _hasMore = {1: true, 2: true, 3: true};
  Map<int, bool> _isFetchingMore = {1: false, 2: false, 3: false};

  // Badge related fields
  UserBadgeModel? _userBadge;
  bool _isBadgeLoading = false;
  final BadgeService _badgeService = BadgeService();
  bool _isBadgeExpanded = false;

  // Selection state
  bool isSelectionMode = false;
  Set<String> selectedEventIds = <String>{};

  // Filter/Sort state
  SortOption currentSortOption = SortOption.none;
  List<String> selectedCategories = [];
  final List<String> _allCategories = [
    'Social & Networking',
    'Entertainment', 
    'Sports & Fitness',
    'Education & Learning',
    'Arts & Culture',
    'Food & Dining',
    'Technology',
    'Community & Charity',
  ];

  // Animation controllers
  late AnimationController _fadeController;
  late Animation<double> _fadeAnimation;
  late AnimationController _slideController;
  late Animation<Offset> _slideAnimation;

  @override
  void initState() {
    super.initState();
    debugPrint('MY_PROFILE_SCREEN: initState called');
    _initializeAnimations();

    // Defer data loading to prevent blocking app startup
    // Load data only when widget is actually visible
    WidgetsBinding.instance.addPostFrameCallback((_) {
      debugPrint(
        'MY_PROFILE_SCREEN: PostFrameCallback executing, about to load profile data',
      );
      if (mounted) {
        debugPrint(
          'MY_PROFILE_SCREEN: Widget is mounted, calling _loadProfileData()',
        );
        _loadProfileData(isRefresh: true);
        // Removed _ensureProfileDataUpdated() - it causes Firebase Auth reload which blocks startup
      } else {
        debugPrint(
          '❌ MY_PROFILE_SCREEN: Widget not mounted in PostFrameCallback',
        );
      }
    });
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
      if (!mounted) return;
      setState(() {
        _hasMore[3] = true;
        _lastDocuments[3] = null;
        savedEvents.clear();
      });
      await _fetchMoreEvents(3);
    } catch (e) {
      debugPrint('Error refreshing saved events: $e');
    }
  }

  Future<void> _loadProfileData({bool isRefresh = false}) async {
    if (!mounted || (isLoading && !isRefresh)) return;

    setState(() {
      isLoading = true;
      if (isRefresh) {
        createdEvents.clear();
        attendedEvents.clear();
        savedEvents.clear();
        _lastDocuments = {};
        _hasMore = {1: true, 2: true, 3: true};
      }
    });

    try {
      if (CustomerController.logeInCustomer == null) {
        if (mounted) {
          setState(() => isLoading = false);
          ShowToast().showNormalToast(
            msg: 'Please log in to view your profile',
          );
        }
        return;
      }

      final userId = CustomerController.logeInCustomer!.uid;

      // Print user info for diagnostics
      debugPrint('CustomerController User ID: $userId');
      debugPrint(
        'CustomerController User Email: ${CustomerController.logeInCustomer!.email}',
      );

      // Load only current tab initially to prevent Firebase overload
      // Other tabs will load on-demand when user switches to them
      debugPrint('🔄 Loading events for current tab ($selectedTab)...');
      await _fetchMoreEvents(selectedTab);

      // Non-blocking background fetches
      _loadUserBadge();
      _refreshUserDataInBackground();

      if (mounted) {
        setState(() {
          isLoading = false;
        });
        debugPrint('✅ MY_PROFILE_SCREEN: Initial data loaded.');
      }
    } catch (e, stackTrace) {
      debugPrint(
        '❌ MY_PROFILE_SCREEN: Error in _loadProfileData: $e\n$stackTrace',
      );
      if (mounted) {
        setState(() => isLoading = false);
        ShowToast().showNormalToast(
          msg: 'Failed to load profile data: ${e.toString()}',
        );
      }
    }
  }

  Future<void> _fetchMoreEvents(int tabIndex) async {
    debugPrint("🔍 _fetchMoreEvents called for tab $tabIndex");
    debugPrint(
      "🔍 _isFetchingMore[$tabIndex]: ${_isFetchingMore[tabIndex]}, _hasMore[$tabIndex]: ${_hasMore[tabIndex]}",
    );

    if ((_isFetchingMore[tabIndex] ?? false) || !(_hasMore[tabIndex] ?? true)) {
      debugPrint(
        "🚫 Skipping fetch for tab $tabIndex - already fetching or no more data",
      );
      return;
    }

    setState(() {
      _isFetchingMore[tabIndex] = true;
    });

    try {
      final userId = CustomerController.logeInCustomer!.uid;
      List<EventModel> newEvents;
      DocumentSnapshot? lastDoc = _lastDocuments[tabIndex];

      debugPrint(
        "🔄 Fetching events for tab $tabIndex (userId: $userId), lastDoc: $lastDoc",
      );

      switch (tabIndex) {
        case 1: // Created
          final result = await FirebaseFirestoreHelper().getEventsCreatedByUser(
            userId,
            limit: 50, // Increased limit to match comprehensive approach
            lastDocument: lastDoc,
          );
          newEvents = result['events'];
          _lastDocuments[tabIndex] = result['lastDoc'];
          break;
        case 2: // Attended
          final result = await FirebaseFirestoreHelper()
              .getEventsAttendedByUser(
                userId,
                limit: 50, // Increased limit to match comprehensive approach
                lastDocument: lastDoc,
              );
          newEvents = result['events'];
          _lastDocuments[tabIndex] = result['lastDoc'];
          break;
        case 3: // Saved
          final result = await FirebaseFirestoreHelper().getFavoritedEvents(
            userId: userId,
            limit: 50, // Increased limit to match comprehensive approach
            lastDocument: lastDoc,
          );
          newEvents = result['events'];
          _lastDocuments[tabIndex] = result['lastDoc'];
          break;
        default:
          newEvents = [];
      }

      // Only log if significant number of events or if there's an issue
      if (newEvents.length > 10 || newEvents.isEmpty) {
        debugPrint("📊 Received ${newEvents.length} events for tab $tabIndex");
      }

      if (mounted) {
        setState(() {
          if (tabIndex == 1) {
            createdEvents.addAll(newEvents);
          } else if (tabIndex == 2) {
            attendedEvents.addAll(newEvents);
          } else if (tabIndex == 3) {
            savedEvents.addAll(newEvents);
          }
          
          // Only log totals if significant or if there are issues
          if (newEvents.length > 5) {
            final totalCount = tabIndex == 1 ? createdEvents.length : 
                              tabIndex == 2 ? attendedEvents.length : 
                              savedEvents.length;
            debugPrint("✅ Tab $tabIndex: Added ${newEvents.length} events (Total: $totalCount)");
          }
          // For created events, we get all on first fetch. For others, check if we need more.
          _hasMore[tabIndex] = (tabIndex != 1) && (newEvents.length >= 50);
          _isFetchingMore[tabIndex] = false;

          // Reduced state logging
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isFetchingMore[tabIndex] = false;
        });
        ShowToast().showNormalToast(
          msg: 'Error loading events. Please try again.',
        );
      }
      debugPrint("❌ Error fetching more events for tab $tabIndex: $e");
    }
  }

  Future<void> _refreshUserDataInBackground() async {
    try {
      final user = await FirebaseFirestoreHelper()
          .getSingleCustomer(customerId: CustomerController.logeInCustomer!.uid)
          .timeout(const Duration(seconds: 5));
      if (user != null && mounted) {
        setState(() {
          CustomerController.logeInCustomer = user;
          isDiscoverable = user.isDiscoverable;
        });
        debugPrint('✅ User data refreshed in background.');
      }
    } catch (e) {
      debugPrint('⚠️ Background user data refresh failed: $e');
    }
  }

  void _onTabChanged(int newIndex) {
    if (selectedTab == newIndex) return;

    setState(() {
      selectedTab = newIndex;
    });
    
    // Load tab data on-demand to prevent Firebase overload
    final events = newIndex == 1
        ? createdEvents
        : (newIndex == 2 ? attendedEvents : savedEvents);
    if (events.isEmpty && (_hasMore[newIndex] ?? true)) {
      // Add small delay to prevent rapid Firebase calls during tab switching
      Future.delayed(const Duration(milliseconds: 100), () {
        if (mounted && selectedTab == newIndex) {
          _fetchMoreEvents(newIndex);
        }
      });
    }
  }

  Future<void> _runComprehensiveDiagnostics() async {
    try {
      debugPrint(
        '🔬 ============== MY PROFILE COMPREHENSIVE DEBUG STARTED ==============',
      );

      final user = CustomerController.logeInCustomer;
      if (user == null) {
        debugPrint('🔬 ❌ No logged in user found');
        return;
      }

      debugPrint('🔬 User ID: ${user.uid}');
      debugPrint('🔬 User Email: ${user.email}');
      debugPrint('🔬 User Name: ${user.name}');
      debugPrint(
        '🔬 Current state - Created: ${createdEvents.length}, Attended: ${attendedEvents.length}, Saved: ${savedEvents.length}',
      );

      // Test each Firebase method individually
      debugPrint('🔬 Testing Created Events...');
      try {
        final createdResult = await FirebaseFirestoreHelper()
            .getEventsCreatedByUser(user.uid, limit: 50);
        final createdEvents = createdResult['events'] as List;
        debugPrint('🔬 ✅ Created Events: ${createdEvents.length}');
        for (int i = 0; i < createdEvents.take(3).length; i++) {
          debugPrint(
            '🔬   - ${createdEvents[i].title} (${createdEvents[i].id})',
          );
        }
      } catch (e) {
        debugPrint('🔬 ❌ Created Events Error: $e');
      }

      debugPrint('🔬 Testing Attended Events...');
      try {
        final attendedResult = await FirebaseFirestoreHelper()
            .getEventsAttendedByUser(user.uid, limit: 50);
        final attendedEvents = attendedResult['events'] as List;
        debugPrint('🔬 ✅ Attended Events: ${attendedEvents.length}');
        for (int i = 0; i < attendedEvents.take(3).length; i++) {
          debugPrint(
            '🔬   - ${attendedEvents[i].title} (${attendedEvents[i].id})',
          );
        }
      } catch (e) {
        debugPrint('🔬 ❌ Attended Events Error: $e');
      }

      debugPrint('🔬 Testing Saved Events...');
      try {
        final savedResult = await FirebaseFirestoreHelper().getFavoritedEvents(
          userId: user.uid,
          limit: 50,
        );
        final savedEvents = savedResult['events'] as List;
        debugPrint('🔬 ✅ Saved Events: ${savedEvents.length}');
        for (int i = 0; i < savedEvents.take(3).length; i++) {
          debugPrint('🔬   - ${savedEvents[i].title} (${savedEvents[i].id})');
        }
      } catch (e) {
        debugPrint('🔬 ❌ Saved Events Error: $e');
      }

      // Test direct Firebase queries
      debugPrint('🔬 Testing Direct Firebase Queries...');
      final directQuery = FirebaseFirestore.instance
          .collection('Events')
          .where('customerUid', isEqualTo: user.uid);
      final directResult = await directQuery.get();
      debugPrint('🔬 Direct query found ${directResult.docs.length} events');

      // Run ProfileDiagnostics as well
      debugPrint('🔬 Running ProfileDiagnostics...');
      await ProfileDiagnostics.runFullDiagnostics();

      debugPrint(
        '🔬 ============== MY PROFILE COMPREHENSIVE DEBUG FINISHED ==============',
      );

      // Automatically reload data after diagnostics to show any fixes
      debugPrint('🔬 Reloading profile data after diagnostics...');
      await _loadProfileData(isRefresh: true);

      // Final comparison
      debugPrint('🔬 FINAL COMPARISON:');
      debugPrint('🔬   My Profile Created Events: ${createdEvents.length}');
      debugPrint('🔬   My Profile Attended Events: ${attendedEvents.length}');
      debugPrint('🔬   My Profile Saved Events: ${savedEvents.length}');
    } catch (e, stackTrace) {
      debugPrint('🔬 ❌ Comprehensive diagnostics failed: $e');
      debugPrint('🔬 ❌ Stack trace: $stackTrace');
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = CustomerController.logeInCustomer;

    // Reduced build logging to prevent main thread blocking
    // Only log during initial load or significant state changes
    if (isLoading && createdEvents.isEmpty && attendedEvents.isEmpty && savedEvents.isEmpty) {
      debugPrint('🏗️ MY_PROFILE_SCREEN: Initial loading state');
    }

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
      onRefresh: () => _loadProfileData(isRefresh: true),
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
        color: Colors.white,
        border: Border(bottom: BorderSide(color: Color(0xFFE5E7EB), width: 1)),
      ),
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
      child: Stack(
        children: [
          Column(
            children: [
              if (widget.showBackButton || isSelectionMode)
                Row(
                  children: [
                    if (widget.showBackButton)
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
                            color: Color(0xFFF3F4F6),
                            borderRadius: BorderRadius.circular(18),
                          ),
                          child: Icon(
                            isSelectionMode ? Icons.close : Icons.arrow_back,
                            color: Colors.black87,
                            size: 18,
                          ),
                        ),
                      )
                    else
                      const SizedBox(width: 36, height: 36),
                    const Spacer(),
                    Text(
                      isSelectionMode
                          ? '${selectedEventIds.length} selected'
                          : '',
                      style: const TextStyle(
                        color: Color(0xFF1F2937),
                        fontWeight: FontWeight.w600,
                        fontSize: 16,
                        fontFamily: 'Roboto',
                      ),
                    ),
                    GestureDetector(
                      onTap: () {
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (context) =>
                                const AccountDetailsScreenV2(),
                          ),
                        );
                      },
                      child: Container(
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(
                          color: Color(0xFFF3F4F6),
                          borderRadius: BorderRadius.circular(18),
                        ),
                        child: const Icon(
                          Icons.edit,
                          color: Colors.black87,
                          size: 18,
                        ),
                      ),
                    ),
                  ],
                ),
              if (widget.showBackButton || isSelectionMode)
                const SizedBox(height: 8),

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
                          border: Border.all(
                            color: Color(0xFFE5E7EB),
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
                              (user?.profilePictureUrl != null &&
                                  (user!.profilePictureUrl!.isNotEmpty))
                              ? SafeNetworkImage(
                                  imageUrl: user.profilePictureUrl!,
                                  fit: BoxFit.cover,
                                  errorWidget: _buildDefaultProfilePicture(),
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
                                color: Colors.black.withValues(alpha: 0.06),
                                blurRadius: 6,
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
                          (user?.name != null &&
                                  user!.name.isNotEmpty &&
                                  !user.name.contains('@') &&
                                  user.name.toLowerCase() != 'user')
                              ? user.name
                              : (user?.email.split('@').first ?? 'User'),
                          style: const TextStyle(
                            color: Color(0xFF1A1A1A),
                            fontSize: 22,
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
                                color: Color(0xFFF3F4F6),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: Color(0xFFE5E7EB),
                                  width: 1,
                                ),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Flexible(
                                    child: Text(
                                      '@${user.username}',
                                      style: const TextStyle(
                                        color: Color(0xFF1F2937),
                                        fontWeight: FontWeight.w500,
                                        fontSize: 16,
                                        fontFamily: 'Roboto',
                                      ),
                                      overflow: TextOverflow.ellipsis,
                                      maxLines: 1,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                        const SizedBox(height: 2),
                        const Text(
                          'Welcome to your profile',
                          style: TextStyle(
                            color: Color(0xFF6B7280),
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

          // Overlay edit button when no back button
          if (!widget.showBackButton && !isSelectionMode)
            Positioned(
              top: 8,
              right: 16,
              child: GestureDetector(
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (context) => const AccountDetailsScreenV2(),
                    ),
                  );
                },
                child: Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: Color(0xFFF3F4F6),
                    borderRadius: BorderRadius.circular(18),
                  ),
                  child: const Icon(
                    Icons.edit,
                    color: Colors.black87,
                    size: 18,
                  ),
                ),
              ),
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
              GestureDetector(
                onTap: () {
                  setState(() {
                    _isBadgeExpanded = !_isBadgeExpanded;
                  });
                },
                behavior: HitTestBehavior.opaque,
                child: Row(
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
                    const SizedBox(width: 8),
                    Icon(
                      _isBadgeExpanded ? Icons.expand_less : Icons.expand_more,
                      color: const Color(0xFF667EEA),
                      size: 18,
                    ),
                  ],
                ),
              ),
            ],
          ),
          AnimatedCrossFade(
            firstChild: Column(
              children: [
                const SizedBox(height: 16),
                Center(
                  child: GestureDetector(
                    onTap: () => _showBadgeWalletModal(context),
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        final availableWidth = constraints.maxWidth;
                        final double badgeWidth = availableWidth.clamp(
                          260.0,
                          360.0,
                        );
                        final double badgeHeight = badgeWidth * (180 / 280);
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
            secondChild: const SizedBox.shrink(),
            crossFadeState: _isBadgeExpanded
                ? CrossFadeState.showFirst
                : CrossFadeState.showSecond,
            duration: const Duration(milliseconds: 200),
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
                activeThumbColor: const Color(0xFF667EEA),
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
              const SizedBox(width: 8),
              // Action buttons in scrollable container
              Expanded(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      _buildActionButton(
                        icon: Icons.refresh,
                        label: 'Refresh',
                        onTap: () async {
                          setState(() {
                            isLoading = true;
                          });
                          await _loadProfileData();
                        },
                        isActive: false,
                      ),
                      const SizedBox(width: 8),
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
                ),
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
        onTap: () => _onTabChanged(index),
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
    final hasMore = _hasMore[selectedTab] ?? false;
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

    // Reduced debug logging to prevent main thread blocking
    // Only log when there are actual issues or state changes

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
      // Category filter applied - only log if significant change
      if (events.length - filteredEvents.length > 5) {
        debugPrint('🔍 Category filter reduced events: ${events.length} → ${filteredEvents.length}');
      }
    }

    // Apply sorting
    final sortedEvents = _sortEvents(filteredEvents);

    return Container(
      margin: const EdgeInsets.fromLTRB(24, 0, 24, 24),
      child: (sortedEvents.isEmpty && !(_isFetchingMore[selectedTab] ?? false))
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
                // Events list - PERFORMANCE: Only show limited items initially
                ListView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: sortedEvents.length + (hasMore ? 1 : 0),
                  itemBuilder: (context, index) {
                    if (index == sortedEvents.length) {
                      // This is the "Load More" item
                      return (_isFetchingMore[selectedTab] ?? false)
                          ? const Center(
                              child: Padding(
                                padding: EdgeInsets.all(16.0),
                                child: CircularProgressIndicator(),
                              ),
                            )
                          : Container(
                              margin: const EdgeInsets.only(top: 16),
                              child: OutlinedButton(
                                onPressed: () => _fetchMoreEvents(selectedTab),
                                child: const Text('Load More'),
                              ),
                            );
                    }
                    // Remove excessive logging for performance
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
    final user = CustomerController.logeInCustomer;
    final userId = user?.uid ?? 'No User ID';
    final userEmail = user?.email ?? 'No Email';

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
          const SizedBox(height: 24),
          // Debug info section
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Color(0xFFF3F4F6),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Color(0xFFE5E7EB)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Debug Info:',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF6B7280),
                    fontFamily: 'Roboto',
                  ),
                ),
                SizedBox(height: 4),
                Text(
                  'User ID: ${userId.substring(0, userId.length > 20 ? 20 : userId.length)}...',
                  style: TextStyle(
                    fontSize: 10,
                    color: Color(0xFF9CA3AF),
                    fontFamily: 'Roboto',
                  ),
                ),
                Text(
                  'Email: $userEmail',
                  style: TextStyle(
                    fontSize: 10,
                    color: Color(0xFF9CA3AF),
                    fontFamily: 'Roboto',
                  ),
                ),
                Text(
                  'Created: ${createdEvents.length}, Attended: ${attendedEvents.length}, Saved: ${savedEvents.length}',
                  style: TextStyle(
                    fontSize: 10,
                    color: Color(0xFF9CA3AF),
                    fontFamily: 'Roboto',
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              ElevatedButton.icon(
                onPressed: () async {
                  debugPrint(
                    '🔄 Manual refresh requested from My Profile empty state',
                  );
                  await _loadProfileData(isRefresh: true);
                },
                icon: Icon(Icons.refresh, size: 18),
                label: Text('Refresh All'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF667EEA),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 12,
                  ),
                ),
              ),
              SizedBox(width: 12),
              OutlinedButton.icon(
                onPressed: () async {
                  await _runComprehensiveDiagnostics();
                  ShowToast().showNormalToast(
                    msg: 'Check console logs for diagnostic results',
                  );
                },
                icon: Icon(Icons.bug_report, size: 18),
                label: Text('Run Full Diagnostics'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xFF667EEA),
                  side: BorderSide(color: Color(0xFF667EEA)),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 12,
                  ),
                ),
              ),
            ],
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

  void _showBadgeWalletModal(BuildContext context) {
    Navigator.of(context).push(
      PageRouteBuilder(
        opaque: false,
        barrierColor: Colors.black.withValues(alpha: 0.9),
        pageBuilder: (context, animation, secondaryAnimation) {
          return Scaffold(
            backgroundColor: Colors.black.withValues(alpha: 0.9),
            body: SafeArea(
              child: Stack(
                children: [
                  // Full screen badge
                  Center(
                    child: Hero(
                      tag: 'badge_photo_view',
                      child: Container(
                        margin: const EdgeInsets.all(32),
                        child: ProfessionalBadgeWidget(
                          badge: _userBadge!,
                          width: MediaQuery.of(context).size.width - 64,
                          height:
                              (MediaQuery.of(context).size.width - 64) *
                              (180 / 280),
                          showActions: false,
                        ),
                      ),
                    ),
                  ),

                  // Close button
                  Positioned(
                    top: 16,
                    right: 16,
                    child: IconButton(
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(
                        Icons.close,
                        color: Colors.white,
                        size: 28,
                      ),
                      style: IconButton.styleFrom(
                        backgroundColor: Colors.black.withValues(alpha: 0.5),
                        shape: const CircleBorder(),
                      ),
                    ),
                  ),

                  // Save to Wallet button at bottom
                  Positioned(
                    left: 24,
                    right: 24,
                    bottom: 32,
                    child: ElevatedButton(
                      onPressed: () => _saveToWallet(context),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF667EEA),
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                        padding: const EdgeInsets.symmetric(vertical: 18),
                        elevation: 8,
                      ),
                      child: const Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.account_balance_wallet_outlined, size: 24),
                          SizedBox(width: 12),
                          Text(
                            'Save to Wallet',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          return FadeTransition(opacity: animation, child: child);
        },
      ),
    );
  }

  Future<void> _saveToWallet(BuildContext context) async {
    try {
      // Show loading indicator
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => const Center(
          child: CircularProgressIndicator(
            valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF667EEA)),
          ),
        ),
      );

      // Determine platform for backend processing
      final platform = Theme.of(context).platform;
      final isApple =
          platform == TargetPlatform.iOS || platform == TargetPlatform.macOS;

      final callable = FirebaseFunctions.instance.httpsCallable(
        'generateUserBadgePass',
      );

      final result = await callable.call({
        'uid': CustomerController.logeInCustomer?.uid ?? '',
        'platform': isApple ? 'apple' : 'google',
      });

      final urlString = result.data['url'] as String;

      // Dismiss loading indicator
      if (context.mounted) {
        Navigator.pop(context);
      }

      if (urlString.startsWith('data:text/plain,')) {
        // Handle error messages
        final message = urlString.substring('data:text/plain,'.length);
        if (!context.mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(Uri.decodeComponent(message)),
            backgroundColor: Colors.red,
          ),
        );
        return;
      }

      final url = Uri.parse(urlString);

      if (await canLaunchUrl(url)) {
        await launchUrl(
          url,
          mode: urlString.startsWith('data:')
              ? LaunchMode.inAppWebView
              : LaunchMode.externalApplication,
        );

        if (!context.mounted) return;
        Navigator.pop(context);

        // Show success message
        const successMessage =
            'Badge generated successfully! You can now add it to your wallet.';

        ShowToast().showNormalToast(msg: successMessage);
      } else {
        if (!context.mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Unable to open wallet pass. Please try again.'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } catch (error) {
      // Dismiss loading indicator if still showing
      if (context.mounted && ModalRoute.of(context)?.isCurrent == false) {
        Navigator.pop(context);
      }

      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Unable to add to wallet: ${error.toString()}'),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 5),
        ),
      );
    }
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
                  'Filters & Sort',
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
          // Footer actions
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 16),
              child: Row(
                children: [
                  TextButton(
                    onPressed: () {
                      _updateCategories([]);
                      _updateSortOption(SortOption.none);
                    },
                    child: const Text(
                      'Reset',
                      style: TextStyle(
                        fontFamily: 'Roboto',
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  const Spacer(),
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF667EEA),
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 12,
                      ),
                      elevation: 0,
                    ),
                    onPressed: () => Navigator.pop(context),
                    child: const Text(
                      'Done',
                      style: TextStyle(
                        fontFamily: 'Roboto',
                        fontWeight: FontWeight.w600,
                      ),
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

  // Build sort section (pill-style like Home screen)
  Widget _buildSortSection() {
    final options = [
      SortOption.none, // Tab-tailored default
      SortOption.dateAddedDesc, // Newest
      SortOption.titleAsc, // A–Z
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.sort, color: const Color(0xFF667EEA), size: 20),
            const SizedBox(width: 8),
            const Text(
              'Sort',
              style: TextStyle(
                color: Color(0xFF1A1A1A),
                fontWeight: FontWeight.w600,
                fontSize: 18,
                fontFamily: 'Roboto',
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: options.map((o) {
            final isSelected = _currentSortOption == o;
            return ChoiceChip(
              selected: isSelected,
              onSelected: (_) => _updateSortOption(o),
              label: Text(
                _getSortOptionText(o),
                style: TextStyle(
                  fontFamily: 'Roboto',
                  fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                ),
              ),
              avatar: Icon(
                _getSortOptionIcon(o),
                size: 18,
                color: isSelected ? Colors.white : const Color(0xFF667EEA),
              ),
              labelPadding: const EdgeInsets.symmetric(horizontal: 8),
              selectedColor: const Color(0xFF667EEA),
              backgroundColor: Colors.grey[50],
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
                side: BorderSide(
                  color: isSelected
                      ? const Color(0xFF667EEA)
                      : const Color(0xFFE1E5E9),
                ),
              ),
            );
          }).toList(),
        ),
      ],
    );
  }

  // (legacy grouped sort widget removed in favor of pill-style chips)

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
        return 'Newest';
      case SortOption.titleAsc:
        return 'A–Z';
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
