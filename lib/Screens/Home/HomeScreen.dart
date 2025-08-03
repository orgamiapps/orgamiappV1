import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';

// IMPORTANT: Ensure Firestore security rules allow authenticated users to read non-private events:
// match /Events/{eventId} {
//   allow read: if request.auth != null &&
//     (resource.data.customerUid == request.auth.uid || resource.data.private == false);
//   allow write: if request.auth != null && request.auth.uid == resource.data.customerUid;
// }
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:orgami/Models/EventModel.dart';
import 'package:orgami/Screens/Events/ChoseDateTimeScreen.dart';
import 'package:orgami/Screens/Events/SingleEventScreen.dart';
import 'package:orgami/Utils/Colors.dart';
import 'package:orgami/Utils/Images.dart';
import 'package:orgami/Utils/Router.dart';
import 'package:carousel_slider/carousel_slider.dart';
import 'package:shimmer/shimmer.dart';
import 'package:intl/intl.dart';
import 'package:cached_network_image/cached_network_image.dart';

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

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with TickerProviderStateMixin {
  double radiusInMiles = 0;
  List<String> selectedCategories = [];
  bool showFeaturedFirst = true;
  bool isLoading = true;
  bool isRefreshing = false;

  // Sorting state
  SortOption currentSortOption = SortOption.none;

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
    selectedCategories = ['Featured']; // Default to showing featured events
    showFeaturedFirst = true;
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

    // Simulate loading
    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) {
        setState(() {
          isLoading = false;
        });
      }
    });
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _pulseController.dispose();
    _fadeController.dispose();
    super.dispose();
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

    // Filter by categories including Featured
    if (selectedCategories.isNotEmpty) {
      filteredEvents = filteredEvents.where((event) {
        // Check if any selected category matches the event
        return selectedCategories.any((category) {
          if (category == 'Featured') {
            // For Featured category, check if the event is featured and still valid
            return event.isFeatured == true &&
                (event.featureEndDate == null ||
                    event.featureEndDate!.isAfter(DateTime.now()));
          } else {
            // For other categories, check if the event has that category
            return event.categories.contains(category);
          }
        });
      }).toList();

      // If we're filtering by Featured and no featured events are found, show all events instead
      if (selectedCategories.contains('Featured') &&
          selectedCategories.length == 1 &&
          filteredEvents.isEmpty) {
        filteredEvents = events;
      }
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
      backgroundColor: const Color(0xFFFAFBFC),
      floatingActionButton: AnimatedOpacity(
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
      body: SafeArea(child: _bodyView()),
    );
  }

  Widget _bodyView() {
    return RefreshIndicator(
      onRefresh: _onRefresh,
      color: const Color(0xFF667EEA),
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        controller: _scrollController,
        child: FadeTransition(
          opacity: _fadeAnimation,
          child: Column(
            children: [_headerView(), _filterSection(), _eventsView()],
          ),
        ),
      ),
    );
  }

  Widget _headerView() {
    return Container(
      width: double.infinity,
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF667EEA), Color(0xFF764BA2)],
        ),
      ),
      padding: const EdgeInsets.fromLTRB(24, 32, 24, 40),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Discover',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w300,
                      fontSize: 28,
                      fontFamily: 'Roboto',
                    ),
                  ),
                  const Text(
                    'Amazing Events',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 32,
                      fontFamily: 'Roboto',
                    ),
                  ),
                ],
              ),
              Container(
                width: 60,
                height: 60,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(30),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(30),
                  child: Image.asset(Images.inAppLogo, width: 50, height: 50),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _filterSection() {
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
          // Distance Slider
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Icon(
                    Icons.location_on,
                    color: const Color(0xFF667EEA),
                    size: 18,
                  ),
                  const SizedBox(width: 8),
                  const Text(
                    'Distance',
                    style: TextStyle(
                      color: Color(0xFF1A1A1A),
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
                    color: const Color(0xFF667EEA).withOpacity(0.1),
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

  Widget _buildFilterChip({
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

  Widget _eventsView() {
    // Create a stream for the Firestore query
    Stream<QuerySnapshot> eventsStream = FirebaseFirestore.instance
        .collection(EventModel.firebaseKey)
        .where('private', isEqualTo: false)
        .orderBy('selectedDateTime', descending: false)
        .snapshots();

    return StreamBuilder<QuerySnapshot>(
      stream: eventsStream,
      builder: (context, snapshot) {
        // Show loading state
        if (snapshot.connectionState == ConnectionState.waiting && isLoading) {
          return _buildSkeletonLoading();
        }

        // Show error state with retry button
        if (snapshot.hasError) {
          return _buildErrorState();
        }

        // Show empty state
        if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
          return _buildEmptyState();
        }

        // Process events data
        List<EventModel> eventsList = snapshot.data!.docs
            .map((e) => EventModel.fromJson(e.data() as Map<String, dynamic>))
            .toList();

        List<EventModel> neededEventList = [];

        for (var element in eventsList) {
          if (!element.selectedDateTime
              .add(const Duration(hours: 2))
              .isBefore(DateTime.now())) {
            neededEventList.add(element);
          }
        }

        List<EventModel> filtered = filterEvents(neededEventList);

        // Apply sorting
        filtered = _sortEvents(filtered);

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

        List<EventModel> nonFeaturedEvents = filtered
            .where(
              (e) =>
                  !(e.isFeatured == true &&
                      (e.featureEndDate == null ||
                          e.featureEndDate!.isAfter(DateTime.now()))),
            )
            .toList();

        return Column(
          children: [
            // Featured Events Carousel
            if (showFeaturedFirst && featuredEvents.isNotEmpty)
              _buildFeaturedCarousel(featuredEvents),

            // All Events List
            if (showFeaturedFirst)
              _buildEventsList([...featuredEvents, ...nonFeaturedEvents])
            else
              _buildEventsList(filtered),
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
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: () {
          RouterClass.nextScreenNormal(
            context,
            SingleEventScreen(eventModel: event),
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
                Container(
                  width: double.infinity,
                  height: 240,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(20),
                    child: CachedNetworkImage(
                      imageUrl: event.imageUrl,
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
                            event.title,
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
                            event.groupName,
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
                                  ).format(event.selectedDateTime),
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

  Widget _buildEventsList(List<EventModel> events) {
    if (events.isEmpty) {
      return _buildEmptyState();
    }

    return ListView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: events.length,
      itemBuilder: (context, index) {
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
          child: _buildEventCard(events[index]),
        );
      },
    );
  }

  Widget _buildEventCard(EventModel event) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: () {
          RouterClass.nextScreenNormal(
            context,
            SingleEventScreen(eventModel: event),
          );
        },
        child: Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.08),
                spreadRadius: 0,
                blurRadius: 20,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Image section
              ClipRRect(
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(20),
                  topRight: Radius.circular(20),
                ),
                child: Stack(
                  children: [
                    AspectRatio(
                      aspectRatio: 16 / 9,
                      child: CachedNetworkImage(
                        imageUrl: event.imageUrl,
                        fit: BoxFit.cover,
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
                                  size: 32,
                                ),
                                SizedBox(height: 4),
                                Text(
                                  'Image not available',
                                  style: TextStyle(
                                    color: Color(0xFF667EEA),
                                    fontSize: 12,
                                    fontFamily: 'Roboto',
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                    if (event.isFeatured)
                      Positioned(
                        top: 12,
                        right: 12,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(0xFFFF9800),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.star, color: Colors.white, size: 12),
                              SizedBox(width: 4),
                              Text(
                                'Featured',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 10,
                                  fontFamily: 'Roboto',
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              // Content section
              Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      event.title,
                      style: const TextStyle(
                        color: Color(0xFF1A1A1A),
                        fontWeight: FontWeight.bold,
                        fontSize: 20,
                        fontFamily: 'Roboto',
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Icon(
                          Icons.group,
                          color: const Color(0xFF667EEA),
                          size: 16,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          event.groupName,
                          style: const TextStyle(
                            color: Color(0xFF6B7280),
                            fontSize: 14,
                            fontFamily: 'Roboto',
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Icon(
                          Icons.location_on,
                          color: const Color(0xFF667EEA),
                          size: 16,
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            event.location,
                            style: const TextStyle(
                              color: Color(0xFF6B7280),
                              fontSize: 14,
                              fontFamily: 'Roboto',
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Text(
                      event.description,
                      style: const TextStyle(
                        color: Color(0xFF4B5563),
                        fontSize: 14,
                        fontFamily: 'Roboto',
                        height: 1.5,
                      ),
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 16),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 8,
                            ),
                            decoration: BoxDecoration(
                              color: const Color(
                                0xFF667EEA,
                              ).withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text(
                              DateFormat(
                                'MMM dd, yyyy\nKK:mm a',
                              ).format(event.selectedDateTime),
                              style: const TextStyle(
                                color: Color(0xFF667EEA),
                                fontWeight: FontWeight.w600,
                                fontSize: 12,
                                fontFamily: 'Roboto',
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 10,
                          ),
                          decoration: BoxDecoration(
                            gradient: const LinearGradient(
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                              colors: [Color(0xFF667EEA), Color(0xFF764BA2)],
                            ),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Text(
                            'View Details',
                            style: TextStyle(
                              color: Colors.white,
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
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSkeletonLoading() {
    return Column(
      children: [
        // Featured skeleton
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Shimmer.fromColors(
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
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
                const SizedBox(height: 16),
                Container(
                  height: 240,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(20),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 24),
        // Event cards skeleton
        ...List.generate(
          3,
          (index) => Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
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

  Widget _buildErrorState() {
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
                Icons.error_outline,
                size: 40,
                color: const Color(0xFF667EEA),
              ),
            ),
            const SizedBox(height: 24),
            const Text(
              'Something went wrong',
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
              'Check your connection and try again',
              style: TextStyle(
                color: const Color(0xFF6B7280),
                fontSize: 16,
                fontFamily: 'Roboto',
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 32),
            ElevatedButton.icon(
              onPressed: () {
                setState(() {});
              },
              icon: const Icon(Icons.refresh),
              label: const Text('Try Again'),
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

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(40),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 100,
              height: 100,
              decoration: BoxDecoration(
                color: const Color(0xFF667EEA).withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(50),
              ),
              child: Icon(
                Icons.event_busy,
                size: 50,
                color: const Color(0xFF667EEA),
              ),
            ),
            const SizedBox(height: 24),
            Text(
              showFeaturedFirst
                  ? 'No featured events available'
                  : 'No events found',
              style: const TextStyle(
                color: Color(0xFF1A1A1A),
                fontSize: 20,
                fontWeight: FontWeight.bold,
                fontFamily: 'Roboto',
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              'Try adjusting your filters or create a new event',
              style: TextStyle(
                color: const Color(0xFF6B7280),
                fontSize: 16,
                fontFamily: 'Roboto',
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 32),
            ElevatedButton.icon(
              onPressed: () {
                RouterClass.nextScreenNormal(
                  context,
                  const ChoseDateTimeScreen(),
                );
              },
              icon: const Icon(Icons.add),
              label: const Text('Create Event'),
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
        color: const Color(0xFF667EEA).withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: const Color(0xFF667EEA).withOpacity(0.3),
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
                    ? const Color(0xFF667EEA).withOpacity(0.1)
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
        return 'No Sorting';
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
