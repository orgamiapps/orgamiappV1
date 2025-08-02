import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_ui_firestore/firebase_ui_firestore.dart';
import 'package:flutter/material.dart';
import 'package:orgami/Controller/CustomerController.dart';
import 'package:orgami/Firebase/FirebaseFirestoreHelper.dart';
import 'package:orgami/Models/AttendanceModel.dart';
import 'package:orgami/Models/EventModel.dart';
import 'package:orgami/Screens/Events/SingleEventScreen.dart';
import 'package:orgami/Utils/Colors.dart';
import 'package:orgami/Utils/dimensions.dart';
import 'package:orgami/Utils/Router.dart';
import 'package:intl/intl.dart';
import 'package:shimmer/shimmer.dart';

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

class MyEventsScreen extends StatefulWidget {
  const MyEventsScreen({super.key});

  @override
  State<MyEventsScreen> createState() => _MyEventsScreenState();
}

class _MyEventsScreenState extends State<MyEventsScreen>
    with TickerProviderStateMixin {
  late final double _screenWidth = MediaQuery.of(context).size.width;
  late final double _screenHeight = MediaQuery.of(context).size.height;

  final FirebaseFirestore _fireStore = FirebaseFirestore.instance;

  int selectedTab = 1;
  bool isLoading = true;

  // Filter/Sort state
  SortOption currentSortOption = SortOption.none;
  List<String> selectedCategories = [];

  // Categories for filtering (tailored for each tab)
  final List<String> _allCategories = ['Educational', 'Professional', 'Other'];

  List<AttendanceModel> attendanceList = [];
  List<AttendanceModel> preRegisteredAttendanceList = [];

  late StreamSubscription<QuerySnapshot<Map<String, dynamic>>>
      _attendanceSubscription;
  late StreamSubscription<QuerySnapshot<Map<String, dynamic>>>
      _preRegisteredSubscription;

  // Animation controllers
  late AnimationController _fadeController;
  late Animation<double> _fadeAnimation;

  // Scroll controller and animation
  late ScrollController _scrollController;
  double _headerOpacity = 1.0;
  double _tabBarOpacity = 1.0;
  double _headerHeight = 120.0; // Reduced initial header height
  double _collapsedHeaderHeight = 70.0; // Reduced collapsed height
  bool _isScrollingDown = false;

  bool signedInEvent({required String eventId}) {
    bool eventSignedIn = false;
    for (var element in attendanceList) {
      if (element.eventId == eventId) {
        eventSignedIn = true;
      }
    }

    return eventSignedIn;
  }

  bool preRegisteredEvent({required String eventId}) {
    bool eventPreRegistered = false;
    for (var element in preRegisteredAttendanceList) {
      if (element.eventId == eventId) {
        eventPreRegistered = true;
      }
    }

    return eventPreRegistered;
  }

  // Sort events based on current sort option
  List<EventModel> _sortEvents(List<EventModel> events) {
    switch (currentSortOption) {
      case SortOption.none:
        break;
      case SortOption.dateAddedAsc:
        events
            .sort((a, b) => a.eventGenerateTime.compareTo(b.eventGenerateTime));
        break;
      case SortOption.dateAddedDesc:
        events
            .sort((a, b) => b.eventGenerateTime.compareTo(a.eventGenerateTime));
        break;
      case SortOption.titleAsc:
        events.sort(
            (a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()));
        break;
      case SortOption.titleDesc:
        events.sort(
            (a, b) => b.title.toLowerCase().compareTo(a.title.toLowerCase()));
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
        return Icons.schedule;
      case SortOption.dateAddedDesc:
        return Icons.schedule;
      case SortOption.titleAsc:
        return Icons.sort_by_alpha;
      case SortOption.titleDesc:
        return Icons.sort_by_alpha;
      case SortOption.eventDateAsc:
        return Icons.event;
      case SortOption.eventDateDesc:
        return Icons.event;
    }
  }

  // Get current sort indicator text
  String _getCurrentSortIndicator() {
    switch (currentSortOption) {
      case SortOption.none:
        return 'Default';
      case SortOption.dateAddedAsc:
        return 'Oldest';
      case SortOption.dateAddedDesc:
        return 'Newest';
      case SortOption.titleAsc:
        return 'A-Z';
      case SortOption.titleDesc:
        return 'Z-A';
      case SortOption.eventDateAsc:
        return 'Earliest';
      case SortOption.eventDateDesc:
        return 'Latest';
    }
  }

  // Get current filter/sort indicator text
  String _getCurrentFilterSortIndicator() {
    if (selectedCategories.isNotEmpty && currentSortOption != SortOption.none) {
      return 'Filtered & Sorted';
    } else if (selectedCategories.isNotEmpty) {
      return 'Filtered';
    } else if (currentSortOption != SortOption.none) {
      return _getCurrentSortIndicator();
    } else {
      return 'Filter/Sort';
    }
  }

  @override
  void initState() {
    super.initState();

    // Initialize scroll controller
    _scrollController = ScrollController();
    _scrollController.addListener(_onScroll);

    // Initialize fade animation
    _fadeController = AnimationController(
      duration: const Duration(milliseconds: 800),
      vsync: this,
    );
    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _fadeController, curve: Curves.easeOut),
    );
    _fadeController.forward();

    _attendanceSubscription = _fireStore
        .collection(AttendanceModel.firebaseKey)
        .where('customerUid', isEqualTo: CustomerController.logeInCustomer!.uid)
        .snapshots()
        .listen((snapshot) {
      setState(() {
        attendanceList = snapshot.docs
            .map((doc) => AttendanceModel.fromJson(doc.data()))
            .toList();
      });
    });

    _preRegisteredSubscription = _fireStore
        .collection(AttendanceModel.registerFirebaseKey)
        .where('customerUid', isEqualTo: CustomerController.logeInCustomer!.uid)
        .snapshots()
        .listen((snapshot) {
      setState(() {
        preRegisteredAttendanceList = snapshot.docs
            .map((doc) => AttendanceModel.fromJson(doc.data()))
            .toList();
      });
    });

    // Simulate loading
    Future.delayed(const Duration(seconds: 1), () {
      if (mounted) {
        setState(() {
          isLoading = false;
        });
      }
    });
  }

  @override
  void dispose() {
    _attendanceSubscription.cancel();
    _preRegisteredSubscription.cancel();
    _fadeController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    final double scrollOffset = _scrollController.offset;
    final double maxScrollOffset = 100.0; // Distance to fully collapse

    if (!mounted) return; // Prevent setState after dispose

    if (scrollOffset > 0) {
      setState(() {
        _isScrollingDown = true;
        // Calculate opacity based on scroll position
        _tabBarOpacity =
            (1.0 - (scrollOffset / maxScrollOffset)).clamp(0.0, 1.0);
        // Calculate header height
        _headerHeight = _collapsedHeaderHeight +
            ((120.0 - _collapsedHeaderHeight) *
                    (1.0 - (scrollOffset / maxScrollOffset)))
                .clamp(0.0, 120.0 - _collapsedHeaderHeight);
      });
    } else {
      setState(() {
        _isScrollingDown = false;
        _tabBarOpacity = 1.0;
        _headerHeight = 120.0;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFFAFBFC),
      body: SafeArea(
        child: FadeTransition(
          opacity: _fadeAnimation,
          child: _bodyView(),
        ),
      ),
    );
  }

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

  // Build sorting modal
  Widget _buildSortModal() {
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
                const Icon(
                  Icons.sort,
                  color: Color(0xFF667EEA),
                  size: 24,
                ),
                const SizedBox(width: 12),
                const Text(
                  'Sort Events',
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
                    child: const Icon(
                      Icons.close,
                      size: 20,
                    ),
                  ),
                ),
              ],
            ),
          ),
          // Sort options with categories
          Flexible(
            child: ListView(
              shrinkWrap: true,
              padding: const EdgeInsets.symmetric(horizontal: 24),
              children: [
                // Date Added section
                _buildSortSection(
                  'Date Added',
                  [
                    SortOption.dateAddedDesc,
                    SortOption.dateAddedAsc,
                  ],
                ),
                const SizedBox(height: 16),
                // Title section
                _buildSortSection(
                  'Title',
                  [
                    SortOption.titleAsc,
                    SortOption.titleDesc,
                  ],
                ),
                const SizedBox(height: 16),
                // Event Date section
                _buildSortSection(
                  'Event Date',
                  [
                    SortOption.eventDateDesc,
                    SortOption.eventDateAsc,
                  ],
                ),
              ],
            ),
          ),
          // Bottom padding
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  // Build sort section with title
  Widget _buildSortSection(String title, List<SortOption> options) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
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
          bool isSelected = currentSortOption == option;
          return GestureDetector(
            onTap: () {
              setState(() {
                currentSortOption = option;
              });
              Navigator.pop(context);
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
                  color:
                      isSelected ? const Color(0xFF667EEA) : Colors.grey[200]!,
                  width: 1,
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    _getSortOptionIcon(option),
                    color:
                        isSelected ? const Color(0xFF667EEA) : Colors.grey[600],
                    size: 20,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      _getSortOptionText(option),
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight:
                            isSelected ? FontWeight.w600 : FontWeight.w500,
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
        }).toList(),
      ],
    );
  }

  Widget _bodyView() {
    return Column(
      children: [
        _headerView(),
        _tabBarView(),
        Expanded(
          child: _eventsHistoryView(),
        ),
      ],
    );
  }

  Widget _headerView() {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      height: _headerHeight,
      width: double.infinity,
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color(0xFF667EEA),
            Color(0xFF764BA2),
          ],
        ),
      ),
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Flexible(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                // Back button
                GestureDetector(
                  onTap: () {
                    Navigator.of(context).pop();
                  },
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
                // Title
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.only(left: 16),
                    child: const Text(
                      'My Events',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 28,
                        fontFamily: 'Roboto',
                      ),
                    ),
                  ),
                ),
                // Sort button with indicator
                AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  child: Column(
                    children: [
                      GestureDetector(
                        onTap: () {
                          _showFilterSortModal();
                        },
                        child: Container(
                          width: 50,
                          height: 50,
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.2),
                            borderRadius: BorderRadius.circular(25),
                          ),
                          child: Stack(
                            children: [
                              const Center(
                                child: Icon(
                                  Icons.tune,
                                  color: Colors.white,
                                  size: 24,
                                ),
                              ),
                              if (selectedCategories.isNotEmpty ||
                                  currentSortOption != SortOption.none)
                                Positioned(
                                  top: 4,
                                  right: 4,
                                  child: Container(
                                    width: 8,
                                    height: 8,
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
                      if (_headerHeight > 100) ...[
                        const SizedBox(height: 4),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.9),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            _getCurrentFilterSortIndicator(),
                            style: const TextStyle(
                              color: Color(0xFF667EEA),
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
                              fontFamily: 'Roboto',
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _tabBarView() {
    return AnimatedOpacity(
      opacity: _tabBarOpacity,
      duration: const Duration(milliseconds: 200),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        height:
            _tabBarOpacity > 0 ? 90 : 0, // Increased height to prevent overflow
        margin: const EdgeInsets.fromLTRB(24, 0, 24, 24),
        padding: const EdgeInsets.all(12), // Increased padding
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
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
            _buildTabButton(
              label: 'Created',
              icon: Icons.create,
              index: 1,
              color: const Color(0xFF667EEA),
            ),
            _buildTabButton(
              label: 'Attended',
              icon: Icons.check_circle,
              index: 2,
              color: const Color(0xFF10B981),
            ),
            _buildTabButton(
              label: 'Registered',
              icon: Icons.event_available,
              index: 3,
              color: const Color(0xFFF59E0B),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTabButton({
    required String label,
    required IconData icon,
    required int index,
    required Color color,
  }) {
    bool isSelected = selectedTab == index;
    return Expanded(
      child: GestureDetector(
        onTap: () {
          if (!mounted) return; // Prevent setState after dispose
          setState(() {
            selectedTab = index;
          });
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 300),
          margin: const EdgeInsets.symmetric(horizontal: 2), // Reduced margin
          padding: const EdgeInsets.symmetric(
              vertical: 8, horizontal: 4), // Reduced padding
          decoration: BoxDecoration(
            color: isSelected ? color : Colors.transparent,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment:
                MainAxisAlignment.center, // Center content vertically
            children: [
              Icon(
                icon,
                color: isSelected ? Colors.white : color,
                size: 18, // Slightly smaller icon
              ),
              const SizedBox(height: 2), // Reduced spacing
              Flexible(
                // Wrap text in Flexible to prevent overflow
                child: Text(
                  label,
                  style: TextStyle(
                    color: isSelected ? Colors.white : const Color(0xFF1A1A1A),
                    fontWeight: FontWeight.w600,
                    fontSize: 11, // Slightly smaller font
                    fontFamily: 'Roboto',
                  ),
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _eventsHistoryView() {
    return StreamBuilder<QuerySnapshot>(
      stream: _fireStore
          .collection(EventModel.firebaseKey)
          .where('customerUid',
              isEqualTo: CustomerController.logeInCustomer!.uid)
          .orderBy(
            'selectedDateTime',
            descending: false,
          )
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting && isLoading) {
          return _buildSkeletonLoading();
        }

        if (snapshot.hasError) {
          return _buildErrorState();
        }

        if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
          return _buildEmptyState();
        }

        List<EventModel> EventsList = snapshot.data!.docs
            .map((e) => EventModel.fromJson(e.data() as Map<String, dynamic>))
            .toList();

        // Filter by tab (Created, Attended, Registered)
        if (selectedTab == 1) {
          List<EventModel> neededEventsList = [];
          for (var element in EventsList) {
            if (element.customerUid == CustomerController.logeInCustomer!.uid) {
              neededEventsList.add(element);
            }
          }
          EventsList = neededEventsList;
        } else if (selectedTab == 3) {
          List<EventModel> neededEventsList = [];
          for (var element in EventsList) {
            if (preRegisteredEvent(eventId: element.id)) {
              neededEventsList.add(element);
            }
          }
          EventsList = neededEventsList;
        } else {
          List<EventModel> neededEventsList = [];
          for (var element in EventsList) {
            if (signedInEvent(eventId: element.id)) {
              neededEventsList.add(element);
            }
          }
          EventsList = neededEventsList;
        }

        // Apply category filtering
        if (selectedCategories.isNotEmpty) {
          EventsList = EventsList.where((event) => event.categories
                  .any((category) => selectedCategories.contains(category)))
              .toList();
        }

        // Apply sorting
        EventsList = _sortEvents(EventsList);

        if (EventsList.isEmpty) {
          return _buildEmptyState();
        }

        return ListView.builder(
          controller: _scrollController,
          padding: const EdgeInsets.symmetric(horizontal: 24),
          itemCount: EventsList.length,
          itemBuilder: (context, index) {
            return Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: _buildEventCard(EventsList[index]),
            );
          },
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
                      child: Image.network(
                        event.imageUrl,
                        fit: BoxFit.cover,
                        loadingBuilder: (context, child, loadingProgress) {
                          if (loadingProgress == null) return child;
                          return Container(
                            color: const Color(0xFFF5F7FA),
                            child: const Center(
                              child: CircularProgressIndicator(
                                color: Color(0xFF667EEA),
                              ),
                            ),
                          );
                        },
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
                              Icon(
                                Icons.star,
                                color: Colors.white,
                                size: 12,
                              ),
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
                    // Status badge based on tab
                    Positioned(
                      top: 12,
                      left: 12,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: _getStatusColor(),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              _getStatusIcon(),
                              color: Colors.white,
                              size: 12,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              _getStatusText(),
                              style: const TextStyle(
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
                        Expanded(
                          child: Text(
                            event.groupName,
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
                      children: [
                        Expanded(
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 8,
                            ),
                            decoration: BoxDecoration(
                              color: const Color(0xFF667EEA)
                                  .withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text(
                              DateFormat('MMM dd, yyyy\nKK:mm a')
                                  .format(event.selectedDateTime),
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
                              colors: [
                                Color(0xFF667EEA),
                                Color(0xFF764BA2),
                              ],
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

  Color _getStatusColor() {
    switch (selectedTab) {
      case 1:
        return const Color(0xFF667EEA); // Created - Blue
      case 2:
        return const Color(0xFF10B981); // Attended - Green
      case 3:
        return const Color(0xFFF59E0B); // Registered - Orange
      default:
        return const Color(0xFF667EEA);
    }
  }

  IconData _getStatusIcon() {
    switch (selectedTab) {
      case 1:
        return Icons.create;
      case 2:
        return Icons.check_circle;
      case 3:
        return Icons.event_available;
      default:
        return Icons.event;
    }
  }

  String _getStatusText() {
    switch (selectedTab) {
      case 1:
        return 'Created';
      case 2:
        return 'Attended';
      case 3:
        return 'Registered';
      default:
        return 'Event';
    }
  }

  Widget _buildSkeletonLoading() {
    return ListView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.symmetric(horizontal: 24),
      itemCount: 3,
      itemBuilder: (context, index) {
        return Padding(
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
        );
      },
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
    String title = '';
    String subtitle = '';
    IconData icon = Icons.event_busy;

    switch (selectedTab) {
      case 1:
        title = 'No events created yet';
        subtitle = 'Start creating amazing events for your community';
        icon = Icons.create;
        break;
      case 2:
        title = 'No events attended yet';
        subtitle = 'Join events to see them here';
        icon = Icons.check_circle;
        break;
      case 3:
        title = 'No events registered yet';
        subtitle = 'Register for events to see them here';
        icon = Icons.event_available;
        break;
    }

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
                icon,
                size: 50,
                color: const Color(0xFF667EEA),
              ),
            ),
            const SizedBox(height: 24),
            Text(
              title,
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
              subtitle,
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
                // Navigate to create event or explore events
                if (selectedTab == 1) {
                  // Navigate to create event
                  // You can add navigation here
                } else {
                  // Navigate to explore events
                  // You can add navigation here
                }
              },
              icon: Icon(selectedTab == 1 ? Icons.add : Icons.explore),
              label: Text(selectedTab == 1 ? 'Create Event' : 'Explore Events'),
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
                const Icon(
                  Icons.tune,
                  color: Color(0xFF667EEA),
                  size: 24,
                ),
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
                    child: const Icon(
                      Icons.close,
                      size: 20,
                    ),
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
              Icon(
                Icons.filter_list,
                color: const Color(0xFF667EEA),
                size: 16,
              ),
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
            Icon(
              Icons.category,
              color: const Color(0xFF667EEA),
              size: 20,
            ),
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
          Icon(
            icon,
            size: 16,
            color: isSelected ? Colors.white : color,
          ),
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
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(22),
      ),
    );
  }

  // Build sort section
  Widget _buildSortSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(
              Icons.sort,
              color: const Color(0xFF667EEA),
              size: 20,
            ),
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
        _buildSortOptionGroup(
          'Default',
          [SortOption.none],
        ),
        const SizedBox(height: 16),
        // Date Added section
        _buildSortOptionGroup(
          'Date Added',
          [
            SortOption.dateAddedDesc,
            SortOption.dateAddedAsc,
          ],
        ),
        const SizedBox(height: 16),
        // Title section
        _buildSortOptionGroup(
          'Title',
          [
            SortOption.titleAsc,
            SortOption.titleDesc,
          ],
        ),
        const SizedBox(height: 16),
        // Event Date section
        _buildSortOptionGroup(
          'Event Date',
          [
            SortOption.eventDateDesc,
            SortOption.eventDateAsc,
          ],
        ),
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
                  color:
                      isSelected ? const Color(0xFF667EEA) : Colors.grey[200]!,
                  width: 1,
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    _getSortOptionIcon(option),
                    color:
                        isSelected ? const Color(0xFF667EEA) : Colors.grey[600],
                    size: 20,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      _getSortOptionText(option),
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight:
                            isSelected ? FontWeight.w600 : FontWeight.w500,
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
