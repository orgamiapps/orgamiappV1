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

  // Scroll controller and animation
  late ScrollController _scrollController;
  double _fabOpacity = 1.0;
  bool _isScrollingDown = false;
  static const double _appBarHeight = 56.0;

  // Animation controllers
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  // Remove 'Featured' from categories
  final List<String> _allCategories = ['Educational', 'Professional', 'Other'];

  LatLng? currentLocation;

  @override
  void initState() {
    super.initState();
    selectedCategories = [];
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
    RouterClass.nextScreenNormal(
      context,
      const ChoseDateTimeScreen(),
    );
  }

  Future<void> getCurrentLocation() async {
    try {
      await Geolocator.getCurrentPosition().then((value) {
        LatLng newLatLng = LatLng(
          value.latitude,
          value.longitude,
        );
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
    double a = sin(dLat / 2) * sin(dLat / 2) +
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
    double a = sin(dLat / 2) * sin(dLat / 2) +
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

    // Only filter by categories (not 'Featured')
    if (selectedCategories.isNotEmpty) {
      filteredEvents = filteredEvents.where((event) {
        return event.categories
            .any((category) => selectedCategories.contains(category));
      }).toList();
    }

    // Filter by distance if location and radius are set
    if (currentLocation != null && radiusInMiles > 0) {
      filteredEvents = filteredEvents
          .where(
            (event) => isInRadius(
              currentLocation!,
              radiusInMiles,
              event.getLatLng(),
            ),
          )
          .toList()
        ..sort((a, b) {
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
      backgroundColor: AppThemeColor.pureWhiteColor,
      floatingActionButton: AnimatedOpacity(
        opacity: _fabOpacity,
        duration: const Duration(milliseconds: 300),
        child: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: const Color(0xFF4CAF50),
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.2),
                spreadRadius: 1,
                blurRadius: 2,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(20),
              onTap: _onFabPressed,
              onLongPress: () {
                // Show tooltip on long press
                final RenderBox renderBox =
                    context.findRenderObject() as RenderBox;
                final Offset position = renderBox.localToGlobal(Offset.zero);

                OverlayEntry? overlayEntry;
                overlayEntry = OverlayEntry(
                  builder: (context) => Positioned(
                    top: position.dy - 50,
                    left: position.dx - 60,
                    child: Material(
                      color: Colors.transparent,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: Colors.black87,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: const Text(
                          'Create Event',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                            fontFamily: 'Roboto',
                          ),
                        ),
                      ),
                    ),
                  ),
                );

                Overlay.of(context).insert(overlayEntry);
                Future.delayed(const Duration(seconds: 2), () {
                  if (mounted) {
                    overlayEntry?.remove();
                  }
                });
              },
              child: const Icon(
                Icons.add,
                color: Colors.white,
                size: 24,
              ),
            ),
          ),
        ),
      ),
      body: SafeArea(
        child: _bodyView(),
      ),
    );
  }

  Widget _bodyView() {
    return RefreshIndicator(
      onRefresh: _onRefresh,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        controller: _scrollController,
        child: Column(
          children: [
            _headerView(),
            _filterSection(),
            _eventsView(),
          ],
        ),
      ),
    );
  }

  Widget _headerView() {
    return Container(
      width: double.infinity,
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Color(0xFFE8F5E8), // Light green
            Colors.white,
          ],
        ),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Upcoming Events',
                style: TextStyle(
                  color: AppThemeColor.pureBlackColor,
                  fontWeight: FontWeight.bold,
                  fontSize: 24,
                  fontFamily: 'Roboto',
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Discover amazing events near you',
                style: TextStyle(
                  color: AppThemeColor.dullFontColor,
                  fontSize: 14,
                  fontFamily: 'Roboto',
                ),
              ),
            ],
          ),
          Image.asset(
            Images.inAppLogo,
            width: 100,
            height: 100,
          ),
        ],
      ),
    );
  }

  Widget _filterSection() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Category Filters
          const Text(
            'Filter by Category',
            style: TextStyle(
              color: AppThemeColor.pureBlackColor,
              fontWeight: FontWeight.w600,
              fontSize: 16,
              fontFamily: 'Roboto',
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 40,
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: [
                // Featured toggle
                Padding(
                  padding: const EdgeInsets.only(right: 12),
                  child: FilterChip(
                    label: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.star,
                          size: 16,
                          color: showFeaturedFirst
                              ? Colors.white
                              : const Color(0xFF4CAF50),
                        ),
                        const SizedBox(width: 4),
                        const Text('Featured'),
                      ],
                    ),
                    selected: showFeaturedFirst,
                    onSelected: (selected) {
                      setState(() {
                        showFeaturedFirst = selected;
                      });
                    },
                    backgroundColor: Colors.white,
                    selectedColor: const Color(0xFF4CAF50),
                    side: BorderSide(
                      color: showFeaturedFirst
                          ? const Color(0xFF4CAF50)
                          : AppThemeColor.grayColor,
                      width: 2,
                    ),
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  ),
                ),
                // Category chips
                ..._allCategories.map((category) {
                  final isSelected = selectedCategories.contains(category);
                  return Padding(
                    padding: const EdgeInsets.only(right: 12),
                    child: FilterChip(
                      label: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            _getCategoryIcon(category),
                            size: 16,
                            color: isSelected
                                ? Colors.white
                                : const Color(0xFF4CAF50),
                          ),
                          const SizedBox(width: 4),
                          Text(category),
                        ],
                      ),
                      selected: isSelected,
                      onSelected: (selected) {
                        setState(() {
                          if (selected) {
                            selectedCategories.add(category);
                          } else {
                            selectedCategories.remove(category);
                          }
                        });
                      },
                      backgroundColor: Colors.white,
                      selectedColor: const Color(0xFF4CAF50),
                      side: BorderSide(
                        color: isSelected
                            ? const Color(0xFF4CAF50)
                            : AppThemeColor.grayColor,
                        width: 2,
                      ),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 8),
                    ),
                  );
                }),
                // Clear filters
                if (selectedCategories.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(right: 12),
                    child: FilterChip(
                      label: const Text('Clear Filters'),
                      selected: false,
                      onSelected: (selected) {
                        setState(() {
                          selectedCategories.clear();
                        });
                      },
                      backgroundColor: Colors.white,
                      side: const BorderSide(
                        color: Color(0xFFFF9800),
                        width: 2,
                      ),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 8),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          // Distance Slider
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Distance',
                style: TextStyle(
                  color: AppThemeColor.pureBlackColor,
                  fontWeight: FontWeight.w600,
                  fontSize: 16,
                  fontFamily: 'Roboto',
                ),
              ),
              Text(
                radiusInMiles > 0
                    ? '${radiusInMiles.toStringAsFixed(0)}mi'
                    : 'Global',
                style: const TextStyle(
                  color: Color(0xFF4CAF50),
                  fontWeight: FontWeight.w600,
                  fontSize: 14,
                  fontFamily: 'Roboto',
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Slider(
            min: 0,
            max: 100,
            value: radiusInMiles,
            activeColor: const Color(0xFF4CAF50),
            inactiveColor: Colors.grey[300],
            onChanged: (value) {
              setState(() {
                radiusInMiles = value;
              });
            },
          ),
        ],
      ),
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
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.error_outline,
                  size: 64,
                  color: Colors.grey[400],
                ),
                const SizedBox(height: 16),
                Text(
                  'Failed to load events. Check your connection or permissions.',
                  style: TextStyle(
                    color: Colors.grey[600],
                    fontSize: 16,
                    fontFamily: 'Roboto',
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 20),
                ElevatedButton.icon(
                  onPressed: () {
                    // Force rebuild to retry the stream
                    setState(() {});
                  },
                  icon: const Icon(Icons.refresh),
                  label: const Text('Retry'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppThemeColor.darkGreenColor,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 24,
                      vertical: 12,
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  'Note: Ensure Firestore rules allow authenticated users to read non-private events',
                  style: TextStyle(
                    color: Colors.grey[500],
                    fontSize: 12,
                    fontStyle: FontStyle.italic,
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          );
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
        List<EventModel> featuredEvents = filtered
            .where((e) =>
                e.isFeatured == true &&
                (e.featureEndDate == null ||
                    e.featureEndDate!.isAfter(DateTime.now())))
            .toList()
          ..sort((a, b) => (b.featureEndDate ?? DateTime(1970))
              .compareTo(a.featureEndDate ?? DateTime(1970)));

        List<EventModel> nonFeaturedEvents = filtered
            .where((e) => !(e.isFeatured == true &&
                (e.featureEndDate == null ||
                    e.featureEndDate!.isAfter(DateTime.now()))))
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
          padding: const EdgeInsets.symmetric(horizontal: 20),
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
                      size: 20,
                    ),
                  );
                },
              ),
              const SizedBox(width: 8),
              const Text(
                'Featured Events',
                style: TextStyle(
                  color: AppThemeColor.pureBlackColor,
                  fontWeight: FontWeight.bold,
                  fontSize: 18,
                  fontFamily: 'Roboto',
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        CarouselSlider.builder(
          itemCount: featuredEvents.length,
          itemBuilder: (context, index, realIndex) {
            return _buildFeaturedCard(featuredEvents[index]);
          },
          options: CarouselOptions(
            height: 200,
            viewportFraction: 0.9,
            enableInfiniteScroll: false,
            autoPlay: featuredEvents.length > 1,
            autoPlayInterval: const Duration(seconds: 4),
          ),
        ),
        const SizedBox(height: 20),
      ],
    );
  }

  Widget _buildFeaturedCard(EventModel event) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () {
          print('Tapped featured card: ${event.id}');
          RouterClass.nextScreenNormal(
            context,
            SingleEventScreen(eventModel: event),
          );
        },
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: const Color(0xFFE65100),
              width: 5.0,
            ),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFFE65100).withValues(alpha: 0.5),
                spreadRadius: 3,
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.3),
                spreadRadius: 5,
                blurRadius: 25,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: Stack(
              children: [
                // Background Image
                Container(
                  width: double.infinity,
                  height: 200,
                  decoration: BoxDecoration(
                    image: DecorationImage(
                      image: NetworkImage(event.imageUrl),
                      fit: BoxFit.cover,
                    ),
                  ),
                ),
                // Gradient Overlay
                Container(
                  width: double.infinity,
                  height: 200,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.black.withValues(alpha: 0.7),
                        Colors.transparent,
                        Colors.black.withValues(alpha: 0.8),
                      ],
                    ),
                  ),
                ),
                // Content
                Padding(
                  padding: const EdgeInsets.all(16),
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
                                Icon(
                                  Icons.star,
                                  color: Colors.white,
                                  size: 12,
                                ),
                                SizedBox(width: 4),
                                Text(
                                  'Featured ★',
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
                              fontSize: 20,
                              fontFamily: 'Roboto',
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 8),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 4,
                                ),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF4CAF50),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Text(
                                  DateFormat('MMM dd, KK:mm a')
                                      .format(event.selectedDateTime),
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w600,
                                    fontSize: 12,
                                    fontFamily: 'Roboto',
                                  ),
                                ),
                              ),
                              Material(
                                color: Colors.transparent,
                                child: InkWell(
                                  borderRadius: BorderRadius.circular(8),
                                  onTap: () {
                                    print('Tapped featured event: ${event.id}');
                                    RouterClass.nextScreenNormal(
                                      context,
                                      SingleEventScreen(eventModel: event),
                                    );
                                  },
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 12,
                                      vertical: 6,
                                    ),
                                    decoration: BoxDecoration(
                                      color: Colors.transparent,
                                      border: Border.all(
                                        color: Colors.white,
                                        width: 1,
                                      ),
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: const Text(
                                      'Details >',
                                      style: TextStyle(
                                        color: Colors.white,
                                        fontWeight: FontWeight.w600,
                                        fontSize: 12,
                                        fontFamily: 'Roboto',
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
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
          child: _buildEventCard(events[index]),
        );
      },
    );
  }

  Widget _buildEventCard(EventModel event) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () {
          print('Tapped event card: ${event.id}');
          RouterClass.nextScreenNormal(
            context,
            SingleEventScreen(eventModel: event),
          );
        },
        child: Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: const Color(0xFF1B5E20),
              width: 4.0,
            ),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF1B5E20).withValues(alpha: 0.4),
                spreadRadius: 2,
                blurRadius: 10,
                offset: const Offset(0, 3),
              ),
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.25),
                spreadRadius: 4,
                blurRadius: 20,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    if (event.isFeatured)
                      const Icon(
                        Icons.star,
                        color: Color(0xFFFF9800),
                        size: 20,
                      ),
                    if (event.isFeatured) const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        event.title,
                        style: const TextStyle(
                          color: AppThemeColor.pureBlackColor,
                          fontWeight: FontWeight.bold,
                          fontSize: 18,
                          fontFamily: 'Roboto',
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  event.groupName,
                  style: TextStyle(
                    color: AppThemeColor.dullFontColor,
                    fontSize: 14,
                    fontFamily: 'Roboto',
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  event.location,
                  style: TextStyle(
                    color: AppThemeColor.dullFontColor,
                    fontSize: 14,
                    fontFamily: 'Roboto',
                  ),
                ),
                const SizedBox(height: 12),
                ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: AspectRatio(
                    aspectRatio: 16 / 9,
                    child: Image.network(
                      event.imageUrl,
                      fit: BoxFit.cover,
                      loadingBuilder: (context, child, loadingProgress) {
                        if (loadingProgress == null) return child;
                        return Container(
                          color: Colors.grey[200],
                          child: const Center(
                            child: CircularProgressIndicator(
                              color: Color(0xFF4CAF50),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  event.description,
                  style: const TextStyle(
                    color: AppThemeColor.pureBlackColor,
                    fontSize: 14,
                    fontFamily: 'Roboto',
                  ),
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 12),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      DateFormat('EEEE, MMMM dd yyyy\nKK:mm a')
                          .format(event.selectedDateTime),
                      style: const TextStyle(
                        color: AppThemeColor.pureBlackColor,
                        fontWeight: FontWeight.w900,
                        fontSize: 12,
                        fontStyle: FontStyle.italic,
                        fontFamily: 'Roboto',
                      ),
                    ),
                    Material(
                      color: const Color(0xFF4CAF50),
                      borderRadius: BorderRadius.circular(8),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(8),
                        onTap: () {
                          print('Tapped event: ${event.id}');
                          RouterClass.nextScreenNormal(
                            context,
                            SingleEventScreen(eventModel: event),
                          );
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 8,
                          ),
                          child: const Text(
                            'Details >>',
                            style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w700,
                              fontSize: 12,
                              fontFamily: 'Roboto',
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
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
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Shimmer.fromColors(
            baseColor: Colors.grey[300]!,
            highlightColor: Colors.grey[100]!,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  height: 20,
                  width: 150,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
                const SizedBox(height: 12),
                Container(
                  height: 200,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 20),
        // Event cards skeleton
        ...List.generate(
            3,
            (index) => Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                  child: Shimmer.fromColors(
                    baseColor: Colors.grey[300]!,
                    highlightColor: Colors.grey[100]!,
                    child: Container(
                      height: 200,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                  ),
                )),
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
            Icon(
              Icons.event_busy,
              size: 64,
              color: Colors.grey[400],
            ),
            const SizedBox(height: 16),
            Text(
              showFeaturedFirst
                  ? 'No featured events—create one!'
                  : 'No events found',
              style: TextStyle(
                color: Colors.grey[600],
                fontSize: 18,
                fontWeight: FontWeight.w600,
                fontFamily: 'Roboto',
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              'Try adjusting your filters or create a new event',
              style: TextStyle(
                color: Colors.grey[500],
                fontSize: 14,
                fontFamily: 'Roboto',
              ),
              textAlign: TextAlign.center,
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
                backgroundColor: const Color(0xFF4CAF50),
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 12,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              child: const Text(
                'Create Event',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                  fontSize: 16,
                  fontFamily: 'Roboto',
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
