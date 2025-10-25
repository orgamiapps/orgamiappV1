import 'dart:async';
import 'dart:math';
import 'package:flutter/foundation.dart';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:attendus/models/customer_model.dart';
import 'package:attendus/Services/subscription_service.dart';
import 'package:attendus/widgets/upgrade_prompt_dialog.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geocoding/geocoding.dart';
import 'package:intl/intl.dart';
import 'package:attendus/controller/customer_controller.dart';
import 'package:attendus/Utils/location_helper.dart';
import 'package:attendus/firebase/dwell_time_tracker.dart';
import 'package:attendus/firebase/firebase_firestore_helper.dart';
import 'package:attendus/models/attendance_model.dart';

import 'package:attendus/models/event_model.dart';
import 'package:attendus/models/event_question_model.dart';
import 'package:attendus/screens/Events/Attendance/attendance_sheet_screen.dart';

import 'package:attendus/screens/Events/Widget/comments_section.dart';

import 'package:attendus/screens/Events/ticket_management_screen.dart';
import 'package:attendus/screens/Events/ticket_scanner_screen.dart';
import 'package:attendus/screens/Events/event_analytics_screen.dart';
import 'package:attendus/screens/Events/event_feedback_screen.dart';
import 'package:attendus/screens/Events/event_feedback_management_screen.dart';
import 'package:attendus/screens/Home/attendee_notification_screen.dart';
import 'package:attendus/screens/MyProfile/my_tickets_screen.dart';
import 'package:attendus/screens/MyProfile/user_profile_screen.dart';

// import 'package:attendus/screens/QRScanner/QrScannerScreenForLogedIn.dart';
import 'package:attendus/screens/QRScanner/qr_scanner_flow_screen.dart';
import 'package:attendus/Utils/colors.dart';
import 'package:attendus/Utils/router.dart';
import 'package:attendus/Utils/toast.dart';
import 'package:attendus/Utils/logger.dart';
import 'package:attendus/Services/ticket_payment_service.dart';
import 'package:attendus/Services/face_recognition_service.dart';
import 'package:attendus/Services/live_quiz_service.dart';
import 'package:attendus/screens/LiveQuiz/quiz_builder_screen.dart';
import 'package:attendus/screens/LiveQuiz/quiz_host_screen.dart';
import 'package:attendus/screens/LiveQuiz/quiz_participant_screen.dart';
import 'package:attendus/models/live_quiz_model.dart';

import 'package:rounded_loading_button_plus/rounded_loading_button.dart';

import 'package:attendus/screens/Events/chose_location_in_map_screen.dart';
import 'package:attendus/screens/Events/feature_event_screen.dart';
import 'package:attendus/screens/Events/edit_event_screen.dart';
import 'package:attendus/screens/Events/event_location_view_screen.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:share_plus/share_plus.dart';
import 'package:attendus/screens/Events/Widget/qr_dialogue.dart';
import 'package:attendus/screens/Events/Widget/access_list_management_widget.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:attendus/screens/Events/Widget/pre_registered_horizontal_list.dart';
import 'package:attendus/screens/FaceRecognition/face_recognition_scanner_screen.dart';
import 'package:attendus/screens/FaceRecognition/face_enrollment_screen.dart';
import 'package:attendus/widgets/app_scaffold_wrapper.dart';

class SingleEventScreen extends StatefulWidget {
  final EventModel eventModel;
  const SingleEventScreen({super.key, required this.eventModel});

  @override
  State<SingleEventScreen> createState() => _SingleEventScreenState();
}

class _SingleEventScreenState extends State<SingleEventScreen>
    with TickerProviderStateMixin, WidgetsBindingObserver {
  late EventModel eventModel;
  StreamSubscription<DocumentSnapshot>? _eventSubscription;
  Timer? _streamDebounceTimer;

  // Live Quiz related state
  LiveQuizModel? _liveQuiz;
  final _liveQuizService = LiveQuizService();
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
  // Tab index removed - no longer using tabs

  // RSVP state
  bool _isRsvped = false;
  bool _isRsvpLoading = false;
  bool _isRsvpStatusLoading =
      true; // Track if we're still checking initial RSVP status

  // _isLoading removed - no longer needed after removing manual code input

  // Dwell time tracking variables
  // ignore: unused_field
  bool _isDwellTrackingActive = false;
  // ignore: unused_field
  String _dwellStatusMessage = '';
  bool _hasShownPrivacyDialog = false;

  // Animation controllers
  late AnimationController _fadeController;
  late Animation<double> _fadeAnimation;
  late AnimationController _slideController;
  late Animation<Offset> _slideAnimation;
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;
  late AnimationController _glowController;
  late Animation<double> _glowAnimation;

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

  // Address lookup state (kept for background resolution if needed)
  String? _resolvedAddress;
  String? _creatorName;
  String? _creatorUsername;
  CustomerModel? _creatorUser;

  // Modern color palette
  static const Color _primaryBlue = Color(0xFF667EEA);
  static const Color _primaryPurple = Color(0xFF764BA2);
  static const Color _accentBlue = Color(0xFF4338CA);

  static const Color _orange = Color(0xFFFF9800);
  static const Color _darkText = Color(0xFF1F2937);
  static const Color _mediumText = Color(0xFF4B5563);
  static const Color _lightText = Color(0xFF6B7280);
  static const Color _backgroundColor = Color(0xFFF8FAFC);
  static const Color _cardBackground = Color(0xFFFFFFFF);
  static const Color _borderColor = Color(0xFFE2E8F0);

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
      if (kDebugMode) {
        Logger.error('Error getting actual attendance: $e');
      }
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
      if (kDebugMode) {
        Logger.error('Error getting used tickets: $e');
      }
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

  /// Async wrapper for loadEventSummary with timeout and error handling
  Future<void> _loadEventSummaryAsync() async {
    try {
      await loadEventSummary().timeout(
        const Duration(seconds: 10),
        onTimeout: () {
          if (mounted) {
            setState(() {
              isLoadingSummary = false;
            });
          }
          Logger.warning('Event summary loading timed out');
        },
      );
    } catch (e) {
      if (mounted) {
        setState(() {
          isLoadingSummary = false;
        });
      }
      Logger.error('Error in async event summary loading: $e');
    }
  }

  Future<void> _checkRsvpStatus() async {
    try {
      final isRegistered = await FirebaseFirestoreHelper()
          .checkIfUserIsRegistered(eventModel.id);
      if (mounted) {
        setState(() {
          _isRsvped = isRegistered;
          _isRsvpStatusLoading = false; // Mark status loading as complete
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _isRsvpStatusLoading =
              false; // Mark status loading as complete even on error
        });
      }
    }
  }

  Future<void> _rsvpForEvent() async {
    if (_isRsvpLoading) return;
    final currentUser = CustomerController.logeInCustomer;
    if (currentUser == null) {
      ShowToast().showSnackBar('Please sign in to RSVP', context);
      return;
    }

    setState(() {
      _isRsvpLoading = true;
    });

    try {
      if (_isRsvped) {
        // User wants to un-RSVP
        await _unrsvpFromEvent();
      } else {
        // User wants to RSVP
        // Avoid duplicate RSVP
        final already = await FirebaseFirestoreHelper().checkIfUserIsRegistered(
          eventModel.id,
        );
        if (!already) {
          final registrationId = FirebaseFirestore.instance
              .collection(AttendanceModel.registerFirebaseKey)
              .doc()
              .id;
          final registration = AttendanceModel(
            id: registrationId,
            eventId: eventModel.id,
            userName: currentUser.name,
            customerUid: currentUser.uid,
            attendanceDateTime: DateTime.now(),
            answers: [],
            isAnonymous: false,
            realName: currentUser.name,
          );
          await FirebaseFirestore.instance
              .collection(AttendanceModel.registerFirebaseKey)
              .doc(registrationId)
              .set(registration.toJson());
        }

        if (mounted) {
          setState(() {
            _isRsvped = true;
            preRegisteredCount = preRegisteredCount + 1;
          });
        }
        if (mounted) {
          ShowToast().showSnackBar("You've RSVP'd", context);
        }
      }
    } catch (e) {
      if (mounted) {
        ShowToast().showSnackBar(
          _isRsvped
              ? 'Failed to remove RSVP. Please try again.'
              : 'Failed to RSVP. Please try again.',
          context,
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isRsvpLoading = false;
        });
      }
    }
  }

  Future<void> _unrsvpFromEvent() async {
    try {
      final success = await FirebaseFirestoreHelper().unregisterFromEvent(
        eventModel.id,
      );

      if (success && mounted) {
        setState(() {
          _isRsvped = false;
          preRegisteredCount = preRegisteredCount > 0
              ? preRegisteredCount - 1
              : 0;
        });
        ShowToast().showSnackBar("You've removed your RSVP", context);
      } else if (mounted) {
        ShowToast().showSnackBar(
          'Failed to remove RSVP. Please try again.',
          context,
        );
      }
    } catch (e) {
      if (mounted) {
        ShowToast().showSnackBar(
          'Failed to remove RSVP. Please try again.',
          context,
        );
      }
      rethrow;
    }
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
      Logger.debug('Exist value is $value');
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
          _isDwellTrackingActive = userAttendance.isDwellActive;
        });
      }
    } catch (e) {
      Logger.error('Error checking dwell tracking status: $e');
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
                  color: const Color(0xFF667EEA).withAlpha((0.1 * 255).round()),
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

  bool isInEventInTime() {
    DateTime eventTime = eventModel.selectedDateTime;
    DateTime eventTimeHourBefore = eventTime.subtract(const Duration(hours: 1));
    DateTime eventTimeHourAfter = eventTime.add(const Duration(hours: 1));
    DateTime nowTime = DateTime.now();

    bool eventIsAfter = eventTimeHourBefore.isBefore(nowTime);

    if (kDebugMode) {
      debugPrint('$eventTimeHourBefore.isAfter($nowTime)');
    }
    bool eventIsBefore = eventTimeHourAfter.isAfter(nowTime);

    if (kDebugMode) {
      debugPrint('$eventTimeHourAfter.isBefore($nowTime)');
    }
    bool eventIsNow = eventTime.isAtSameMomentAs(nowTime);

    bool answer = false;
    if (eventIsNow || (eventIsBefore && eventIsAfter)) {
      answer = true;
    }

    if (kDebugMode) {
      debugPrint(
        'answer Is $answer  $eventIsNow || ($eventIsBefore && $eventIsAfter $nowTime -- $eventTimeHourBefore -- $eventTimeHourAfter)',
      );
    }

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

    try {
      final position = await LocationHelper.getCurrentLocation(
        showErrorDialog: true,
        context: context,
      );

      if (position != null) {
        LatLng newLatLng = LatLng(position.latitude, position.longitude);
        bool inRadius = isInInRadius(
          eventModel.getLatLng(),
          eventModel.radius,
          newLatLng,
        );
        if (inRadius) {
          _showSignInDialog();
        }
        Logger.debug(
          'Current Location is $inRadius and radius is ${widget.eventModel.radius}',
        );
      } else {
        Logger.warning('Could not get current location for radius check');
      }
    } catch (e) {
      Logger.error('Error getting location for radius check: $e');
    }
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
                      color: Colors.black.withAlpha((0.1 * 255).round()),
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
                              color: Colors.grey.withAlpha((0.1 * 255).round()),
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
                                  ).withAlpha((0.3 * 255).round()),
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

      Logger.debug('=== SIGN-IN DEBUG ===');
      Logger.debug('Event ID: ${eventModel.id}');
      Logger.debug('User ID: ${CustomerController.logeInCustomer!.uid}');
      Logger.debug('Document ID: $docId');

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

      Logger.debug('Attendance model created: ${newAttendanceModel.toJson()}');

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
      Logger.error('Error is ${e.toString()}');
      _btnCtlr.error();
      ShowToast().showNormalToast(
        msg: 'Failed to sign in: $e. Please try again.',
      );
      Future.delayed(const Duration(seconds: 2), () => _btnCtlr.reset());
    }
  }

  Future<void> _performSignIn(AttendanceModel attendanceModel) async {
    try {
      Logger.debug('Saving attendance to Firestore...');
      await FirebaseFirestore.instance
          .collection(AttendanceModel.firebaseKey)
          .doc(attendanceModel.id)
          .set(attendanceModel.toJson());

      Logger.debug('Attendance saved successfully!');
      _btnCtlr.success();
      ShowToast().showNormalToast(msg: 'Signed In Successfully!');

      // Pop the sign-in dialog
      if (!mounted) return;
      if (Navigator.canPop(context)) {
        Navigator.of(context).pop();
      }

      // Refresh event details to update UI

      setState(() {
        _justSignedIn = true;
      });

      // Reset the button and the flag after a delay
      Future.delayed(const Duration(seconds: 2), () {
        if (!mounted) return;
        _btnCtlr.reset();
        setState(() {
          _justSignedIn = false;
        });
      });

      // Show privacy dialog for dwell tracking if event has location enabled
      if (eventModel.getLocation && !_hasShownPrivacyDialog) {
        Future.delayed(const Duration(seconds: 4), () {
          if (mounted) {
            _showPrivacyDialog();
          }
        });
      }
    } catch (firestoreError) {
      Logger.error('Firestore error during sign-in: $firestoreError');
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
                color: AppThemeColor.dullBlueColor.withValues(alpha: 0.3),
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
                      color: AppThemeColor.darkBlueColor.withValues(alpha: 0.1),
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
                            color: Colors.black.withValues(alpha: 0.02),
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
                                    color: AppThemeColor.orangeColor.withAlpha(
                                      (0.1 * 255).round(),
                                    ),
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
                                        .withAlpha((0.1 * 255).round()),
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
                                color: AppThemeColor.dullFontColor.withValues(
                                  alpha: 153,
                                ),
                                fontFamily: 'Roboto',
                              ),
                              filled: true,
                              fillColor: AppThemeColor.lightBlueColor
                                  .withValues(alpha: 0.1),
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
                    color: Colors.black.withValues(alpha: 0.05),
                    spreadRadius: 0,
                    blurRadius: 10,
                    offset: const Offset(0, -2),
                  ),
                ],
              ),
              child: SafeArea(
                child: SizedBox(
                  width: double.infinity,
                  child: RoundedLoadingButton(
                    animateOnTap: true,
                    borderRadius: 12,
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
            ),
          ],
        ),
      ),
    );
  }

  @override
  void initState() {
    super.initState();

    // Initialize event model
    eventModel = widget.eventModel;

    // Initialize animation controllers first for immediate UI response
    _initAnimationControllers();

    // Start animations immediately
    _fadeController.forward();
    _slideController.forward();
    _pulseController.forward();
    _glowController.forward();

    // Add lifecycle observer
    WidgetsBinding.instance.addObserver(this);

    // Set up the event stream listener with debouncing to prevent excessive updates
    _setupEventStreamListener();

    // Load data progressively to prevent UI blocking
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadDataProgressively();
    });
  }

  void _initAnimationControllers() {
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

    _pulseController = AnimationController(
      duration: const Duration(milliseconds: 1000),
      vsync: this,
    );
    _pulseAnimation = Tween<double>(begin: 1.0, end: 1.2).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    _glowController = AnimationController(
      duration: const Duration(milliseconds: 1500),
      vsync: this,
    );
    _glowAnimation = Tween<double>(begin: 1.0, end: 1.5).animate(
      CurvedAnimation(parent: _glowController, curve: Curves.easeInOut),
    );
  }

  void _setupEventStreamListener() {
    _eventSubscription = FirebaseFirestore.instance
        .collection(EventModel.firebaseKey)
        .doc(widget.eventModel.id)
        .snapshots()
        .listen((snapshot) {
          if (!snapshot.exists || !mounted) return;

          // Debounce rapid stream updates to prevent UI blocking
          _streamDebounceTimer?.cancel();
          _streamDebounceTimer = Timer(const Duration(milliseconds: 300), () {
            if (!mounted) return;
            _processEventUpdate(snapshot);
          });
        });
  }

  void _processEventUpdate(DocumentSnapshot snapshot) {
    final newEventModel = EventModel.fromJson(snapshot.data()!);
    final coordinatesChanged =
        newEventModel.latitude != eventModel.latitude ||
        newEventModel.longitude != eventModel.longitude;

    // Check if ticket settings have changed
    final ticketSettingsChanged =
        newEventModel.ticketsEnabled != eventModel.ticketsEnabled ||
        newEventModel.ticketPrice != eventModel.ticketPrice ||
        newEventModel.maxTickets != eventModel.maxTickets;

    setState(() {
      eventModel = newEventModel;
      // Reset address lookup if coordinates changed
      if (coordinatesChanged) {
        _resolvedAddress = null;
      }

      // Reload Live Quiz if event quiz settings changed
      if (eventModel.hasLiveQuiz) {
        _loadLiveQuizAsync();
      } else {
        _liveQuiz = null;
      }
    });

    // Handle changes asynchronously to avoid blocking UI
    if (coordinatesChanged) {
      _getAddressFromCoordinatesAsync();
    }

    if (ticketSettingsChanged) {
      _handleTicketSettingsChangeAsync(newEventModel);
    }
  }

  /// Progressive data loading to prevent UI blocking
  Future<void> _loadDataProgressively() async {
    try {
      // Phase 1: Load critical user-facing data first
      await _loadCriticalData();

      // Phase 2: Load secondary data with small delays to prevent blocking
      await _loadSecondaryData();

      // Phase 3: Load non-critical background data
      await _loadBackgroundData();
    } catch (e) {
      Logger.error('Error in progressive data loading: $e');
    }
  }

  /// Phase 1: Load critical data needed for immediate user interaction
  Future<void> _loadCriticalData() async {
    if (!mounted) return;

    // Load attendance status first (needed for sign-in functionality)
    await getAttendance();

    // Small delay to prevent blocking
    await Future.delayed(const Duration(milliseconds: 50));

    if (!mounted) return;

    // Load RSVP status (important for user interaction)
    await _checkRsvpStatus();
  }

  /// Phase 2: Load secondary data that affects UI but isn't critical
  Future<void> _loadSecondaryData() async {
    await Future.delayed(const Duration(milliseconds: 100));
    if (!mounted) return;

    // Load these in parallel but separate from critical data
    await Future.wait([_checkFavoriteStatus(), _loadCreatorNameAsync()]);

    await Future.delayed(const Duration(milliseconds: 100));
    if (!mounted) return;

    // Load ticket status
    checkUserTicket(updateUI: true);
  }

  /// Phase 3: Load background data that's nice to have but not immediately needed
  Future<void> _loadBackgroundData() async {
    await Future.delayed(const Duration(milliseconds: 200));
    if (!mounted) return;

    // Load summary data (counts) - this is heavy but not immediately critical
    await _loadEventSummaryAsync();

    await Future.delayed(const Duration(milliseconds: 100));
    if (!mounted) return;

    // Load quiz data if needed
    if (eventModel.hasLiveQuiz) {
      await _loadLiveQuizAsync();
    }

    // Load address in background (lowest priority)
    _getAddressFromCoordinatesAsync();
  }

  Future<void> _loadCreatorName() async {
    try {
      final users = await FirebaseFirestoreHelper().getUsersByIds(
        userIds: [eventModel.customerUid],
      );
      if (users.isNotEmpty && mounted) {
        setState(() {
          _creatorUser = users.first;
          _creatorName = users.first.name;
          _creatorUsername = users.first.username;
        });
      }
    } catch (e) {
      Logger.error('Error loading creator name: $e');
    }
  }

  /// Async wrapper for _loadCreatorName with timeout
  Future<void> _loadCreatorNameAsync() async {
    try {
      await _loadCreatorName().timeout(
        const Duration(seconds: 5),
        onTimeout: () {
          Logger.warning('Creator name loading timed out');
        },
      );
    } catch (e) {
      Logger.error('Error in async creator name loading: $e');
    }
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
      Logger.error('Error checking favorite status: $e');
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
      Logger.error('Error toggling favorite: $e');
    }
  }

  Future<void> _loadLiveQuiz() async {
    if (!eventModel.hasLiveQuiz || eventModel.liveQuizId == null) {
      setState(() => _liveQuiz = null);
      return;
    }

    try {
      final quiz = await _liveQuizService.getQuiz(eventModel.liveQuizId!);
      if (mounted) {
        setState(() {
          _liveQuiz = quiz;
        });
      }
    } catch (e) {
      Logger.error('Error loading live quiz: $e');
    }
  }

  /// Async wrapper for _loadLiveQuiz with timeout
  Future<void> _loadLiveQuizAsync() async {
    try {
      await _loadLiveQuiz().timeout(
        const Duration(seconds: 8),
        onTimeout: () {
          Logger.warning('Live quiz loading timed out');
        },
      );
    } catch (e) {
      Logger.error('Error in async live quiz loading: $e');
    }
  }

  /// Handle ticket settings changes asynchronously
  Future<void> _handleTicketSettingsChangeAsync(
    EventModel newEventModel,
  ) async {
    try {
      Logger.info('Ticket settings changed - refreshing ticket status');

      // If tickets are now disabled, clear the ticket status
      if (!newEventModel.ticketsEnabled) {
        if (mounted) {
          setState(() {
            _hasTicket = false;
          });
        }
      } else {
        // Re-check if user has a ticket for this event
        await checkUserTicket(updateUI: true);
      }

      // Refresh the attendance and ticket counts in background
      _loadEventSummaryAsync();
    } catch (e) {
      Logger.error('Error handling ticket settings change: $e');
    }
  }

  void _navigateToQuizBuilder() {
    Navigator.pop(context); // Close modal first
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => QuizBuilderScreen(
          eventId: eventModel.id,
          existingQuizId: eventModel.liveQuizId,
        ),
      ),
    ).then((_) {
      // Reload quiz after returning from builder
      _loadLiveQuiz();
    });
  }

  void _navigateToQuizHost() {
    if (_liveQuiz == null) {
      ShowToast().showNormalToast(msg: 'Quiz not available');
      return;
    }

    Navigator.pop(context); // Close modal first
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => QuizHostScreen(quizId: _liveQuiz!.id),
      ),
    ).then((_) {
      // Reload quiz after returning from host
      _loadLiveQuiz();
    });
  }

  void _navigateToQuizParticipant() {
    if (_liveQuiz == null) {
      ShowToast().showNormalToast(msg: 'Quiz not available');
      return;
    }

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => QuizParticipantScreen(
          quizId: _liveQuiz!.id,
          isAnonymous: CustomerController.logeInCustomer == null,
          displayName: CustomerController.logeInCustomer?.name,
        ),
      ),
    );
  }

  @override
  void dispose() {
    // Cancel debounce timer
    _streamDebounceTimer?.cancel();

    // Remove lifecycle observer
    WidgetsBinding.instance.removeObserver(this);

    _fadeController.dispose();
    _slideController.dispose();
    _pulseController.dispose();
    _glowController.dispose();
    _eventSubscription?.cancel();

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

  Future<void> checkUserTicket({bool updateUI = true}) async {
    if (CustomerController.logeInCustomer == null) {
      return;
    }

    // If tickets are not enabled for this event, user can't have a ticket
    if (!eventModel.ticketsEnabled) {
      if (mounted && updateUI) {
        setState(() {
          _hasTicket = false;
          _isCheckingTicket = false;
        });
      }
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
      Logger.error('Error checking user ticket: $e');
      if (mounted && updateUI) {
        setState(() {
          _isCheckingTicket = false;
        });
      }
    }
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
                    color: AppThemeColor.dullBlueColor.withAlpha(
                      (0.3 * 255).round(),
                    ),
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
                          color: AppThemeColor.darkBlueColor.withAlpha(
                            (0.1 * 255).round(),
                          ),
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
                const SizedBox(height: 20),
                // Management options - Compact Grid Layout
                Expanded(
                  child: SingleChildScrollView(
                    controller: scrollController,
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Quick Actions Grid (Most Used)
                        _buildSectionHeader(
                          title: 'Quick Actions',
                          icon: Icons.flash_on,
                          color: const Color(0xFF667EEA),
                        ),
                        const SizedBox(height: 12),
                        _buildCompactActionsGrid([
                          _CompactAction(
                            icon: Icons.confirmation_number,
                            title: 'Tickets',
                            subtitle: 'Manage',
                            color: const Color(0xFF667EEA),
                            onTap: () {
                              Navigator.pop(context);
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (context) => TicketManagementScreen(
                                    eventModel: eventModel,
                                  ),
                                ),
                              ).then((_) => _showEventManagementModal());
                            },
                          ),
                          _CompactAction(
                            icon: Icons.qr_code_scanner,
                            title: 'Scanner',
                            subtitle: 'Scan Tickets',
                            color: const Color(0xFF10B981),
                            onTap: () {
                              Navigator.pop(context);
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (context) => TicketScannerScreen(
                                    eventId: eventModel.id,
                                    eventTitle: eventModel.title,
                                  ),
                                ),
                              ).then((_) => _showEventManagementModal());
                            },
                          ),
                          _CompactAction(
                            icon: Icons.people,
                            title: 'Attendance',
                            subtitle: 'View Records',
                            color: const Color(0xFFEC4899),
                            onTap: () {
                              Navigator.pop(context);
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (context) => AttendanceSheetScreen(
                                    eventModel: eventModel,
                                  ),
                                ),
                              ).then((_) => _showEventManagementModal());
                            },
                          ),
                          _CompactAction(
                            icon: Icons.qr_code,
                            title: 'Sign-In QR',
                            subtitle: 'Share Code',
                            color: const Color(0xFFFF9800),
                            onTap: () {
                              Navigator.pop(context);
                              showDialog(
                                context: context,
                                barrierDismissible: true,
                                builder: (context) =>
                                    ShareQRDialog(singleEvent: eventModel),
                              ).then((_) => _showEventManagementModal());
                            },
                          ),
                        ]),

                        const SizedBox(height: 24),

                        // Communication & Engagement
                        _buildSectionHeader(
                          title: 'Communication',
                          icon: Icons.campaign,
                          color: const Color(0xFF8B5CF6),
                        ),
                        const SizedBox(height: 12),
                        _buildCompactActionsGrid([
                          _CompactAction(
                            icon: Icons.notifications,
                            title: 'Notify',
                            subtitle: 'Send Updates',
                            color: const Color(0xFFEF4444),
                            onTap: () {
                              Navigator.pop(context);
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (context) =>
                                      const AttendeeNotificationScreen(),
                                ),
                              ).then((_) => _showEventManagementModal());
                            },
                          ),
                          _CompactAction(
                            icon: Icons.feedback,
                            title: 'Feedback',
                            subtitle: 'Manage Reviews',
                            color: const Color(0xFF06B6D4),
                            onTap: () {
                              Navigator.pop(context);
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (context) =>
                                      EventFeedbackManagementScreen(
                                        eventModel: eventModel,
                                      ),
                                ),
                              ).then((_) => _showEventManagementModal());
                            },
                          ),
                          if (!eventModel.hasLiveQuiz)
                            _CompactAction(
                              icon: Icons.quiz,
                              title: 'Live Quiz',
                              subtitle: 'Create Quiz',
                              color: const Color(0xFF7C3AED),
                              onTap: _navigateToQuizBuilder,
                            )
                          else
                            _CompactAction(
                              icon: _liveQuiz?.isDraft == true
                                  ? Icons.edit
                                  : Icons.quiz,
                              title: 'Live Quiz',
                              subtitle: _liveQuiz?.isDraft == true
                                  ? 'Edit Quiz'
                                  : 'Manage',
                              color: const Color(0xFF7C3AED),
                              onTap: _liveQuiz?.isDraft == true
                                  ? _navigateToQuizBuilder
                                  : _navigateToQuizHost,
                            ),
                          _CompactAction(
                            icon: Icons.map,
                            title: 'Location',
                            subtitle: 'Edit Place',
                            color: const Color(0xFF3B82F6),
                            onTap: () {
                              Navigator.pop(context);
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (context) =>
                                      ChoseLocationInMapScreen(
                                        selectedDateTime:
                                            eventModel.selectedDateTime,
                                        eventDurationHours:
                                            eventModel.eventDuration,
                                      ),
                                ),
                              ).then((_) => _showEventManagementModal());
                            },
                          ),
                        ]),

                        const SizedBox(height: 24),

                        // Analytics & Promotion
                        Consumer<SubscriptionService>(
                          builder: (context, subscriptionService, child) {
                            final canAccessAnalytics = subscriptionService
                                .canAccessAnalytics();

                            return Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                _buildSectionHeader(
                                  title: 'Insights & Growth',
                                  icon: Icons.trending_up,
                                  color: const Color(0xFF10B981),
                                ),
                                const SizedBox(height: 12),
                                _buildCompactActionsGrid([
                                  _CompactAction(
                                    icon: Icons.analytics,
                                    title: 'Analytics',
                                    subtitle: canAccessAnalytics
                                        ? 'View Insights'
                                        : 'Premium',
                                    color: const Color(0xFF059669),
                                    isPremium: !canAccessAnalytics,
                                    onTap: () {
                                      Navigator.pop(context);
                                      if (!canAccessAnalytics) {
                                        UpgradePromptDialog.showAnalyticsUpgrade(
                                          context,
                                        );
                                        return;
                                      }
                                      Navigator.push(
                                        context,
                                        MaterialPageRoute(
                                          builder: (context) =>
                                              EventAnalyticsScreen(
                                                eventId: eventModel.id,
                                              ),
                                        ),
                                      ).then(
                                        (_) => _showEventManagementModal(),
                                      );
                                    },
                                  ),
                                  _CompactAction(
                                    icon: eventModel.isFeatured
                                        ? Icons.star
                                        : Icons.star_border,
                                    title: 'Feature',
                                    subtitle: eventModel.isFeatured
                                        ? 'Featured'
                                        : eventModel.selectedDateTime.isBefore(
                                            DateTime.now(),
                                          )
                                        ? 'Past Event'
                                        : 'Promote',
                                    color: const Color(0xFFFF9800),
                                    isDisabled:
                                        eventModel.isFeatured ||
                                        eventModel.selectedDateTime.isBefore(
                                          DateTime.now(),
                                        ),
                                    onTap:
                                        (eventModel.isFeatured ||
                                            eventModel.selectedDateTime
                                                .isBefore(DateTime.now()))
                                        ? null
                                        : () {
                                            Navigator.pop(context);
                                            Navigator.push(
                                              context,
                                              MaterialPageRoute(
                                                builder: (context) =>
                                                    FeatureEventScreen(
                                                      eventModel: eventModel,
                                                    ),
                                              ),
                                            );
                                          },
                                  ),
                                  if (_liveQuiz != null &&
                                      (_liveQuiz!.isLive || _liveQuiz!.isEnded))
                                    _CompactAction(
                                      icon: Icons.emoji_events,
                                      title: 'Quiz Results',
                                      subtitle: 'View Analytics',
                                      color: const Color(0xFF7C3AED),
                                      onTap: () {
                                        Navigator.pop(context);
                                        Navigator.push(
                                          context,
                                          MaterialPageRoute(
                                            builder: (context) =>
                                                QuizHostScreen(
                                                  quizId: _liveQuiz!.id,
                                                ),
                                          ),
                                        ).then((_) => _loadLiveQuiz());
                                      },
                                    ),
                                ]),
                              ],
                            );
                          },
                        ),

                        // Private Event Management (if applicable)
                        if (eventModel.private) ...[
                          const SizedBox(height: 24),
                          _buildSectionHeader(
                            title: 'Private Access',
                            icon: Icons.lock,
                            color: const Color(0xFFEF4444),
                          ),
                          const SizedBox(height: 12),
                          _buildCompactActionsGrid([
                            _CompactAction(
                              icon: Icons.person_add,
                              title: 'Invites',
                              subtitle: 'Manage Access',
                              color: const Color(0xFFDC2626),
                              onTap: () {
                                Navigator.pop(context);
                                showModalBottomSheet(
                                  context: context,
                                  isScrollControlled: true,
                                  builder: (_) => DraggableScrollableSheet(
                                    initialChildSize: 0.85,
                                    minChildSize: 0.5,
                                    maxChildSize: 0.95,
                                    expand: false,
                                    builder: (_, index) =>
                                        AccessListManagementWidget(
                                          eventModel: eventModel,
                                        ),
                                  ),
                                ).then((_) => _showEventManagementModal());
                              },
                            ),
                            _CompactAction(
                              icon: Icons.person_search,
                              title: 'Requests',
                              subtitle: 'Review Access',
                              color: const Color(0xFFEAB308),
                              onTap: () {
                                Navigator.pop(context);
                                showModalBottomSheet(
                                  context: context,
                                  isScrollControlled: true,
                                  builder: (_) => DraggableScrollableSheet(
                                    initialChildSize: 0.85,
                                    minChildSize: 0.5,
                                    maxChildSize: 0.95,
                                    expand: false,
                                    builder: (_, index) => _AccessRequestsList(
                                      eventId: eventModel.id,
                                    ),
                                  ),
                                ).then((_) => _showEventManagementModal());
                              },
                            ),
                          ]),
                        ],

                        const SizedBox(height: 32), // Extra space at bottom
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

  Widget _buildSectionHeader({
    required String title,
    required IconData icon,
    required Color color,
  }) {
    return Row(
      children: [
        Container(
          width: 28,
          height: 28,
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, color: color, size: 16),
        ),
        const SizedBox(width: 12),
        Text(
          title,
          style: const TextStyle(
            color: Color(0xFF1A1A1A),
            fontWeight: FontWeight.w700,
            fontSize: 18,
            fontFamily: 'Roboto',
            letterSpacing: -0.2,
          ),
        ),
      ],
    );
  }

  Widget _buildCompactActionsGrid(List<_CompactAction> actions) {
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      padding: EdgeInsets.zero,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        childAspectRatio: 1.15,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
      ),
      itemCount: actions.length,
      itemBuilder: (context, index) {
        final action = actions[index];
        return _buildCompactActionCard(action);
      },
    );
  }

  Widget _buildCompactActionCard(_CompactAction action) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: action.isDisabled ?? false
              ? const Color(0xFFE5E7EB)
              : action.color.withValues(alpha: 0.15),
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
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
          onTap: action.isDisabled ?? false ? null : action.onTap,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // Icon with background
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: action.isDisabled ?? false
                        ? const Color(0xFFF3F4F6)
                        : action.color.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      Icon(
                        action.icon,
                        color: action.isDisabled ?? false
                            ? const Color(0xFF9CA3AF)
                            : action.color,
                        size: 24,
                      ),
                      // Premium badge overlay
                      if (action.isPremium ?? false)
                        Positioned(
                          top: 2,
                          right: 2,
                          child: Container(
                            width: 16,
                            height: 16,
                            decoration: BoxDecoration(
                              color: const Color(0xFFFFD700),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: Colors.white, width: 1),
                            ),
                            child: const Icon(
                              Icons.star,
                              color: Colors.white,
                              size: 10,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                // Title
                Text(
                  action.title,
                  style: TextStyle(
                    color: action.isDisabled ?? false
                        ? const Color(0xFF9CA3AF)
                        : const Color(0xFF1A1A1A),
                    fontWeight: FontWeight.w600,
                    fontSize: 16,
                    fontFamily: 'Roboto',
                    letterSpacing: -0.1,
                  ),
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 4),
                // Subtitle
                Text(
                  action.subtitle,
                  style: TextStyle(
                    color: action.isDisabled ?? false
                        ? const Color(0xFFD1D5DB)
                        : const Color(0xFF6B7280),
                    fontSize: 12,
                    fontFamily: 'Roboto',
                    letterSpacing: 0.1,
                  ),
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _showQuickShareOptions() {
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
            initialChildSize: 0.5,
            minChildSize: 0.5,
            maxChildSize: 0.5,
            builder: (context, scrollController) => Column(
              children: [
                // Handle bar
                Container(
                  margin: const EdgeInsets.only(top: 12),
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: AppThemeColor.dullBlueColor.withAlpha(
                      (0.3 * 255).round(),
                    ),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(height: 16),
                // Header
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: AppThemeColor.darkBlueColor.withAlpha(
                            (0.1 * 255).round(),
                          ),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Icon(
                          CupertinoIcons.share,
                          color: AppThemeColor.darkBlueColor,
                          size: 24,
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Text(
                          'Share Event',
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
                // Share options
                Expanded(
                  child: SingleChildScrollView(
                    controller: scrollController,
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    child: Column(
                      children: [
                        _buildShareOption(
                          icon: CupertinoIcons.share,
                          title: 'Share Event Details',
                          subtitle: 'Share event information with others',
                          onTap: () {
                            Navigator.pop(context);
                            _shareEventDetails();
                          },
                        ),
                        const SizedBox(height: 12),
                        _buildShareOption(
                          icon: Icons.calendar_today,
                          title: 'Add to Calendar',
                          subtitle: 'Add event to your calendar',
                          onTap: () {
                            Navigator.pop(context);
                            _addToCalendar();
                          },
                        ),
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

  Widget _buildShareOption({
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE5E7EB), width: 1),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withAlpha((0.05 * 255).round()),
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
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: const Color(0xFFF3F4F6),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(icon, color: const Color(0xFF6B7280), size: 20),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: const TextStyle(
                          color: Color(0xFF1A1A1A),
                          fontWeight: FontWeight.w600,
                          fontSize: 16,
                          fontFamily: 'Roboto',
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        subtitle,
                        style: const TextStyle(
                          color: Color(0xFF6B7280),
                          fontSize: 14,
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
        ),
      ),
    );
  }

  void _shareEventDetails() {
    final eventUrl = 'https://attendus.app/event/${eventModel.id}';
    final shareText =
        '''
${eventModel.title}

 ${eventModel.description}

  📅 ${DateFormat('EEEE, MMMM d, y').format(eventModel.selectedDateTime)}
  ⏰ ${DateFormat('h:mm a').format(eventModel.selectedDateTime)} – ${DateFormat('h:mm a').format(eventModel.eventEndTime)}
📍 ${eventModel.location}

Join us at: $eventUrl
''';

    Share.share(shareText);
  }

  void _handleSignIn() {
    // Check if already signed in
    if (signedIn == null || signedIn!) {
      ShowToast().showNormalToast(
        msg: 'You\'re already signed in for this event.',
      );
      return;
    }

    // Show sign-in method selector
    _showSignInMethodSelector();
  }

  void _showSignInMethodSelector() {
    final availableMethods = eventModel.signInMethods;

    if (availableMethods.length == 1) {
      // Only one method available, use it directly
      _handleSignInMethod(availableMethods.first);
      return;
    }

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        padding: const EdgeInsets.all(20),
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.only(
            topLeft: Radius.circular(20),
            topRight: Radius.circular(20),
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey[300],
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 20),
            Text(
              'Choose Sign-In Method',
              style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: Color(0xFF1A1A1A),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              eventModel.title,
              style: TextStyle(fontSize: 16, color: Colors.grey[600]),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            ...availableMethods.map((method) => _buildSignInMethodTile(method)),
            const SizedBox(height: 20),
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSignInMethodTile(String method) {
    Map<String, dynamic> methodInfo = _getMethodInfo(method);

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () {
            Navigator.pop(context);
            _handleSignInMethod(method);
          },
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: methodInfo['color'].withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: methodInfo['color'], width: 1),
            ),
            child: Row(
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: methodInfo['color'],
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    methodInfo['icon'],
                    color: Colors.white,
                    size: 24,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        methodInfo['title'],
                        style: TextStyle(
                          color: methodInfo['color'],
                          fontWeight: FontWeight.w600,
                          fontSize: 16,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        methodInfo['description'],
                        style: TextStyle(color: Colors.grey[600], fontSize: 14),
                      ),
                    ],
                  ),
                ),
                Icon(
                  Icons.arrow_forward_ios,
                  color: methodInfo['color'],
                  size: 16,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Map<String, dynamic> _getMethodInfo(String method) {
    switch (method) {
      case 'facial_recognition':
        return {
          'title': 'Facial Recognition',
          'description': 'Sign in with face scan',
          'icon': Icons.face,
          'color': const Color(0xFFFF6B6B),
        };
      case 'qr_code':
        return {
          'title': 'QR Code',
          'description': 'Scan QR codes for quick sign-in',
          'icon': Icons.qr_code_scanner,
          'color': const Color(0xFF667EEA),
        };
      case 'manual_code':
        return {
          'title': 'Manual Code',
          'description': 'Enter event code manually',
          'icon': Icons.keyboard,
          'color': const Color(0xFF764BA2),
        };
      case 'geofence':
        return {
          'title': 'Geofence',
          'description': 'Auto-sign-in when near event',
          'icon': Icons.location_on,
          'color': const Color(0xFFF093FB),
        };
      default:
        return {
          'title': 'Sign In',
          'description': 'Sign in to event',
          'icon': Icons.login,
          'color': const Color(0xFF667EEA),
        };
    }
  }

  void _handleSignInMethod(String method) {
    switch (method) {
      case 'facial_recognition':
        _handleFacialRecognitionSignIn();
        break;
      case 'qr_code':
      case 'manual_code':
        Navigator.push(
          context,
          MaterialPageRoute(builder: (context) => const QRScannerFlowScreen()),
        );
        break;
      case 'geofence':
        // Geofence is handled automatically by location services
        ShowToast().showNormalToast(
          msg:
              'Geofence sign-in is automatic when you\'re near the event location.',
        );
        break;
    }
  }

  void _handleFacialRecognitionSignIn() async {
    if (CustomerController.logeInCustomer == null) {
      ShowToast().showNormalToast(
        msg: 'Please log in to use facial recognition.',
      );
      return;
    }

    // Check if user is enrolled for facial recognition
    final faceService = FaceRecognitionService();
    final isEnrolled = await faceService.isUserEnrolled(
      userId: CustomerController.logeInCustomer!.uid,
      eventId: eventModel.id,
    );

    if (!mounted) return;

    if (isEnrolled) {
      // Navigate to face recognition scanner
      final result = await Navigator.push<bool>(
        context,
        MaterialPageRoute(
          builder: (context) =>
              FaceRecognitionScannerScreen(eventModel: eventModel),
        ),
      );

      if (result == true) {
        // Successful sign-in, refresh attendance status
        getAttendance();
      }
    } else {
      // Show enrollment dialog
      _showFaceEnrollmentDialog();
    }
  }

  void _showFaceEnrollmentDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Face Recognition Setup'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.face, size: 64, color: Color(0xFFFF6B6B)),
            const SizedBox(height: 16),
            const Text(
              'To use facial recognition sign-in, you need to enroll your face first. This is a one-time setup for this event.',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.blue.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  const Icon(Icons.info, color: Colors.blue, size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Your face data is stored securely and only used for this event.',
                      style: TextStyle(color: Colors.blue[800], fontSize: 12),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Not Now'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              _navigateToFaceEnrollment();
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFFF6B6B),
            ),
            child: const Text(
              'Enroll Face',
              style: TextStyle(color: Colors.white),
            ),
          ),
        ],
      ),
    );
  }

  void _navigateToFaceEnrollment() async {
    final result = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (context) => FaceEnrollmentScreen(eventModel: eventModel),
      ),
    );

    if (result == true && mounted) {
      // After successful enrollment, refresh attendance status
      getAttendance();
    }
  }

  void _addToCalendar() async {
    if (!mounted) return;

    try {
      // Show calendar options dialog
      _showCalendarOptionsDialog();
    } catch (e) {
      ShowToast().showNormalToast(msg: 'Failed to add to calendar: $e');
    }
  }

  void _showCalendarOptionsDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Add to Calendar'),
        content: const Text('Choose your calendar app:'),
        actions: [
          _buildCalendarOption(
            icon: Icons.calendar_today,
            title: 'Google Calendar',
            onTap: () {
              Navigator.pop(context);
              _openGoogleCalendar();
            },
          ),
          _buildCalendarOption(
            icon: Icons.calendar_today,
            title: 'Apple Calendar',
            onTap: () {
              Navigator.pop(context);
              _openAppleCalendar();
            },
          ),
          _buildCalendarOption(
            icon: Icons.calendar_today,
            title: 'Outlook Calendar',
            onTap: () {
              Navigator.pop(context);
              _openOutlookCalendar();
            },
          ),
        ],
      ),
    );
  }

  Widget _buildCalendarOption({
    required IconData icon,
    required String title,
    required VoidCallback onTap,
  }) {
    return TextButton(
      onPressed: onTap,
      child: Row(
        children: [Icon(icon, size: 20), const SizedBox(width: 8), Text(title)],
      ),
    );
  }

  void _openGoogleCalendar() async {
    final eventUrl = Uri.encodeFull('''
https://calendar.google.com/calendar/render?action=TEMPLATE&text=${Uri.encodeComponent(eventModel.title)}&dates=${DateFormat('yyyyMMddTHHmmss').format(eventModel.selectedDateTime)}/${DateFormat('yyyyMMddTHHmmss').format(eventModel.eventEndTime)}&details=${Uri.encodeComponent(eventModel.description)}&location=${Uri.encodeComponent(eventModel.location)}
''');

    if (await canLaunchUrl(Uri.parse(eventUrl))) {
      await launchUrl(Uri.parse(eventUrl));
    } else {
      ShowToast().showNormalToast(msg: 'Could not open Google Calendar');
    }
  }

  void _openAppleCalendar() async {
    final eventUrl = Uri.encodeFull('''
https://calendar.google.com/calendar/render?action=TEMPLATE&text=${Uri.encodeComponent(eventModel.title)}&dates=${DateFormat('yyyyMMddTHHmmss').format(eventModel.selectedDateTime)}/${DateFormat('yyyyMMddTHHmmss').format(eventModel.eventEndTime)}&details=${Uri.encodeComponent(eventModel.description)}&location=${Uri.encodeComponent(eventModel.location)}
''');

    if (await canLaunchUrl(Uri.parse(eventUrl))) {
      await launchUrl(Uri.parse(eventUrl));
    } else {
      ShowToast().showNormalToast(msg: 'Could not open Apple Calendar');
    }
  }

  void _openOutlookCalendar() async {
    final eventUrl = Uri.encodeFull('''
https://outlook.live.com/calendar/0/deeplink/compose?subject=${Uri.encodeComponent(eventModel.title)}&body=${Uri.encodeComponent(eventModel.description)}&startdt=${DateFormat('yyyy-MM-ddTHH:mm:ss').format(eventModel.selectedDateTime)}&enddt=${DateFormat('yyyy-MM-ddTHH:mm:ss').format(eventModel.eventEndTime)}
''');

    if (await canLaunchUrl(Uri.parse(eventUrl))) {
      await launchUrl(Uri.parse(eventUrl));
    } else {
      ShowToast().showNormalToast(msg: 'Could not open Outlook Calendar');
    }
  }

  Future<void> _getTicket() async {
    if (CustomerController.logeInCustomer == null) {
      ShowToast().showNormalToast(msg: 'Please log in to get a ticket');
      return;
    }

    // Check if tickets are enabled for this event
    if (!eventModel.ticketsEnabled) {
      ShowToast().showNormalToast(msg: 'This event does not require tickets');
      return;
    }

    setState(() {
      _isGettingTicket = true;
    });

    try {
      // Check if the event has a ticket price
      if (eventModel.ticketPrice != null && eventModel.ticketPrice! > 0) {
        // Handle paid ticket
        await _purchaseTicket();
      } else {
        // Handle free ticket
        await FirebaseFirestoreHelper().issueTicket(
          customerUid: CustomerController.logeInCustomer!.uid,
          eventId: eventModel.id,
          customerName: CustomerController.logeInCustomer!.name,
          eventModel: eventModel,
        );

        if (mounted) {
          setState(() {
            _isGettingTicket = false;
          });

          ShowToast().showNormalToast(msg: 'Ticket obtained successfully!');
          // Refresh ticket status
          checkUserTicket(updateUI: true);
        }
      }
    } catch (e) {
      Logger.error('Error in _getTicket: $e');
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

  Future<void> _purchaseTicket() async {
    try {
      // Create a temporary ticket ID
      final ticketId = FirebaseFirestore.instance
          .collection('Tickets')
          .doc()
          .id;

      // Create payment intent
      final paymentData = await TicketPaymentService.createTicketPaymentIntent(
        eventId: eventModel.id,
        ticketId: ticketId,
        amount: eventModel.ticketPrice!,
        customerUid: CustomerController.logeInCustomer!.uid,
        customerName: CustomerController.logeInCustomer!.name,
        customerEmail: CustomerController.logeInCustomer!.email,
        creatorUid: eventModel.customerUid,
        eventTitle: eventModel.title,
      );

      // Process payment
      final paymentSuccess = await TicketPaymentService.processTicketPayment(
        clientSecret: paymentData['clientSecret'],
        eventTitle: eventModel.title,
      );

      if (paymentSuccess) {
        // Confirm payment and issue ticket
        await TicketPaymentService.confirmTicketPayment(
          paymentIntentId: paymentData['paymentIntentId'],
          ticketId: ticketId,
          eventId: eventModel.id,
        );

        // Issue the paid ticket
        await TicketPaymentService.issuePaidTicket(
          eventId: eventModel.id,
          customerUid: CustomerController.logeInCustomer!.uid,
          customerName: CustomerController.logeInCustomer!.name,
          eventModel: eventModel,
          paymentIntentId: paymentData['paymentIntentId'],
        );

        if (mounted) {
          setState(() {
            _isGettingTicket = false;
          });

          ShowToast().showNormalToast(msg: 'Ticket purchased successfully!');
          // Refresh ticket status
          checkUserTicket(updateUI: true);

          // Removed post-purchase upgrade prompt per new UX
        }
      } else {
        if (mounted) {
          setState(() {
            _isGettingTicket = false;
          });
          ShowToast().showNormalToast(msg: 'Payment cancelled');
        }
      }
    } catch (e) {
      Logger.error('Error purchasing ticket: $e');
      if (mounted) {
        setState(() {
          _isGettingTicket = false;
        });
        ShowToast().showNormalToast(
          msg: 'Failed to purchase ticket: ${e.toString()}',
        );
      }
    }
  }

  /// Gets the address from latitude and longitude coordinates using reverse geocoding
  Future<void> _getAddressFromCoordinates() async {
    // Only attempt if coordinates are available and address hasn't been resolved yet
    if (eventModel.latitude == 0 ||
        eventModel.longitude == 0 ||
        _resolvedAddress != null) {
      return;
    }

    // No UI spinner; silently resolve in background if ever used again

    try {
      List<Placemark> placemarks = await placemarkFromCoordinates(
        eventModel.latitude,
        eventModel.longitude,
      );

      if (placemarks.isNotEmpty && mounted) {
        Placemark place = placemarks[0];

        // Build a formatted address from placemark components
        List<String> addressParts = [];

        // Add street number and name
        if (place.subThoroughfare?.isNotEmpty == true) {
          addressParts.add(place.subThoroughfare!);
        }
        if (place.thoroughfare?.isNotEmpty == true) {
          addressParts.add(place.thoroughfare!);
        }

        // Add locality (city/town)
        if (place.locality?.isNotEmpty == true) {
          addressParts.add(place.locality!);
        }

        // Add administrative area (state/province)
        if (place.administrativeArea?.isNotEmpty == true) {
          addressParts.add(place.administrativeArea!);
        }

        // Add postal code
        if (place.postalCode?.isNotEmpty == true) {
          addressParts.add(place.postalCode!);
        }

        // Add country
        if (place.country?.isNotEmpty == true) {
          addressParts.add(place.country!);
        }

        String formattedAddress = addressParts.join(', ');

        // If we couldn't build a good address, fall back to name or description
        if (formattedAddress.isEmpty) {
          if (place.name?.isNotEmpty == true) {
            formattedAddress = place.name!;
          } else if (place.locality?.isNotEmpty == true) {
            formattedAddress = place.locality!;
          } else {
            formattedAddress =
                'Location coordinates: ${eventModel.latitude.toStringAsFixed(6)}, ${eventModel.longitude.toStringAsFixed(6)}';
          }
        }

        setState(() {
          _resolvedAddress = formattedAddress;
        });

        Logger.debug('Address resolved: $formattedAddress');
      } else {
        throw Exception('No address found for coordinates');
      }
    } catch (e) {
      Logger.error('Error getting address from coordinates: $e');
      if (mounted) {
        setState(() {
          _resolvedAddress =
              'Coordinates: ${eventModel.latitude.toStringAsFixed(6)}, ${eventModel.longitude.toStringAsFixed(6)}';
        });
      }
    }
  }

  /// Async wrapper for address resolution with timeout
  Future<void> _getAddressFromCoordinatesAsync() async {
    try {
      await _getAddressFromCoordinates().timeout(
        const Duration(seconds: 8),
        onTimeout: () {
          Logger.warning('Address resolution timed out');
        },
      );
    } catch (e) {
      Logger.error('Error in async address resolution: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return AppScaffoldWrapper(
      selectedBottomNavIndex: 1, // Groups tab
      backgroundColor: _backgroundColor,
      floatingActionButton:
          eventModel.hasManagementPermissions(
            FirebaseAuth.instance.currentUser!.uid,
          )
          ? _buildFloatingActionButton()
          : null,
      body: SafeArea(
        child: FadeTransition(opacity: _fadeAnimation, child: _bodyView()),
      ),
    );
  }

  Widget _buildFloatingActionButton() {
    return AnimatedBuilder(
      animation: _pulseAnimation,
      builder: (context, child) {
        return Container(
          margin: const EdgeInsets.only(bottom: 24),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [_primaryBlue, _primaryPurple],
            ),
            borderRadius: BorderRadius.circular(28),
            boxShadow: [
              BoxShadow(
                color: _primaryBlue.withValues(alpha: 0.4),
                spreadRadius: 0,
                blurRadius: 15,
                offset: const Offset(0, 6),
              ),
              BoxShadow(
                color: _primaryPurple.withValues(alpha: 0.3),
                spreadRadius: 0,
                blurRadius: 25,
                offset: const Offset(0, 12),
              ),
            ],
          ),
          child: FloatingActionButton.extended(
            onPressed: () => _showEventManagementModal(),
            backgroundColor: Colors.transparent,
            foregroundColor: Colors.white,
            elevation: 0,
            extendedPadding: const EdgeInsets.symmetric(horizontal: 24),
            icon: Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(16),
              ),
              child: const Icon(
                Icons.dashboard_outlined,
                size: 18,
                color: Colors.white,
              ),
            ),
            label: const Text(
              'Manage Event',
              style: TextStyle(
                fontWeight: FontWeight.w700,
                fontFamily: 'Roboto',
                fontSize: 16,
                letterSpacing: 0.2,
              ),
            ),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(28),
            ),
          ),
        );
      },
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
    return AnimatedBuilder(
      animation: _glowAnimation,
      builder: (context, child) {
        return Container(
          width: double.infinity,
          decoration: BoxDecoration(
            color: Colors.white,
            border: Border(bottom: BorderSide(color: _borderColor, width: 1)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.04),
                blurRadius: 6,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
            child: Column(
              children: [
                // Back button, title, and action buttons
                Row(
                  children: [
                    _buildModernButton(
                      icon: Icons.arrow_back_ios_new,
                      onTap: () => Navigator.pop(context),
                      tooltip: 'Back',
                    ),
                    const SizedBox(width: 20),
                    const Expanded(child: SizedBox()),
                    if (eventModel.hasManagementPermissions(
                      FirebaseAuth.instance.currentUser!.uid,
                    ))
                      Row(
                        children: [
                          _buildModernButton(
                            icon: _isFavorited
                                ? Icons.bookmark
                                : Icons.bookmark_border,
                            onTap: _isLoadingFavorite ? null : _toggleFavorite,
                            tooltip: _isFavorited
                                ? 'Remove from Saved'
                                : 'Add to Saved',
                            isLoading: _isLoadingFavorite,
                            isActive: _isFavorited,
                          ),
                          const SizedBox(width: 16),
                          _buildModernButton(
                            icon: CupertinoIcons.share,
                            onTap: () => _showQuickShareOptions(),
                            tooltip: 'Share Event',
                          ),
                        ],
                      )
                    else
                      // QR Scanner, Calendar, Favorite, and Share buttons for non-creators
                      Row(
                        children: [
                          _buildModernButton(
                            icon: Icons.qr_code_scanner,
                            onTap: () => _handleSignIn(),
                            tooltip: 'Sign In',
                          ),
                          const SizedBox(width: 16),
                          _buildCalendarAddButton(
                            onTap: () => _addToCalendar(),
                            tooltip: 'Add to Calendar',
                          ),
                          const SizedBox(width: 16),
                          _buildModernButton(
                            icon: _isFavorited
                                ? Icons.bookmark
                                : Icons.bookmark_border,
                            onTap: _isLoadingFavorite ? null : _toggleFavorite,
                            tooltip: _isFavorited
                                ? 'Remove from Saved'
                                : 'Add to Saved',
                            isLoading: _isLoadingFavorite,
                            isActive: _isFavorited,
                          ),
                          const SizedBox(width: 16),
                          _buildModernButton(
                            icon: CupertinoIcons.share,
                            onTap: () => _shareEventDetails(),
                            tooltip: 'Share Event',
                          ),
                        ],
                      ),
                  ],
                ),
                if (eventModel.status.toLowerCase() == 'cancelled') ...[
                  const SizedBox(height: 10),
                  _buildCanceledBanner(),
                ],
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildModernButton({
    required IconData icon,
    required VoidCallback? onTap,
    required String tooltip,
    bool isLoading = false,
    bool isActive = false,
  }) {
    return Tooltip(
      message: tooltip,
      child: AnimatedBuilder(
        animation: _pulseAnimation,
        builder: (context, child) {
          return GestureDetector(
            onTap: onTap,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: isActive
                    ? _primaryBlue.withValues(alpha: 0.10)
                    : const Color(0xFFF3F4F6),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: isActive
                      ? _primaryBlue.withValues(alpha: 0.30)
                      : _borderColor,
                  width: 1.5,
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.04),
                    spreadRadius: 0,
                    blurRadius: 6,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: isLoading
                  ? const Center(
                      child: SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.5,
                          valueColor: AlwaysStoppedAnimation<Color>(
                            _primaryBlue,
                          ),
                        ),
                      ),
                    )
                  : Icon(
                      icon,
                      color: isActive ? _primaryBlue : _darkText,
                      size: 20,
                    ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildCalendarAddButton({
    required VoidCallback? onTap,
    required String tooltip,
  }) {
    return Tooltip(
      message: tooltip,
      child: AnimatedBuilder(
        animation: _pulseAnimation,
        builder: (context, child) {
          return GestureDetector(
            onTap: onTap,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: const Color(0xFFF3F4F6),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: _borderColor, width: 1.5),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.04),
                    spreadRadius: 0,
                    blurRadius: 6,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Stack(
                children: [
                  // Main calendar icon
                  Center(
                    child: Icon(
                      Icons.calendar_today,
                      color: _darkText,
                      size: 20,
                    ),
                  ),
                  // Plus badge in top-right corner
                  Positioned(
                    top: 2,
                    right: 2,
                    child: Container(
                      width: 14,
                      height: 14,
                      decoration: BoxDecoration(
                        color: _primaryBlue,
                        borderRadius: BorderRadius.circular(7),
                        border: Border.all(
                          color: const Color(0xFFF3F4F6),
                          width: 1.5,
                        ),
                      ),
                      child: const Icon(
                        Icons.add,
                        color: Colors.white,
                        size: 8,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _contentView() {
    return SlideTransition(
      position: _slideAnimation,
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
        physics: const BouncingScrollPhysics(),
        child: Column(
          children: [
            // Event Image
            _buildEventImage(),
            const SizedBox(height: 24),

            // Live Quiz Card (prominently displayed under event image)
            if (eventModel.hasLiveQuiz && _liveQuiz != null)
              _buildLiveQuizCard(),
            if (eventModel.hasLiveQuiz && _liveQuiz != null)
              const SizedBox(height: 24),

            // RSVP Button
            _buildRsvpButton(),
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

            // RSVPs horizontal list (above attendees)
            PreRegisteredHorizontalList(eventModel: eventModel),
            const SizedBox(height: 8),

            // Attendees List (for everyone) - Now as dropdown
            _buildAttendeesDropdown(),
            const SizedBox(height: 24),

            // Comments Section (for everyone)
            CommentsSection(eventModel: eventModel),
            const SizedBox(height: 24),

            // Dwell tracking UI hidden in public view; functionality remains available elsewhere
            const SizedBox(height: 140), // Increased space for bottom buttons
          ],
        ),
      ),
    );
  }

  Widget _buildCanceledBanner() {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: Colors.red.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.red.withValues(alpha: 0.2)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          const Icon(Icons.cancel, color: Colors.red, size: 18),
          const SizedBox(width: 10),
          const Expanded(
            child: Text(
              'Event canceled',
              style: TextStyle(
                color: Colors.red,
                fontWeight: FontWeight.w700,
                fontSize: 14,
                letterSpacing: 0.1,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _startDwellTracking() async {
    if (CustomerController.logeInCustomer == null) {
      ShowToast().showNormalToast(
        msg: 'Please log in to enable dwell tracking',
      );
      return;
    }

    try {
      await DwellTimeTracker.startDwellTracking(eventModel.id);
      // Start monitoring location to track exit/away automatically
      DwellTimeTracker.startLocationMonitoring(eventModel.id);

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

  // ignore: unused_element
  Future<void> _stopDwellTracking() async {
    if (CustomerController.logeInCustomer == null) return;

    try {
      await DwellTimeTracker.stopDwellTracking(eventModel.id);

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

  Widget _buildEventImage() {
    return AnimatedBuilder(
      animation: _pulseAnimation,
      builder: (context, child) {
        return Container(
          width: double.infinity,
          height: 220,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(24),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.15),
                spreadRadius: 0,
                blurRadius: 25,
                offset: const Offset(0, 8),
              ),
              BoxShadow(
                color: _primaryBlue.withValues(alpha: 0.1),
                spreadRadius: 0,
                blurRadius: 40,
                offset: const Offset(0, 16),
              ),
            ],
          ),
          child: Stack(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(24),
                child: CachedNetworkImage(
                  imageUrl: eventModel.imageUrl,
                  fit: BoxFit.cover,
                  width: double.infinity,
                  height: 220,
                  placeholder: (context, url) => Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [_backgroundColor, _borderColor],
                      ),
                    ),
                    child: Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          CircularProgressIndicator(
                            color: _primaryBlue,
                            strokeWidth: 3,
                          ),
                          const SizedBox(height: 16),
                          Text(
                            'Loading image...',
                            style: TextStyle(
                              color: _lightText,
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                              fontFamily: 'Roboto',
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  errorWidget: (context, url, error) => Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [_backgroundColor, _borderColor],
                      ),
                    ),
                    child: Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Container(
                            width: 64,
                            height: 64,
                            decoration: BoxDecoration(
                              color: _primaryBlue.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(32),
                            ),
                            child: Icon(
                              Icons.image_not_supported_outlined,
                              color: _primaryBlue,
                              size: 32,
                            ),
                          ),
                          const SizedBox(height: 16),
                          Text(
                            'Image not available',
                            style: TextStyle(
                              color: _mediumText,
                              fontSize: 16,
                              fontWeight: FontWeight.w500,
                              fontFamily: 'Roboto',
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Unable to load event image',
                            style: TextStyle(
                              color: _lightText,
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
              // Gradient overlay for better text readability if needed
              Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(24),
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.transparent,
                      Colors.black.withValues(alpha: 0.02),
                    ],
                  ),
                ),
              ),
              // Subtle border
              Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.1),
                    width: 1,
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildFeaturedBadge() {
    return AnimatedBuilder(
      animation: _pulseAnimation,
      builder: (context, child) {
        return Transform.scale(
          scale: 1.0 + (0.05 * sin(_pulseAnimation.value * 2 * pi)),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  _orange,
                  const Color(0xFFFF5722),
                  const Color(0xFFE65100),
                ],
                stops: const [0.0, 0.6, 1.0],
              ),
              borderRadius: BorderRadius.circular(24),
              boxShadow: [
                BoxShadow(
                  color: _orange.withValues(alpha: 0.4),
                  spreadRadius: 0,
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
                BoxShadow(
                  color: _orange.withValues(alpha: 0.2),
                  spreadRadius: 0,
                  blurRadius: 20,
                  offset: const Offset(0, 8),
                ),
              ],
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.2),
                width: 1,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 24,
                  height: 24,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(
                    Icons.star_rounded,
                    color: Colors.white,
                    size: 16,
                  ),
                ),
                const SizedBox(width: 10),
                const Text(
                  'Featured Event',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                    fontSize: 15,
                    fontFamily: 'Roboto',
                    letterSpacing: 0.5,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildEventDetailsCard() {
    return AnimatedBuilder(
      animation: _fadeAnimation,
      builder: (context, child) {
        return Container(
          width: double.infinity,
          padding: const EdgeInsets.all(28),
          decoration: BoxDecoration(
            color: _cardBackground,
            borderRadius: BorderRadius.circular(24),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.12),
                spreadRadius: 0,
                blurRadius: 30,
                offset: const Offset(0, 8),
              ),
              BoxShadow(
                color: _primaryBlue.withValues(alpha: 0.08),
                spreadRadius: 0,
                blurRadius: 40,
                offset: const Offset(0, 16),
              ),
            ],
            border: Border.all(
              color: _borderColor.withValues(alpha: 0.5),
              width: 1,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Hosted by + Edit row ABOVE the title for better layout
              Row(
                children: [
                  if (_creatorName != null)
                    Material(
                      color: Colors.transparent,
                      child: InkWell(
                        borderRadius: BorderRadius.circular(12),
                        mouseCursor: SystemMouseCursors.click,
                        onTap: () {
                          if (_creatorUser != null) {
                            RouterClass.nextScreenNormal(
                              context,
                              UserProfileScreen(
                                user: _creatorUser!,
                                isOwnProfile:
                                    CustomerController.logeInCustomer?.uid ==
                                    _creatorUser!.uid,
                              ),
                            );
                          }
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: _backgroundColor,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: _borderColor, width: 1),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.person_outline,
                                color: _lightText,
                                size: 16,
                              ),
                              const SizedBox(width: 6),
                              RichText(
                                text: TextSpan(
                                  style: TextStyle(
                                    color: _lightText,
                                    fontWeight: FontWeight.w600,
                                    fontSize: 12,
                                    fontFamily: 'Roboto',
                                  ),
                                  children: [
                                    const TextSpan(text: 'Hosted by '),
                                    TextSpan(
                                      text:
                                          '@${_creatorUsername ?? (_creatorName ?? '')}',
                                      style: const TextStyle(
                                        color: _accentBlue,
                                        decoration: TextDecoration.underline,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  const Spacer(),
                  if (eventModel.hasManagementPermissions(
                    FirebaseAuth.instance.currentUser!.uid,
                  ))
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
                          color: const Color(0xFF667EEA).withValues(alpha: 0.1),
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
                ],
              ),
              const SizedBox(height: 12),
              Text(
                eventModel.title,
                style: TextStyle(
                  color: _darkText,
                  fontWeight: FontWeight.w800,
                  fontSize: 28,
                  fontFamily: 'Roboto',
                  letterSpacing: -0.5,
                  height: 1.2,
                ),
              ),
              const SizedBox(height: 8),
              // Event Details
              _buildDetailItem(
                icon: Icons.calendar_month_rounded,
                label: 'Date',
                value: DateFormat(
                  'EEEE, MMMM dd, yyyy',
                ).format(eventModel.selectedDateTime),
              ),
              const SizedBox(height: 20),
              _buildDetailItem(
                icon: Icons.access_time_rounded,
                label: 'Time',
                value:
                    '${DateFormat('h:mm a').format(eventModel.selectedDateTime)} – ${DateFormat('h:mm a').format(eventModel.eventEndTime)}',
              ),
              const SizedBox(height: 20),
              _buildLocationItem(),
              const SizedBox(height: 20),
              // Ticket Quantity Display
              if (eventModel.ticketsEnabled) _buildTicketQuantityItem(),
              const SizedBox(height: 20),
              // Description
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: _backgroundColor,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: _borderColor, width: 1),
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
                            color: _primaryBlue.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Icon(
                            Icons.description_outlined,
                            color: _primaryBlue,
                            size: 18,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Text(
                          'Description',
                          style: TextStyle(
                            color: _darkText,
                            fontWeight: FontWeight.w700,
                            fontSize: 18,
                            fontFamily: 'Roboto',
                            letterSpacing: -0.2,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Text(
                      eventModel.description,
                      style: TextStyle(
                        color: _mediumText,
                        fontSize: 16,
                        fontFamily: 'Roboto',
                        height: 1.6,
                        letterSpacing: 0.1,
                      ),
                    ),
                  ],
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
      },
    );
  }

  Widget _buildDetailItem({
    required IconData icon,
    required String label,
    required String value,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _backgroundColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _borderColor, width: 1),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            spreadRadius: 0,
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  _primaryBlue.withValues(alpha: 0.15),
                  _primaryBlue.withValues(alpha: 0.08),
                ],
              ),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: _primaryBlue.withValues(alpha: 0.2),
                width: 1,
              ),
            ),
            child: Icon(icon, color: _primaryBlue, size: 24),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    color: _lightText,
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    fontFamily: 'Roboto',
                    letterSpacing: 0.3,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  value,
                  style: TextStyle(
                    color: _darkText,
                    fontWeight: FontWeight.w700,
                    fontSize: 17,
                    fontFamily: 'Roboto',
                    letterSpacing: -0.2,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLocationItem() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _backgroundColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _borderColor, width: 1),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            spreadRadius: 0,
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  _primaryBlue.withValues(alpha: 0.15),
                  _primaryBlue.withValues(alpha: 0.08),
                ],
              ),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: _primaryBlue.withValues(alpha: 0.2),
                width: 1,
              ),
            ),
            child: Icon(
              Icons.location_on_outlined,
              color: _primaryBlue,
              size: 24,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Location',
                  style: TextStyle(
                    color: _lightText,
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    fontFamily: 'Roboto',
                    letterSpacing: 0.3,
                  ),
                ),
                const SizedBox(height: 4),
                _buildLocationText(),
              ],
            ),
          ),
          // Hyper-realistic globe button for map view - with better spacing
          if (eventModel.latitude != 0 && eventModel.longitude != 0) ...[
            const SizedBox(width: 8),
            SizedBox(
              width: 48, // Constraining the button size to prevent overflow
              height: 48,
              child: _buildHyperRealisticGlobeButton(),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildLocationText() {
    // Show optional locationName above the address/location if provided
    final String? locationName = eventModel.locationName;
    final String displayText = eventModel.location;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildPrivateAccessNotice(),
        if (locationName != null && locationName.isNotEmpty) ...[
          Text(
            locationName,
            style: TextStyle(
              color: _darkText,
              fontWeight: FontWeight.w800,
              fontSize: 18,
              fontFamily: 'Roboto',
              letterSpacing: -0.2,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            softWrap: false,
          ),
          const SizedBox(height: 2),
        ],
        Text(
          displayText,
          style: TextStyle(
            color: _darkText,
            fontWeight: FontWeight.w700,
            fontSize: 17,
            fontFamily: 'Roboto',
            letterSpacing: -0.2,
          ),
          maxLines: 3, // Allow up to 3 lines for long addresses
          overflow: TextOverflow.ellipsis,
          softWrap: true,
        ),
        // No reverse-geocoded hint; prioritize creator-entered location
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
        color: const Color(0xFFFF9800).withAlpha((0.05 * 255).round()),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: const Color(0xFFFF9800).withAlpha((0.2 * 255).round()),
          width: 1,
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: const Color(0xFFFF9800).withAlpha((0.1 * 255).round()),
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
                          ).withAlpha((0.2 * 255).round()),
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
                  : const Color(0xFF667EEA).withAlpha((0.1 * 255).round()),
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
                        : const Color(
                            0xFF667EEA,
                          ).withAlpha((0.2 * 255).round()),
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
            color: Colors.black.withAlpha((0.08 * 255).round()),
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
                  color: const Color(0xFF667EEA).withAlpha((0.1 * 255).round()),
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
                  color: const Color(0xFF667EEA).withAlpha((0.1 * 255).round()),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: const Color(
                      0xFF667EEA,
                    ).withAlpha((0.3 * 255).round()),
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

  // Modern Event Ticket Section with Professional UI/UX
  Widget _buildTabbedContentSection() {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF000000).withValues(alpha: 0.04),
            spreadRadius: 0,
            blurRadius: 24,
            offset: const Offset(0, 8),
          ),
          BoxShadow(
            color: const Color(0xFF000000).withValues(alpha: 0.02),
            spreadRadius: 0,
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: Column(
          children: [
            // Modern gradient header - Dynamic based on ticket status
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: eventModel.ticketsEnabled
                      ? [const Color(0xFFFFF4E6), const Color(0xFFFFEDD5)]
                      : [const Color(0xFFF0FDF4), const Color(0xFFDCFCE7)],
                ),
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: [
                        BoxShadow(
                          color: eventModel.ticketsEnabled
                              ? const Color(0xFFFF9800).withValues(alpha: 0.2)
                              : const Color(0xFF10B981).withValues(alpha: 0.2),
                          spreadRadius: 0,
                          blurRadius: 8,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: Icon(
                      eventModel.ticketsEnabled
                          ? Icons.confirmation_number_rounded
                          : Icons.event_available_rounded,
                      color: eventModel.ticketsEnabled
                          ? const Color(0xFFFF9800)
                          : const Color(0xFF10B981),
                      size: 22,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          eventModel.ticketsEnabled
                              ? 'Event Ticket'
                              : 'Event Access',
                          style: const TextStyle(
                            color: Color(0xFF1F2937),
                            fontWeight: FontWeight.w700,
                            fontSize: 17,
                            fontFamily: 'Roboto',
                            letterSpacing: -0.2,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          eventModel.ticketsEnabled
                              ? (eventModel.ticketPrice != null &&
                                        eventModel.ticketPrice! > 0
                                    ? 'Price: \$${eventModel.ticketPrice!.toStringAsFixed(2)}'
                                    : 'Free Ticket Required')
                              : 'Open Event - No Ticket Required',
                          style: const TextStyle(
                            color: Color(0xFF6B7280),
                            fontWeight: FontWeight.w500,
                            fontSize: 13,
                            fontFamily: 'Roboto',
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (_hasTicket && eventModel.ticketsEnabled)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFF10B981).withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: const Color(0xFF10B981).withValues(alpha: 0.3),
                          width: 1,
                        ),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.check_circle,
                            color: Color(0xFF10B981),
                            size: 14,
                          ),
                          SizedBox(width: 4),
                          Text(
                            'Obtained',
                            style: TextStyle(
                              color: Color(0xFF10B981),
                              fontWeight: FontWeight.w600,
                              fontSize: 12,
                              fontFamily: 'Roboto',
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),

            // Ticket Content with padding
            Container(
              padding: const EdgeInsets.all(20),
              child: _buildTicketsTab(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTicketsTab() {
    if (!eventModel.ticketsEnabled) {
      return Container(
        padding: const EdgeInsets.symmetric(vertical: 32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFFF3F4F6),
                borderRadius: BorderRadius.circular(16),
              ),
              child: const Icon(
                Icons.event_available_rounded,
                color: Color(0xFF10B981),
                size: 40,
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              'Free Entry',
              style: TextStyle(
                color: Color(0xFF1F2937),
                fontWeight: FontWeight.w600,
                fontSize: 16,
                fontFamily: 'Roboto',
                letterSpacing: -0.2,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'No ticket required for this event',
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
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Status message with modern design
        if (_hasTicket) ...[
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  const Color(0xFF10B981).withValues(alpha: 0.05),
                  const Color(0xFF059669).withValues(alpha: 0.05),
                ],
              ),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: const Color(0xFF10B981).withValues(alpha: 0.2),
                width: 1,
              ),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(
                    Icons.check_circle_rounded,
                    color: Color(0xFF10B981),
                    size: 20,
                  ),
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'You\'re all set!',
                        style: TextStyle(
                          color: Color(0xFF065F46),
                          fontWeight: FontWeight.w600,
                          fontSize: 15,
                          fontFamily: 'Roboto',
                        ),
                      ),
                      SizedBox(height: 4),
                      Text(
                        'Show your QR code at the event entrance',
                        style: TextStyle(
                          color: Color(0xFF047857),
                          fontSize: 13,
                          fontFamily: 'Roboto',
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
        ] else ...[
          // Info card for getting ticket
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFFF9FAFB),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0xFFE5E7EB), width: 1),
            ),
            child: Row(
              children: [
                const Icon(
                  Icons.info_outline_rounded,
                  color: Color(0xFF6B7280),
                  size: 20,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    eventModel.ticketPrice != null &&
                            eventModel.ticketPrice! > 0
                        ? 'Secure your spot for this event'
                        : 'Reserve your free ticket now',
                    style: const TextStyle(
                      color: Color(0xFF4B5563),
                      fontSize: 14,
                      fontFamily: 'Roboto',
                      height: 1.4,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
        ],

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
                  color: const Color(0xFF10B981).withAlpha((0.3 * 255).round()),
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
                  color: const Color(0xFFFF9800).withValues(alpha: 0.25),
                  spreadRadius: 0,
                  blurRadius: 12,
                  offset: const Offset(0, 6),
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
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            color: Colors.white,
                            strokeWidth: 2.5,
                          ),
                        )
                      : Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(
                              Icons.shopping_bag_rounded,
                              color: Colors.white,
                              size: 20,
                            ),
                            const SizedBox(width: 10),
                            Text(
                              eventModel.ticketPrice != null &&
                                      eventModel.ticketPrice! > 0
                                  ? 'Buy Ticket • \$${eventModel.ticketPrice!.toStringAsFixed(2)}'
                                  : 'Get Free Ticket',
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w600,
                                fontSize: 15,
                                fontFamily: 'Roboto',
                                letterSpacing: -0.2,
                              ),
                            ),
                          ],
                        ),
                ),
              ),
            ),
          ),
      ],
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
            color: Colors.black.withAlpha((0.05 * 255).round()),
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
                      color: const Color(
                        0xFF10B981,
                      ).withAlpha((0.1 * 255).round()),
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
                          eventModel.signInMethods.isEmpty
                              ? 'No Attendance Tracking'
                              : 'Attendees ($actualAttendanceCount)',
                          style: const TextStyle(
                            color: Color(0xFF1A1A1A),
                            fontSize: 18,
                            fontWeight: FontWeight.w600,
                            fontFamily: 'Roboto',
                          ),
                        ),
                        Text(
                          eventModel.signInMethods.isEmpty
                              ? 'No sign-in methods enabled'
                              : 'Tap to see attendees',
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
                    child: eventModel.signInMethods.isEmpty
                        ? _buildNoAttendanceTrackingContent()
                        : _buildAttendeesContent(),
                  )
                : const SizedBox.shrink(),
          ),
        ],
      ),
    );
  }

  Widget _buildRsvpButton() {
    // Hide for event managers
    final String uid = FirebaseAuth.instance.currentUser?.uid ?? '';
    final bool isManager = eventModel.hasManagementPermissions(uid);
    if (isManager) return const SizedBox.shrink();

    return Container(
      width: double.infinity,
      height: 64,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: _isRsvpStatusLoading
              ? [
                  const Color(0xFF9CA3AF),
                  const Color(0xFF6B7280),
                ] // Gray gradient while loading
              : _isRsvped
              ? [const Color(0xFF10B981), const Color(0xFF059669)]
              : [const Color(0xFF667EEA), const Color(0xFF5B67CA)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: _isRsvpStatusLoading
                ? const Color(0xFF9CA3AF).withValues(alpha: 0.3)
                : (_isRsvped
                          ? const Color(0xFF10B981)
                          : const Color(0xFF667EEA))
                      .withValues(alpha: 0.3),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: (_isRsvpLoading || _isRsvpStatusLoading)
              ? null
              : _rsvpForEvent,
          borderRadius: BorderRadius.circular(16),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: (_isRsvpLoading || _isRsvpStatusLoading)
                ? const Center(
                    child: SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.5,
                        color: Colors.white,
                      ),
                    ),
                  )
                : Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Icon(
                          _isRsvped
                              ? Icons.check_circle_outline
                              : Icons.calendar_today_outlined,
                          size: 22,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _isRsvpStatusLoading
                                  ? 'Loading...'
                                  : _isRsvped
                                  ? 'Spot Reserved'
                                  : 'Reserve Your Spot',
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w700,
                                fontSize: 17,
                                fontFamily: 'Roboto',
                                letterSpacing: -0.2,
                              ),
                            ),
                            if (_isRsvped && !_isRsvpStatusLoading) ...[
                              const SizedBox(height: 2),
                              Text(
                                'See you at the event',
                                style: TextStyle(
                                  color: Colors.white.withValues(alpha: 0.9),
                                  fontWeight: FontWeight.w400,
                                  fontSize: 13,
                                  fontFamily: 'Roboto',
                                  letterSpacing: 0.1,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                      if (!_isRsvped && !_isRsvpStatusLoading)
                        Icon(
                          Icons.arrow_forward_ios,
                          size: 16,
                          color: Colors.white.withValues(alpha: 0.8),
                        ),
                    ],
                  ),
          ),
        ),
      ),
    );
  }

  Widget _buildNoAttendanceTrackingContent() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFF6B7280).withAlpha((0.05 * 255).round()),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: const Color(0xFF6B7280).withAlpha((0.2 * 255).round()),
          width: 1,
        ),
      ),
      child: Column(
        children: [
          Icon(Icons.info_outline, color: const Color(0xFF6B7280), size: 48),
          const SizedBox(height: 16),
          const Text(
            'No Attendance Tracking',
            style: TextStyle(
              color: Color(0xFF1A1A1A),
              fontWeight: FontWeight.w600,
              fontSize: 18,
              fontFamily: 'Roboto',
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'This event doesn\'t require attendees to sign in. Anyone can join without tracking their attendance.',
            style: TextStyle(
              color: Colors.grey[600],
              fontSize: 14,
              fontFamily: 'Roboto',
              height: 1.4,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          if (eventModel.hasManagementPermissions(
            FirebaseAuth.instance.currentUser!.uid,
          ))
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: () {
                  Navigator.pop(context);
                  RouterClass.nextScreenNormal(
                    context,
                    EditEventScreen(eventModel: eventModel),
                  );
                },
                icon: const Icon(Icons.edit, size: 18),
                label: const Text(
                  'Enable Sign-In Methods',
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    fontFamily: 'Roboto',
                  ),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF667EEA),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
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
                          color: const Color(
                            0xFF10B981,
                          ).withAlpha((0.1 * 255).round()),
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
                              () async {
                                final customer = await FirebaseFirestoreHelper()
                                    .getSingleCustomer(
                                      customerId: attendee.customerUid,
                                    );
                                if (customer != null && mounted) {
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (context) => UserProfileScreen(
                                        user: customer,
                                        isOwnProfile:
                                            CustomerController
                                                .logeInCustomer
                                                ?.uid ==
                                            customer.uid,
                                      ),
                                    ),
                                  );
                                }
                              }();
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
                                              ).withAlpha((0.3 * 255).round())
                                            : const Color(
                                                0xFF10B981,
                                              ).withAlpha((0.3 * 255).round()),
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
                        color: const Color(
                          0xFF10B981,
                        ).withAlpha((0.1 * 255).round()),
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
                            color: Colors.grey.withAlpha((0.1 * 255).round()),
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
                                          ).withAlpha((0.3 * 255).round())
                                        : const Color(
                                            0xFF10B981,
                                          ).withAlpha((0.3 * 255).round()),
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

  /// Builds a hyper-realistic animated globe button for location viewing
  Widget _buildHyperRealisticGlobeButton() {
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 0.0, end: 1.0),
      duration: const Duration(seconds: 4),
      curve: Curves.easeInOutCubic,
      builder: (context, animationValue, child) {
        return Transform.scale(
          scale: 0.85 + (0.15 * animationValue),
          child: Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              // Enhanced 3D gradient for more realistic sphere effect
              gradient: RadialGradient(
                center: const Alignment(-0.4, -0.6),
                radius: 1.4,
                stops: const [0.0, 0.2, 0.5, 0.7, 0.85, 1.0],
                colors: [
                  const Color(0xFFE6F3FF), // Bright highlight
                  const Color(0xFF87CEEB), // Light sky blue
                  const Color(0xFF4169E1), // Royal blue (ocean)
                  const Color(0xFF1E6091), // Medium ocean blue
                  const Color(0xFF0D2F5C), // Deep ocean
                  const Color(0xFF051529), // Shadow edge
                ],
              ),
              // Enhanced shadows for better 3D effect and clickability cues
              boxShadow: [
                // Outer elevated shadow for clickable appearance
                BoxShadow(
                  color: const Color(0xFF2563EB).withValues(alpha: 0.3),
                  spreadRadius: 1,
                  blurRadius: 16,
                  offset: const Offset(0, 6),
                ),
                // Inner depth shadow
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.4),
                  spreadRadius: -3,
                  blurRadius: 12,
                  offset: const Offset(3, 3),
                ),
                // Subtle outer glow for interactivity
                BoxShadow(
                  color: const Color(0xFF60A5FA).withValues(alpha: 0.6),
                  spreadRadius: 0,
                  blurRadius: 8,
                  offset: const Offset(0, 0),
                ),
              ],
              // Subtle border for clickability
              border: Border.all(
                color: const Color(0xFF93C5FD).withValues(alpha: 0.4),
                width: 0.5,
              ),
            ),
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                borderRadius: BorderRadius.circular(24),
                splashColor: const Color(0xFF60A5FA).withValues(alpha: 0.3),
                highlightColor: const Color(0xFF93C5FD).withValues(alpha: 0.2),
                onTap: () {
                  // Enhanced haptic feedback
                  HapticFeedback.mediumImpact();
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (context) =>
                          EventLocationViewScreen(eventModel: eventModel),
                    ),
                  );
                },
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    // Base globe surface
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: RadialGradient(
                          center: const Alignment(0.2, -0.3),
                          radius: 0.9,
                          colors: [
                            const Color(0xFF228B22).withValues(alpha: 0.3),
                            const Color(0xFF32CD32).withValues(alpha: 0.2),
                            Colors.transparent,
                          ],
                        ),
                      ),
                    ),
                    // Rotating continents
                    Transform.rotate(
                      angle:
                          animationValue *
                          2 *
                          pi /
                          12, // Slower, more realistic rotation
                      child: CustomPaint(
                        size: const Size(40, 40),
                        painter: EnhancedContinentPainter(animationValue),
                      ),
                    ),
                    // Enhanced grid system
                    CustomPaint(
                      size: const Size(42, 42),
                      painter: RealisticGridPainter(animationValue),
                    ),
                    // Atmospheric glow effect
                    Container(
                      width: 42,
                      height: 42,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: RadialGradient(
                          center: const Alignment(-0.3, -0.4),
                          radius: 1.1,
                          colors: [
                            Colors.white.withValues(
                              alpha: 0.4 * animationValue,
                            ),
                            Colors.white.withValues(
                              alpha: 0.1 * animationValue,
                            ),
                            Colors.transparent,
                          ],
                        ),
                      ),
                    ),
                    // Subtle rotating shimmer for interactivity
                    Transform.rotate(
                      angle: animationValue * 2 * pi / 2,
                      child: Container(
                        width: 46,
                        height: 46,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: SweepGradient(
                            colors: [
                              Colors.transparent,
                              Colors.white.withValues(alpha: 0.3),
                              Colors.transparent,
                              Colors.transparent,
                            ],
                            stops: const [0.0, 0.1, 0.2, 1.0],
                          ),
                        ),
                      ),
                    ),
                    // Click indicator pulse
                    AnimatedContainer(
                      duration: Duration(
                        milliseconds: (2000 + (animationValue * 1000)).round(),
                      ),
                      width: 48 + (3 * sin(animationValue * 2 * pi)),
                      height: 48 + (3 * sin(animationValue * 2 * pi)),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: const Color(
                            0xFF60A5FA,
                          ).withValues(alpha: 0.4 * (1 - animationValue * 0.3)),
                          width: 1.5,
                        ),
                      ),
                    ),
                    // Tap indicator overlay
                    Positioned.fill(
                      child: Container(
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: const Color(
                              0xFFFFFFFF,
                            ).withValues(alpha: 0.2),
                            width: 0.5,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildPrivateAccessNotice() {
    final String uid = FirebaseAuth.instance.currentUser?.uid ?? '';
    final bool hasAccess =
        !eventModel.private ||
        eventModel.customerUid == uid ||
        eventModel.coHosts.contains(uid) ||
        eventModel.accessList.contains(uid);

    if (hasAccess) return const SizedBox.shrink();

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFFFFBEB),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFF59E0B)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'This is a private event',
            style: TextStyle(
              fontWeight: FontWeight.w700,
              color: Color(0xFF92400E),
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Request access from the host to view full details.',
            style: TextStyle(color: Color(0xFF92400E)),
          ),
          const SizedBox(height: 12),
          ElevatedButton.icon(
            icon: const Icon(Icons.lock_open),
            label: const Text('Request Access'),
            onPressed: () async {
              await FirebaseFirestoreHelper().requestEventAccess(
                eventId: eventModel.id,
              );
              if (!mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Access request sent')),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildLiveQuizCard() {
    if (_liveQuiz == null) return const SizedBox();

    Color statusColor;
    String statusText;
    String statusDescription;
    String buttonText;
    IconData buttonIcon;
    bool canJoin;

    switch (_liveQuiz!.status) {
      case QuizStatus.live:
        statusColor = const Color(0xFF10B981);
        statusText = '🔴 LIVE NOW';
        statusDescription =
            'Interactive quiz is currently active! Join the competition.';
        buttonText = 'Join Live Quiz';
        buttonIcon = Icons.live_tv;
        canJoin = true;
        break;
      case QuizStatus.draft:
        statusColor = Colors.orange;
        statusText = '⏳ COMING SOON';
        statusDescription =
            'An interactive quiz will be available during this event.';
        buttonText = 'Quiz Starting Soon';
        buttonIcon = Icons.quiz;
        canJoin = false;
        break;
      case QuizStatus.ended:
        statusColor = Colors.grey;
        statusText = '✅ COMPLETED';
        statusDescription =
            'The interactive quiz has ended. Thanks to everyone who participated!';
        buttonText = 'View Results';
        buttonIcon = Icons.emoji_events;
        canJoin = true; // Can view final results
        break;
      case QuizStatus.paused:
        statusColor = Colors.amber;
        statusText = '⏸️ PAUSED';
        statusDescription =
            'Quiz temporarily paused by the host. Please wait...';
        buttonText = 'Quiz Paused';
        buttonIcon = Icons.pause_circle;
        canJoin = false;
        break;
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            const Color(0xFF667EEA).withValues(alpha: 0.15),
            const Color(0xFF764BA2).withValues(alpha: 0.08),
          ],
        ),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: const Color(0xFF667EEA).withValues(alpha: 0.3),
          width: 2,
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF667EEA).withValues(alpha: 0.15),
            spreadRadius: 0,
            blurRadius: 24,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFF667EEA), Color(0xFF764BA2)],
                  ),
                  borderRadius: BorderRadius.circular(24),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF667EEA).withValues(alpha: 0.4),
                      spreadRadius: 0,
                      blurRadius: 12,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: const Icon(Icons.quiz, color: Colors.white, size: 24),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Live Quiz Experience',
                      style: TextStyle(
                        color: Color(0xFF1A1A1A),
                        fontWeight: FontWeight.w700,
                        fontSize: 20,
                        fontFamily: 'Roboto',
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _liveQuiz!.title,
                      style: const TextStyle(
                        color: Color(0xFF667EEA),
                        fontWeight: FontWeight.w600,
                        fontSize: 16,
                        fontFamily: 'Roboto',
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: statusColor,
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color: statusColor.withValues(alpha: 0.3),
                      spreadRadius: 0,
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (_liveQuiz!.status == QuizStatus.live) ...[
                      Container(
                        width: 8,
                        height: 8,
                        decoration: const BoxDecoration(
                          color: Colors.white,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 6),
                    ],
                    Text(
                      statusText,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 0.3,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          Text(
            statusDescription,
            style: TextStyle(
              color: Colors.grey.withValues(alpha: 0.8),
              fontSize: 16,
              fontFamily: 'Roboto',
              height: 1.5,
            ),
          ),
          if (_liveQuiz!.description?.isNotEmpty == true) ...[
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.6),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: const Color(0xFF667EEA).withValues(alpha: 0.2),
                ),
              ),
              child: Text(
                _liveQuiz!.description!,
                style: TextStyle(
                  color: Colors.grey.withValues(alpha: 0.9),
                  fontSize: 15,
                  fontFamily: 'Roboto',
                  height: 1.4,
                ),
              ),
            ),
          ],
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(
                child: _buildQuizInfoChip(
                  Icons.timer,
                  '${_liveQuiz!.timePerQuestion}s per question',
                  const Color(0xFF667EEA),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildQuizInfoChip(
                  Icons.people,
                  '${_liveQuiz!.participantCount} participants',
                  const Color(0xFF10B981),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildQuizInfoChip(
                  Icons.quiz,
                  '${_liveQuiz!.totalQuestions} questions',
                  Colors.orange,
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          Container(
            width: double.infinity,
            height: 56,
            decoration: BoxDecoration(
              gradient: canJoin
                  ? (_liveQuiz!.status == QuizStatus.live
                        ? const LinearGradient(
                            colors: [Color(0xFF10B981), Color(0xFF059669)],
                          )
                        : const LinearGradient(
                            colors: [Color(0xFF667EEA), Color(0xFF764BA2)],
                          ))
                  : LinearGradient(
                      colors: [
                        Colors.grey.withValues(alpha: 0.4),
                        Colors.grey.withValues(alpha: 0.4),
                      ],
                    ),
              borderRadius: BorderRadius.circular(16),
              boxShadow: canJoin
                  ? [
                      BoxShadow(
                        color:
                            (_liveQuiz!.status == QuizStatus.live
                                    ? const Color(0xFF10B981)
                                    : const Color(0xFF667EEA))
                                .withValues(alpha: 0.4),
                        spreadRadius: 0,
                        blurRadius: 16,
                        offset: const Offset(0, 6),
                      ),
                    ]
                  : [],
            ),
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                borderRadius: BorderRadius.circular(16),
                onTap: canJoin ? _navigateToQuizParticipant : null,
                child: Center(
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(buttonIcon, color: Colors.white, size: 24),
                      const SizedBox(width: 12),
                      Text(
                        buttonText,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 18,
                          fontFamily: 'Roboto',
                          letterSpacing: 0.2,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          if (_liveQuiz!.status == QuizStatus.live) ...[
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFF10B981).withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: const Color(0xFF10B981).withValues(alpha: 0.3),
                ),
              ),
              child: Row(
                children: [
                  Container(
                    width: 6,
                    height: 6,
                    decoration: const BoxDecoration(
                      color: Color(0xFF10B981),
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Text(
                      'Quiz is live and accepting participants right now!',
                      style: TextStyle(
                        color: Color(0xFF10B981),
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        fontFamily: 'Roboto',
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

  Widget _buildQuizInfoChip(IconData icon, String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Column(
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(height: 4),
          Text(
            text,
            style: TextStyle(
              fontSize: 12,
              color: color,
              fontWeight: FontWeight.w600,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

/// Compact action class for the grid-based event management interface
class _CompactAction {
  final IconData icon;
  final String title;
  final String subtitle;
  final Color color;
  final VoidCallback? onTap;
  final bool? isPremium;
  final bool? isDisabled;

  const _CompactAction({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.color,
    this.onTap,
    this.isPremium = false,
    this.isDisabled = false,
  });
}

/// Enhanced custom painter for drawing more realistic continent shapes on the globe
class EnhancedContinentPainter extends CustomPainter {
  final double animationValue;

  EnhancedContinentPainter(this.animationValue);

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2;

    // Clip to circle first
    canvas.clipRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(center: center, width: size.width, height: size.height),
        Radius.circular(radius),
      ),
    );

    // Save canvas state for rotation
    canvas.save();
    canvas.translate(center.dx, center.dy);
    canvas.rotate(animationValue * 2 * pi / 15); // Slower rotation
    canvas.translate(-center.dx, -center.dy);

    // Enhanced continent colors with gradients
    final landPaint = Paint()
      ..shader =
          RadialGradient(
            center: const Alignment(0.2, -0.3),
            radius: 1.2,
            colors: [
              const Color(
                0xFF32CD32,
              ).withValues(alpha: 0.9), // Bright green highlight
              const Color(0xFF228B22).withValues(alpha: 0.8), // Medium green
              const Color(
                0xFF006400,
              ).withValues(alpha: 0.7), // Dark green shadow
            ],
          ).createShader(
            Rect.fromCenter(
              center: center,
              width: size.width,
              height: size.height,
            ),
          )
      ..style = PaintingStyle.fill;

    // More realistic continent shapes
    // North America
    final northAmericaPath = Path()
      ..moveTo(center.dx - 12, center.dy - 8)
      ..quadraticBezierTo(
        center.dx - 8,
        center.dy - 12,
        center.dx - 3,
        center.dy - 10,
      )
      ..quadraticBezierTo(
        center.dx + 2,
        center.dy - 8,
        center.dx - 1,
        center.dy - 4,
      )
      ..quadraticBezierTo(
        center.dx - 6,
        center.dy - 2,
        center.dx - 12,
        center.dy - 8,
      )
      ..close();

    // South America
    final southAmericaPath = Path()
      ..addOval(
        Rect.fromCenter(
          center: Offset(center.dx - 6, center.dy + 8),
          width: 5,
          height: 10,
        ),
      );

    // Africa (more detailed)
    final africaPath = Path()
      ..moveTo(center.dx + 2, center.dy - 6)
      ..quadraticBezierTo(
        center.dx + 5,
        center.dy - 4,
        center.dx + 6,
        center.dy + 2,
      )
      ..quadraticBezierTo(
        center.dx + 4,
        center.dy + 8,
        center.dx + 2,
        center.dy + 10,
      )
      ..quadraticBezierTo(
        center.dx - 1,
        center.dy + 8,
        center.dx + 1,
        center.dy + 2,
      )
      ..quadraticBezierTo(
        center.dx - 1,
        center.dy - 2,
        center.dx + 2,
        center.dy - 6,
      )
      ..close();

    // Europe
    final europePath = Path()
      ..addOval(
        Rect.fromCenter(
          center: Offset(center.dx + 2, center.dy - 8),
          width: 4,
          height: 3,
        ),
      );

    // Asia (larger, more detailed)
    final asiaPath = Path()
      ..moveTo(center.dx + 6, center.dy - 8)
      ..quadraticBezierTo(
        center.dx + 12,
        center.dy - 6,
        center.dx + 14,
        center.dy - 2,
      )
      ..quadraticBezierTo(
        center.dx + 12,
        center.dy + 2,
        center.dx + 8,
        center.dy + 1,
      )
      ..quadraticBezierTo(
        center.dx + 4,
        center.dy - 4,
        center.dx + 6,
        center.dy - 8,
      )
      ..close();

    // Australia
    final australiaPath = Path()
      ..addOval(
        Rect.fromCenter(
          center: Offset(center.dx + 10, center.dy + 6),
          width: 3,
          height: 2,
        ),
      );

    // Draw all continents
    canvas.drawPath(northAmericaPath, landPaint);
    canvas.drawPath(southAmericaPath, landPaint);
    canvas.drawPath(africaPath, landPaint);
    canvas.drawPath(europePath, landPaint);
    canvas.drawPath(asiaPath, landPaint);
    canvas.drawPath(australiaPath, landPaint);

    canvas.restore();
  }

  @override
  bool shouldRepaint(EnhancedContinentPainter oldDelegate) {
    return oldDelegate.animationValue != animationValue;
  }
}

/// Custom painter for realistic globe grid lines
class RealisticGridPainter extends CustomPainter {
  final double animationValue;

  RealisticGridPainter(this.animationValue);

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2;

    // Enhanced grid paint with better visibility
    final gridPaint = Paint()
      ..color = Colors.white.withValues(
        alpha: 0.25 + (0.1 * sin(animationValue * 2 * pi)),
      )
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.8;

    final faintGridPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.15)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.4;

    // Clip to circle
    canvas.clipRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(center: center, width: size.width, height: size.height),
        Radius.circular(radius),
      ),
    );

    // Latitude lines (horizontal) - more realistic spacing
    final latitudes = [
      -0.7,
      -0.35,
      0.0,
      0.35,
      0.7,
    ]; // Representing major parallels
    for (double lat in latitudes) {
      final y = center.dy + (radius * lat);
      final lineRadius = radius * cos(lat * pi / 2);

      // Draw elliptical latitude lines for 3D effect
      final path = Path();
      path.addOval(
        Rect.fromCenter(
          center: Offset(center.dx, y),
          width: lineRadius * 2,
          height: lineRadius * 0.3, // Compressed for 3D perspective
        ),
      );

      canvas.drawPath(
        path,
        lat == 0.0 ? gridPaint : faintGridPaint, // Equator more prominent
      );
    }

    // Longitude lines (vertical) - more realistic curved lines
    for (int i = 0; i < 8; i++) {
      final angle = (i * pi / 4);
      final path = Path();

      // Create curved longitude lines
      for (double t = -1.0; t <= 1.0; t += 0.1) {
        final x = center.dx + (radius * 0.9 * sin(angle) * cos(t * pi / 2));
        final y = center.dy + (radius * 0.9 * t);
        final z = cos(angle) * cos(t * pi / 2);

        // Only draw visible parts (front of sphere)
        if (z > 0) {
          if (t == -1.0) {
            path.moveTo(x, y);
          } else {
            path.lineTo(x, y);
          }
        }
      }

      canvas.drawPath(
        path,
        i % 2 == 0 ? gridPaint : faintGridPaint, // Alternate line prominence
      );
    }

    // Add prime meridian emphasis
    final primeMeridianPath = Path();
    primeMeridianPath.moveTo(center.dx, center.dy - radius * 0.9);
    primeMeridianPath.lineTo(center.dx, center.dy + radius * 0.9);

    final primeMeridianPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.4)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0;

    canvas.drawPath(primeMeridianPath, primeMeridianPaint);
  }

  @override
  bool shouldRepaint(RealisticGridPainter oldDelegate) {
    return oldDelegate.animationValue != animationValue;
  }
}

/// Legacy painter class kept for backward compatibility
class ContinentPainter extends CustomPainter {
  final double animationValue;

  ContinentPainter(this.animationValue);

  @override
  void paint(Canvas canvas, Size size) {
    // Redirects to enhanced version
    final enhancedPainter = EnhancedContinentPainter(animationValue);
    enhancedPainter.paint(canvas, size);
  }

  @override
  bool shouldRepaint(ContinentPainter oldDelegate) {
    return oldDelegate.animationValue != animationValue;
  }
}

class _AccessRequestsList extends StatelessWidget {
  final String eventId;
  const _AccessRequestsList({required this.eventId});

  @override
  Widget build(BuildContext context) {
    final col = FirebaseFirestore.instance
        .collection(EventModel.firebaseKey)
        .doc(eventId)
        .collection('AccessRequests')
        .orderBy('createdAt', descending: true);

    return Material(
      child: SafeArea(
        child: StreamBuilder<QuerySnapshot>(
          stream: col.snapshots(),
          builder: (context, snap) {
            if (!snap.hasData) {
              return const Center(child: CircularProgressIndicator());
            }
            final docs = snap.data!.docs;
            if (docs.isEmpty) {
              return const Center(child: Text('No pending requests'));
            }
            return ListView.separated(
              itemCount: docs.length,
              separatorBuilder: (_, index) => const Divider(height: 0),
              itemBuilder: (context, i) {
                final data = docs[i].data() as Map<String, dynamic>;
                final userId = (data['userId'] ?? '').toString();
                final status = (data['status'] ?? 'pending').toString();
                return ListTile(
                  leading: const CircleAvatar(child: Icon(Icons.person)),
                  title: Text(userId),
                  subtitle: Text('Status: $status'),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.check, color: Colors.green),
                        onPressed: () async {
                          await FirebaseFirestoreHelper().approveEventAccess(
                            eventId: eventId,
                            userId: userId,
                          );
                        },
                      ),
                      IconButton(
                        icon: const Icon(Icons.close, color: Colors.red),
                        onPressed: () async {
                          await FirebaseFirestoreHelper().declineEventAccess(
                            eventId: eventId,
                            userId: userId,
                          );
                        },
                      ),
                    ],
                  ),
                );
              },
            );
          },
        ),
      ),
    );
  }
}
