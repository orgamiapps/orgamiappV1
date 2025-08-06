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
import 'package:orgami/Firebase/DwellTimeTracker.dart';
import 'package:orgami/Firebase/FirebaseFirestoreHelper.dart';
import 'package:orgami/Models/AttendanceModel.dart';
import 'package:orgami/Models/CustomerModel.dart';
import 'package:orgami/Models/EventModel.dart';
import 'package:orgami/Models/EventQuestionModel.dart';
import 'package:orgami/Screens/Events/AddQuestionsToEventScreen.dart';
import 'package:orgami/Screens/Events/Attendance/AttendanceSheetScreen.dart';
import 'package:orgami/Screens/Events/Widget/AttendeesHorizontalList.dart';
import 'package:orgami/Screens/Events/Widget/CoHostManagementWidget.dart';
import 'package:orgami/Screens/Events/Widget/CommentsSection.dart';
// DeleteEventDialouge import removed - no longer needed in SingleEventScreen
import 'package:orgami/Screens/Events/Widget/QRDialouge.dart';
import 'package:orgami/Screens/Events/TicketManagementScreen.dart';
import 'package:orgami/Screens/Events/TicketScannerScreen.dart';
import 'package:orgami/Screens/Events/EventAnalyticsScreen.dart';
import 'package:orgami/Screens/Events/EventFeedbackScreen.dart';
import 'package:orgami/Screens/Events/EventFeedbackManagementScreen.dart';
import 'package:orgami/Screens/MyProfile/MyTicketsScreen.dart';
import 'package:orgami/Screens/MyProfile/UserProfileScreen.dart';
import 'package:orgami/Screens/QRScanner/AnsQuestionsToSignInEventScreen.dart';
import 'package:orgami/Screens/QRScanner/QrScannerScreenForLogedIn.dart';
import 'package:orgami/Screens/QRScanner/QRScannerFlowScreen.dart';
import 'package:orgami/Utils/Colors.dart';
import 'package:orgami/Utils/Router.dart';
import 'package:orgami/Utils/Toast.dart';
import 'package:orgami/Utils/dimensions.dart';
import 'package:orgami/Models/TicketModel.dart';
import 'package:rounded_loading_button_plus/rounded_loading_button.dart';

import 'package:orgami/Screens/Events/FeatureEventScreen.dart';
import 'package:orgami/Screens/Events/EditEventScreen.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

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
  final _btnCtlr = RoundedLoadingButtonController();
  bool _isAnonymousSignIn = false;
  bool _isGettingTicket = false;
  bool _hasTicket = false;
  bool _isCheckingTicket = false;
  bool _justSignedIn =
      false; // Flag to prevent showing sign-in dialog immediately after sign-in
  int _selectedTabIndex = 0;
  final TextEditingController _codeController = TextEditingController();
  // _isLoading removed - no longer needed after removing manual code input

  // Dwell time tracking variables
  final DwellTimeTracker _dwellTracker = DwellTimeTracker();
  bool _isDwellTrackingActive = false;
  String _dwellStatusMessage = '';
  bool _hasShownPrivacyDialog = false;
  AttendanceModel? _currentAttendance;

  // Animation controllers
  late AnimationController _fadeController;
  late Animation<double> _fadeAnimation;
  late AnimationController _slideController;
  late Animation<Offset> _slideAnimation;

  double radians(double degrees) {
    return degrees * pi / 180.0;
  }

  int preRegisteredCount = 0;
  int actualAttendanceCount = 0;
  int usedTicketsCount = 0;
  bool isLoadingSummary = false;

  // Favorite functionality
  bool _isFavorited = false;
  bool _isLoadingFavorite = false;

  // Attendees dropdown state
  bool _isAttendeesExpanded = false;

  Future<void> getPreRegisterCount() async {
    await FirebaseFirestoreHelper()
        .getPreRegisterAttendanceCount(eventId: eventModel.id)
        .then((countValue) {
          setState(() {
            preRegisteredCount = countValue;
          });
        });
  }

  Future<void> getActualAttendanceCount() async {
    try {
      final attendanceList = await FirebaseFirestoreHelper().getAttendance(
        eventId: eventModel.id,
      );
      setState(() {
        actualAttendanceCount = attendanceList.length;
      });
    } catch (e) {
      print('Error getting actual attendance: $e');
    }
  }

  Future<void> getUsedTicketsCount() async {
    try {
      final ticketsList = await FirebaseFirestoreHelper().getEventTickets(
        eventId: eventModel.id,
      );
      final usedTickets = ticketsList.where((ticket) => ticket.isUsed).length;
      setState(() {
        usedTicketsCount = usedTickets;
      });
    } catch (e) {
      print('Error getting used tickets: $e');
    }
  }

  Future<void> loadEventSummary() async {
    setState(() {
      isLoadingSummary = true;
    });

    await Future.wait([
      getPreRegisterCount(),
      getActualAttendanceCount(),
      getUsedTicketsCount(),
    ]);

    setState(() {
      isLoadingSummary = false;
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

      // Only show sign-in dialog if user is not signed in and meets all conditions
      // and hasn't just signed in (to prevent showing dialog immediately after sign-in)
      if (!signedIn! &&
          !_justSignedIn &&
          eventModel.getLocation &&
          eventModel.customerUid != CustomerController.logeInCustomer!.uid &&
          isInEventInTime()) {
        _getCurrentLocation();
      }

      // Check dwell tracking status if user is signed in
      if (signedIn! && CustomerController.logeInCustomer != null) {
        _checkDwellTrackingStatus();
      }
    });
  }

  /// Checks if dwell tracking is active for the current user
  Future<void> _checkDwellTrackingStatus() async {
    if (CustomerController.logeInCustomer == null) return;

    try {
      final attendanceList = await FirebaseFirestoreHelper().getAttendance(
        eventId: eventModel.id,
      );

      final userAttendance = attendanceList.firstWhere(
        (attendance) =>
            attendance.customerUid == CustomerController.logeInCustomer!.uid,
        orElse: () => AttendanceModel(
          id: '',
          userName: '',
          eventId: '',
          customerUid: '',
          attendanceDateTime: DateTime.now(),
          answers: [],
        ),
      );

      if (mounted) {
        setState(() {
          _currentAttendance = userAttendance.id.isNotEmpty
              ? userAttendance
              : null;
          _isDwellTrackingActive = userAttendance.isDwellActive;
        });
      }
    } catch (e) {
      print('Error checking dwell tracking status: $e');
    }
  }

  /// Shows privacy opt-in dialog for dwell tracking
  void _showPrivacyDialog() {
    if (_hasShownPrivacyDialog) return;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20.0),
          ),
          title: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: const Color(0xFF667EEA).withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.location_on,
                  color: Color(0xFF667EEA),
                  size: 24,
                ),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Text(
                  'Enable Dwell Tracking',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    fontFamily: 'Roboto',
                  ),
                ),
              ),
            ],
          ),
          content: const Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'This event uses location tracking to measure your time at the venue.',
                style: TextStyle(
                  fontSize: 16,
                  fontFamily: 'Roboto',
                  height: 1.4,
                ),
              ),
              SizedBox(height: 16),
              Text(
                'What we track:',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  fontFamily: 'Roboto',
                ),
              ),
              SizedBox(height: 8),
              Text(
                '• Entry and exit times\n'
                '• Total time spent at the event\n'
                '• Location within 200 feet of venue\n'
                '• Auto-stop when event ends',
                style: TextStyle(
                  fontSize: 14,
                  fontFamily: 'Roboto',
                  height: 1.4,
                ),
              ),
              SizedBox(height: 16),
              Text(
                'Privacy:',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  fontFamily: 'Roboto',
                ),
              ),
              SizedBox(height: 8),
              Text(
                '• Data is only visible to event organizers\n'
                '• Tracking stops automatically\n'
                '• You can manually stop tracking anytime',
                style: TextStyle(
                  fontSize: 14,
                  fontFamily: 'Roboto',
                  height: 1.4,
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
                setState(() {
                  _hasShownPrivacyDialog = true;
                });
              },
              child: const Text(
                'Decline',
                style: TextStyle(
                  color: Color(0xFF6B7280),
                  fontFamily: 'Roboto',
                ),
              ),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.of(context).pop();
                _startDwellTracking();
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF667EEA),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: const Text(
                'Enable Tracking',
                style: TextStyle(color: Colors.white, fontFamily: 'Roboto'),
              ),
            ),
          ],
        );
      },
    );
  }

  /// Starts dwell time tracking
  Future<void> _startDwellTracking() async {
    if (CustomerController.logeInCustomer == null) {
      ShowToast().showNormalToast(
        msg: 'Please log in to enable dwell tracking',
      );
      return;
    }

    try {
      await _dwellTracker.startDwellTracking(
        eventId: eventModel.id,
        customerUid: CustomerController.logeInCustomer!.uid,
        eventModel: eventModel,
        onStatusUpdate: (String status) {
          if (mounted) {
            setState(() {
              _dwellStatusMessage = status;
            });
          }
        },
      );

      if (mounted) {
        setState(() {
          _isDwellTrackingActive = true;
          _hasShownPrivacyDialog = true;
        });
      }

      ShowToast().showNormalToast(msg: 'Dwell tracking started');
    } catch (e) {
      ShowToast().showNormalToast(msg: 'Failed to start dwell tracking: $e');
    }
  }

  /// Stops dwell time tracking
  Future<void> _stopDwellTracking() async {
    if (CustomerController.logeInCustomer == null) return;

    try {
      await _dwellTracker.stopDwellTracking(
        eventId: eventModel.id,
        customerUid: CustomerController.logeInCustomer!.uid,
        notes: 'Manual check-out',
      );

      if (mounted) {
        setState(() {
          _isDwellTrackingActive = false;
          _dwellStatusMessage = '';
        });
      }

      ShowToast().showNormalToast(msg: 'Dwell tracking stopped');
    } catch (e) {
      ShowToast().showNormalToast(msg: 'Failed to stop dwell tracking: $e');
    }
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
        entryTimestamp: eventModel.getLocation ? DateTime.now() : null,
        dwellStatus: eventModel.getLocation ? 'active' : null,
        dwellNotes: eventModel.getLocation ? 'Geofence entry detected' : null,
      );

      print('Attendance model created: ${newAttendanceModel.toJson()}');

      // Check for sign-in prompts
      final questions = await FirebaseFirestoreHelper().getEventQuestions(
        eventId: eventModel.id,
      );
      if (questions.isNotEmpty) {
        _btnCtlr.reset(); // Reset before showing modal
        _showSignInQuestionsModal(newAttendanceModel, questions);
      } else {
        // No prompts, sign in directly
        await _performSignIn(newAttendanceModel);
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

  Future<void> _performSignIn(AttendanceModel attendanceModel) async {
    try {
      print('Saving attendance to Firestore...');
      print('Collection: ${AttendanceModel.firebaseKey}');
      print('Document ID: ${attendanceModel.id}');
      print('Data: ${attendanceModel.toJson()}');

      await FirebaseFirestore.instance
          .collection(AttendanceModel.firebaseKey)
          .doc(attendanceModel.id)
          .set(attendanceModel.toJson());

      print('Attendance saved successfully!');
      _btnCtlr.success(); // Show success state
      ShowToast().showNormalToast(msg: 'Signed In Successfully!');

      // Set flag to prevent showing sign-in dialog immediately after sign-in
      setState(() {
        _justSignedIn = true;
      });

      // Refresh attendance status and stay on the same screen
      Future.delayed(const Duration(seconds: 2), () {
        _btnCtlr.reset();
        // Refresh attendance status with a longer delay to ensure Firestore write is committed
        getAttendance();
        getActualAttendanceCount();
        // Reset the flag after a delay
        Future.delayed(const Duration(seconds: 3), () {
          setState(() {
            _justSignedIn = false;
          });
        });
        // Refresh the current screen to show updated sign-in status
        setState(() {
          // Trigger a rebuild to show the updated UI
        });

        // Show privacy dialog for dwell tracking if event has location enabled
        if (eventModel.getLocation && !_hasShownPrivacyDialog) {
          Future.delayed(const Duration(seconds: 4), () {
            if (mounted) {
              _showPrivacyDialog();
            }
          });
        }
      });
    } catch (firestoreError) {
      print('Firestore error during sign-in: $firestoreError');
      _btnCtlr.error();
      ShowToast().showNormalToast(
        msg: 'Failed to save attendance: $firestoreError. Please try again.',
      );
      Future.delayed(const Duration(seconds: 2), () => _btnCtlr.reset());
    }
  }

  void _showSignInQuestionsModal(
    AttendanceModel attendanceModel,
    List<EventQuestionModel> questions,
  ) {
    final GlobalKey<FormState> formKey = GlobalKey<FormState>();
    final List<TextEditingController> textControllers = [];
    final RoundedLoadingButtonController modalBtnController =
        RoundedLoadingButtonController();

    // Initialize text controllers
    for (int i = 0; i < questions.length; i++) {
      textControllers.add(TextEditingController());
    }

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        height: MediaQuery.of(context).size.height * 0.85,
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.only(
            topLeft: Radius.circular(20),
            topRight: Radius.circular(20),
          ),
        ),
        child: Column(
          children: [
            // Handle bar
            Container(
              margin: const EdgeInsets.only(top: 12),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: AppThemeColor.dullBlueColor.withOpacity(0.3),
                borderRadius: BorderRadius.circular(2),
              ),
            ),

            // Header
            Container(
              padding: const EdgeInsets.all(20),
              child: Row(
                children: [
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: AppThemeColor.darkBlueColor.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(
                      Icons.question_answer,
                      color: AppThemeColor.darkBlueColor,
                      size: 24,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Event Questions',
                          style: const TextStyle(
                            color: AppThemeColor.pureBlackColor,
                            fontSize: 20,
                            fontWeight: FontWeight.w600,
                            fontFamily: 'Roboto',
                          ),
                        ),
                        Text(
                          'Please answer the following questions to complete your sign-in',
                          style: const TextStyle(
                            color: AppThemeColor.dullFontColor,
                            fontSize: 14,
                            fontFamily: 'Roboto',
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(
                      Icons.close,
                      color: AppThemeColor.dullFontColor,
                    ),
                  ),
                ],
              ),
            ),

            // Questions Form
            Expanded(
              child: Form(
                key: formKey,
                child: ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  itemCount: questions.length,
                  itemBuilder: (context, index) {
                    final question = questions[index];
                    final isRequired = question.required;

                    return Container(
                      margin: const EdgeInsets.only(bottom: 16),
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: AppThemeColor.borderColor,
                          width: 1,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.02),
                            spreadRadius: 0,
                            blurRadius: 4,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Question Header
                          Row(
                            children: [
                              Container(
                                width: 32,
                                height: 32,
                                decoration: BoxDecoration(
                                  color: AppThemeColor.darkBlueColor,
                                  borderRadius: BorderRadius.circular(16),
                                ),
                                child: Center(
                                  child: Text(
                                    '${index + 1}',
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 14,
                                      fontWeight: FontWeight.w600,
                                      fontFamily: 'Roboto',
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  question.questionTitle,
                                  style: const TextStyle(
                                    color: AppThemeColor.pureBlackColor,
                                    fontSize: 16,
                                    fontWeight: FontWeight.w600,
                                    fontFamily: 'Roboto',
                                  ),
                                ),
                              ),
                              if (isRequired)
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 4,
                                  ),
                                  decoration: BoxDecoration(
                                    color: AppThemeColor.orangeColor
                                        .withOpacity(0.1),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: const Text(
                                    'Required',
                                    style: TextStyle(
                                      color: AppThemeColor.orangeColor,
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                      fontFamily: 'Roboto',
                                    ),
                                  ),
                                )
                              else
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 4,
                                  ),
                                  decoration: BoxDecoration(
                                    color: AppThemeColor.dullFontColor
                                        .withOpacity(0.1),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: const Text(
                                    'Optional',
                                    style: TextStyle(
                                      color: AppThemeColor.dullFontColor,
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                      fontFamily: 'Roboto',
                                    ),
                                  ),
                                ),
                            ],
                          ),

                          const SizedBox(height: 16),

                          // Answer Input
                          TextFormField(
                            controller: textControllers[index],
                            decoration: InputDecoration(
                              hintText: 'Type your answer here...',
                              hintStyle: TextStyle(
                                color: AppThemeColor.dullFontColor.withOpacity(
                                  0.6,
                                ),
                                fontFamily: 'Roboto',
                              ),
                              filled: true,
                              fillColor: AppThemeColor.lightBlueColor
                                  .withOpacity(0.1),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                                borderSide: BorderSide(
                                  color: AppThemeColor.borderColor,
                                  width: 1,
                                ),
                              ),
                              enabledBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                                borderSide: BorderSide(
                                  color: AppThemeColor.borderColor,
                                  width: 1,
                                ),
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                                borderSide: BorderSide(
                                  color: AppThemeColor.darkBlueColor,
                                  width: 2,
                                ),
                              ),
                              errorBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                                borderSide: BorderSide(
                                  color: AppThemeColor.orangeColor,
                                  width: 1,
                                ),
                              ),
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 16,
                              ),
                            ),
                            maxLines: 3,
                            validator: (value) {
                              if (isRequired &&
                                  (value == null || value.trim().isEmpty)) {
                                return 'This question is required';
                              }
                              return null;
                            },
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
            ),

            // Sign In Button
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.white,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.05),
                    spreadRadius: 0,
                    blurRadius: 10,
                    offset: const Offset(0, -2),
                  ),
                ],
              ),
              child: SafeArea(
                child: RoundedLoadingButton(
                  animateOnTap: true,
                  borderRadius: 12,
                  width: double.infinity,
                  controller: modalBtnController,
                  onPressed: () async {
                    if (formKey.currentState!.validate()) {
                      formKey.currentState!.save();

                      // Collect answers
                      for (int i = 0; i < questions.length; i++) {
                        final answer = textControllers[i].text.trim();
                        if (answer.isNotEmpty) {
                          attendanceModel.answers.add(
                            '${questions[i].questionTitle}--ans--$answer',
                          );
                        }
                      }

                      // Close modal and perform sign-in
                      Navigator.pop(context);
                      await _performSignIn(attendanceModel);
                    } else {
                      modalBtnController.reset();
                    }
                  },
                  color: AppThemeColor.darkBlueColor,
                  elevation: 0,
                  child: const Text(
                    'Sign In',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: Colors.white,
                      fontFamily: 'Roboto',
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
    getPreRegisterCount();
    checkUserTicket(updateUI: true);
    loadEventSummary();

    // Check if event is favorited
    _checkFavoriteStatus();
  }

  // Favorite functionality methods
  Future<void> _checkFavoriteStatus() async {
    if (CustomerController.logeInCustomer == null) return;

    try {
      final isFavorited = await FirebaseFirestoreHelper().isEventFavorited(
        userId: CustomerController.logeInCustomer!.uid,
        eventId: eventModel.id,
      );

      if (mounted) {
        setState(() {
          _isFavorited = isFavorited;
        });
      }
    } catch (e) {
      print('Error checking favorite status: $e');
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
          eventId: eventModel.id,
        );
      } else {
        success = await FirebaseFirestoreHelper().addToFavorites(
          userId: CustomerController.logeInCustomer!.uid,
          eventId: eventModel.id,
        );
      }

      if (mounted) {
        setState(() {
          _isFavorited = !_isFavorited;
          _isLoadingFavorite = false;
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
      print('Error toggling favorite: $e');
    }
  }

  @override
  void dispose() {
    // Remove lifecycle observer
    WidgetsBinding.instance.removeObserver(this);

    _fadeController.dispose();
    _slideController.dispose();

    // Dispose dwell tracker
    _dwellTracker.dispose();

    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    // Refresh attendance data when app becomes active
    if (state == AppLifecycleState.resumed) {
      getAttendance();
      getActualAttendanceCount();
      checkUserTicket(updateUI: true); // Also refresh ticket status
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
          getActualAttendanceCount();
          checkUserTicket(updateUI: true); // Also refresh ticket status
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      floatingActionButton:
          eventModel.hasManagementPermissions(
            FirebaseAuth.instance.currentUser!.uid,
          )
          ? _buildFloatingActionButton()
          : null,
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

  Widget _buildFloatingActionButton() {
    return Container(
      margin: const EdgeInsets.only(
        bottom: 20,
      ), // Reduced margin since no bottom buttons
      child: FloatingActionButton.extended(
        onPressed: () => _showEventManagementModal(),
        backgroundColor: const Color(0xFF667EEA),
        foregroundColor: Colors.white,
        elevation: 8,
        icon: const Icon(Icons.dashboard),
        label: const Text(
          'Manage Event',
          style: TextStyle(fontWeight: FontWeight.w600, fontFamily: 'Roboto'),
        ),
      ),
    );
  }

  void _showQuickActionsMenu() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        decoration: BoxDecoration(
          color: Theme.of(context).cardColor,
          borderRadius: const BorderRadius.only(
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
                'Quick Actions',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF1A1A1A),
                  fontFamily: 'Roboto',
                ),
              ),
              const SizedBox(height: 24),
              // Action options
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Column(
                  children: [
                    _buildQuickActionOption(
                      icon: Icons.qr_code_scanner,
                      title: 'Scan QR Codes',
                      subtitle: 'Scan attendee QR codes',
                      onTap: () {
                        Navigator.pop(context);
                        RouterClass.nextScreenNormal(
                          context,
                          QrScannerScreenForLogedIn(),
                        );
                      },
                    ),
                    const SizedBox(height: 12),
                    _buildQuickActionOption(
                      icon: Icons.analytics,
                      title: 'Event Analytics',
                      subtitle: 'View event performance',
                      onTap: () {
                        Navigator.pop(context);
                        RouterClass.nextScreenNormal(
                          context,
                          EventAnalyticsScreen(eventId: eventModel.id),
                        );
                      },
                    ),
                    const SizedBox(height: 12),
                    _buildQuickActionOption(
                      icon: Icons.edit,
                      title: 'Edit Event',
                      subtitle: 'Modify event details',
                      onTap: () {
                        Navigator.pop(context);
                        RouterClass.nextScreenNormal(
                          context,
                          EditEventScreen(eventModel: eventModel),
                        );
                      },
                    ),
                    const SizedBox(height: 12),
                    _buildQuickActionOption(
                      icon: Icons.star,
                      title: 'Event Feedback',
                      subtitle: 'Rate and comment on this event',
                      onTap: () {
                        Navigator.pop(context);
                        RouterClass.nextScreenNormal(
                          context,
                          EventFeedbackScreen(eventModel: eventModel),
                        );
                      },
                    ),
                    const SizedBox(height: 12),
                    _buildQuickActionOption(
                      icon: Icons.share,
                      title: 'Share Event',
                      subtitle: 'Share with attendees',
                      onTap: () {
                        Navigator.pop(context);
                        _showQuickShareOptions();
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

  Widget _buildQuickActionOption({
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
          color: const Color(0xFFF8F9FA),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFFE5E7EB), width: 1),
        ),
        child: Row(
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: const Color(0xFF667EEA).withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: const Color(0xFF667EEA), size: 24),
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
                      color: Color(0xFF1A1A1A),
                      fontFamily: 'Roboto',
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: const TextStyle(
                      fontSize: 14,
                      color: Color(0xFF6B7280),
                      fontFamily: 'Roboto',
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              Icons.arrow_forward_ios,
              color: const Color(0xFF6B7280),
              size: 16,
            ),
          ],
        ),
      ),
    );
  }

  Widget _bodyView() {
    return SafeArea(
      child: SizedBox(
        width: _screenWidth,
        height: _screenHeight,
        child: Column(
          children: [
            _headerView(),
            Expanded(child: _contentView()),
            // Remove the large action buttons section from bottom
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
              const Expanded(child: SizedBox()),
              if (eventModel.hasManagementPermissions(
                FirebaseAuth.instance.currentUser!.uid,
              ))
                Row(
                  children: [
                    Tooltip(
                      message: 'Event Management',
                      child: GestureDetector(
                        onTap: () => _showEventManagementModal(),
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
                            Icons.dashboard,
                            color: Colors.white,
                            size: 20,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Tooltip(
                      message: _isFavorited
                          ? 'Remove from Saved'
                          : 'Add to Saved',
                      child: GestureDetector(
                        onTap: _isLoadingFavorite ? null : _toggleFavorite,
                        child: Container(
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(
                            color: _isFavorited
                                ? Colors.red.withOpacity(0.2)
                                : Colors.white.withOpacity(0.2),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(
                              color: _isFavorited
                                  ? Colors.red.withOpacity(0.3)
                                  : Colors.white.withOpacity(0.3),
                              width: 1,
                            ),
                          ),
                          child: _isLoadingFavorite
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    valueColor: AlwaysStoppedAnimation<Color>(
                                      Colors.white,
                                    ),
                                  ),
                                )
                              : Icon(
                                  _isFavorited
                                      ? Icons.bookmark
                                      : Icons.bookmark_border,
                                  color: _isFavorited
                                      ? Colors.red
                                      : Colors.white,
                                  size: 20,
                                ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Tooltip(
                      message: 'Share Event',
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
                            Icons.share_rounded,
                            color: Colors.white,
                            size: 20,
                          ),
                        ),
                      ),
                    ),
                  ],
                )
              else
                // Calendar, Favorite, and Share buttons for non-creators
                Row(
                  children: [
                    Tooltip(
                      message: 'Add to Calendar',
                      child: GestureDetector(
                        onTap: () => _addToCalendar(),
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
                            Icons.calendar_today,
                            color: Colors.white,
                            size: 20,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Tooltip(
                      message: _isFavorited
                          ? 'Remove from Saved'
                          : 'Add to Saved',
                      child: GestureDetector(
                        onTap: _isLoadingFavorite ? null : _toggleFavorite,
                        child: Container(
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(
                            color: _isFavorited
                                ? Colors.red.withOpacity(0.2)
                                : Colors.white.withOpacity(0.2),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(
                              color: _isFavorited
                                  ? Colors.red.withOpacity(0.3)
                                  : Colors.white.withOpacity(0.3),
                              width: 1,
                            ),
                          ),
                          child: _isLoadingFavorite
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    valueColor: AlwaysStoppedAnimation<Color>(
                                      Colors.white,
                                    ),
                                  ),
                                )
                              : Icon(
                                  _isFavorited
                                      ? Icons.bookmark
                                      : Icons.bookmark_border,
                                  color: _isFavorited
                                      ? Colors.red
                                      : Colors.white,
                                  size: 20,
                                ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Tooltip(
                      message: 'Share Event',
                      child: GestureDetector(
                        onTap: () => _shareEventDetails(),
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
                            Icons.share_rounded,
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
          // Subtitle removed
        ],
      ),
    );
  }

  Widget _contentView() {
    return SlideTransition(
      position: _slideAnimation,
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        physics: const BouncingScrollPhysics(),
        child: Column(
          children: [
            // Event Image
            _buildEventImage(),
            const SizedBox(height: 24),

            // Featured Badge
            if (eventModel.isFeatured) _buildFeaturedBadge(),
            if (eventModel.isFeatured) const SizedBox(height: 24),

            // Event Details Card
            _buildEventDetailsCard(),
            const SizedBox(height: 24),

            // Categories
            if (eventModel.categories.isNotEmpty) _buildCategoriesCard(),
            if (eventModel.categories.isNotEmpty) const SizedBox(height: 24),

            // Tabbed Content Section (only for non-creators)
            if (!eventModel.hasManagementPermissions(
              FirebaseAuth.instance.currentUser!.uid,
            ))
              _buildTabbedContentSection(),

            // Attendees List (for everyone) - Now as dropdown
            _buildAttendeesDropdown(),
            const SizedBox(height: 24),

            // Comments Section (for everyone)
            CommentsSection(eventModel: eventModel),
            const SizedBox(height: 24),

            // Dwell Tracking Section (for signed-in users)
            if (signedIn == true && CustomerController.logeInCustomer != null)
              _buildDwellTrackingSection(),

            const SizedBox(height: 140), // Increased space for bottom buttons
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
          // Title and Edit/Delete Buttons (for creators)
          Row(
            children: [
              Expanded(
                child: Text(
                  eventModel.title,
                  style: const TextStyle(
                    color: Color(0xFF1A1A1A),
                    fontWeight: FontWeight.bold,
                    fontSize: 24,
                    fontFamily: 'Roboto',
                  ),
                ),
              ),
              if (eventModel.hasManagementPermissions(
                FirebaseAuth.instance.currentUser!.uid,
              ))
                Row(
                  children: [
                    GestureDetector(
                      onTap: () => RouterClass.nextScreenNormal(
                        context,
                        EditEventScreen(eventModel: eventModel),
                      ),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFF667EEA).withOpacity(0.1),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: const Color(0xFF667EEA),
                            width: 1,
                          ),
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.edit,
                              color: Color(0xFF667EEA),
                              size: 16,
                            ),
                            SizedBox(width: 4),
                            Text(
                              'Edit',
                              style: TextStyle(
                                color: Color(0xFF667EEA),
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                fontFamily: 'Roboto',
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    // Delete button moved to EditEventScreen
                  ],
                ),
            ],
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
          const SizedBox(height: 16),
          // Ticket Quantity Display
          if (eventModel.ticketsEnabled) _buildTicketQuantityItem(),
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
          const SizedBox(height: 20),
          // Feedback Button (for attendees only)
          if (!eventModel.hasManagementPermissions(
            FirebaseAuth.instance.currentUser!.uid,
          ))
            _buildFeedbackButton(),
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

  Widget _buildTicketQuantityItem() {
    final int issued = eventModel.issuedTickets;
    final int max = eventModel.maxTickets;
    final bool hasMaxLimit = max > 0;
    final double percentage = hasMaxLimit ? (issued / max) * 100 : 0.0;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFFF9800).withOpacity(0.05),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: const Color(0xFFFF9800).withOpacity(0.2),
          width: 1,
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: const Color(0xFFFF9800).withOpacity(0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(
              Icons.confirmation_number,
              color: Color(0xFFFF9800),
              size: 20,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Tickets Issued',
                  style: const TextStyle(
                    color: Color(0xFF6B7280),
                    fontSize: 12,
                    fontFamily: 'Roboto',
                  ),
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Text(
                      '$issued',
                      style: const TextStyle(
                        color: Color(0xFF1A1A1A),
                        fontWeight: FontWeight.bold,
                        fontSize: 18,
                        fontFamily: 'Roboto',
                      ),
                    ),
                    if (hasMaxLimit) ...[
                      const Text(
                        ' / ',
                        style: TextStyle(
                          color: Color(0xFF6B7280),
                          fontWeight: FontWeight.w500,
                          fontSize: 16,
                          fontFamily: 'Roboto',
                        ),
                      ),
                      Text(
                        '$max',
                        style: const TextStyle(
                          color: Color(0xFF6B7280),
                          fontWeight: FontWeight.w500,
                          fontSize: 16,
                          fontFamily: 'Roboto',
                        ),
                      ),
                    ],
                  ],
                ),
                if (hasMaxLimit) ...[
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: LinearProgressIndicator(
                          value: percentage / 100,
                          backgroundColor: const Color(
                            0xFFFF9800,
                          ).withOpacity(0.2),
                          valueColor: const AlwaysStoppedAnimation<Color>(
                            Color(0xFFFF9800),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        '${percentage.toInt()}%',
                        style: const TextStyle(
                          color: Color(0xFFFF9800),
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          fontFamily: 'Roboto',
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFeedbackButton() {
    return FutureBuilder<bool>(
      future: FirebaseFirestoreHelper().hasUserSubmittedFeedback(
        eventId: eventModel.id,
        userId: FirebaseAuth.instance.currentUser?.uid ?? '',
      ),
      builder: (context, snapshot) {
        final hasSubmittedFeedback = snapshot.data ?? false;

        return GestureDetector(
          onTap: hasSubmittedFeedback
              ? null
              : () {
                  RouterClass.nextScreenNormal(
                    context,
                    EventFeedbackScreen(eventModel: eventModel),
                  );
                },
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: hasSubmittedFeedback
                  ? Colors.grey[100]
                  : const Color(0xFF667EEA).withOpacity(0.1),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: hasSubmittedFeedback
                    ? Colors.grey[300]!
                    : const Color(0xFF667EEA),
                width: 1,
              ),
            ),
            child: Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: hasSubmittedFeedback
                        ? Colors.grey[300]
                        : const Color(0xFF667EEA).withOpacity(0.2),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    hasSubmittedFeedback ? Icons.check_circle : Icons.star,
                    color: hasSubmittedFeedback
                        ? Colors.grey[600]
                        : const Color(0xFF667EEA),
                    size: 20,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        hasSubmittedFeedback
                            ? 'Feedback Submitted'
                            : 'Rate This Event',
                        style: TextStyle(
                          color: hasSubmittedFeedback
                              ? Colors.grey[600]
                              : const Color(0xFF1A1A1A),
                          fontWeight: FontWeight.w600,
                          fontSize: 16,
                          fontFamily: 'Roboto',
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        hasSubmittedFeedback
                            ? 'Thank you for your feedback!'
                            : 'Share your experience and help improve future events',
                        style: TextStyle(
                          color: hasSubmittedFeedback
                              ? Colors.grey[500]
                              : const Color(0xFF6B7280),
                          fontSize: 14,
                          fontFamily: 'Roboto',
                        ),
                      ),
                    ],
                  ),
                ),
                if (!hasSubmittedFeedback)
                  Icon(
                    Icons.arrow_forward_ios,
                    color: const Color(0xFF6B7280),
                    size: 16,
                  ),
              ],
            ),
          ),
        );
      },
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
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF10B981), Color(0xFF059669)],
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF10B981).withOpacity(0.3),
            spreadRadius: 0,
            blurRadius: 20,
            offset: const Offset(0, 8),
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
                  color: Colors.white.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.qr_code_scanner,
                  color: Colors.white,
                  size: 20,
                ),
              ),
              const SizedBox(width: 16),
              const Expanded(
                child: Text(
                  'Sign In to Event',
                  style: TextStyle(
                    color: Colors.white,
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
              color: Colors.white,
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
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.1),
                  spreadRadius: 0,
                  blurRadius: 8,
                  offset: const Offset(0, 2),
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
                        color: Color(0xFF10B981),
                        size: 24,
                      ),
                      SizedBox(width: 12),
                      Text(
                        'Scan QR Code to Sign In',
                        style: TextStyle(
                          color: Color(0xFF10B981),
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

  // Old _buildTicketSection() method removed - replaced by _buildTicketAction() in Quick Action Section

  Widget _buildActionButtons() {
    return Container(
      padding: const EdgeInsets.all(20),
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
          // Event Management Section
          _buildEventManagementSection(),
          const SizedBox(height: 16),

          // Quick Actions Section
          _buildQuickActionsSection(),
          const SizedBox(height: 16),

          // Event Summary Section
          _buildEventSummarySection(),
        ],
      ),
    );
  }

  Widget _buildEventSummarySection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Section Header
        Row(
          children: [
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: const Color(0xFF10B981).withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(
                Icons.insights,
                color: Color(0xFF10B981),
                size: 18,
              ),
            ),
            const SizedBox(width: 12),
            const Text(
              'Event Summary',
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

        // Summary Cards
        if (isLoadingSummary) ...[
          Row(
            children: [
              Expanded(
                child: _buildSummaryCard(
                  icon: Icons.hourglass_empty,
                  title: 'Loading...',
                  value: '...',
                  color: const Color(0xFF6B7280),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildSummaryCard(
                  icon: Icons.hourglass_empty,
                  title: 'Loading...',
                  value: '...',
                  color: const Color(0xFF6B7280),
                ),
              ),
            ],
          ),
        ] else ...[
          Row(
            children: [
              Expanded(
                child: _buildSummaryCard(
                  icon: Icons.check_circle,
                  title: 'Attendance',
                  value: '$actualAttendanceCount',
                  color: const Color(0xFF10B981),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildSummaryCard(
                  icon: Icons.confirmation_number,
                  title: 'Tickets Used',
                  value: eventModel.ticketsEnabled
                      ? '$usedTicketsCount/${eventModel.issuedTickets}'
                      : 'Disabled',
                  color: const Color(0xFFFF9800),
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }

  Widget _buildSummaryCard({
    required IconData icon,
    required String title,
    required String value,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withOpacity(0.2), width: 1),
        boxShadow: [
          BoxShadow(
            color: color.withOpacity(0.1),
            spreadRadius: 0,
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: color.withOpacity(0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: color, size: 20),
          ),
          const SizedBox(height: 8),
          Text(
            value,
            style: TextStyle(
              color: color,
              fontWeight: FontWeight.bold,
              fontSize: 18,
              fontFamily: 'Roboto',
            ),
          ),
          const SizedBox(height: 4),
          Text(
            title,
            style: const TextStyle(
              color: Color(0xFF6B7280),
              fontSize: 12,
              fontFamily: 'Roboto',
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildEventManagementSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Section Header
        Row(
          children: [
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: const Color(0xFF667EEA).withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(
                Icons.event_available,
                color: Color(0xFF667EEA),
                size: 18,
              ),
            ),
            const SizedBox(width: 12),
            const Text(
              'Event Management',
              style: TextStyle(
                color: Color(0xFF1A1A1A),
                fontWeight: FontWeight.w600,
                fontSize: 16,
                fontFamily: 'Roboto',
              ),
            ),
            const Spacer(),
            // Event Status Badge
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: eventModel.isFeatured
                    ? const Color(0xFFFF9800).withOpacity(0.1)
                    : const Color(0xFF6B7280).withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: eventModel.isFeatured
                      ? const Color(0xFFFF9800)
                      : const Color(0xFF6B7280),
                  width: 1,
                ),
              ),
              child: Text(
                eventModel.isFeatured ? 'Featured' : 'Standard',
                style: TextStyle(
                  color: eventModel.isFeatured
                      ? const Color(0xFFFF9800)
                      : const Color(0xFF6B7280),
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  fontFamily: 'Roboto',
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),

        // Feature Event Button
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
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.star, color: Colors.white, size: 20),
                      SizedBox(width: 8),
                      Text(
                        'Feature This Event',
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
            child: const Center(
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.star, color: Colors.white, size: 20),
                  SizedBox(width: 8),
                  Text(
                    'Featured Event',
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
      ],
    );
  }

  Widget _buildQuickActionsSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Section Header
        Row(
          children: [
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: const Color(0xFF10B981).withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(
                Icons.dashboard,
                color: Color(0xFF10B981),
                size: 18,
              ),
            ),
            const SizedBox(width: 12),
            const Text(
              'Quick Actions',
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

        // Action Grid
        Row(
          children: [
            // Add Prompts Button
            Expanded(
              child: _buildActionCard(
                icon: Icons.question_answer,
                title: 'Add Prompts',
                subtitle: 'Create sign-in questions',
                color: const Color(0xFF667EEA),
                onTap: () => RouterClass.nextScreenNormal(
                  context,
                  AddQuestionsToEventScreen(eventModel: eventModel),
                ),
              ),
            ),
            const SizedBox(width: 12),
            // View Attendance Button
            Expanded(
              child: _buildActionCard(
                icon: Icons.people,
                title: 'View Attendance',
                subtitle: 'See who\'s coming',
                color: const Color(0xFF10B981),
                onTap: () => RouterClass.nextScreenNormal(
                  context,
                  AttendanceSheetScreen(eventModel: eventModel),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),

        // Manage Tickets Button (Full Width)
        _buildActionCard(
          icon: Icons.confirmation_number,
          title: 'Manage Tickets',
          subtitle: 'Create and track event tickets',
          color: const Color(0xFFFF9800),
          onTap: () => RouterClass.nextScreenNormal(
            context,
            TicketManagementScreen(eventModel: eventModel),
          ),
          isFullWidth: true,
        ),
        const SizedBox(height: 12),

        // Scan Tickets Button (Full Width)
        if (eventModel.ticketsEnabled && eventModel.issuedTickets > 0)
          _buildActionCard(
            icon: Icons.qr_code_scanner,
            title: 'Scan Tickets',
            subtitle: 'Scan attendee QR codes to validate tickets',
            color: const Color(0xFF10B981),
            onTap: () async {
              final result = await Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => TicketScannerScreen(
                    eventId: eventModel.id,
                    eventTitle: eventModel.title,
                  ),
                ),
              );

              // Show success message if ticket was validated
              if (result == true) {
                ShowToast().showNormalToast(
                  msg: 'Ticket validated successfully!',
                );
              }
            },
            isFullWidth: true,
          ),
      ],
    );
  }

  Widget _buildActionCard({
    required IconData icon,
    required String title,
    required String subtitle,
    required Color color,
    required VoidCallback onTap,
    bool isFullWidth = false,
  }) {
    return Container(
      height: 90, // Increased height to prevent overflow
      width: isFullWidth ? double.infinity : null,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withOpacity(0.2), width: 1),
        boxShadow: [
          BoxShadow(
            color: color.withOpacity(0.1),
            spreadRadius: 0,
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: color.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(icon, color: color, size: 24),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        title,
                        style: const TextStyle(
                          color: Color(0xFF1A1A1A),
                          fontWeight: FontWeight.w600,
                          fontSize: 14,
                          fontFamily: 'Roboto',
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        subtitle,
                        style: const TextStyle(
                          color: Color(0xFF6B7280),
                          fontSize: 12,
                          fontFamily: 'Roboto',
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                Icon(
                  Icons.arrow_forward_ios,
                  color: color.withOpacity(0.6),
                  size: 16,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _showEventManagementModal() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.only(
            topLeft: Radius.circular(24),
            topRight: Radius.circular(24),
          ),
        ),
        child: SafeArea(
          child: DraggableScrollableSheet(
            initialChildSize: 0.85,
            minChildSize: 0.6,
            maxChildSize: 0.95,
            builder: (context, scrollController) => Column(
              children: [
                // Handle bar
                Container(
                  margin: const EdgeInsets.only(top: 12),
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: AppThemeColor.dullBlueColor.withOpacity(0.3),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(height: 16),
                // Header with title and icon
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: AppThemeColor.darkBlueColor.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Icon(
                          Icons.dashboard,
                          color: AppThemeColor.darkBlueColor,
                          size: 24,
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Text(
                          'Event Management',
                          style: TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.bold,
                            color: AppThemeColor.pureBlackColor,
                            fontFamily: 'Roboto',
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
                // Management options - moved to top
                Expanded(
                  child: SingleChildScrollView(
                    controller: scrollController,
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    child: Column(
                      children: [
                        // Feature Event Section
                        _buildManagementSection(
                          icon: Icons.star,
                          title: 'Event Promotion',
                          color: const Color(0xFFFF9800),
                          children: [
                            _buildManagementOption(
                              icon: Icons.star,
                              title: eventModel.isFeatured
                                  ? 'Featured Event'
                                  : 'Feature This Event',
                              subtitle: eventModel.isFeatured
                                  ? 'Your event is currently featured'
                                  : 'Make your event stand out',
                              onTap: eventModel.isFeatured
                                  ? null
                                  : () {
                                      Navigator.pop(context);
                                      RouterClass.nextScreenNormal(
                                        context,
                                        FeatureEventScreen(
                                          eventModel: eventModel,
                                        ),
                                      );
                                    },
                              isActive: eventModel.isFeatured,
                            ),
                          ],
                        ),
                        const SizedBox(height: 20),

                        // Event Management Section
                        _buildManagementSection(
                          icon: Icons.dashboard,
                          title: 'Event Management',
                          color: const Color(0xFF667EEA),
                          children: [
                            _buildManagementOption(
                              icon: Icons.question_answer,
                              title: 'Add Prompts',
                              subtitle:
                                  'Create sign-in questions for attendees',
                              onTap: () {
                                Navigator.pop(context);
                                RouterClass.nextScreenNormal(
                                  context,
                                  AddQuestionsToEventScreen(
                                    eventModel: eventModel,
                                    onBackPressed: () =>
                                        _showEventManagementModal(),
                                  ),
                                );
                              },
                            ),
                            const SizedBox(height: 12),
                            _buildManagementOption(
                              icon: Icons.people,
                              title: 'View Attendance',
                              subtitle: 'See who has signed in to your event',
                              onTap: () {
                                Navigator.pop(context);
                                RouterClass.nextScreenNormal(
                                  context,
                                  AttendanceSheetScreen(
                                    eventModel: eventModel,
                                    onBackPressed: () =>
                                        _showEventManagementModal(),
                                  ),
                                );
                              },
                            ),
                            const SizedBox(height: 12),
                            _buildManagementOption(
                              icon: Icons.confirmation_number,
                              title: 'Manage Tickets',
                              subtitle: 'Create and track event tickets',
                              onTap: () {
                                Navigator.pop(context);
                                RouterClass.nextScreenNormal(
                                  context,
                                  TicketManagementScreen(
                                    eventModel: eventModel,
                                    onBackPressed: () =>
                                        _showEventManagementModal(),
                                  ),
                                );
                              },
                            ),
                            const SizedBox(height: 12),
                            _buildManagementOption(
                              icon: Icons.star,
                              title: 'Event Feedback',
                              subtitle:
                                  'View and manage event ratings and comments',
                              onTap: () {
                                Navigator.pop(context);
                                RouterClass.nextScreenNormal(
                                  context,
                                  EventFeedbackManagementScreen(
                                    eventModel: eventModel,
                                  ),
                                );
                              },
                            ),
                            const SizedBox(height: 12),
                            _buildManagementOption(
                              icon: Icons.qr_code_scanner,
                              title: 'Scan Tickets',
                              subtitle:
                                  'Scan attendee ticket QR codes for validation',
                              onTap: () async {
                                Navigator.pop(context);
                                final result = await Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (context) => TicketScannerScreen(
                                      eventId: eventModel.id,
                                      eventTitle: eventModel.title,
                                    ),
                                  ),
                                );

                                // Show success message if ticket was validated
                                if (result == true) {
                                  ShowToast().showNormalToast(
                                    msg: 'Ticket validated successfully!',
                                  );
                                }
                              },
                            ),
                            const SizedBox(height: 12),
                            _buildManagementOption(
                              icon: Icons.analytics,
                              title: 'Event Analytics',
                              subtitle: 'View event performance and insights',
                              onTap: () {
                                Navigator.pop(context);
                                RouterClass.nextScreenNormal(
                                  context,
                                  EventAnalyticsScreen(eventId: eventModel.id),
                                );
                              },
                            ),
                          ],
                        ),
                        const SizedBox(height: 20),

                        // Co-Host Management Section
                        _buildManagementSection(
                          icon: Icons.people_alt,
                          title: 'Co-Host Management',
                          color: const Color(0xFF9C27B0),
                          children: [
                            CoHostManagementWidget(
                              eventModel: eventModel,
                              onCoHostsChanged: () {
                                // Refresh the event model to get updated co-hosts
                                setState(() {});
                              },
                            ),
                          ],
                        ),

                        const SizedBox(height: 24),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildManagementSection({
    required IconData icon,
    required String title,
    required Color color,
    required List<Widget> children,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withOpacity(0.2), width: 1),
        boxShadow: [
          BoxShadow(
            color: color.withOpacity(0.1),
            spreadRadius: 0,
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: color.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(icon, color: color, size: 18),
              ),
              const SizedBox(width: 12),
              Text(
                title,
                style: const TextStyle(
                  color: Color(0xFF1A1A1A),
                  fontWeight: FontWeight.w600,
                  fontSize: 16,
                  fontFamily: 'Roboto',
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          ...children,
        ],
      ),
    );
  }

  Widget _buildManagementOption({
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback? onTap,
    bool isActive = false,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: isActive
              ? const Color(0xFFFF9800).withOpacity(0.1)
              : const Color(0xFFF8F9FA),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isActive ? const Color(0xFFFF9800) : const Color(0xFFE5E7EB),
            width: 1,
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: isActive
                    ? const Color(0xFFFF9800).withOpacity(0.1)
                    : const Color(0xFF667EEA).withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                icon,
                color: isActive
                    ? const Color(0xFFFF9800)
                    : const Color(0xFF667EEA),
                size: 24,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: isActive
                          ? const Color(0xFFFF9800)
                          : const Color(0xFF1A1A1A),
                      fontFamily: 'Roboto',
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: TextStyle(
                      fontSize: 14,
                      color: isActive
                          ? const Color(0xFFFF9800).withOpacity(0.8)
                          : const Color(0xFF6B7280),
                      fontFamily: 'Roboto',
                    ),
                  ),
                ],
              ),
            ),
            if (!isActive)
              Icon(
                Icons.arrow_forward_ios,
                color: const Color(0xFF6B7280),
                size: 16,
              ),
          ],
        ),
      ),
    );
  }

  void _showQuickShareOptions() {
    final bool isCreator = eventModel.hasManagementPermissions(
      FirebaseAuth.instance.currentUser!.uid,
    );

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
                    if (isCreator) ...[
                      _buildShareOption(
                        icon: Icons.qr_code_2_rounded,
                        title: 'Share QR Code & Event ID',
                        subtitle:
                            'Generate QR code with event identifier (Creator Only)',
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
                    ],
                    _buildShareOption(
                      icon: Icons.calendar_today,
                      title: 'Add to Calendar',
                      subtitle: 'Add this event to your calendar',
                      onTap: () {
                        Navigator.pop(context);
                        _addToCalendar();
                      },
                    ),
                    const SizedBox(height: 16),
                    _buildShareOption(
                      icon: Icons.share_rounded,
                      title: 'Share Event Details',
                      subtitle: isCreator
                          ? 'Share event information with others'
                          : 'Share this event with friends',
                      onTap: () {
                        Navigator.pop(context);
                        _shareEventDetails();
                      },
                    ),
                    if (!isCreator) ...[
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
    final bool isCreator = eventModel.hasManagementPermissions(
      FirebaseAuth.instance.currentUser!.uid,
    );

    final eventDetails = isCreator
        ? '''
🎉 Join my event!

📅 Event: ${eventModel.title}
📍 Location: ${eventModel.location}
🆔 Event ID: ${eventModel.rawId}
📝 Description: ${eventModel.description}

Join us for an amazing time!
        '''
              .trim()
        : '''
🎉 Check out this event!

📅 Event: ${eventModel.title}
📍 Location: ${eventModel.location}
📝 Description: ${eventModel.description}

This looks like a great event!
        '''
              .trim();

    Share.share(
      eventDetails,
      subject: isCreator
          ? 'Event Invitation - ${eventModel.title}'
          : 'Event Recommendation - ${eventModel.title}',
    );
  }

  void _copyEventId() {
    HapticFeedback.lightImpact();
    Clipboard.setData(ClipboardData(text: eventModel.rawId));
    ShowToast().showSnackBar('Event ID copied to clipboard', context);
  }

  void _addToCalendar() async {
    HapticFeedback.lightImpact();

    try {
      // Format the event details for calendar
      final eventTitle = Uri.encodeComponent(eventModel.title);
      final eventDescription = Uri.encodeComponent(eventModel.description);
      final eventLocation = Uri.encodeComponent(eventModel.location);

      // Format date and time for calendar
      final eventDate = eventModel.selectedDateTime;
      final startTime = eventDate.toUtc().toIso8601String().replaceAll(
        RegExp(r'[-:]|\.\d{3}'),
        '',
      );
      final endTime = eventDate
          .add(const Duration(hours: 2))
          .toUtc()
          .toIso8601String()
          .replaceAll(RegExp(r'[-:]|\.\d{3}'), '');

      // Create calendar URL (Google Calendar format)
      final calendarUrl =
          'https://calendar.google.com/calendar/render?'
          'action=TEMPLATE'
          '&text=$eventTitle'
          '&dates=$startTime/$endTime'
          '&details=$eventDescription'
          '&location=$eventLocation'
          '&sf=true'
          '&output=xml';

      // Try to launch the calendar URL
      final uri = Uri.parse(calendarUrl);
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
        ShowToast().showSnackBar('Opening calendar app...', context);
      } else {
        // Fallback: show a dialog with calendar options
        _showCalendarOptionsDialog();
      }
    } catch (e) {
      print('Error adding to calendar: $e');
      ShowToast().showSnackBar('Failed to open calendar', context);
    }
  }

  void _showCalendarOptionsDialog() {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20.0),
          ),
          title: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: const Color(0xFF667EEA).withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.calendar_today,
                  color: Color(0xFF667EEA),
                  size: 24,
                ),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Text(
                  'Add to Calendar',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    fontFamily: 'Roboto',
                  ),
                ),
              ),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Choose your calendar app:',
                style: TextStyle(
                  fontSize: 16,
                  fontFamily: 'Roboto',
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 16),
              _buildCalendarOption(
                'Google Calendar',
                'calendar.google.com',
                Icons.calendar_today,
                () => _openGoogleCalendar(),
              ),
              const SizedBox(height: 8),
              _buildCalendarOption(
                'Apple Calendar',
                'Calendar app',
                Icons.apple,
                () => _openAppleCalendar(),
              ),
              const SizedBox(height: 8),
              _buildCalendarOption(
                'Outlook Calendar',
                'outlook.live.com',
                Icons.email,
                () => _openOutlookCalendar(),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text(
                'Cancel',
                style: TextStyle(
                  color: Color(0xFF6B7280),
                  fontFamily: 'Roboto',
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildCalendarOption(
    String title,
    String subtitle,
    IconData icon,
    VoidCallback onTap,
  ) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: const Color(0xFFF9FAFB),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFFE5E7EB), width: 1),
        ),
        child: Row(
          children: [
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: const Color(0xFF667EEA).withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(icon, color: const Color(0xFF667EEA), size: 18),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      fontFamily: 'Roboto',
                    ),
                  ),
                  Text(
                    subtitle,
                    style: const TextStyle(
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
              color: Color(0xFF6B7280),
              size: 16,
            ),
          ],
        ),
      ),
    );
  }

  void _openGoogleCalendar() async {
    Navigator.of(context).pop();
    final eventTitle = Uri.encodeComponent(eventModel.title);
    final eventDescription = Uri.encodeComponent(eventModel.description);
    final eventLocation = Uri.encodeComponent(eventModel.location);

    final eventDate = eventModel.selectedDateTime;
    final startTime = eventDate.toUtc().toIso8601String().replaceAll(
      RegExp(r'[-:]|\.\d{3}'),
      '',
    );
    final endTime = eventDate
        .add(const Duration(hours: 2))
        .toUtc()
        .toIso8601String()
        .replaceAll(RegExp(r'[-:]|\.\d{3}'), '');

    final calendarUrl =
        'https://calendar.google.com/calendar/render?'
        'action=TEMPLATE'
        '&text=$eventTitle'
        '&dates=$startTime/$endTime'
        '&details=$eventDescription'
        '&location=$eventLocation'
        '&sf=true'
        '&output=xml';

    final uri = Uri.parse(calendarUrl);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  void _openAppleCalendar() async {
    Navigator.of(context).pop();
    final eventTitle = Uri.encodeComponent(eventModel.title);
    final eventDescription = Uri.encodeComponent(eventModel.description);
    final eventLocation = Uri.encodeComponent(eventModel.location);

    final eventDate = eventModel.selectedDateTime;
    final startTime = eventDate.toUtc().toIso8601String().replaceAll(
      RegExp(r'[-:]|\.\d{3}'),
      '',
    );
    final endTime = eventDate
        .add(const Duration(hours: 2))
        .toUtc()
        .toIso8601String()
        .replaceAll(RegExp(r'[-:]|\.\d{3}'), '');

    // Apple Calendar uses a different format
    final calendarUrl =
        'webcal://calendar.google.com/calendar/event?'
        'action=TEMPLATE'
        '&text=$eventTitle'
        '&dates=$startTime/$endTime'
        '&details=$eventDescription'
        '&location=$eventLocation';

    final uri = Uri.parse(calendarUrl);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  void _openOutlookCalendar() async {
    Navigator.of(context).pop();
    final eventTitle = Uri.encodeComponent(eventModel.title);
    final eventDescription = Uri.encodeComponent(eventModel.description);
    final eventLocation = Uri.encodeComponent(eventModel.location);

    final eventDate = eventModel.selectedDateTime;
    final startTime = eventDate.toUtc().toIso8601String().replaceAll(
      RegExp(r'[-:]|\.\d{3}'),
      '',
    );
    final endTime = eventDate
        .add(const Duration(hours: 2))
        .toUtc()
        .toIso8601String()
        .replaceAll(RegExp(r'[-:]|\.\d{3}'), '');

    final calendarUrl =
        'https://outlook.live.com/calendar/0/deeplink/compose?'
        'subject=$eventTitle'
        '&body=$eventDescription'
        '&location=$eventLocation'
        '&startdt=$startTime'
        '&enddt=$endTime';

    final uri = Uri.parse(calendarUrl);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
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
          // Immediately update the UI to show ticket received
          setState(() {
            _hasTicket = true;
            _isGettingTicket = false;
          });

          ShowToast().showNormalToast(
            msg:
                'Ticket obtained successfully! You are now registered for this event.',
          );

          // Refresh ticket status and pre-registered count in background
          checkUserTicket(updateUI: false);
          getPreRegisterCount();

          // Add a small delay to let user see the "Ticket Received" state
          Future.delayed(const Duration(milliseconds: 1500), () {
            if (mounted) {
              // Navigate to MyTicketsScreen to show the new ticket
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const MyTicketsScreen(),
                ),
              );
            }
          });
        }
      }
    } catch (e) {
      print('Error in _getTicket: $e');
      if (mounted) {
        setState(() {
          _isGettingTicket = false;
        });

        // Handle specific error cases more gracefully
        String errorMessage = 'Failed to get ticket';
        if (e.toString().contains('You already have a ticket for this event')) {
          errorMessage = 'You already have a ticket for this event';
          // Refresh ticket status to ensure UI is up to date with a small delay
          Future.delayed(const Duration(milliseconds: 500), () {
            if (mounted) {
              checkUserTicket(updateUI: true);
            }
          });
        } else if (e.toString().contains('Tickets are not enabled')) {
          errorMessage = 'Tickets are not enabled for this event';
        } else if (e.toString().contains('No tickets available')) {
          errorMessage = 'No tickets available for this event';
        } else if (e.toString().contains('Event not found')) {
          errorMessage = 'Event not found';
        } else {
          errorMessage = 'Failed to get ticket: $e';
        }

        ShowToast().showNormalToast(msg: errorMessage);
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
      checkUserTicket(updateUI: true);
    } catch (e) {
      ShowToast().showNormalToast(msg: 'Failed to clear tickets: $e');
    }
  }

  Future<void> checkUserTicket({bool updateUI = true}) async {
    if (CustomerController.logeInCustomer == null) {
      return;
    }

    if (updateUI) {
      setState(() {
        _isCheckingTicket = true;
      });
    }

    try {
      final userTickets = await FirebaseFirestoreHelper().getUserTickets(
        customerUid: CustomerController.logeInCustomer!.uid,
      );

      // Check if user has an active ticket for this event
      final hasActiveTicket = userTickets.any(
        (ticket) => ticket.eventId == eventModel.id && !ticket.isUsed,
      );

      if (mounted && updateUI) {
        setState(() {
          _hasTicket = hasActiveTicket;
          _isCheckingTicket = false;
        });
      }
    } catch (e) {
      print('Error checking user ticket: $e');
      if (mounted && updateUI) {
        setState(() {
          _isCheckingTicket = false;
        });
      }
    }
  }

  // Tabbed Content Section - Clean and organized
  Widget _buildTabbedContentSection() {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.symmetric(horizontal: 4),
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
          // Tab Headers
          Container(
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              color: const Color(0xFFF8F9FA),
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(20),
                topRight: Radius.circular(20),
              ),
            ),
            child: Row(
              children: [
                Expanded(
                  child: _buildTabButton(
                    index: 0,
                    icon: Icons.confirmation_number,
                    label: 'Get Ticket',
                    isSelected: _selectedTabIndex == 0,
                  ),
                ),
                Expanded(
                  child: _buildTabButton(
                    index: 1,
                    icon: Icons.qr_code_scanner,
                    label: 'Sign In',
                    isSelected: _selectedTabIndex == 1,
                  ),
                ),
              ],
            ),
          ),

          // Tab Content
          Container(
            padding: const EdgeInsets.all(20),
            child: _buildTabContent(),
          ),
        ],
      ),
    );
  }

  Widget _buildTabButton({
    required int index,
    required IconData icon,
    required String label,
    required bool isSelected,
  }) {
    return GestureDetector(
      onTap: () {
        setState(() {
          _selectedTabIndex = index;
        });
      },
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
        decoration: BoxDecoration(
          color: isSelected ? Colors.white : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.1),
                    spreadRadius: 0,
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ]
              : null,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              color: isSelected
                  ? const Color(0xFF667EEA)
                  : const Color(0xFF6B7280),
              size: 20,
            ),
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(
                color: isSelected
                    ? const Color(0xFF667EEA)
                    : const Color(0xFF6B7280),
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                fontSize: 12,
                fontFamily: 'Roboto',
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTabContent() {
    switch (_selectedTabIndex) {
      case 0:
        return _buildTicketsTab();
      case 1:
        return _buildSignInTab();
      default:
        return _buildTicketsTab();
    }
  }

  Widget _buildTicketsTab() {
    if (!eventModel.ticketsEnabled) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.event_busy, color: Color(0xFF6B7280), size: 48),
            SizedBox(height: 16),
            Text(
              'Tickets Not Available',
              style: TextStyle(
                color: Color(0xFF1A1A1A),
                fontWeight: FontWeight.w600,
                fontSize: 16,
                fontFamily: 'Roboto',
              ),
            ),
            SizedBox(height: 8),
            Text(
              'This event doesn\'t offer tickets.',
              style: TextStyle(
                color: Color(0xFF6B7280),
                fontSize: 14,
                fontFamily: 'Roboto',
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      );
    }

    return Column(
      children: [
        // Ticket Status
        Row(
          children: [
            Icon(
              _hasTicket ? Icons.check_circle : Icons.confirmation_number,
              color: _hasTicket
                  ? const Color(0xFF10B981)
                  : const Color(0xFFFF9800),
              size: 24,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                _hasTicket ? 'Ticket Received' : 'Get Event Ticket',
                style: const TextStyle(
                  color: Color(0xFF1A1A1A),
                  fontWeight: FontWeight.w600,
                  fontSize: 16,
                  fontFamily: 'Roboto',
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),

        // Description
        Text(
          _hasTicket
              ? 'You have a ticket for this event and are pre-registered. Show the QR code to the event host when you arrive.'
              : 'Get a free ticket for this event. You\'ll be automatically pre-registered and receive a QR code to show the event host when you arrive.',
          style: const TextStyle(
            color: Color(0xFF6B7280),
            fontSize: 14,
            fontFamily: 'Roboto',
            height: 1.4,
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 20),

        // Action Button
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
            height: 48,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0xFF10B981), Color(0xFF059669)],
              ),
              borderRadius: BorderRadius.circular(12),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF10B981).withOpacity(0.3),
                  spreadRadius: 0,
                  blurRadius: 8,
                  offset: const Offset(0, 4),
                ),
              ],
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
                child: const Center(
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.visibility, color: Colors.white, size: 20),
                      SizedBox(width: 8),
                      Text(
                        'View Ticket',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
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
            height: 48,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0xFFFF9800), Color(0xFFFF5722)],
              ),
              borderRadius: BorderRadius.circular(12),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFFFF9800).withOpacity(0.3),
                  spreadRadius: 0,
                  blurRadius: 8,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: _isGettingTicket ? null : _getTicket,
                child: Center(
                  child: _isGettingTicket
                      ? const SizedBox(
                          width: 20,
                          height: 20,
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
                              size: 20,
                            ),
                            SizedBox(width: 8),
                            Text(
                              'Get Ticket',
                              style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
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

        // Debug button (smaller and less prominent)
        if (!_hasTicket) ...[
          const SizedBox(height: 12),
          GestureDetector(
            onTap: _clearTicketsForTesting,
            child: const Text(
              'Clear Tickets (Debug)',
              style: TextStyle(
                color: Color(0xFF9CA3AF),
                fontSize: 12,
                fontFamily: 'Roboto',
                decoration: TextDecoration.underline,
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildSignInTab() {
    if (signedIn == null || signedIn!) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.check_circle, color: Color(0xFF10B981), size: 48),
            SizedBox(height: 16),
            Text(
              'Already Signed In',
              style: TextStyle(
                color: Color(0xFF1A1A1A),
                fontWeight: FontWeight.w600,
                fontSize: 16,
                fontFamily: 'Roboto',
              ),
            ),
            SizedBox(height: 8),
            Text(
              'You\'re already signed in for this event.',
              style: TextStyle(
                color: Color(0xFF6B7280),
                fontSize: 14,
                fontFamily: 'Roboto',
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      );
    }

    return Column(
      children: [
        // Header
        Row(
          children: [
            const Icon(
              Icons.qr_code_scanner,
              color: Color(0xFF10B981),
              size: 24,
            ),
            const SizedBox(width: 12),
            const Expanded(
              child: Text(
                'Sign In to Event',
                style: TextStyle(
                  color: Color(0xFF1A1A1A),
                  fontWeight: FontWeight.w600,
                  fontSize: 16,
                  fontFamily: 'Roboto',
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),

        // Description
        const Text(
          'Scan QR code or manually enter the event code to sign in.',
          style: TextStyle(
            color: Color(0xFF6B7280),
            fontSize: 14,
            fontFamily: 'Roboto',
            height: 1.4,
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 20),

        // QR Code Scanner Button
        Container(
          width: double.infinity,
          height: 48,
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFF10B981), Color(0xFF059669)],
            ),
            borderRadius: BorderRadius.circular(12),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF10B981).withOpacity(0.3),
                spreadRadius: 0,
                blurRadius: 8,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const QRScannerFlowScreen(),
                  ),
                );
              },
              child: const Center(
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      CupertinoIcons.qrcode_viewfinder,
                      color: Colors.white,
                      size: 20,
                    ),
                    SizedBox(width: 8),
                    Text(
                      'Scan QR Code or Enter Code',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
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
        // OR Divider removed - no longer needed since manual code input section was removed
        // Manual Code Input Section removed - functionality now handled by QRScannerFlowScreen
      ],
    );
  }

  // _signInWithCode method removed - functionality now handled by QRScannerFlowScreen

  /// Builds the dwell tracking section UI
  Widget _buildDwellTrackingSection() {
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
          // Header
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
                  Icons.timer,
                  color: Color(0xFF667EEA),
                  size: 20,
                ),
              ),
              const SizedBox(width: 16),
              const Expanded(
                child: Text(
                  'Dwell Time Tracking',
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

          // Status and Controls
          if (_isDwellTrackingActive) ...[
            // Active tracking status
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFF10B981).withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: const Color(0xFF10B981).withOpacity(0.3),
                  width: 1,
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(
                        Icons.location_on,
                        color: Color(0xFF10B981),
                        size: 20,
                      ),
                      const SizedBox(width: 8),
                      const Text(
                        'Tracking Active',
                        style: TextStyle(
                          color: Color(0xFF10B981),
                          fontWeight: FontWeight.w600,
                          fontSize: 16,
                          fontFamily: 'Roboto',
                        ),
                      ),
                    ],
                  ),
                  if (_dwellStatusMessage.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Text(
                      _dwellStatusMessage,
                      style: const TextStyle(
                        color: Color(0xFF6B7280),
                        fontSize: 14,
                        fontFamily: 'Roboto',
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 16),

            // Check Out button
            Container(
              width: double.infinity,
              height: 48,
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [Color(0xFFFF5722), Color(0xFFE91E63)],
                ),
                borderRadius: BorderRadius.circular(12),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFFFF5722).withOpacity(0.3),
                    spreadRadius: 0,
                    blurRadius: 8,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  borderRadius: BorderRadius.circular(12),
                  onTap: _stopDwellTracking,
                  child: const Center(
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.logout, color: Colors.white, size: 20),
                        SizedBox(width: 8),
                        Text(
                          'Check Out',
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
          ] else if (_currentAttendance?.isDwellCompleted == true) ...[
            // Completed tracking display
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFF6B7280).withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: const Color(0xFF6B7280).withOpacity(0.3),
                  width: 1,
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(
                        Icons.check_circle,
                        color: Color(0xFF6B7280),
                        size: 20,
                      ),
                      const SizedBox(width: 8),
                      const Text(
                        'Tracking Completed',
                        style: TextStyle(
                          color: Color(0xFF6B7280),
                          fontWeight: FontWeight.w600,
                          fontSize: 16,
                          fontFamily: 'Roboto',
                        ),
                      ),
                    ],
                  ),
                  if (_currentAttendance?.formattedDwellTime.isNotEmpty ==
                      true) ...[
                    const SizedBox(height: 8),
                    Text(
                      'Dwell Time: ${_currentAttendance!.formattedDwellTime}',
                      style: const TextStyle(
                        color: Color(0xFF6B7280),
                        fontSize: 14,
                        fontFamily: 'Roboto',
                      ),
                    ),
                  ],
                  if (_currentAttendance?.dwellNotes != null) ...[
                    const SizedBox(height: 4),
                    Text(
                      'Note: ${_currentAttendance!.dwellNotes}',
                      style: const TextStyle(
                        color: Color(0xFF6B7280),
                        fontSize: 12,
                        fontFamily: 'Roboto',
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ] else ...[
            // Enable tracking option
            Container(
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
                  const Text(
                    'Track your time at this event',
                    style: TextStyle(
                      color: Color(0xFF1A1A1A),
                      fontWeight: FontWeight.w600,
                      fontSize: 16,
                      fontFamily: 'Roboto',
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Enable location tracking to automatically measure your time spent at the event venue.',
                    style: TextStyle(
                      color: Color(0xFF6B7280),
                      fontSize: 14,
                      fontFamily: 'Roboto',
                      height: 1.4,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Container(
                    width: double.infinity,
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
                          color: const Color(0xFF667EEA).withOpacity(0.3),
                          spreadRadius: 0,
                          blurRadius: 8,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Material(
                      color: Colors.transparent,
                      child: InkWell(
                        borderRadius: BorderRadius.circular(12),
                        onTap: _showPrivacyDialog,
                        child: const Center(
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.location_on,
                                color: Colors.white,
                                size: 20,
                              ),
                              SizedBox(width: 8),
                              Text(
                                'Enable Tracking',
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
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildAttendeesDropdown() {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            spreadRadius: 0,
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        children: [
          // Dropdown Header Button
          InkWell(
            onTap: () {
              setState(() {
                _isAttendeesExpanded = !_isAttendeesExpanded;
              });
            },
            borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
              child: Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: const Color(0xFF10B981).withOpacity(0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(
                      Icons.people,
                      color: Color(0xFF10B981),
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Attendees (${actualAttendanceCount})',
                          style: const TextStyle(
                            color: Color(0xFF1A1A1A),
                            fontSize: 18,
                            fontWeight: FontWeight.w600,
                            fontFamily: 'Roboto',
                          ),
                        ),
                        Text(
                          'Tap to see attendees',
                          style: TextStyle(
                            color: Colors.grey[600],
                            fontSize: 14,
                            fontFamily: 'Roboto',
                          ),
                        ),
                      ],
                    ),
                  ),
                  AnimatedRotation(
                    turns: _isAttendeesExpanded ? 0.5 : 0.0,
                    duration: const Duration(milliseconds: 300),
                    child: const Icon(
                      Icons.keyboard_arrow_down,
                      color: Color(0xFF10B981),
                      size: 24,
                    ),
                  ),
                ],
              ),
            ),
          ),
          // Dropdown Content
          AnimatedContainer(
            duration: const Duration(milliseconds: 300),
            height: _isAttendeesExpanded ? null : 0,
            child: _isAttendeesExpanded
                ? Container(
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                    child: _buildAttendeesContent(),
                  )
                : const SizedBox.shrink(),
          ),
        ],
      ),
    );
  }

  Widget _buildAttendeesContent() {
    return FutureBuilder<List<AttendanceModel>>(
      future: FirebaseFirestoreHelper().getAttendance(eventId: eventModel.id),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const SizedBox(
            height: 100,
            child: Center(
              child: CircularProgressIndicator(
                color: Color(0xFF10B981),
                strokeWidth: 2,
              ),
            ),
          );
        }

        if (snapshot.hasError || !snapshot.hasData) {
          return const SizedBox(
            height: 100,
            child: Center(
              child: Text(
                'No attendees yet',
                style: TextStyle(
                  color: Color(0xFF6B7280),
                  fontSize: 14,
                  fontFamily: 'Roboto',
                ),
              ),
            ),
          );
        }

        final attendees = snapshot.data!;

        return Column(
          children: [
            // See All Button Row
            if (attendees.isNotEmpty)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    GestureDetector(
                      onTap: () => _showAllAttendeesPopup(attendees),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFF10B981).withOpacity(0.1),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: const Color(0xFF10B981),
                            width: 1,
                          ),
                        ),
                        child: const Text(
                          'See All',
                          style: TextStyle(
                            color: Color(0xFF10B981),
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            fontFamily: 'Roboto',
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            // Horizontal Attendees List
            SizedBox(
              height: 100,
              child: attendees.isEmpty
                  ? Center(
                      child: Text(
                        'No attendees yet',
                        style: TextStyle(
                          color: Colors.grey[500],
                          fontSize: 14,
                          fontFamily: 'Roboto',
                        ),
                      ),
                    )
                  : ListView.builder(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      itemCount: attendees.length > 5 ? 5 : attendees.length,
                      itemBuilder: (context, index) {
                        final attendee = attendees[index];
                        final isAnon = attendee.isAnonymous;

                        return GestureDetector(
                          onTap: () {
                            if (!isAnon) {
                              // Navigate to user profile if not anonymous
                              FirebaseFirestoreHelper()
                                  .getSingleCustomer(
                                    customerId: attendee.customerUid,
                                  )
                                  .then((customer) {
                                    if (customer != null) {
                                      Navigator.push(
                                        context,
                                        MaterialPageRoute(
                                          builder: (context) =>
                                              UserProfileScreen(user: customer),
                                        ),
                                      );
                                    }
                                  });
                            }
                          },
                          child: Container(
                            margin: const EdgeInsets.only(right: 16),
                            child: Column(
                              children: [
                                // Profile Picture
                                Container(
                                  width: 56,
                                  height: 56,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    gradient: isAnon
                                        ? const LinearGradient(
                                            begin: Alignment.topLeft,
                                            end: Alignment.bottomRight,
                                            colors: [
                                              Color(0xFF6B7280),
                                              Color(0xFF9CA3AF),
                                            ],
                                          )
                                        : const LinearGradient(
                                            begin: Alignment.topLeft,
                                            end: Alignment.bottomRight,
                                            colors: [
                                              Color(0xFF10B981),
                                              Color(0xFF059669),
                                            ],
                                          ),
                                    boxShadow: [
                                      BoxShadow(
                                        color: isAnon
                                            ? const Color(
                                                0xFF6B7280,
                                              ).withOpacity(0.3)
                                            : const Color(
                                                0xFF10B981,
                                              ).withOpacity(0.3),
                                        spreadRadius: 0,
                                        blurRadius: 8,
                                        offset: const Offset(0, 2),
                                      ),
                                    ],
                                  ),
                                  child: Center(
                                    child: Text(
                                      isAnon
                                          ? 'A'
                                          : attendee.userName.isNotEmpty
                                          ? attendee.userName[0].toUpperCase()
                                          : 'U',
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 20,
                                        fontWeight: FontWeight.bold,
                                        fontFamily: 'Roboto',
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 8),
                                // Name
                                Text(
                                  isAnon ? 'Anonymous' : attendee.userName,
                                  style: const TextStyle(
                                    color: Color(0xFF1A1A1A),
                                    fontSize: 12,
                                    fontWeight: FontWeight.w500,
                                    fontFamily: 'Roboto',
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
            ),
          ],
        );
      },
    );
  }

  void _showAllAttendeesPopup(List<AttendanceModel> attendees) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return Dialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          child: Container(
            constraints: const BoxConstraints(maxHeight: 500),
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: const Color(0xFF10B981).withOpacity(0.1),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(
                        Icons.people,
                        color: Color(0xFF10B981),
                        size: 20,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'All Attendees',
                            style: TextStyle(
                              color: Color(0xFF1A1A1A),
                              fontSize: 20,
                              fontWeight: FontWeight.w600,
                              fontFamily: 'Roboto',
                            ),
                          ),
                          Text(
                            '${attendees.length} people signed in',
                            style: const TextStyle(
                              color: Color(0xFF6B7280),
                              fontSize: 14,
                              fontFamily: 'Roboto',
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.of(context).pop(),
                      icon: const Icon(Icons.close, color: Color(0xFF6B7280)),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                Flexible(
                  child: ListView.builder(
                    shrinkWrap: true,
                    itemCount: attendees.length,
                    itemBuilder: (context, index) {
                      final attendee = attendees[index];
                      final isAnon = attendee.isAnonymous;

                      return Container(
                        margin: const EdgeInsets.only(bottom: 12),
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: Colors.grey.withOpacity(0.1),
                            width: 1,
                          ),
                        ),
                        child: Row(
                          children: [
                            // Avatar
                            Container(
                              width: 48,
                              height: 48,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                gradient: isAnon
                                    ? const LinearGradient(
                                        begin: Alignment.topLeft,
                                        end: Alignment.bottomRight,
                                        colors: [
                                          Color(0xFF6B7280),
                                          Color(0xFF9CA3AF),
                                        ],
                                      )
                                    : const LinearGradient(
                                        begin: Alignment.topLeft,
                                        end: Alignment.bottomRight,
                                        colors: [
                                          Color(0xFF10B981),
                                          Color(0xFF059669),
                                        ],
                                      ),
                                boxShadow: [
                                  BoxShadow(
                                    color: isAnon
                                        ? const Color(
                                            0xFF6B7280,
                                          ).withOpacity(0.3)
                                        : const Color(
                                            0xFF10B981,
                                          ).withOpacity(0.3),
                                    spreadRadius: 0,
                                    blurRadius: 8,
                                    offset: const Offset(0, 2),
                                  ),
                                ],
                              ),
                              child: Center(
                                child: Text(
                                  isAnon
                                      ? 'A'
                                      : attendee.userName.isNotEmpty
                                      ? attendee.userName[0].toUpperCase()
                                      : 'U',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 18,
                                    fontWeight: FontWeight.bold,
                                    fontFamily: 'Roboto',
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    isAnon
                                        ? 'Anonymous User'
                                        : attendee.userName,
                                    style: const TextStyle(
                                      color: Color(0xFF1A1A1A),
                                      fontSize: 16,
                                      fontWeight: FontWeight.w600,
                                      fontFamily: 'Roboto',
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    isAnon
                                        ? 'Anonymous sign-in'
                                        : 'Registered user',
                                    style: const TextStyle(
                                      color: Color(0xFF6B7280),
                                      fontSize: 14,
                                      fontFamily: 'Roboto',
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
