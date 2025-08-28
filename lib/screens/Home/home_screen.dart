import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';

// IMPORTANT: Ensure Firestore security rules allow authenticated users to read non-private events:
// match /Events/{eventId} {
//   allow read: if request.auth != null &&
//     (resource.data.customerUid == request.auth.uid || resource.data.private == false);
//   allow write: if request.auth != null && request.auth.uid == resource.data.customerUid;
// }
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:orgami/models/event_model.dart';
import 'package:orgami/models/customer_model.dart';
import 'package:orgami/screens/Events/single_event_screen.dart';
import 'package:orgami/screens/MyProfile/user_profile_screen.dart';
import 'package:orgami/Utils/router.dart';
import 'package:carousel_slider/carousel_slider.dart';
import 'package:shimmer/shimmer.dart';
import 'package:intl/intl.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:orgami/screens/Events/Widget/single_event_list_view_item.dart';
import 'package:orgami/firebase/firebase_firestore_helper.dart';
import 'package:orgami/controller/customer_controller.dart';
import 'package:orgami/Utils/toast.dart';
import 'package:orgami/screens/QRScanner/qr_scanner_flow_screen.dart';

import 'package:orgami/Utils/theme_provider.dart';
import 'package:provider/provider.dart';
import 'package:orgami/Utils/location_helper.dart';
import 'package:orgami/Utils/logger.dart';
import 'package:orgami/screens/Events/chose_sign_in_methods_screen.dart';

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

// Enum for search type
enum SearchType { events, users }

class HomeScreen extends StatefulWidget {
  final bool showHeader;
  const HomeScreen({super.key, this.showHeader = true});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with TickerProviderStateMixin {
  double radiusInMiles = 0;
  List<String> selectedCategories = [];
  bool isLoading = true;
  bool isRefreshing = false;

  // Search functionality
  bool _isSearchExpanded = false;
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();
  String _searchValue = '';
  SearchType _currentSearchType = SearchType.events;
  List<CustomerModel> _searchUsers = [];
  bool _isSearchingUsers = false;
  List<EventModel> _searchEvents = [];
  bool _isSearchingEvents = false;

  // Default content state variables
  List<EventModel> _defaultEvents = [];
  List<CustomerModel> _defaultUsers = [];
  bool _isLoadingDefaultEvents = false;
  bool _isLoadingDefaultUsers = false;
  bool _isFeaturedExpanded = true;

  // Sorting state
  SortOption currentSortOption =
      SortOption.none; // Default to none which will use our custom sorting

  // Scroll controller and animation
  late ScrollController _scrollController;
  bool _isScrollingDown = false;
  static const double _appBarHeight = 56.0;
  double _lastScrollOffset = 0.0;

  // Animation controllers
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;
  late AnimationController _fadeController;
  late Animation<double> _fadeAnimation;
  late AnimationController _searchAnimationController;
  late AnimationController _fabOpacityController;
  late Animation<double> _fabOpacityAnimation;

  // Categories including Featured for HomeScreen
  final List<String> _allCategories = [
    'Featured',
    'Educational',
    'Professional',
    'Other',
  ];

  LatLng? currentLocation;

  // Show filter/sort modal
  void _showFilterSortModal() {
    if (!mounted) return;

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => _FilterSortModal(
        selectedCategories: selectedCategories,
        currentSortOption: currentSortOption,
        allCategories: _allCategories,
        onCategoriesChanged: (categories) {
          if (mounted) {
            setState(() {
              selectedCategories = categories;
            });
          }
        },
        onSortOptionChanged: (sortOption) {
          if (mounted) {
            setState(() {
              currentSortOption = sortOption;
            });
          }
        },
      ),
    );
  }

  // Removed 'All' header per design

  // Sort events based on current sort option
  List<EventModel> _sortEvents(List<EventModel> events) {
    switch (currentSortOption) {
      case SortOption.none:
        // Default sorting: by event date ascending, then by creation date ascending
        events.sort((a, b) {
          // First sort by event date (ascending - most upcoming first)
          int dateComparison = a.selectedDateTime.compareTo(b.selectedDateTime);
          if (dateComparison != 0) {
            return dateComparison;
          }
          // If dates are the same, sort by creation date (ascending - oldest created first)
          return a.eventGenerateTime.compareTo(b.eventGenerateTime);
        });
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

  @override
  void initState() {
    super.initState();
    selectedCategories =
        []; // Start with no category filters to show all events
    getCurrentLocation();

    // Initialize scroll controller
    _scrollController = ScrollController();
    _scrollController.addListener(_onScroll);

    // Initialize animations with reduced durations for better performance
    _pulseController = AnimationController(
      duration: const Duration(milliseconds: 800), // Slightly increased for smoother animation
      vsync: this,
    );
    _pulseAnimation = Tween<double>(begin: 0.95, end: 1.05).animate( // Reduced animation range
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
    // Defer animation start to reduce initial load
    Future.delayed(const Duration(milliseconds: 500), () {
      if (mounted) {
        _pulseController.repeat(reverse: true);
      }
    });

    // Initialize fade animation
    _fadeController = AnimationController(
      duration: const Duration(milliseconds: 400),
      vsync: this,
    );
    _fadeAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(parent: _fadeController, curve: Curves.easeOut));
    _fadeController.forward();

    // Initialize search animation
    _searchAnimationController = AnimationController(
      duration: const Duration(milliseconds: 200),
      vsync: this,
    );

    // Initialize FAB opacity animation
    _fabOpacityController = AnimationController(
      duration: const Duration(milliseconds: 200),
      vsync: this,
      value: 1.0,
    );
    _fabOpacityAnimation = Tween<double>(begin: 0.3, end: 1.0).animate(
      CurvedAnimation(parent: _fabOpacityController, curve: Curves.easeInOut),
    );

    // Defer loading default content to avoid blocking the UI
    // This allows the screen to render immediately while data loads in background
    Future.delayed(const Duration(milliseconds: 100), () {
      if (mounted) {
        _loadDefaultEvents();
        _loadDefaultUsers();
      }
    });

    // Set loading to false immediately since StreamBuilder will handle the loading state
    setState(() {
      isLoading = false;
    });
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _pulseController.dispose();
    _fadeController.dispose();
    _searchAnimationController.dispose();
    _fabOpacityController.dispose();
    _searchController.dispose();
    _searchFocusNode.dispose();
    super.dispose();
  }

  // Search functionality methods
  void _toggleSearch() {
    setState(() {
      _isSearchExpanded = !_isSearchExpanded;
    });

    if (_isSearchExpanded) {
      _searchAnimationController.forward();
      Future.delayed(const Duration(milliseconds: 100), () {
        _searchFocusNode.requestFocus();
      });
    } else {
      _searchAnimationController.reverse();
      _searchController.clear();
      _searchValue = '';
      _searchUsers.clear();
      _searchEvents.clear();
      _searchFocusNode.unfocus();
    }
  }

  Future<void> _performSearch() async {
    if (_searchValue.isEmpty) {
      setState(() {
        _searchUsers.clear();
        _searchEvents.clear();
      });
      return;
    }

    if (_currentSearchType == SearchType.users) {
      setState(() {
        _isSearchingUsers = true;
      });

      try {
        final users = await FirebaseFirestoreHelper().searchUsers(
          searchQuery: _searchValue,
          limit: 100,
        );

        if (mounted) {
          setState(() {
            _searchUsers = users;
            _isSearchingUsers = false;
          });
        }
      } catch (e) {
        if (mounted) {
          setState(() {
            _isSearchingUsers = false;
          });
        }
        if (kDebugMode) {
          debugPrint('Error searching users: $e');
        }
      }
    } else {
      // For events, we'll use client-side filtering since there's no searchEvents method
      setState(() {
        _isSearchingEvents = true;
      });

      try {
        // Get all events and filter client-side
        final eventsQuery = await FirebaseFirestore.instance
            .collection(EventModel.firebaseKey)
            .where('private', isEqualTo: false)
            .get();

        final allEvents = eventsQuery.docs
            .map((doc) {
              final data = doc.data();
              data['id'] = doc.id; // Ensure document ID is included
              return EventModel.fromJson(data);
            })
            .where(
              (event) => event.title.toLowerCase().contains(
                _searchValue.toLowerCase(),
              ),
            )
            .toList();

        if (mounted) {
          setState(() {
            _searchEvents = allEvents;
            _isSearchingEvents = false;
          });
        }
      } catch (e) {
        if (mounted) {
          setState(() {
            _isSearchingEvents = false;
          });
        }
        if (kDebugMode) {
          debugPrint('Error searching events: $e');
        }
      }
    }
  }

  void _onScroll() {
    // Use a threshold to prevent excessive calls during small scroll changes
    const scrollThreshold = 10.0;

    // Only process significant scroll changes
    if ((_scrollController.offset - _lastScrollOffset).abs() <
        scrollThreshold) {
      return;
    }

    _lastScrollOffset = _scrollController.offset;

    if (_scrollController.offset > _appBarHeight && !_isScrollingDown) {
      _isScrollingDown = true;
      _animateFabOpacity(0.3);
    } else if (_scrollController.offset <= _appBarHeight && _isScrollingDown) {
      _isScrollingDown = false;
      _animateFabOpacity(1.0);
    }
  }

  void _animateFabOpacity(double targetOpacity) {
    // Use AnimationController for smooth transitions without rebuilding the whole widget
    if (targetOpacity >= 1.0) {
      _fabOpacityController.forward();
    } else {
      _fabOpacityController.reverse();
    }
  }

  void _onFabPressed() {
    RouterClass.nextScreenNormal(context, const ChoseSignInMethodsScreen());
  }

  Future<void> getCurrentLocation() async {
    try {
      final position = await LocationHelper.getCurrentLocation(
        showErrorDialog: false,
        context:
            null, // Don't show dialogs on home screen to avoid interrupting user experience
      );

      if (position != null && mounted) {
        setState(() {
          currentLocation = LatLng(position.latitude, position.longitude);
        });
        Logger.success(
          'Home screen location updated: ${position.latitude}, ${position.longitude}',
        );
      } else {
        Logger.info(
          'Getting error in current Location Fatching! User denied permissions to access the device\'s location.',
        );
      }
    } catch (e) {
      Logger.error('Error getting location in home screen: $e');
    }
  }

  bool isInRadius(LatLng center, double radiusInFeet, LatLng point) {
    double radiusInMeters = radiusInFeet * 1609.34; // Convert miles to meters
    double earthRadius = 6378137; // Earth's radius in meters

    double dLat = radians(point.latitude - center.latitude);
    double dLng = radians(point.longitude - center.longitude);
    double a =
        sin(dLat / 2) * sin(dLat / 2) +
        cos(radians(center.latitude)) *
            cos(radians(point.latitude)) *
            sin(dLng / 2) *
            sin(dLng / 2);
    double c = 2 * atan2(sqrt(a), sqrt(1 - a));
    double distance = earthRadius * c;

    return distance <= radiusInMeters;
  }

  double radians(double degrees) {
    return degrees * pi / 180;
  }

  double calculateDistance(LatLng start, LatLng end) {
    double earthRadius = 6378137; // Earth's radius in meters

    double dLat = radians(end.latitude - start.latitude);
    double dLng = radians(end.longitude - start.longitude);
    double a =
        sin(dLat / 2) * sin(dLat / 2) +
        cos(radians(start.latitude)) *
            cos(radians(end.latitude)) *
            sin(dLng / 2) *
            sin(dLng / 2);
    double c = 2 * atan2(sqrt(a), sqrt(1 - a));
    double distance = earthRadius * c;

    return distance;
  }

  List<EventModel> filterEvents(List<EventModel> events) {
    List<EventModel> filteredEvents = events;

    // Filter by categories (excluding Featured - Featured filter only controls carousel visibility)
    List<String> nonFeaturedCategories = selectedCategories
        .where((category) => category != 'Featured')
        .toList();

    if (nonFeaturedCategories.isNotEmpty) {
      filteredEvents = filteredEvents.where((event) {
        // Check if any selected category matches the event
        return nonFeaturedCategories.any((category) {
          return event.categories.contains(category);
        });
      }).toList();
    }

    // Filter by distance if location and radius are set
    if (currentLocation != null && radiusInMiles > 0) {
      filteredEvents = filteredEvents
          .where(
            (event) =>
                isInRadius(currentLocation!, radiusInMiles, event.getLatLng()),
          )
          .toList();

      // Sort by distance after filtering
      filteredEvents.sort((a, b) {
        double distanceA = calculateDistance(currentLocation!, a.getLatLng());
        double distanceB = calculateDistance(currentLocation!, b.getLatLng());

        if (distanceA == distanceB) {
          return a.selectedDateTime.compareTo(b.selectedDateTime);
        } else {
          return distanceA.compareTo(distanceB);
        }
      });
    }

    return filteredEvents;
  }

  Future<void> _onRefresh() async {
    setState(() {
      isRefreshing = true;
    });

    await Future.delayed(const Duration(seconds: 1));

    setState(() {
      isRefreshing = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      floatingActionButton: _isSearchExpanded
          ? null
          : AnimatedBuilder(
              animation: _fabOpacityAnimation,
              builder: (context, child) {
                return Opacity(
                  opacity: _fabOpacityAnimation.value,
                  child: Container(
                    width: 56,
                    height: 56,
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [Color(0xFF667EEA), Color(0xFF764BA2)],
                      ),
                      borderRadius: BorderRadius.circular(28),
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFF667EEA).withValues(alpha: 0.3),
                          spreadRadius: 2,
                          blurRadius: 8,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Material(
                      color: Colors.transparent,
                      child: InkWell(
                        borderRadius: BorderRadius.circular(28),
                        onTap: _onFabPressed,
                        child: const Icon(
                          Icons.add,
                          color: Colors.white,
                          size: 28,
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
      body: _isSearchExpanded
          ? _buildFullScreenSearch()
          : SafeArea(child: _bodyView()),
    );
  }

  Widget _bodyView() {
    return RefreshIndicator(
      onRefresh: _onRefresh,
      color: const Color(0xFF667EEA),
      child: FadeTransition(
        opacity: _fadeAnimation,
        child: CustomScrollView(
          controller: _scrollController,
          physics: const BouncingScrollPhysics(
            parent: AlwaysScrollableScrollPhysics(),
          ),
          slivers: [
            if (widget.showHeader)
              // Header Section as Sliver
              SliverToBoxAdapter(child: _headerView()),
            // Filter Section as Sliver
            SliverToBoxAdapter(child: _filterSection()),
            // Events Content as Sliver
            SliverToBoxAdapter(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [_eventsView()],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _headerView() {
    final themeProvider = Provider.of<ThemeProvider>(context);
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: themeProvider.getGradientColors(context),
        ),
      ),
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Discover',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w300,
                        fontSize: 20,
                        fontFamily: 'Roboto',
                      ),
                    ),
                    ShaderMask(
                      shaderCallback: (Rect bounds) {
                        return const LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [Color(0xFFFFFFFF), Color(0xFFDEE9FF)],
                        ).createShader(
                          Rect.fromLTWH(0, 0, bounds.width, bounds.height),
                        );
                      },
                      blendMode: BlendMode.srcIn,
                      child: const Text(
                        'Amazing Events',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 26,
                          fontFamily: 'Roboto',
                          letterSpacing: 0.3,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Row(
                children: [
                  // QR Code Icon (now to the left of search)
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 300),
                    width: _isSearchExpanded ? 0 : 40,
                    child: _isSearchExpanded
                        ? const SizedBox.shrink()
                        : Container(
                            width: 40,
                            height: 40,
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.2),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Material(
                              color: Colors.transparent,
                              child: InkWell(
                                borderRadius: BorderRadius.circular(20),
                                onTap: () {
                                  RouterClass.nextScreenNormal(
                                    context,
                                    const QRScannerFlowScreen(),
                                  );
                                },
                                child: const Icon(
                                  Icons.qr_code_scanner,
                                  color: Colors.white,
                                  size: 20,
                                ),
                              ),
                            ),
                          ),
                  ),
                  const SizedBox(width: 8),
                  // Search Icon (now on far right)
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 300),
                    width: _isSearchExpanded ? 0 : 40,
                    child: _isSearchExpanded
                        ? const SizedBox.shrink()
                        : Container(
                            width: 40,
                            height: 40,
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.2),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Material(
                              color: Colors.transparent,
                              child: InkWell(
                                borderRadius: BorderRadius.circular(20),
                                onTap: _toggleSearch,
                                child: const Icon(
                                  Icons.search,
                                  color: Colors.white,
                                  size: 20,
                                ),
                              ),
                            ),
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

  Widget _filterSection() {
    final themeProvider = Provider.of<ThemeProvider>(context);
    return Container(
      margin: const EdgeInsets.fromLTRB(24, 0, 24, 24),
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: themeProvider.isDarkMode
                ? Colors.black.withValues(alpha: 0.3)
                : Colors.black.withValues(alpha: 0.05),
            spreadRadius: 0,
            blurRadius: 20,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Distance Slider
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Icon(
                    Icons.location_on,
                    color: Theme.of(context).colorScheme.primary,
                    size: 18,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'Distance',
                    style: TextStyle(
                      color:
                          Theme.of(context).textTheme.titleMedium?.color ??
                          const Color(0xFF1A1A1A),
                      fontWeight: FontWeight.w600,
                      fontSize: 16,
                      fontFamily: 'Roboto',
                    ),
                  ),
                  const SizedBox(width: 12),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFF667EEA).withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      radiusInMiles > 0
                          ? '${radiusInMiles.toStringAsFixed(0)} mi'
                          : 'Global',
                      style: const TextStyle(
                        color: Color(0xFF667EEA),
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
                        fontFamily: 'Roboto',
                      ),
                    ),
                  ),
                ],
              ),
              GestureDetector(
                onTap: () {
                  _showFilterSortModal();
                },
                child: Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: const Color(0xFF667EEA).withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(18),
                  ),
                  child: Stack(
                    children: [
                      const Center(
                        child: Icon(
                          Icons.tune,
                          color: Color(0xFF667EEA),
                          size: 20,
                        ),
                      ),
                      if (selectedCategories.isNotEmpty ||
                          currentSortOption != SortOption.none)
                        Positioned(
                          top: 4,
                          right: 4,
                          child: Container(
                            width: 6,
                            height: 6,
                            decoration: const BoxDecoration(
                              color: Color(0xFFFF6B6B),
                              shape: BoxShape.circle,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          SliderTheme(
            data: SliderTheme.of(context).copyWith(
              activeTrackColor: const Color(0xFF667EEA),
              inactiveTrackColor: const Color(0xFFE1E5E9),
              thumbColor: const Color(0xFF667EEA),
              overlayColor: const Color(0xFF667EEA).withValues(alpha: 0.2),
              trackHeight: 4,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 8),
              overlayShape: const RoundSliderOverlayShape(overlayRadius: 16),
            ),
            child: Slider(
              min: 0,
              max: 1000,
              value: radiusInMiles,
              onChanged: (value) {
                setState(() {
                  radiusInMiles = value;
                });
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _eventsView() {
    // If search is active and has a value, show search results
    if (_isSearchExpanded && _searchValue.isNotEmpty) {
      if (_currentSearchType == SearchType.users) {
        return _buildUsersSearchResults();
      } else {
        return _buildEventsSearchResults();
      }
    }

    // If search is expanded but no value, show empty search state
    if (_isSearchExpanded && _searchValue.isEmpty) {
      return _buildSearchEmptyState();
    }

    return _buildFirestoreStreamContent();
  }

  Widget _buildFirestoreStreamContent() {
    // Create a stream for the Firestore query
    // Start with the simplest possible query
    Stream<QuerySnapshot> eventsStream;

    try {
      // Filter events to show only those that haven't ended more than 3 hours ago
      final threeHoursAgo = DateTime.now().subtract(const Duration(hours: 3));

      eventsStream = FirebaseFirestore.instance
          .collection(EventModel.firebaseKey)
          .where('private', isEqualTo: false) // Filter out private events
          .where(
            'selectedDateTime',
            isGreaterThan: Timestamp.fromDate(threeHoursAgo),
          ) // Show recent events
          .snapshots();
    } catch (e) {
      // Fallback: return simple error widget if stream creation fails
      if (kDebugMode) {
        debugPrint('Failed to create Firestore stream: $e');
      }
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error, size: 48, color: Colors.red),
            const SizedBox(height: 16),
            Text('Failed to connect to database: $e'),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: () => setState(() {}),
              child: const Text('Retry'),
            ),
          ],
        ),
      );
    }

    return StreamBuilder<QuerySnapshot>(
      stream: eventsStream,
      builder: (context, snapshot) {
        // Show loading state
        if (snapshot.connectionState == ConnectionState.waiting) {
          return _buildSkeletonLoading();
        }

        // Show error state
        if (snapshot.hasError) {
          return _buildDetailedErrorState(snapshot.error.toString());
        }

        // Show empty state
        if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
          return _buildEmptyState();
        }

        // Process events data with error handling and performance optimization
        List<EventModel> eventsList = [];
        try {
          // Limit processing to prevent overwhelming the main thread
          final limitedDocs = snapshot.data!.docs.take(50).toList();

          for (var doc in limitedDocs) {
            try {
              final data = doc.data() as Map<String, dynamic>?;
              if (data != null) {
                // Ensure the document ID is included in the data
                data['id'] = doc.id;
                eventsList.add(EventModel.fromJson(data));
              }
            } catch (e) {
              Logger.error('Error parsing event document: $e');
              continue; // Skip this document and continue processing
            }
          }
        } catch (e) {
          Logger.error('Error processing events data: $e');
          return _buildDetailedErrorState('Error processing events: $e');
        }

        List<EventModel> neededEventList = [];
        final now = DateTime.now();
        final cutoffTime = now.subtract(const Duration(hours: 2));

        try {
          for (var element in eventsList) {
            // Filter out events that ended more than 2 hours ago with error handling
            try {
              final eventEndTime = element.selectedDateTime.add(
                Duration(hours: element.eventDuration),
              );
              if (eventEndTime.isAfter(cutoffTime)) {
                neededEventList.add(element);
              }
            } catch (e) {
              Logger.error('Error processing event time: $e');
              continue; // Skip this event
            }
          }
        } catch (e) {
          Logger.error('Error filtering events: $e');
          return _buildDetailedErrorState('Error processing events: $e');
        }

        List<EventModel> filtered = [];
        try {
          filtered = filterEvents(neededEventList);
          // Apply sorting with error handling
          filtered = _sortEvents(filtered);
        } catch (e) {
          Logger.error('Error filtering/sorting events: $e');
          return _buildDetailedErrorState('Error processing events: $e');
        }

        // Separate featured and non-featured events for carousel display
        List<EventModel> featuredEvents =
            filtered
                .where(
                  (e) =>
                      e.isFeatured == true &&
                      (e.featureEndDate == null ||
                          e.featureEndDate!.isAfter(DateTime.now())),
                )
                .toList()
              ..sort(
                (a, b) => (b.featureEndDate ?? DateTime(1970)).compareTo(
                  a.featureEndDate ?? DateTime(1970),
                ),
              );

        // Create a combined list that maintains chronological order
        // Featured events will still be visually distinguished in the UI
        List<EventModel> allEventsInChronologicalOrder = [...filtered];

        // Show empty state if no events after filtering
        if (allEventsInChronologicalOrder.isEmpty) {
          return _buildEmptyStateWithFilters();
        }

        return Column(
          children: [
            // Featured Events Carousel - show if there are featured events (regardless of filter)
            if (featuredEvents.isNotEmpty)
              _buildFeaturedCarousel(featuredEvents),
            // Section separator indicating the list below is not featured
            // All Events List - show events in chronological order
            _buildEventsColumn(allEventsInChronologicalOrder),
          ],
        );
      },
    );
  }

  Widget _buildFeaturedCarousel(List<EventModel> featuredEvents) {
    return Container(
      decoration: _isFeaturedExpanded
          ? null
          : BoxDecoration(
              color: const Color(0xFFF3F4F6),
              borderRadius: BorderRadius.circular(16),
            ),
      padding: _isFeaturedExpanded
          ? EdgeInsets.zero
          : const EdgeInsets.symmetric(vertical: 8),
      margin: _isFeaturedExpanded
          ? EdgeInsets.zero
          : const EdgeInsets.fromLTRB(16, 0, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Row(
              children: [
                AnimatedBuilder(
                  animation: _pulseAnimation,
                  builder: (context, child) {
                    return Transform.scale(
                      scale: _pulseAnimation.value,
                      child: const Icon(
                        Icons.star,
                        color: Color(0xFFFF9800),
                        size: 24,
                      ),
                    );
                  },
                ),
                const SizedBox(width: 12),
                const Text(
                  'Featured Events',
                  style: TextStyle(
                    color: Color(0xFF1A1A1A),
                    fontWeight: FontWeight.bold,
                    fontSize: 22,
                    fontFamily: 'Roboto',
                  ),
                ),
                const Spacer(),
                GestureDetector(
                  onTap: () {
                    setState(() {
                      _isFeaturedExpanded = !_isFeaturedExpanded;
                    });
                  },
                  child: Container(
                    width: 36,
                    height: 36,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: const Color(0xFFE5E7EB)),
                      color: Colors.white,
                    ),
                    child: Icon(
                      _isFeaturedExpanded
                          ? Icons.expand_more
                          : Icons.expand_less,
                      color: const Color(0xFF1A1A1A),
                      size: 20,
                    ),
                  ),
                ),
              ],
            ),
          ),
          AnimatedSize(
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeInOut,
            child: _isFeaturedExpanded
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SizedBox(height: 16),
                      CarouselSlider.builder(
                        itemCount: featuredEvents.length,
                        itemBuilder: (context, index, realIndex) {
                          return _buildFeaturedCard(featuredEvents[index]);
                        },
                        options: CarouselOptions(
                          height: 240,
                          viewportFraction: 0.85,
                          enableInfiniteScroll: false,
                          autoPlay: featuredEvents.length > 1,
                          autoPlayInterval: const Duration(seconds: 4),
                        ),
                      ),
                      const SizedBox(height: 24),
                    ],
                  )
                : const SizedBox.shrink(),
          ),
        ],
      ),
    );
  }

  Widget _buildFeaturedCard(EventModel event) {
    return _FeaturedEventCard(event: event);
  }

  Widget _buildSkeletonLoading() {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Featured skeleton
          Shimmer.fromColors(
            baseColor: const Color(0xFFE1E5E9),
            highlightColor: Colors.white,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  height: 24,
                  width: 150,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                const SizedBox(height: 16),
                Container(
                  height: 200,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(20),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          // Events skeleton
          ...List.generate(
            3,
            (index) => Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: Shimmer.fromColors(
                baseColor: const Color(0xFFE1E5E9),
                highlightColor: Colors.white,
                child: Container(
                  height: 280,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(20),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(40),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                color: const Color(0xFF667EEA).withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(40),
              ),
              child: Icon(
                Icons.event_busy,
                size: 40,
                color: const Color(0xFF667EEA),
              ),
            ),
            const SizedBox(height: 24),
            const Text(
              'No Events Yet',
              style: TextStyle(
                color: Color(0xFF1A1A1A),
                fontSize: 20,
                fontWeight: FontWeight.bold,
                fontFamily: 'Roboto',
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            const Text(
              'Events will appear here once they are created.\nCheck back soon!',
              style: TextStyle(
                color: Color(0xFF6B7280),
                fontSize: 16,
                fontFamily: 'Roboto',
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyStateWithFilters() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(40),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                color: const Color(0xFF667EEA).withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(40),
              ),
              child: Icon(
                Icons.filter_alt_off,
                size: 40,
                color: const Color(0xFF667EEA),
              ),
            ),
            const SizedBox(height: 24),
            const Text(
              'No events match your filters',
              style: TextStyle(
                color: Color(0xFF1A1A1A),
                fontSize: 20,
                fontWeight: FontWeight.bold,
                fontFamily: 'Roboto',
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              'Try adjusting your filters or distance settings',
              style: TextStyle(
                color: const Color(0xFF6B7280),
                fontSize: 16,
                fontFamily: 'Roboto',
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: () {
                setState(() {
                  selectedCategories = ['Featured'];
                  radiusInMiles = 0;
                  currentSortOption = SortOption.none;
                });
              },
              icon: const Icon(Icons.clear_all),
              label: const Text('Clear Filters'),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF667EEA),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 12,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEventsColumn(List<EventModel> events) {
    if (events.isEmpty) {
      return _buildEmptyState();
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
      child: Column(
        children: events.map((event) {
          return Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: _buildEventCard(event),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildEventCard(EventModel event) {
    return SingleEventListViewItem(eventModel: event);
  }

  // Search results methods
  Widget _buildEventsSearchResults() {
    if (_isSearchingEvents) {
      return _buildSearchLoadingState();
    }

    if (_searchEvents.isEmpty) {
      return _buildSearchEmptyState();
    }

    return ListView.separated(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
      physics: const BouncingScrollPhysics(
        parent: AlwaysScrollableScrollPhysics(),
      ),
      itemCount: _searchEvents.length,
      separatorBuilder: (_, index) => const SizedBox(height: 8),
      itemBuilder: (context, index) {
        final event = _searchEvents[index];
        return _buildEventCard(event);
      },
    );
  }

  Widget _buildUsersSearchResults() {
    if (_isSearchingUsers) {
      return _buildSearchLoadingState();
    }

    if (_searchUsers.isEmpty) {
      return _buildSearchEmptyState();
    }

    return ListView.separated(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
      physics: const BouncingScrollPhysics(
        parent: AlwaysScrollableScrollPhysics(),
      ),
      itemCount: _searchUsers.length,
      separatorBuilder: (_, index) => const SizedBox(height: 8),
      itemBuilder: (context, index) {
        final user = _searchUsers[index];
        return _buildUserCard(user);
      },
    );
  }

  Widget _buildUserCard(CustomerModel user) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            spreadRadius: 0,
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          // User Avatar
          Container(
            width: 50,
            height: 50,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: const Color(0xFF667EEA).withValues(alpha: 0.1),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(25),
              child:
                  user.profilePictureUrl != null &&
                      user.profilePictureUrl!.isNotEmpty
                  ? CachedNetworkImage(
                      imageUrl: user.profilePictureUrl!,
                      fit: BoxFit.cover,
                      placeholder: (context, url) => const Center(
                        child: CircularProgressIndicator(
                          color: Color(0xFF667EEA),
                          strokeWidth: 2,
                        ),
                      ),
                      errorWidget: (context, url, error) => const Icon(
                        Icons.person,
                        color: Color(0xFF667EEA),
                        size: 24,
                      ),
                    )
                  : const Icon(
                      Icons.person,
                      color: Color(0xFF667EEA),
                      size: 24,
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
                  user.name,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                    fontFamily: 'Roboto',
                  ),
                ),
                if (user.username != null && user.username!.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    '@${user.username}',
                    style: TextStyle(
                      color: Colors.grey[600],
                      fontSize: 14,
                      fontFamily: 'Roboto',
                    ),
                  ),
                ],
              ],
            ),
          ),
          // View Profile Button
          GestureDetector(
            onTap: () {
              final isOwn = CustomerController.logeInCustomer?.uid == user.uid;
              RouterClass.nextScreenNormal(
                context,
                UserProfileScreen(user: user, isOwnProfile: isOwn),
              );
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: const Color(0xFF667EEA),
                borderRadius: BorderRadius.circular(20),
              ),
              child: const Text(
                'View Profile',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                  fontSize: 12,
                  fontFamily: 'Roboto',
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSearchLoadingState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(40),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const CircularProgressIndicator(color: Color(0xFF667EEA)),
            const SizedBox(height: 16),
            Text(
              'Searching ${_currentSearchType == SearchType.events ? 'events' : 'users'}...',
              style: TextStyle(
                color: Colors.grey[600],
                fontSize: 16,
                fontFamily: 'Roboto',
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSearchEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(40),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              _currentSearchType == SearchType.events
                  ? Icons.event_busy
                  : Icons.people_outline,
              size: 64,
              color: Colors.grey[400],
            ),
            const SizedBox(height: 16),
            Text(
              'No ${_currentSearchType == SearchType.events ? 'events' : 'users'} found',
              style: TextStyle(
                color: Colors.grey[600],
                fontSize: 18,
                fontWeight: FontWeight.w600,
                fontFamily: 'Roboto',
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Try adjusting your search terms',
              style: TextStyle(
                color: Colors.grey[500],
                fontSize: 14,
                fontFamily: 'Roboto',
              ),
            ),
          ],
        ),
      ),
    );
  }

  // Load default events (all events, past and present)
  Future<void> _loadDefaultEvents() async {
    if (!mounted) return;
    
    setState(() {
      _isLoadingDefaultEvents = true;
    });

    try {
      // Get all non-private events from Firestore without complex ordering
      // Use smaller limit initially for faster load
      final querySnapshot = await FirebaseFirestore.instance
          .collection(EventModel.firebaseKey)
          .where('private', isEqualTo: false)
          .limit(20) // Reduced from 50 to improve initial load
          .get();

      if (mounted) {
        List<EventModel> events = querySnapshot.docs.map((doc) {
          final data = doc.data();
          data['id'] = doc.id; // Ensure document ID is included
          return EventModel.fromJson(data);
        }).toList();

        // Include all events (past and present) for search screen
        // Sort by event date (most recent first) on the client side
        events.sort((a, b) => b.selectedDateTime.compareTo(a.selectedDateTime));

        setState(() {
          _defaultEvents = events;
          _isLoadingDefaultEvents = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoadingDefaultEvents = false;
        });
      }
      if (kDebugMode) {
        debugPrint('Error loading default events: $e');
      }
    }
  }

  // Load default users (ascending by name)
  Future<void> _loadDefaultUsers() async {
    if (!mounted) return;
    
    setState(() {
      _isLoadingDefaultUsers = true;
    });

    try {
      final users = await FirebaseFirestoreHelper().searchUsers(
        searchQuery: '', // Empty query to get all users
        limit: 20, // Reduced from 50 to improve initial load
      );

      if (mounted) {
        setState(() {
          _defaultUsers = users;
          _isLoadingDefaultUsers = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoadingDefaultUsers = false;
        });
      }
      if (kDebugMode) {
        debugPrint('Error loading default users: $e');
      }
    }
  }

  // Build default content based on current search type
  Widget _buildDefaultContent() {
    if (_currentSearchType == SearchType.events) {
      return _buildDefaultEventsContent();
    } else {
      return _buildDefaultUsersContent();
    }
  }

  // Build default events content
  Widget _buildDefaultEventsContent() {
    if (_isLoadingDefaultEvents) {
      return const Center(
        child: CircularProgressIndicator(color: Color(0xFF667EEA)),
      );
    }

    if (_defaultEvents.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(40),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.event_busy, size: 64, color: Colors.grey[400]),
              const SizedBox(height: 16),
              Text(
                'No events found',
                style: TextStyle(
                  color: Colors.grey[600],
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  fontFamily: 'Roboto',
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Try searching for specific events or check back later',
                style: TextStyle(
                  color: Colors.grey[500],
                  fontSize: 14,
                  fontFamily: 'Roboto',
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
      physics: const BouncingScrollPhysics(
        parent: AlwaysScrollableScrollPhysics(),
      ),
      itemCount: _defaultEvents.length,
      separatorBuilder: (_, index) => const SizedBox(height: 8),
      itemBuilder: (context, index) {
        final event = _defaultEvents[index];
        return _buildEventCard(event);
      },
    );
  }

  // Build default users content
  Widget _buildDefaultUsersContent() {
    if (_isLoadingDefaultUsers) {
      return const Center(
        child: CircularProgressIndicator(color: Color(0xFF667EEA)),
      );
    }

    if (_defaultUsers.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(40),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.people_outline, size: 64, color: Colors.grey[400]),
              const SizedBox(height: 16),
              Text(
                'No users available',
                style: TextStyle(
                  color: Colors.grey[600],
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  fontFamily: 'Roboto',
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Check back later for new users',
                style: TextStyle(
                  color: Colors.grey[500],
                  fontSize: 14,
                  fontFamily: 'Roboto',
                ),
              ),
            ],
          ),
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
      physics: const BouncingScrollPhysics(
        parent: AlwaysScrollableScrollPhysics(),
      ),
      itemCount: _defaultUsers.length,
      separatorBuilder: (_, index) => const SizedBox(height: 8),
      itemBuilder: (context, index) {
        final user = _defaultUsers[index];
        return GestureDetector(
          onTap: () {
            final isOwn = CustomerController.logeInCustomer?.uid == user.uid;
            RouterClass.nextScreenNormal(
              context,
              UserProfileScreen(user: user, isOwnProfile: isOwn),
            );
          },
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              boxShadow: [
                BoxShadow(
                  color: Colors.grey.withValues(alpha: 0.1),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Row(
              children: [
                Container(
                  width: 50,
                  height: 50,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(25),
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(25),
                    child:
                        user.profilePictureUrl != null &&
                            user.profilePictureUrl!.isNotEmpty
                        ? CachedNetworkImage(
                            imageUrl: user.profilePictureUrl!,
                            fit: BoxFit.cover,
                            placeholder: (context, url) => const Center(
                              child: CircularProgressIndicator(
                                color: Color(0xFF667EEA),
                                strokeWidth: 2,
                              ),
                            ),
                            errorWidget: (context, url, error) => const Icon(
                              Icons.person,
                              color: Color(0xFF667EEA),
                              size: 24,
                            ),
                          )
                        : const Icon(
                            Icons.person,
                            color: Color(0xFF667EEA),
                            size: 24,
                          ),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        user.name,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          fontFamily: 'Roboto',
                        ),
                      ),
                      if (user.username != null &&
                          user.username!.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text(
                          '@${user.username}',
                          style: TextStyle(
                            fontSize: 14,
                            color: Colors.grey[600],
                            fontFamily: 'Roboto',
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                      if (user.bio != null && user.bio!.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text(
                          user.bio!,
                          style: TextStyle(
                            fontSize: 14,
                            color: Colors.grey[600],
                            fontFamily: 'Roboto',
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ],
                  ),
                ),
                const Icon(
                  Icons.arrow_forward_ios,
                  color: Colors.grey,
                  size: 16,
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  // Full Screen Search
  Widget _buildFullScreenSearch() {
    return Container(
      color: Theme.of(context).scaffoldBackgroundColor,
      child: SafeArea(
        child: Column(
          children: [
            // Search Header
            Container(
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
                  // Header with close button
                  Row(
                    children: [
                      GestureDetector(
                        onTap: _toggleSearch,
                        child: Container(
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.2),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: const Icon(
                            Icons.arrow_back,
                            color: Colors.white,
                            size: 24,
                          ),
                        ),
                      ),
                      const SizedBox(width: 16),
                      const Expanded(
                        child: Text(
                          'Search',
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 24,
                            fontFamily: 'Roboto',
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  // Search Type Toggle
                  Container(
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.2),
                        width: 1,
                      ),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: GestureDetector(
                            onTap: () {
                              setState(() {
                                _currentSearchType = SearchType.events;
                                _searchUsers.clear();
                                _searchEvents.clear();
                                _searchValue = '';
                                _searchController.clear();
                              });
                            },
                            child: Container(
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              decoration: BoxDecoration(
                                color: _currentSearchType == SearchType.events
                                    ? Colors.white.withValues(alpha: 0.3)
                                    : Colors.transparent,
                                borderRadius: const BorderRadius.only(
                                  topLeft: Radius.circular(12),
                                  bottomLeft: Radius.circular(12),
                                ),
                              ),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(
                                    Icons.event,
                                    color: Colors.white,
                                    size: 18,
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    'Events',
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontWeight:
                                          _currentSearchType ==
                                              SearchType.events
                                          ? FontWeight.bold
                                          : FontWeight.normal,
                                      fontSize: 14,
                                      fontFamily: 'Roboto',
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                        Expanded(
                          child: GestureDetector(
                            onTap: () async {
                              setState(() {
                                _currentSearchType = SearchType.users;
                                _searchUsers.clear();
                                _searchEvents.clear();
                                _searchValue = '';
                                _searchController.clear();
                              });
                              _performSearch();
                            },
                            child: Container(
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              decoration: BoxDecoration(
                                color: _currentSearchType == SearchType.users
                                    ? Colors.white.withValues(alpha: 0.3)
                                    : Colors.transparent,
                                borderRadius: const BorderRadius.only(
                                  topRight: Radius.circular(12),
                                  bottomRight: Radius.circular(12),
                                ),
                              ),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(
                                    Icons.people,
                                    color: Colors.white,
                                    size: 18,
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    'Users',
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontWeight:
                                          _currentSearchType == SearchType.users
                                          ? FontWeight.bold
                                          : FontWeight.normal,
                                      fontSize: 14,
                                      fontFamily: 'Roboto',
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  // Search Input
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 12,
                    ),
                    decoration: BoxDecoration(
                      // Solid white field for maximum contrast with black text
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: const Color(0xFFE2E8F0),
                        width: 1.2,
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.search, color: Colors.black54, size: 20),
                        const SizedBox(width: 12),
                        Expanded(
                          child: TextField(
                            controller: _searchController,
                            focusNode: _searchFocusNode,
                            cursorColor: Colors.black,
                            style: const TextStyle(
                              color: Colors.black,
                              fontSize: 16,
                              fontFamily: 'Roboto',
                            ),
                            decoration: InputDecoration(
                              hintText: _currentSearchType == SearchType.events
                                  ? 'Search events by title...'
                                  : 'Search users by name...',
                              hintStyle: TextStyle(
                                color: Colors.black45,
                                fontSize: 16,
                                fontFamily: 'Roboto',
                              ),
                              border: InputBorder.none,
                              contentPadding: EdgeInsets.zero,
                            ),
                            onChanged: (newVal) {
                              setState(() {
                                _searchValue = newVal;
                              });
                              _performSearch();
                            },
                          ),
                        ),
                        if (_searchValue.isNotEmpty)
                          GestureDetector(
                            onTap: () {
                              _searchController.clear();
                              setState(() {
                                _searchValue = '';
                              });
                              _performSearch();
                            },
                            child: Icon(
                              Icons.clear,
                              color: Colors.black54,
                              size: 20,
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            // Search Results
            Expanded(
              child: _searchValue.isEmpty
                  ? _buildDefaultContent()
                  : _currentSearchType == SearchType.users
                  ? _buildUsersSearchResults()
                  : _buildEventsSearchResults(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDetailedErrorState(String error) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.error_outline, size: 64, color: Colors.red),
            const SizedBox(height: 16),
            const Text(
              'Firestore Connection Error',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.red.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.red.withValues(alpha: 0.3)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Error Details:',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    error.length > 200
                        ? '${error.substring(0, 200)}...'
                        : error,
                    style: const TextStyle(
                      fontSize: 12,
                      fontFamily: 'monospace',
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: () {
                if (mounted) setState(() {});
              },
              child: const Text('Retry Connection'),
            ),
          ],
        ),
      ),
    );
  }
}

class _FeaturedEventCard extends StatefulWidget {
  final EventModel event;

  const _FeaturedEventCard({required this.event});

  @override
  State<_FeaturedEventCard> createState() => _FeaturedEventCardState();
}

class _FeaturedEventCardState extends State<_FeaturedEventCard>
    with SingleTickerProviderStateMixin {
  bool _isFavorited = false;
  bool _isLoadingFavorite = false;
  late AnimationController _favoriteController;
  late Animation<double> _favoriteScaleAnimation;

  @override
  void initState() {
    super.initState();
    _favoriteController = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );
    _favoriteScaleAnimation = Tween<double>(begin: 1.0, end: 1.2).animate(
      CurvedAnimation(parent: _favoriteController, curve: Curves.elasticOut),
    );

    _checkFavoriteStatus();
  }

  @override
  void dispose() {
    _favoriteController.dispose();
    super.dispose();
  }

  Future<void> _checkFavoriteStatus() async {
    if (CustomerController.logeInCustomer == null) return;

    try {
      final isFavorited = await FirebaseFirestoreHelper().isEventFavorited(
        userId: CustomerController.logeInCustomer!.uid,
        eventId: widget.event.id,
      );

      if (mounted) {
        setState(() {
          _isFavorited = isFavorited;
        });
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('Error checking favorite status: $e');
      }
    }
  }

  Future<void> _toggleFavorite() async {
    if (CustomerController.logeInCustomer == null) {
      ShowToast().showNormalToast(msg: 'Please log in to save events');
      return;
    }

    setState(() {
      _isLoadingFavorite = true;
    });

    try {
      bool success;
      if (_isFavorited) {
        success = await FirebaseFirestoreHelper().removeFromFavorites(
          userId: CustomerController.logeInCustomer!.uid,
          eventId: widget.event.id,
        );
      } else {
        success = await FirebaseFirestoreHelper().addToFavorites(
          userId: CustomerController.logeInCustomer!.uid,
          eventId: widget.event.id,
        );
      }

      if (mounted) {
        setState(() {
          _isFavorited = !_isFavorited;
          _isLoadingFavorite = false;
        });

        // Trigger animation
        _favoriteController.forward().then((_) {
          _favoriteController.reverse();
        });

        if (success) {
          ShowToast().showNormalToast(
            msg: _isFavorited ? 'Event saved!' : 'Event removed from saved!',
          );
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoadingFavorite = false;
        });
      }
      ShowToast().showNormalToast(msg: 'Failed to update saved events');
      if (kDebugMode) {
        debugPrint('Error toggling favorite: $e');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: () {
          RouterClass.nextScreenNormal(
            context,
            SingleEventScreen(eventModel: widget.event),
          );
        },
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFFFF9800).withValues(alpha: 0.3),
                spreadRadius: 0,
                blurRadius: 20,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(20),
            child: Stack(
              children: [
                // Background Image
                SizedBox(
                  width: double.infinity,
                  height: 240,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(20),
                    child: CachedNetworkImage(
                      imageUrl: widget.event.imageUrl,
                      fit: BoxFit.cover,
                      width: double.infinity,
                      height: 240,
                      placeholder: (context, url) => Container(
                        color: const Color(0xFFF5F7FA),
                        child: const Center(
                          child: CircularProgressIndicator(
                            color: Color(0xFF667EEA),
                          ),
                        ),
                      ),
                      errorWidget: (context, url, error) => Container(
                        color: const Color(0xFFF5F7FA),
                        child: const Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.image_not_supported,
                                color: Color(0xFF667EEA),
                                size: 48,
                              ),
                              SizedBox(height: 8),
                              Text(
                                'Image not available',
                                style: TextStyle(
                                  color: Color(0xFF667EEA),
                                  fontSize: 14,
                                  fontFamily: 'Roboto',
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                // Gradient Overlay
                Container(
                  width: double.infinity,
                  height: 240,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.black.withValues(alpha: 0.1),
                        Colors.transparent,
                        Colors.black.withValues(alpha: 0.8),
                      ],
                    ),
                  ),
                ),
                // Favorite button
                Positioned(
                  top: 16,
                  right: 16,
                  child: AnimatedBuilder(
                    animation: _favoriteController,
                    builder: (context, child) {
                      return Transform.scale(
                        scale: _favoriteScaleAnimation.value,
                        child: Container(
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.3),
                            shape: BoxShape.circle,
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.2),
                                blurRadius: 8,
                                offset: const Offset(0, 2),
                              ),
                            ],
                          ),
                          child: Material(
                            color: Colors.transparent,
                            child: InkWell(
                              borderRadius: BorderRadius.circular(20),
                              onTap: _isLoadingFavorite
                                  ? null
                                  : () {
                                      _toggleFavorite();
                                    },
                              child: Container(
                                width: 40,
                                height: 40,
                                decoration: BoxDecoration(
                                  color: _isFavorited
                                      ? const Color(0xFFE53E3E)
                                      : Colors.white.withValues(alpha: 0.9),
                                  shape: BoxShape.circle,
                                ),
                                child: _isLoadingFavorite
                                    ? const Center(
                                        child: SizedBox(
                                          width: 20,
                                          height: 20,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                            color: Colors.white,
                                          ),
                                        ),
                                      )
                                    : Icon(
                                        _isFavorited
                                            ? Icons.bookmark
                                            : Icons.bookmark_border,
                                        color: _isFavorited
                                            ? Colors.white
                                            : const Color(0xFF667EEA),
                                        size: 20,
                                      ),
                              ),
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
                // Content
                Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      // Top section with badge
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 6,
                            ),
                            decoration: BoxDecoration(
                              color: const Color(0xFFFF9800),
                              borderRadius: BorderRadius.circular(16),
                            ),
                            child: const Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.star, color: Colors.white, size: 14),
                                SizedBox(width: 4),
                                Text(
                                  'Featured',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 12,
                                    fontFamily: 'Roboto',
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      // Bottom section with title, date, and button
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            widget.event.title,
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 24,
                              fontFamily: 'Roboto',
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 8),
                          Text(
                            widget.event.groupName,
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.9),
                              fontSize: 16,
                              fontFamily: 'Roboto',
                            ),
                          ),
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              Expanded(
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 12,
                                    vertical: 8,
                                  ),
                                  decoration: BoxDecoration(
                                    color: Colors.white.withValues(alpha: 0.2),
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(
                                      color: Colors.white.withValues(
                                        alpha: 0.3,
                                      ),
                                      width: 1,
                                    ),
                                  ),
                                  child: Text(
                                    '${DateFormat('MMM dd, h:mm a').format(widget.event.selectedDateTime)} – ${DateFormat('h:mm a').format(widget.event.eventEndTime)}',
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.w600,
                                      fontSize: 14,
                                      fontFamily: 'Roboto',
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    softWrap: false,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 16,
                                  vertical: 8,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: const Text(
                                  'View Details',
                                  style: TextStyle(
                                    color: Color(0xFF1A1A1A),
                                    fontWeight: FontWeight.w600,
                                    fontSize: 14,
                                    fontFamily: 'Roboto',
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
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

  const _FilterSortModal({
    required this.selectedCategories,
    required this.currentSortOption,
    required this.allCategories,
    required this.onCategoriesChanged,
    required this.onSortOptionChanged,
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

  // Build sort section
  Widget _buildSortSection() {
    final options = [
      SortOption.none, // Upcoming
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

  IconData _getCategoryIcon(String category) {
    switch (category) {
      case 'Featured':
        return Icons.star;
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
        return 'Upcoming';
      case SortOption.dateAddedAsc:
        return 'Date Added (Oldest First)';
      case SortOption.dateAddedDesc:
        return 'Newest';
      case SortOption.titleAsc:
        return 'A–Z';
      case SortOption.titleDesc:
        return 'Title (Z-A)';
      case SortOption.eventDateAsc:
        return 'Upcoming';
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
