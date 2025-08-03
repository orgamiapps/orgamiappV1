import 'dart:async';
import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:intl/intl.dart';
import 'package:orgami/Controller/CustomerController.dart';
import 'package:orgami/Firebase/FirebaseFirestoreHelper.dart';
import 'package:orgami/Models/AttendanceModel.dart';
import 'package:orgami/Models/EventModel.dart';
import 'package:orgami/Screens/Events/AddQuestionsToEventScreen.dart';
import 'package:orgami/Screens/Events/Attendance/AttendanceSheetScreen.dart';
import 'package:orgami/Screens/Events/Widget/AttendeesHorizontalList.dart';
import 'package:orgami/Screens/Events/Widget/PreRegisteredHorizontalList.dart';
import 'package:orgami/Screens/Events/Widget/CommentsSection.dart';
import 'package:orgami/Screens/Events/Widget/DeleteEventDialouge.dart';
import 'package:orgami/Screens/Events/Widget/QRDialouge.dart';
import 'package:orgami/Screens/Events/TicketManagementScreen.dart';
import 'package:orgami/Screens/MyProfile/MyTicketsScreen.dart';
import 'package:orgami/Screens/QRScanner/AnsQuestionsToSignInEventScreen.dart';
import 'package:orgami/Screens/QRScanner/QrScannerScreenForLogedIn.dart';
import 'package:orgami/Utils/Colors.dart';
import 'package:orgami/Utils/Router.dart';
import 'package:orgami/Utils/Toast.dart';
import 'package:orgami/Utils/dimensions.dart';
import 'package:orgami/Models/TicketModel.dart';
import 'package:rounded_loading_button_plus/rounded_loading_button.dart';
import 'package:orgami/Screens/MyEvents/MyEventsScreen.dart';
import 'package:orgami/Screens/Events/FeatureEventScreen.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:share_plus/share_plus.dart';

class SingleEventScreen extends StatefulWidget {
  final EventModel eventModel;
  const SingleEventScreen({super.key, required this.eventModel});

  @override
  State<SingleEventScreen> createState() => _SingleEventScreenState();
}

class _SingleEventScreenState extends State<SingleEventScreen>
    with TickerProviderStateMixin, WidgetsBindingObserver {
  late EventModel eventModel;
  late final double _screenWidth = MediaQuery.of(context).size.width;
  late final double _screenHeight = MediaQuery.of(context).size.height;
  bool? signedIn;
  bool? registered;
  final _btnCtlr = RoundedLoadingButtonController();
  bool _isAnonymousSignIn = false;
  bool _isAnonymousPreRegister = false;
  bool _isGettingTicket = false;
  bool _hasTicket = false;
  bool _isCheckingTicket = false;

  // Animation controllers
  late AnimationController _fadeController;
  late Animation<double> _fadeAnimation;
  late AnimationController _slideController;
  late Animation<Offset> _slideAnimation;

  double radians(double degrees) {
    return degrees * pi / 180.0;
  }

  int preRegisteredCount = 0;

  Future<void> getPreRegisterCount() async {
    await FirebaseFirestoreHelper()
        .getPreRegisterAttendanceCount(eventId: eventModel.id)
        .then((countValue) {
          setState(() {
            preRegisteredCount = countValue;
          });
        });
  }

  bool isInInRadius(LatLng center, double radiusInFeet, LatLng point) {
    double radiusInMeters = radiusInFeet * 0.3048; // Convert feet to meters
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

  Future<void> getAttendance() async {
    await FirebaseFirestoreHelper().checkIfUserIsSignedIn(eventModel.id).then((
      value,
    ) {
      print('Exist value is $value');
      setState(() {
        signedIn = value;
      });

      if (!signedIn! &&
          eventModel.getLocation &&
          eventModel.customerUid != CustomerController.logeInCustomer!.uid &&
          isInEventInTime()) {
        _getCurrentLocation();
      }
    });
  }

  Future<void> getRegisterAttendance() async {
    await FirebaseFirestoreHelper().checkIfUserIsRegistered(eventModel.id).then(
      (value) {
        print('Register Exist value is $value');
        setState(() {
          registered = value;
        });
      },
    );
  }

  bool isInEventInTime() {
    DateTime eventTime = eventModel.selectedDateTime;
    DateTime eventTimeHourBefore = eventTime.subtract(const Duration(hours: 1));
    DateTime eventTimeHourAfter = eventTime.add(const Duration(hours: 1));
    DateTime nowTime = DateTime.now();

    bool eventIsAfter = eventTimeHourBefore.isBefore(nowTime);

    print('$eventTimeHourBefore.isAfter($nowTime)');
    bool eventIsBefore = eventTimeHourAfter.isAfter(nowTime);

    print('$eventTimeHourAfter.isBefore($nowTime)');
    bool eventIsNow = eventTime.isAtSameMomentAs(nowTime);

    bool answer = false;
    if (eventIsNow || (eventIsBefore && eventIsAfter)) {
      answer = true;
    }

    print(
      'answer Is $answer  $eventIsNow || ($eventIsBefore && $eventIsAfter $nowTime -- $eventTimeHourBefore -- $eventTimeHourAfter)',
    );

    return answer;
  }

  Future<void> _getCurrentLocation() async {
    bool serviceEnabled;
    LocationPermission permission;

    serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      return Future.error('Location services are disabled.');
    }

    permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        return Future.error('Location permissions are denied');
      }
    }

    if (permission == LocationPermission.deniedForever) {
      // Permissions are denied forever, handle appropriately.
      return Future.error(
        'Location permissions are permanently denied, we cannot request permissions.',
      );
    }

    await Geolocator.getCurrentPosition().then((value) {
      LatLng newLatLng = LatLng(value.latitude, value.longitude);
      bool inRadius = isInInRadius(
        eventModel.getLatLng(),
        eventModel.radius,
        newLatLng,
      );
      if (inRadius) {
        _showSignInDialog();
      }
      print(
        'Current Location is  $inRadius and radius is ${widget.eventModel.radius}',
      );
    });
  }

  void _showSignInDialog() {
    showDialog(
      context: context,
      builder: (BuildContext dialogContext) {
        return StatefulBuilder(
          builder: (BuildContext context, StateSetter dialogSetState) {
            return Dialog(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20.0),
              ),
              elevation: 0,
              backgroundColor: Colors.transparent,
              child: Container(
                padding: const EdgeInsets.all(24.0),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(20.0),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.1),
                      spreadRadius: 0,
                      blurRadius: 20,
                      offset: const Offset(0, 10),
                    ),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 60,
                      height: 60,
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [Color(0xFF667EEA), Color(0xFF764BA2)],
                        ),
                        borderRadius: BorderRadius.circular(30),
                      ),
                      child: const Icon(
                        Icons.celebration,
                        color: Colors.white,
                        size: 30.0,
                      ),
                    ),
                    const SizedBox(height: 20),
                    Text(
                      "Welcome to ${eventModel.title}!",
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        fontFamily: 'Roboto',
                        color: Color(0xFF1A1A1A),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      "Tap 'Sign In' to confirm your attendance.",
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 16,
                        color: const Color(0xFF6B7280),
                        fontFamily: 'Roboto',
                      ),
                    ),
                    const SizedBox(height: 24),
                    // Anonymous checkbox
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF9FAFB),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: const Color(0xFFE5E7EB),
                          width: 1,
                        ),
                      ),
                      child: Row(
                        children: [
                          Checkbox(
                            value: _isAnonymousSignIn,
                            onChanged: (value) {
                              dialogSetState(() {
                                _isAnonymousSignIn = value ?? false;
                              });
                            },
                            activeColor: const Color(0xFF667EEA),
                          ),
                          const SizedBox(width: 12),
                          const Expanded(
                            child: Text(
                              'Sign In anonymously to public',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w500,
                                fontFamily: 'Roboto',
                                color: Color(0xFF1A1A1A),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 24),
                    Row(
                      children: [
                        Expanded(
                          child: Container(
                            height: 48,
                            decoration: BoxDecoration(
                              color: Colors.grey.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Material(
                              color: Colors.transparent,
                              child: InkWell(
                                borderRadius: BorderRadius.circular(12),
                                onTap: () {
                                  Navigator.of(context).pop();
                                },
                                child: const Center(
                                  child: Text(
                                    'Close',
                                    style: TextStyle(
                                      color: Color(0xFF6B7280),
                                      fontSize: 16,
                                      fontWeight: FontWeight.w600,
                                      fontFamily: 'Roboto',
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Container(
                            height: 48,
                            decoration: BoxDecoration(
                              gradient: const LinearGradient(
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                                colors: [Color(0xFF667EEA), Color(0xFF764BA2)],
                              ),
                              borderRadius: BorderRadius.circular(12),
                              boxShadow: [
                                BoxShadow(
                                  color: const Color(
                                    0xFF667EEA,
                                  ).withOpacity(0.3),
                                  spreadRadius: 0,
                                  blurRadius: 8,
                                  offset: const Offset(0, 2),
                                ),
                              ],
                            ),
                            child: Material(
                              color: Colors.transparent,
                              child: InkWell(
                                borderRadius: BorderRadius.circular(12),
                                onTap: makeSignInToEvent,
                                child: const Center(
                                  child: Text(
                                    'Sign In',
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontSize: 16,
                                      fontWeight: FontWeight.w600,
                                      fontFamily: 'Roboto',
                                    ),
                                  ),
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
            );
          },
        );
      },
    );
  }

  void makeSignInToEvent() async {
    try {
      _btnCtlr.start();

      // Ensure user is properly authenticated
      if (CustomerController.logeInCustomer == null) {
        _btnCtlr.reset();
        ShowToast().showNormalToast(msg: 'Please log in to sign in to events.');
        return;
      }

      String docId =
          '${eventModel.id}-${CustomerController.logeInCustomer!.uid}';

      print('=== SIGN-IN DEBUG ===');
      print('Event ID: ${eventModel.id}');
      print('User ID: ${CustomerController.logeInCustomer!.uid}');
      print('Document ID: $docId');

      AttendanceModel newAttendanceModel = AttendanceModel(
        id: docId,
        eventId: eventModel.id,
        userName: _isAnonymousSignIn
            ? 'Anonymous'
            : CustomerController.logeInCustomer!.name,
        customerUid: CustomerController.logeInCustomer!.uid,
        attendanceDateTime: DateTime.now(),
        answers: [],
        isAnonymous: _isAnonymousSignIn,
        realName: _isAnonymousSignIn
            ? CustomerController.logeInCustomer!.name
            : null,
      );

      print('Attendance model created: ${newAttendanceModel.toJson()}');

      // Check for sign-in prompts
      final questions = await FirebaseFirestoreHelper().getEventQuestions(
        eventId: eventModel.id,
      );
      if (questions.isNotEmpty) {
        _btnCtlr.reset(); // Reset before navigation
        RouterClass.nextScreenAndReplacement(
          context,
          AnsQuestionsToSignInEventScreen(
            eventModel: eventModel,
            newAttendance: newAttendanceModel,
            nextPageRoute: 'singleEventPopup',
          ),
        );
      } else {
        // No prompts, sign in directly
        try {
          print('Saving attendance to Firestore...');
          print('Collection: ${AttendanceModel.firebaseKey}');
          print('Document ID: ${newAttendanceModel.id}');
          print('Data: ${newAttendanceModel.toJson()}');

          await FirebaseFirestore.instance
              .collection(AttendanceModel.firebaseKey)
              .doc(newAttendanceModel.id)
              .set(newAttendanceModel.toJson());

          print('Attendance saved successfully!');
          _btnCtlr.success(); // Show success state
          ShowToast().showNormalToast(msg: 'Signed In Successfully!');

          // Refresh attendance status and stay on the same screen
          Future.delayed(const Duration(seconds: 1), () {
            _btnCtlr.reset();
            // Refresh attendance status
            getAttendance();
            // Refresh the current screen to show updated sign-in status
            setState(() {
              // Trigger a rebuild to show the updated UI
            });
          });
        } catch (firestoreError) {
          print('Firestore error during sign-in: $firestoreError');
          _btnCtlr.error();
          ShowToast().showNormalToast(
            msg:
                'Failed to save attendance: $firestoreError. Please try again.',
          );
          Future.delayed(const Duration(seconds: 2), () => _btnCtlr.reset());
        }
      }
    } catch (e) {
      print('Error is ${e.toString()}');
      _btnCtlr.error();
      ShowToast().showNormalToast(
        msg: 'Failed to sign in: $e. Please try again.',
      );
      Future.delayed(const Duration(seconds: 2), () => _btnCtlr.reset());
    }
  }

  @override
  void initState() {
    super.initState();

    // Add lifecycle observer to refresh data when screen is focused
    WidgetsBinding.instance.addObserver(this);

    // Initialize eventModel with the widget's eventModel
    eventModel = widget.eventModel;

    // Initialize animations
    _fadeController = AnimationController(
      duration: const Duration(milliseconds: 800),
      vsync: this,
    );
    _fadeAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(parent: _fadeController, curve: Curves.easeOut));

    _slideController = AnimationController(
      duration: const Duration(milliseconds: 600),
      vsync: this,
    );
    _slideAnimation = Tween<Offset>(
      begin: const Offset(0, 0.3),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _slideController, curve: Curves.easeOut));

    _fadeController.forward();
    _slideController.forward();

    getAttendance();
    getRegisterAttendance();
    getPreRegisterCount();
    checkUserTicket();
  }

  @override
  void dispose() {
    // Remove lifecycle observer
    WidgetsBinding.instance.removeObserver(this);

    _fadeController.dispose();
    _slideController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    // Refresh attendance data when app becomes active
    if (state == AppLifecycleState.resumed) {
      getAttendance();
      getRegisterAttendance();
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Refresh data when dependencies change (e.g., when navigating back to this screen)
    // Only refresh if the screen is mounted and visible
    if (mounted) {
      // Add a small delay to ensure the screen is fully visible
      Future.delayed(const Duration(milliseconds: 100), () {
        if (mounted) {
          getAttendance();
          getRegisterAttendance();
        }
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
          child: StreamBuilder<DocumentSnapshot>(
            stream: FirebaseFirestore.instance
                .collection(EventModel.firebaseKey)
                .doc(widget.eventModel.id)
                .snapshots(),
            builder: (context, snapshot) {
              if (snapshot.hasData && snapshot.data!.exists) {
                // Update the eventModel with real-time data
                final updatedEventModel = EventModel.fromJson(
                  snapshot.data!.data() as Map<String, dynamic>,
                );

                // Update the eventModel immediately
                eventModel = updatedEventModel;

                return _bodyView();
              } else if (snapshot.hasError) {
                // Fallback to the original eventModel if there's an error
                eventModel = widget.eventModel;
                return _bodyView();
              } else {
                // Show loading or fallback to original eventModel
                eventModel = widget.eventModel;
                return _bodyView();
              }
            },
          ),
        ),
      ),
    );
  }

  Widget _bodyView() {
    return SizedBox(
      width: _screenWidth,
      height: _screenHeight,
      child: Column(
        children: [
          _headerView(),
          Expanded(child: _contentView()),
          if (eventModel.customerUid == FirebaseAuth.instance.currentUser!.uid)
            _buildActionButtons(),
        ],
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
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 24),
      child: Column(
        children: [
          // Back button, title, and action buttons
          Row(
            children: [
              GestureDetector(
                onTap: () => Navigator.pop(context),
                child: Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: const Icon(
                    Icons.arrow_back_ios_new,
                    color: Colors.white,
                    size: 20,
                  ),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Text(
                  eventModel.title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    fontFamily: 'Roboto',
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (eventModel.customerUid ==
                  FirebaseAuth.instance.currentUser!.uid)
                Row(
                  children: [
                    GestureDetector(
                      onTap: () => showDialog(
                        context: context,
                        builder: (context) =>
                            DeleteEventDialoge(singleEvent: eventModel),
                      ),
                      child: Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: Colors.red.withOpacity(0.2),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: const Icon(
                          Icons.delete_forever_rounded,
                          color: Colors.white,
                          size: 20,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Tooltip(
                      message: 'Share QR Code & Event ID',
                      child: GestureDetector(
                        onTap: () => _showQuickShareOptions(),
                        child: Container(
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.2),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(
                              color: Colors.white.withOpacity(0.3),
                              width: 1,
                            ),
                          ),
                          child: const Icon(
                            Icons.qr_code_2_rounded,
                            color: Colors.white,
                            size: 20,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
            ],
          ),
          const SizedBox(height: 12),
          // Subtitle
          Text(
            eventModel.groupName,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 16,
              fontFamily: 'Roboto',
              height: 1.4,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _contentView() {
    return SlideTransition(
      position: _slideAnimation,
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            // Event Image
            _buildEventImage(),
            const SizedBox(height: 24),
            // Featured Badge
            if (eventModel.isFeatured) _buildFeaturedBadge(),
            const SizedBox(height: 24),
            // Event Details Card
            _buildEventDetailsCard(),
            const SizedBox(height: 24),
            // Categories
            if (eventModel.categories.isNotEmpty) _buildCategoriesCard(),
            const SizedBox(height: 24),
            // Sign In Section (for non-owners)
            if (eventModel.customerUid !=
                FirebaseAuth.instance.currentUser!.uid)
              if (signedIn != null)
                if (!signedIn!) _buildSignInSection(),
            const SizedBox(height: 24),
            // Ticket Section (for non-owners)
            if (eventModel.customerUid !=
                FirebaseAuth.instance.currentUser!.uid)
              if (eventModel.ticketsEnabled) _buildTicketSection(),
            const SizedBox(height: 24),
            // Attendees List
            AttendeesHorizontalList(eventModel: eventModel),
            const SizedBox(height: 24),
            // Pre-Registered List
            PreRegisteredHorizontalList(eventModel: eventModel),
            const SizedBox(height: 24),
            // Comments Section
            CommentsSection(eventModel: eventModel),
            const SizedBox(height: 100), // Space for bottom buttons
          ],
        ),
      ),
    );
  }

  Widget _buildEventImage() {
    return Container(
      width: double.infinity,
      height: 200,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            spreadRadius: 0,
            blurRadius: 20,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: CachedNetworkImage(
          imageUrl: eventModel.imageUrl,
          fit: BoxFit.cover,
          placeholder: (context, url) => Container(
            color: const Color(0xFFF5F7FA),
            child: const Center(
              child: CircularProgressIndicator(color: Color(0xFF667EEA)),
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
    );
  }

  Widget _buildFeaturedBadge() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFFFF9800), Color(0xFFFF5722)],
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFFFF9800).withOpacity(0.3),
            spreadRadius: 0,
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.star, color: Colors.white, size: 16),
          SizedBox(width: 8),
          Text(
            'Featured Event',
            style: TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
              fontSize: 14,
              fontFamily: 'Roboto',
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEventDetailsCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.08),
            spreadRadius: 0,
            blurRadius: 20,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Title
          Text(
            eventModel.title,
            style: const TextStyle(
              color: Color(0xFF1A1A1A),
              fontWeight: FontWeight.bold,
              fontSize: 24,
              fontFamily: 'Roboto',
            ),
          ),
          const SizedBox(height: 8),
          // Organizer
          Text(
            eventModel.groupName,
            style: const TextStyle(
              color: Color(0xFF6B7280),
              fontSize: 16,
              fontFamily: 'Roboto',
            ),
          ),
          const SizedBox(height: 20),
          // Event Details
          _buildDetailItem(
            icon: Icons.groups_rounded,
            label: 'Pre-Registered',
            value: '$preRegisteredCount people',
          ),
          const SizedBox(height: 16),
          _buildDetailItem(
            icon: Icons.calendar_month_rounded,
            label: 'Date',
            value: DateFormat(
              'EEEE, MMMM dd, yyyy',
            ).format(eventModel.selectedDateTime),
          ),
          const SizedBox(height: 16),
          _buildDetailItem(
            icon: Icons.access_time_rounded,
            label: 'Time',
            value: DateFormat('KK:mm a').format(eventModel.selectedDateTime),
          ),
          const SizedBox(height: 16),
          _buildDetailItem(
            icon: Icons.location_on,
            label: 'Location',
            value: eventModel.location,
          ),
          const SizedBox(height: 20),
          // Description
          Text(
            'Description',
            style: const TextStyle(
              color: Color(0xFF1A1A1A),
              fontWeight: FontWeight.w600,
              fontSize: 16,
              fontFamily: 'Roboto',
            ),
          ),
          const SizedBox(height: 8),
          Text(
            eventModel.description,
            style: const TextStyle(
              color: Color(0xFF4B5563),
              fontSize: 16,
              fontFamily: 'Roboto',
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDetailItem({
    required IconData icon,
    required String label,
    required String value,
  }) {
    return Row(
      children: [
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: const Color(0xFF667EEA).withOpacity(0.1),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(icon, color: const Color(0xFF667EEA), size: 20),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: const TextStyle(
                  color: Color(0xFF6B7280),
                  fontSize: 12,
                  fontFamily: 'Roboto',
                ),
              ),
              const SizedBox(height: 2),
              Text(
                value,
                style: const TextStyle(
                  color: Color(0xFF1A1A1A),
                  fontWeight: FontWeight.w600,
                  fontSize: 16,
                  fontFamily: 'Roboto',
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildCategoriesCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.08),
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
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: const Color(0xFF667EEA).withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.category,
                  color: Color(0xFF667EEA),
                  size: 20,
                ),
              ),
              const SizedBox(width: 16),
              const Text(
                'Categories',
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
            children: eventModel.categories.map((category) {
              return Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: const Color(0xFF667EEA).withOpacity(0.1),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: const Color(0xFF667EEA).withOpacity(0.3),
                    width: 1,
                  ),
                ),
                child: Text(
                  category,
                  style: const TextStyle(
                    color: Color(0xFF667EEA),
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    fontFamily: 'Roboto',
                  ),
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  Widget _buildSignInSection() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.08),
            spreadRadius: 0,
            blurRadius: 20,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: const Color(0xFF667EEA).withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.qr_code_scanner,
                  color: Color(0xFF667EEA),
                  size: 20,
                ),
              ),
              const SizedBox(width: 16),
              const Expanded(
                child: Text(
                  'Sign In to Event',
                  style: TextStyle(
                    color: Color(0xFF1A1A1A),
                    fontWeight: FontWeight.w600,
                    fontSize: 18,
                    fontFamily: 'Roboto',
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          const Text(
            'Enable location to auto sign-in when near the event, or scan QR code.',
            style: TextStyle(
              color: Color(0xFF6B7280),
              fontSize: 14,
              fontFamily: 'Roboto',
              height: 1.4,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 20),
          Container(
            width: double.infinity,
            height: 56,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0xFF667EEA), Color(0xFF764BA2)],
              ),
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF667EEA).withOpacity(0.3),
                  spreadRadius: 0,
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                borderRadius: BorderRadius.circular(16),
                onTap: () {
                  RouterClass.nextScreenAndReplacement(
                    context,
                    QrScannerScreenForLogedIn(),
                  );
                },
                child: const Center(
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        CupertinoIcons.qrcode_viewfinder,
                        color: Colors.white,
                        size: 24,
                      ),
                      SizedBox(width: 12),
                      Text(
                        'Scan QR Code to Sign In',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                          fontFamily: 'Roboto',
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTicketSection() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.08),
            spreadRadius: 0,
            blurRadius: 20,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: _hasTicket
                      ? const Color(0xFF10B981).withOpacity(0.1)
                      : const Color(0xFFFF9800).withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  _hasTicket ? Icons.check_circle : Icons.confirmation_number,
                  color: _hasTicket
                      ? const Color(0xFF10B981)
                      : const Color(0xFFFF9800),
                  size: 20,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Text(
                  _hasTicket ? 'Ticket Received' : 'Get Event Ticket',
                  style: const TextStyle(
                    color: Color(0xFF1A1A1A),
                    fontWeight: FontWeight.w600,
                    fontSize: 18,
                    fontFamily: 'Roboto',
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Text(
            _hasTicket
                ? 'You have a ticket for this event. Show the ticket code to the event host when you arrive.'
                : 'Get a free ticket for this event. Show the ticket code to the event host when you arrive.',
            style: const TextStyle(
              color: Color(0xFF6B7280),
              fontSize: 14,
              fontFamily: 'Roboto',
              height: 1.4,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 20),
          if (_isCheckingTicket)
            const Center(
              child: SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(
                  color: Color(0xFFFF9800),
                  strokeWidth: 2,
                ),
              ),
            )
          else if (_hasTicket)
            Container(
              width: double.infinity,
              height: 56,
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [Color(0xFF10B981), Color(0xFF059669)],
                ),
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF10B981).withOpacity(0.3),
                    spreadRadius: 0,
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  borderRadius: BorderRadius.circular(16),
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => const MyTicketsScreen(),
                      ),
                    );
                  },
                  child: const Center(
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.visibility, color: Colors.white, size: 24),
                        SizedBox(width: 12),
                        Text(
                          'View Ticket',
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                            fontFamily: 'Roboto',
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            )
          else
            Container(
              width: double.infinity,
              height: 56,
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [Color(0xFFFF9800), Color(0xFFFF5722)],
                ),
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFFFF9800).withOpacity(0.3),
                    spreadRadius: 0,
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  borderRadius: BorderRadius.circular(16),
                  onTap: _isGettingTicket ? null : _getTicket,
                  child: Center(
                    child: _isGettingTicket
                        ? const SizedBox(
                            width: 24,
                            height: 24,
                            child: CircularProgressIndicator(
                              color: Colors.white,
                              strokeWidth: 2,
                            ),
                          )
                        : const Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.confirmation_number,
                                color: Colors.white,
                                size: 24,
                              ),
                              SizedBox(width: 12),
                              Text(
                                'Get Ticket',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 16,
                                  fontFamily: 'Roboto',
                                ),
                              ),
                            ],
                          ),
                  ),
                ),
              ),
            ),
          const SizedBox(height: 12),
          // Debug button for testing
          Container(
            width: double.infinity,
            height: 40,
            decoration: BoxDecoration(
              color: Colors.grey.withOpacity(0.1),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.grey.withOpacity(0.3)),
            ),
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: _clearTicketsForTesting,
                child: const Center(
                  child: Text(
                    'Clear Tickets (Debug)',
                    style: TextStyle(
                      color: Colors.grey,
                      fontSize: 12,
                      fontFamily: 'Roboto',
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActionButtons() {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            spreadRadius: 0,
            blurRadius: 20,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Feature Event Button (for event owners)
          if (eventModel.customerUid == FirebaseAuth.instance.currentUser!.uid)
            if (!eventModel.isFeatured)
              Container(
                width: double.infinity,
                height: 56,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [Color(0xFFFF9800), Color(0xFFFF5722)],
                  ),
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFFFF9800).withOpacity(0.3),
                      spreadRadius: 0,
                      blurRadius: 12,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(16),
                    onTap: () {
                      RouterClass.nextScreenNormal(
                        context,
                        FeatureEventScreen(eventModel: eventModel),
                      );
                    },
                    child: const Center(
                      child: Text(
                        'Feature This Event',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                          fontFamily: 'Roboto',
                        ),
                      ),
                    ),
                  ),
                ),
              )
            else
              Container(
                width: double.infinity,
                height: 56,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [Color(0xFFFF9800), Color(0xFFFF5722)],
                  ),
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFFFF9800).withOpacity(0.3),
                      spreadRadius: 0,
                      blurRadius: 12,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: const Center(
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.star, color: Colors.white, size: 20),
                      SizedBox(width: 8),
                      Text(
                        'Featured',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                          fontFamily: 'Roboto',
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          if (eventModel.customerUid == FirebaseAuth.instance.currentUser!.uid)
            const SizedBox(height: 12),
          // Action Buttons Row
          Row(
            children: [
              // Add Questions Button
              if (eventModel.customerUid ==
                  FirebaseAuth.instance.currentUser!.uid)
                Expanded(
                  child: Container(
                    height: 56,
                    decoration: BoxDecoration(
                      color: const Color(0xFF667EEA).withOpacity(0.1),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: const Color(0xFF667EEA).withOpacity(0.3),
                        width: 1,
                      ),
                    ),
                    child: Material(
                      color: Colors.transparent,
                      child: InkWell(
                        borderRadius: BorderRadius.circular(16),
                        onTap: () => RouterClass.nextScreenNormal(
                          context,
                          AddQuestionsToEventScreen(eventModel: eventModel),
                        ),
                        child: const Center(
                          child: Text(
                            'Add Prompts',
                            style: TextStyle(
                              color: Color(0xFF667EEA),
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                              fontFamily: 'Roboto',
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              if (eventModel.customerUid ==
                  FirebaseAuth.instance.currentUser!.uid)
                const SizedBox(width: 12),
              // View Attendance Button
              if (eventModel.customerUid ==
                  FirebaseAuth.instance.currentUser!.uid)
                Expanded(
                  child: Container(
                    height: 56,
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [Color(0xFF667EEA), Color(0xFF764BA2)],
                      ),
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFF667EEA).withOpacity(0.3),
                          spreadRadius: 0,
                          blurRadius: 12,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Material(
                      color: Colors.transparent,
                      child: InkWell(
                        borderRadius: BorderRadius.circular(16),
                        onTap: () => RouterClass.nextScreenNormal(
                          context,
                          AttendanceSheetScreen(eventModel: eventModel),
                        ),
                        child: const Center(
                          child: Text(
                            'View Attendance',
                            style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                              fontFamily: 'Roboto',
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
          // Ticket Management Button (for event creators)
          if (eventModel.customerUid == FirebaseAuth.instance.currentUser!.uid)
            const SizedBox(height: 12),
          if (eventModel.customerUid == FirebaseAuth.instance.currentUser!.uid)
            Container(
              width: double.infinity,
              height: 56,
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [Color(0xFFFF9800), Color(0xFFFF5722)],
                ),
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFFFF9800).withOpacity(0.3),
                    spreadRadius: 0,
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  borderRadius: BorderRadius.circular(16),
                  onTap: () => RouterClass.nextScreenNormal(
                    context,
                    TicketManagementScreen(eventModel: eventModel),
                  ),
                  child: const Center(
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.confirmation_number,
                          color: Colors.white,
                          size: 20,
                        ),
                        SizedBox(width: 8),
                        Text(
                          'Manage Tickets',
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                            fontFamily: 'Roboto',
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          // Pre-Register Button (for non-owners)
          if (eventModel.customerUid != FirebaseAuth.instance.currentUser!.uid)
            if (registered != null)
              if (!registered!) ...[
                const SizedBox(height: 16),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF9FAFB),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: const Color(0xFFE5E7EB),
                      width: 1,
                    ),
                  ),
                  child: Row(
                    children: [
                      Checkbox(
                        value: _isAnonymousPreRegister,
                        onChanged: (value) {
                          setState(() {
                            _isAnonymousPreRegister = value ?? false;
                          });
                        },
                        activeColor: const Color(0xFF667EEA),
                      ),
                      const SizedBox(width: 12),
                      const Expanded(
                        child: Text(
                          'Pre-Register anonymously to public',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w500,
                            fontFamily: 'Roboto',
                            color: Color(0xFF1A1A1A),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                Container(
                  width: double.infinity,
                  height: 56,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [Color(0xFF667EEA), Color(0xFF764BA2)],
                    ),
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFF667EEA).withOpacity(0.3),
                        spreadRadius: 0,
                        blurRadius: 12,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Material(
                    color: Colors.transparent,
                    child: InkWell(
                      borderRadius: BorderRadius.circular(16),
                      onTap: () {
                        try {
                          String docId = FirebaseFirestore.instance
                              .collection(AttendanceModel.registerFirebaseKey)
                              .doc()
                              .id;
                          AttendanceModel newAttendanceMode = AttendanceModel(
                            id: docId,
                            eventId: eventModel.id,
                            userName: _isAnonymousPreRegister
                                ? 'Anonymous'
                                : CustomerController.logeInCustomer!.name,
                            customerUid: CustomerController.logeInCustomer!.uid,
                            attendanceDateTime: DateTime.now(),
                            answers: [],
                            isAnonymous: _isAnonymousPreRegister,
                            realName: _isAnonymousPreRegister
                                ? CustomerController.logeInCustomer!.name
                                : null,
                          );
                          FirebaseFirestore.instance
                              .collection(AttendanceModel.registerFirebaseKey)
                              .doc(docId)
                              .set(newAttendanceMode.toJson())
                              .then((value) {
                                ShowToast().showSnackBar(
                                  'Register Successful!',
                                  context,
                                );
                                Navigator.pop(context);
                              });
                        } catch (e) {
                          ShowToast().showNormalToast(
                            msg: 'Failed to register. Please try again.',
                          );
                        }
                      },
                      child: const Center(
                        child: Text(
                          'Pre-Register',
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                            fontFamily: 'Roboto',
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
        ],
      ),
    );
  }

  void _showQuickShareOptions() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.only(
            topLeft: Radius.circular(24),
            topRight: Radius.circular(24),
          ),
        ),
        child: SafeArea(
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
              const SizedBox(height: 24),
              // Title
              const Text(
                'Share Event',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: AppThemeColor.darkBlueColor,
                ),
              ),
              const SizedBox(height: 24),
              // Share options
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Column(
                  children: [
                    _buildShareOption(
                      icon: Icons.qr_code_2_rounded,
                      title: 'Share QR Code & Event ID',
                      subtitle: 'Generate QR code with event identifier',
                      onTap: () {
                        Navigator.pop(context);
                        showDialog(
                          context: context,
                          barrierDismissible: true,
                          builder: (context) =>
                              ShareQRDialog(singleEvent: eventModel),
                        );
                      },
                    ),
                    const SizedBox(height: 16),
                    _buildShareOption(
                      icon: Icons.share_rounded,
                      title: 'Share Event Details',
                      subtitle: 'Share event information',
                      onTap: () {
                        Navigator.pop(context);
                        _shareEventDetails();
                      },
                    ),
                    const SizedBox(height: 16),
                    _buildShareOption(
                      icon: Icons.copy_rounded,
                      title: 'Copy Event ID',
                      subtitle: 'Copy event identifier to clipboard',
                      onTap: () {
                        Navigator.pop(context);
                        _copyEventId();
                      },
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildShareOption({
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.grey[50],
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.grey[200]!),
        ),
        child: Row(
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: AppThemeColor.darkGreenColor.withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: AppThemeColor.darkGreenColor, size: 24),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: AppThemeColor.darkBlueColor,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: TextStyle(
                      fontSize: 14,
                      color: AppThemeColor.dullFontColor,
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              Icons.arrow_forward_ios,
              color: AppThemeColor.dullFontColor,
              size: 16,
            ),
          ],
        ),
      ),
    );
  }

  void _shareEventDetails() {
    HapticFeedback.lightImpact();
    final eventDetails =
        '''
🎉 Join my event!

📅 Event: ${eventModel.title}
📍 Location: ${eventModel.location}
🆔 Event ID: ${eventModel.rawId}
📝 Description: ${eventModel.description}

Join us for an amazing time!
    '''
            .trim();

    Share.share(
      eventDetails,
      subject: 'Event Invitation - ${eventModel.title}',
    );
  }

  void _copyEventId() {
    HapticFeedback.lightImpact();
    Clipboard.setData(ClipboardData(text: eventModel.rawId));
    ShowToast().showSnackBar('Event ID copied to clipboard', context);
  }

  Future<void> _getTicket() async {
    print('=== GET TICKET DEBUG ===');
    print('Customer logged in: ${CustomerController.logeInCustomer != null}');
    if (CustomerController.logeInCustomer != null) {
      print('Customer UID: ${CustomerController.logeInCustomer!.uid}');
      print('Customer Name: ${CustomerController.logeInCustomer!.name}');
    }
    print('Event ID: ${eventModel.id}');
    print('Event Title: ${eventModel.title}');
    print('Tickets Enabled: ${eventModel.ticketsEnabled}');
    print('Max Tickets: ${eventModel.maxTickets}');
    print('Issued Tickets: ${eventModel.issuedTickets}');

    if (CustomerController.logeInCustomer == null) {
      ShowToast().showNormalToast(msg: 'Please log in to get a ticket');
      return;
    }

    setState(() {
      _isGettingTicket = true;
    });

    try {
      final ticket = await FirebaseFirestoreHelper().issueTicket(
        eventId: eventModel.id,
        customerUid: CustomerController.logeInCustomer!.uid,
        customerName: CustomerController.logeInCustomer!.name,
        eventModel: eventModel,
      );

      if (mounted) {
        setState(() {
          _isGettingTicket = false;
        });

        if (ticket != null) {
          ShowToast().showNormalToast(msg: 'Ticket obtained successfully!');
          // Refresh ticket status
          checkUserTicket();
          // Navigate to MyTicketsScreen to show the new ticket
          Navigator.push(
            context,
            MaterialPageRoute(builder: (context) => const MyTicketsScreen()),
          );
        }
      }
    } catch (e) {
      print('Error in _getTicket: $e');
      if (mounted) {
        setState(() {
          _isGettingTicket = false;
        });
        ShowToast().showNormalToast(msg: 'Failed to get ticket: $e');
      }
    }
  }

  // Debug method to clear tickets for testing
  Future<void> _clearTicketsForTesting() async {
    if (CustomerController.logeInCustomer == null) {
      ShowToast().showNormalToast(msg: 'Please log in first');
      return;
    }

    try {
      await FirebaseFirestoreHelper().clearUserTickets(
        customerUid: CustomerController.logeInCustomer!.uid,
        eventId: eventModel.id,
      );
      ShowToast().showNormalToast(msg: 'Tickets cleared for testing');
      // Refresh ticket status after clearing
      checkUserTicket();
    } catch (e) {
      ShowToast().showNormalToast(msg: 'Failed to clear tickets: $e');
    }
  }

  Future<void> checkUserTicket() async {
    if (CustomerController.logeInCustomer == null) {
      return;
    }

    setState(() {
      _isCheckingTicket = true;
    });

    try {
      final userTickets = await FirebaseFirestoreHelper().getUserTickets(
        customerUid: CustomerController.logeInCustomer!.uid,
      );

      // Check if user has an active ticket for this event
      final hasActiveTicket = userTickets.any(
        (ticket) => ticket.eventId == eventModel.id && !ticket.isUsed,
      );

      if (mounted) {
        setState(() {
          _hasTicket = hasActiveTicket;
          _isCheckingTicket = false;
        });
      }
    } catch (e) {
      print('Error checking user ticket: $e');
      if (mounted) {
        setState(() {
          _isCheckingTicket = false;
        });
      }
    }
  }
}
