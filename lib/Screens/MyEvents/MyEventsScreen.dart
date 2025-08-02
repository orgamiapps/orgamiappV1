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
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'My',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w300,
                          fontSize: 24,
                          fontFamily: 'Roboto',
                        ),
                      ),
                      const Text(
                        'Events',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 28,
                          fontFamily: 'Roboto',
                        ),
                      ),
                    ],
                  ),
                ),
                // Calendar icon
                Container(
                  width: 50,
                  height: 50,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(25),
                  ),
                  child: const Icon(
                    Icons.event,
                    color: Colors.white,
                    size: 24,
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
        height: _tabBarOpacity > 0 ? 90 : 0, // Increased height to prevent overflow
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
          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4), // Reduced padding
          decoration: BoxDecoration(
            color: isSelected ? color : Colors.transparent,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center, // Center content vertically
            children: [
              Icon(
                icon,
                color: isSelected ? Colors.white : color,
                size: 18, // Slightly smaller icon
              ),
              const SizedBox(height: 2), // Reduced spacing
              Flexible( // Wrap text in Flexible to prevent overflow
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
            .toList()
          ..sort((a, b) => a.selectedDateTime.compareTo(b.selectedDateTime));

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
