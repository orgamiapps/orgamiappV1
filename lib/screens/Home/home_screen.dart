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
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:orgami/models/event_model.dart';
import 'package:orgami/models/customer_model.dart';
import 'package:orgami/Screens/Events/chose_date_time_screen.dart';
import 'package:orgami/Screens/Events/single_event_screen.dart';
import 'package:orgami/Screens/MyProfile/user_profile_screen.dart';
import 'package:orgami/Utils/images.dart';
import 'package:orgami/Utils/router.dart';
import 'package:carousel_slider/carousel_slider.dart';
import 'package:shimmer/shimmer.dart';
import 'package:intl/intl.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:orgami/Screens/Events/Widget/single_event_list_view_item.dart';
import 'package:orgami/firebase/firebase_firestore_helper.dart';
import 'package:orgami/controller/customer_controller.dart';
import 'package:orgami/Utils/toast.dart';
import 'package:orgami/Screens/QRScanner/qr_scanner_flow_screen.dart';
import 'package:orgami/Screens/Messaging/messaging_screen.dart';
import 'package:orgami/Screens/Home/notifications_screen.dart';
import 'package:orgami/Screens/Home/account_screen.dart';
import 'package:orgami/Utils/theme_provider.dart';
import 'package:provider/provider.dart';

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
  const HomeScreen({super.key});

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

  // Sorting state
  SortOption currentSortOption =
      SortOption.none; // Default to none which will use our custom sorting

  // Scroll controller and animation
  late ScrollController _scrollController;
  double _fabOpacity = 1.0;
  bool _isScrollingDown = false;
  static const double _appBarHeight = 56.0;

  // Animation controllers
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;
  late AnimationController _fadeController;
  late Animation<double> _fadeAnimation;
  late AnimationController _searchAnimationController;

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

    // Initialize pulse animation
    _pulseController = AnimationController(
      duration: const Duration(seconds: 2),
      vsync: this,
    );
    _pulseAnimation = Tween<double>(begin: 0.8, end: 1.2).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
    _pulseController.repeat(reverse: true);

    // Initialize fade animation
    _fadeController = AnimationController(
      duration: const Duration(milliseconds: 800),
      vsync: this,
    );
    _fadeAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(parent: _fadeController, curve: Curves.easeOut));
    _fadeController.forward();

    // Initialize search animation
    _searchAnimationController = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );

    // Load default content
    _loadDefaultEvents();
    _loadDefaultUsers();

    // Remove the artificial loading delay - let StreamBuilder handle loading state
    // Future.delayed(const Duration(seconds: 2), () {
    //   if (mounted) {
    //     setState(() {
    //       isLoading = false;
    //     });
    //   }
    // });

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
            .map((e) => EventModel.fromJson(e.data()))
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
    if (_scrollController.offset > _appBarHeight && !_isScrollingDown) {
      setState(() {
        _isScrollingDown = true;
      });
      _animateFabOpacity(0.3);
    } else if (_scrollController.offset <= _appBarHeight && _isScrollingDown) {
      setState(() {
        _isScrollingDown = false;
      });
      _animateFabOpacity(1.0);
    }
  }

  void _animateFabOpacity(double targetOpacity) {
    setState(() {
      _fabOpacity = targetOpacity;
    });
  }

  void _onFabPressed() {
    RouterClass.nextScreenNormal(context, const ChoseDateTimeScreen());
  }

  Future<void> getCurrentLocation() async {
    try {
      await Geolocator.getCurrentPosition().then((value) {
        LatLng newLatLng = LatLng(value.latitude, value.longitude);
        setState(() {
          currentLocation = newLatLng;
        });
      });
    } catch (e) {
      debugPrint('Getting error in current Location Fatching! ${e.toString()}');
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
      filteredEvents =
          filteredEvents
              .where(
                (event) => isInRadius(
                  currentLocation!,
                  radiusInMiles,
                  event.getLatLng(),
                ),
              )
              .toList()
            ..sort((a, b) {
              double distanceA = calculateDistance(
                currentLocation!,
                a.getLatLng(),
              );
              double distanceB = calculateDistance(
                currentLocation!,
                b.getLatLng(),
              );

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
          : AnimatedOpacity(
              opacity: _fabOpacity,
              duration: const Duration(milliseconds: 300),
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
                    child: const Icon(Icons.add, color: Colors.white, size: 28),
                  ),
                ),
              ),
            ),
      bottomNavigationBar: BottomNavigationBar(
        type: BottomNavigationBarType.fixed,
        currentIndex: 0, // Home is always selected when in HomeScreen
        selectedItemColor: Theme.of(context).colorScheme.primary,
        unselectedItemColor: Theme.of(
          context,
        ).colorScheme.onSurface.withValues(alpha: 0.6),
        backgroundColor: Theme.of(
          context,
        ).bottomNavigationBarTheme.backgroundColor,
        onTap: (index) {
          // Navigate to different screens based on index
          switch (index) {
            case 0:
              // Already on home, do nothing
              break;
            case 1:
              RouterClass.nextScreenNormal(context, const MessagingScreen());
              break;
            case 2:
              RouterClass.nextScreenNormal(
                context,
                const NotificationsScreen(),
              );
              break;
            case 3:
              RouterClass.nextScreenNormal(context, const AccountScreen());
              break;
          }
        },
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.event, size: 20), label: ''),
          BottomNavigationBarItem(
            icon: Icon(Icons.message, size: 20),
            label: '',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.notifications, size: 20),
            label: '',
          ),
          BottomNavigationBarItem(icon: Icon(Icons.menu, size: 20), label: ''),
        ],
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
        child: Column(
          children: [
            _headerView(),
            _filterSection(),
            Expanded(child: _eventsView()),
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
                    const Text(
                      'Amazing Events',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 24,
                        fontFamily: 'Roboto',
                      ),
                    ),
                  ],
                ),
              ),
              Row(
                children: [
                  // Search Icon
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
                  const SizedBox(width: 8),
                  // QR Code Icon
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
                  // Logo
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(20),
                      child: Image.asset(
                        Images.inAppLogo,
                        width: 32,
                        height: 32,
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

    return _buildFirestoreStream();
  }

  Widget _buildFirestoreStream() {
    // Create a stream for the Firestore query
    // Start with the simplest possible query
    Stream<QuerySnapshot> eventsStream;

    try {
      eventsStream = FirebaseFirestore.instance
          .collection(EventModel.firebaseKey)
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
          return _buildEmptyStateWithDebug();
        }

        // Process events data
        List<EventModel> eventsList = snapshot.data!.docs
            .map((e) => EventModel.fromJson(e.data() as Map<String, dynamic>))
            .toList();

        List<EventModel> neededEventList = [];

        for (var element in eventsList) {
          // Filter out events that ended more than 2 hours ago
          final eventEndTime = element.selectedDateTime.add(
            Duration(hours: element.eventDuration),
          );
          final cutoffTime = DateTime.now().subtract(const Duration(hours: 2));
          if (eventEndTime.isAfter(cutoffTime)) {
            neededEventList.add(element);
          }
        }

        List<EventModel> filtered = filterEvents(neededEventList);

        // Apply sorting
        filtered = _sortEvents(filtered);

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
            // All Events List - show events in chronological order
            Expanded(child: _buildEventsList(allEventsInChronologicalOrder)),
          ],
        );
      },
    );
  }

  Widget _buildFeaturedCarousel(List<EventModel> featuredEvents) {
    return Column(
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
            ],
          ),
        ),
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
    );
  }

  Widget _buildFeaturedCard(EventModel event) {
    return _FeaturedEventCard(event: event);
  }

  Widget _buildSkeletonLoading() {
    return ListView(
      padding: const EdgeInsets.all(24),
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
              'No events found',
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
              'No events are currently available in the database',
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

  Widget _buildEventsList(List<EventModel> events) {
    if (events.isEmpty) {
      return _buildEmptyState();
    }

    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
      itemCount: events.length,
      itemBuilder: (context, index) {
        return Padding(
          padding: const EdgeInsets.only(bottom: 16),
          child: _buildEventCard(events[index]),
        );
      },
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

    return ListView.builder(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.symmetric(vertical: 0),
      itemCount: _searchEvents.length,
      itemBuilder: (context, index) {
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
          child: _buildEventCard(_searchEvents[index]),
        );
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

    return ListView.builder(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.symmetric(vertical: 0),
      itemCount: _searchUsers.length,
      itemBuilder: (context, index) {
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
          child: _buildUserCard(_searchUsers[index]),
        );
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
              RouterClass.nextScreenNormal(
                context,
                UserProfileScreen(user: user),
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
    setState(() {
      _isLoadingDefaultEvents = true;
    });

    try {
      // Get all non-private events from Firestore without complex ordering
      final querySnapshot = await FirebaseFirestore.instance
          .collection(EventModel.firebaseKey)
          .where('private', isEqualTo: false)
          .limit(50)
          .get();

      if (mounted) {
        List<EventModel> events = querySnapshot.docs
            .map((doc) => EventModel.fromJson(doc.data()))
            .toList();

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
    setState(() {
      _isLoadingDefaultUsers = true;
    });

    try {
      final users = await FirebaseFirestoreHelper().searchUsers(
        searchQuery: '', // Empty query to get all users
        limit: 50,
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

    return ListView.builder(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.symmetric(vertical: 0),
      itemCount: _defaultEvents.length,
      itemBuilder: (context, index) {
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
          child: _buildEventCard(_defaultEvents[index]),
        );
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

    return ListView.builder(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.symmetric(vertical: 0),
      itemCount: _defaultUsers.length,
      itemBuilder: (context, index) {
        final user = _defaultUsers[index];
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
          child: GestureDetector(
            onTap: () {
              RouterClass.nextScreenNormal(
                context,
                UserProfileScreen(user: user),
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
                      color: Colors.white.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.2),
                        width: 1,
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.search,
                          color: Colors.white.withValues(alpha: 0.8),
                          size: 20,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: TextField(
                            controller: _searchController,
                            focusNode: _searchFocusNode,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 16,
                              fontFamily: 'Roboto',
                            ),
                            decoration: InputDecoration(
                              hintText: _currentSearchType == SearchType.events
                                  ? 'Search events by title...'
                                  : 'Search users by name...',
                              hintStyle: TextStyle(
                                color: Colors.white.withValues(alpha: 0.8),
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
                              color: Colors.white.withValues(alpha: 0.8),
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

  Widget _buildEmptyStateWithDebug() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.info_outline, size: 64, color: Colors.blue),
            const SizedBox(height: 16),
            const Text(
              'Firestore Connected Successfully',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Colors.green,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Collection: ${EventModel.firebaseKey}',
              style: const TextStyle(fontSize: 14),
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.yellow.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.orange),
              ),
              child: const Column(
                children: [
                  Text(
                    '🎯 No Events Found',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                  SizedBox(height: 8),
                  Text(
                    'The database connection is working, but there are currently no events in the "Events" collection.',
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: () {
                RouterClass.nextScreenNormal(
                  context,
                  const ChoseDateTimeScreen(),
                );
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF667EEA),
                foregroundColor: Colors.white,
              ),
              child: const Text('Create First Event'),
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: () {
                // Show sample static events for testing
                _showSampleEvents();
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.orange,
                foregroundColor: Colors.white,
              ),
              child: const Text('Show Sample Events (Test UI)'),
            ),
          ],
        ),
      ),
    );
  }

  void _showSampleEvents() {
    // Create sample events to test UI components
    List<EventModel> sampleEvents = [
      EventModel(
        id: 'sample1',
        groupName: 'Tech Meetup',
        title: 'Flutter Development Workshop',
        description: 'Learn Flutter development basics',
        location: 'Community Center',
        customerUid: 'sample-user',
        imageUrl:
            'https://via.placeholder.com/300x200/667EEA/FFFFFF?text=Flutter+Workshop',
        selectedDateTime: DateTime.now().add(const Duration(days: 1)),
        eventGenerateTime: DateTime.now(),
        status: 'active',
        private: false,
        getLocation: true,
        radius: 100,
        latitude: 37.7749,
        longitude: -122.4194,
        categories: ['Educational'],
        isFeatured: true,
        featureEndDate: DateTime.now().add(const Duration(days: 30)),
        ticketsEnabled: true,
        maxTickets: 50,
        issuedTickets: 12,
        eventDuration: 3,
        coHosts: [],
        signInMethods: ['qr_code'],
        manualCode: null,
      ),
      EventModel(
        id: 'sample2',
        groupName: 'Business Network',
        title: 'Networking Event',
        description: 'Professional networking opportunity',
        location: 'Downtown Office',
        customerUid: 'sample-user',
        imageUrl:
            'https://via.placeholder.com/300x200/764BA2/FFFFFF?text=Networking',
        selectedDateTime: DateTime.now().add(const Duration(days: 3)),
        eventGenerateTime: DateTime.now(),
        status: 'active',
        private: false,
        getLocation: true,
        radius: 200,
        latitude: 37.7849,
        longitude: -122.4094,
        categories: ['Professional'],
        isFeatured: false,
        featureEndDate: null,
        ticketsEnabled: false,
        maxTickets: 0,
        issuedTickets: 0,
        eventDuration: 2,
        coHosts: [],
        signInMethods: ['manual_code'],
        manualCode: 'NET123',
      ),
    ];

    // Navigate to a new screen showing sample events
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.8,
        builder: (context, scrollController) => Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.only(
              topLeft: Radius.circular(20),
              topRight: Radius.circular(20),
            ),
          ),
          child: Column(
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
              Padding(
                padding: const EdgeInsets.all(20),
                child: Row(
                  children: [
                    const Text(
                      'Sample Events (UI Test)',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const Spacer(),
                    IconButton(
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.close),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: ListView.builder(
                  controller: scrollController,
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  itemCount: sampleEvents.length,
                  itemBuilder: (context, index) {
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 16),
                      child: _buildEventCard(sampleEvents[index]),
                    );
                  },
                ),
              ),
            ],
          ),
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
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 8,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.white.withValues(alpha: 0.2),
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(
                                    color: Colors.white.withValues(alpha: 0.3),
                                    width: 1,
                                  ),
                                ),
                                child: Text(
                                  DateFormat(
                                    'MMM dd, KK:mm a',
                                  ).format(widget.event.selectedDateTime),
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w600,
                                    fontSize: 14,
                                    fontFamily: 'Roboto',
                                  ),
                                ),
                              ),
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
        // Default (Event Date Ascending)
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
        return 'Default (Event Date Ascending)';
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
