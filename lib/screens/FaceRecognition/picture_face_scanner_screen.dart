import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'package:camera/camera.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import '../../Services/face_recognition_service.dart';
import '../../Services/user_identity_service.dart';
import '../../models/attendance_model.dart';
import '../../models/event_model.dart';
import '../../Utils/logger.dart';
import '../../Utils/toast.dart';
import 'picture_face_enrollment_screen.dart';

/// Picture-based Face Recognition Scanner
/// Uses takePicture() for reliable face detection and matching
class PictureFaceScannerScreen extends StatefulWidget {
  final EventModel eventModel;
  final String? guestUserId;
  final String? guestUserName;

  const PictureFaceScannerScreen({
    super.key,
    required this.eventModel,
    this.guestUserId,
    this.guestUserName,
  });

  @override
  State<PictureFaceScannerScreen> createState() =>
      _PictureFaceScannerScreenState();
}

enum ScanState {
  INITIALIZING,
  READY,
  SCANNING,
  MATCHING,
  SUCCESS,
  NOT_ENROLLED,
  NO_MATCH,
  ERROR,
}

class _PictureFaceScannerScreenState extends State<PictureFaceScannerScreen>
    with TickerProviderStateMixin {
  // State
  ScanState _currentState = ScanState.INITIALIZING;
  String _statusMessage = 'Initializing scanner...';
  String _errorMessage = '';
  UserIdentityResult? _currentUserIdentity;

  // Camera
  CameraController? _cameraController;
  CameraDescription? _selectedCamera;
  bool _isCameraInitialized = false;

  // Face Detection
  final FaceRecognitionService _faceService = FaceRecognitionService();
  FaceDetector? _faceDetector;

  // Scanning
  bool _isScanning = false;
  int _scanAttempts = 0;
  Timer? _autoScanTimer;

  // Animation
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  // Debug
  bool _showDebugPanel = true;
  DateTime _startTime = DateTime.now();

  @override
  void initState() {
    super.initState();
    _logTimestamp('PictureFaceScannerScreen: initState');
    _initializeAnimations();
    _startScanning();
  }

  void _initializeAnimations() {
    _pulseController = AnimationController(
      duration: const Duration(milliseconds: 1200),
      vsync: this,
    );
    _pulseAnimation = Tween<double>(begin: 1.0, end: 1.15).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
    _pulseController.repeat(reverse: true);
  }

  void _startScanning() async {
    _updateState(ScanState.INITIALIZING);

    try {
      // Check if user is enrolled first
      _updateStatus('Checking enrollment status...');
      final isEnrolled = await _checkEnrollmentStatus();

      if (!isEnrolled) {
        _updateState(ScanState.NOT_ENROLLED);
        _updateStatus('Face not enrolled for this event');
        _showEnrollmentPrompt();
        return;
      }

      // Initialize face detector
      _updateStatus('Initializing face recognition...');
      await _initializeFaceDetector();

      // Initialize camera
      _updateStatus('Setting up camera...');
      await _initializeCamera();

      // Ready to scan
      _updateState(ScanState.READY);
      _updateStatus('Position your face to sign in');

      // Start auto-scan
      _startAutoScan();
    } catch (e, stack) {
      _logTimestamp('Initialization error: $e\n$stack');
      _handleError('Initialization failed: $e');
    }
  }

  Future<bool> _checkEnrollmentStatus() async {
    try {
      // Get user identity using centralized service
      final userIdentity = await UserIdentityService.getCurrentUserIdentity(
        guestUserId: widget.guestUserId,
        guestUserName: widget.guestUserName,
      );

      if (userIdentity == null) {
        _logTimestamp('ERROR: No user identity available');
        return false;
      }

      // Log identity details for debugging
      UserIdentityService.logIdentityDetails(userIdentity, 'Scanner Check');
      
      final enrollmentDocId = UserIdentityService.generateEnrollmentDocumentId(
        widget.eventModel.id,
        userIdentity.userId,
      );
      _logTimestamp('Checking enrollment at: FaceEnrollments/$enrollmentDocId');

      final isEnrolled = await _faceService.isUserEnrolled(
        userId: userIdentity.userId,
        eventId: widget.eventModel.id,
      );

      _logTimestamp('Enrollment status for ${userIdentity.userName}: $isEnrolled');
      
      // Store user identity for later use
      _currentUserIdentity = userIdentity;
      
      return isEnrolled;
    } catch (e) {
      _logTimestamp('Error checking enrollment: $e');
      return false;
    }
  }

  Future<void> _initializeFaceDetector() async {
    try {
      final options = FaceDetectorOptions(
        enableContours: false,
        enableLandmarks: true,
        enableClassification: true,
        enableTracking: false,
        minFaceSize: 0.1,
        performanceMode: FaceDetectorMode.accurate,
      );

      _faceDetector = FaceDetector(options: options);
      await _faceService.initialize(useFastMode: false);

      _logTimestamp('Face detector initialized for scanning');
    } catch (e) {
      throw Exception('Failed to initialize face detector: $e');
    }
  }

  Future<void> _initializeCamera() async {
    try {
      final cameras = await availableCameras();

      if (cameras.isEmpty) {
        throw Exception('No cameras found');
      }

      _selectedCamera = cameras.firstWhere(
        (camera) => camera.lensDirection == CameraLensDirection.front,
        orElse: () => cameras.first,
      );

      _cameraController = CameraController(
        _selectedCamera!,
        ResolutionPreset.medium,
        enableAudio: false,
      );

      await _cameraController!.initialize();

      _logTimestamp('Scanner camera initialized');

      if (mounted) {
        setState(() {
          _isCameraInitialized = true;
        });
      }
    } catch (e) {
      throw Exception('Camera setup failed: $e');
    }
  }

  void _startAutoScan() {
    // Auto-scan every 2 seconds
    _autoScanTimer = Timer.periodic(Duration(seconds: 2), (timer) {
      if (mounted && _currentState == ScanState.READY && !_isScanning) {
        _scanFace();
      }
    });

    // Also scan immediately after initialization
    Future.delayed(Duration(milliseconds: 500), () {
      if (mounted && _currentState == ScanState.READY) {
        _scanFace();
      }
    });
  }

  Future<void> _scanFace() async {
    if (_isScanning || !_isCameraInitialized || _cameraController == null) {
      return;
    }

    setState(() {
      _isScanning = true;
      _scanAttempts++;
    });

    _updateState(ScanState.SCANNING);
    _updateStatus('Scanning... Hold still');

    try {
      _logTimestamp('Taking scan photo ${_scanAttempts}...');

      // Take picture
      final XFile imageFile = await _cameraController!.takePicture();
      _logTimestamp('Scan photo taken: ${imageFile.path}');

      // Process the image
      await _processScannedImage(imageFile);

      // Delete temp file
      try {
        await File(imageFile.path).delete();
      } catch (e) {
        _logTimestamp('Could not delete temp file: $e');
      }
    } catch (e) {
      _logTimestamp('Scan error: $e');
      _updateState(ScanState.READY);
      _updateStatus('Scan failed, retrying...');
    } finally {
      setState(() {
        _isScanning = false;
      });
    }
  }

  Future<void> _processScannedImage(XFile imageFile) async {
    try {
      _logTimestamp('Processing scan image: ${imageFile.path}');

      // Create InputImage from file
      final inputImage = InputImage.fromFilePath(imageFile.path);

      // Detect faces
      final faces = await _faceDetector!.processImage(inputImage);
      _logTimestamp('Faces detected in scan: ${faces.length}');

      if (faces.isEmpty) {
        _updateState(ScanState.READY);
        _updateStatus('No face detected - please position your face');
        return;
      }

      final face = faces.first;

      // Check if face is suitable
      if (!_faceService.isFaceSuitable(face)) {
        _updateState(ScanState.READY);
        _updateStatus('Please look straight at the camera');
        return;
      }

      // Match face
      _updateState(ScanState.MATCHING);
      _updateStatus('Matching face...');

      final matchResult = await _faceService.matchFace(
        detectedFace: face,
        eventId: widget.eventModel.id,
      );

      _logTimestamp('Match result: $matchResult');

      if (matchResult != null && matchResult.matched) {
        await _handleSuccessfulMatch(matchResult);
      } else {
        _handleNoMatch(matchResult);
      }
    } catch (e, stack) {
      _logTimestamp('Scan processing error: $e\n$stack');
      _updateState(ScanState.READY);
      _updateStatus('Processing failed, retrying...');
    }
  }

  Future<void> _handleSuccessfulMatch(FaceMatchResult matchResult) async {
    _autoScanTimer?.cancel();
    _updateState(ScanState.SUCCESS);
    _updateStatus('Welcome, ${matchResult.userName}!');

    _logTimestamp('✅ Face matched successfully!');
    _logTimestamp('  - User: ${matchResult.userName}');
    _logTimestamp('  - UserID: ${matchResult.userId}');
    _logTimestamp('  - Confidence: ${(matchResult.confidence * 100).toStringAsFixed(1)}%');

    // Haptic feedback
    HapticFeedback.heavyImpact();

    try {
      // Sign in the user
      _logTimestamp('Recording attendance for ${matchResult.userName}...');
      await _signInUser(matchResult.userId!, matchResult.userName!);

      ShowToast().showNormalToast(
        msg: 'Welcome, ${matchResult.userName}! Signed in successfully.',
      );

      await Future.delayed(Duration(seconds: 2));

      if (mounted) {
        Navigator.pop(context, true);
      }
    } catch (e) {
      _logTimestamp('Sign-in error: $e');
      _handleError('Failed to complete sign-in: $e');
    }
  }

  void _handleNoMatch(FaceMatchResult? matchResult) {
    _updateState(ScanState.NO_MATCH);
    _updateStatus('Face not recognized. Please try again.');

    _logTimestamp('No match found: ${matchResult?.reason}');

    // Reset to ready after delay
    Future.delayed(Duration(seconds: 2), () {
      if (mounted && _currentState == ScanState.NO_MATCH) {
        _updateState(ScanState.READY);
        _updateStatus('Position your face to sign in');
      }
    });
  }

  Future<void> _signInUser(String userId, String userName) async {
    try {
      final now = DateTime.now();
      final attendanceId =
          '${widget.eventModel.id}-$userId-${now.millisecondsSinceEpoch}';

      _logTimestamp('Creating attendance record:');
      _logTimestamp('  - AttendanceID: $attendanceId');
      _logTimestamp('  - UserID: $userId');
      _logTimestamp('  - UserName: $userName');
      _logTimestamp('  - EventID: ${widget.eventModel.id}');
      _logTimestamp('  - Method: facial_recognition');

      final attendance = AttendanceModel(
        id: attendanceId,
        userName: userName,
        eventId: widget.eventModel.id,
        customerUid: userId,
        attendanceDateTime: now,
        answers: [], // No questions for facial recognition
        isAnonymous: false,
        signInMethod: 'facial_recognition',
        entryTimestamp: now,
      );

      await FirebaseFirestore.instance
          .collection('Attendance')
          .doc(attendanceId)
          .set(attendance.toJson());

      _logTimestamp('✅ Attendance saved to Firestore: Attendance/$attendanceId');
      _logTimestamp('✅ User $userName signed in successfully via facial recognition');
    } catch (e) {
      _logTimestamp('❌ Failed to record attendance: $e');
      throw e;
    }
  }

  void _showEnrollmentPrompt() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Face Not Enrolled'),
        content: Text(
          'You need to enroll your face before you can sign in with facial recognition.',
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              Navigator.pop(context);
            },
            child: Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              Navigator.pushReplacement(
                context,
                MaterialPageRoute(
                  builder: (context) => PictureFaceEnrollmentScreen(
                    eventModel: widget.eventModel,
                    guestUserId: widget.guestUserId,
                    guestUserName: widget.guestUserName,
                  ),
                ),
              );
            },
            child: Text('Enroll Now'),
          ),
        ],
      ),
    );
  }

  void _handleError(String message) {
    _updateState(ScanState.ERROR);
    _errorMessage = message;
    ShowToast().showNormalToast(msg: message);
  }

  void _updateState(ScanState newState) {
    if (mounted) {
      setState(() {
        _currentState = newState;
      });
      _logTimestamp('State: $newState');
    }
  }

  void _updateStatus(String message) {
    if (mounted) {
      setState(() {
        _statusMessage = message;
      });
    }
  }

  void _logTimestamp(String message) {
    final timestamp = DateTime.now().toIso8601String();
    Logger.info('[$timestamp] $message');
  }

  void _retryScanning() {
    setState(() {
      _currentState = ScanState.INITIALIZING;
      _scanAttempts = 0;
      _errorMessage = '';
      _startTime = DateTime.now();
    });
    _startScanning();
  }

  void _goBack() {
    Navigator.pop(context);
  }

  @override
  void dispose() {
    _logTimestamp('Disposing scanner screen');
    _autoScanTimer?.cancel();
    _pulseController.dispose();
    _cameraController?.dispose();
    _faceDetector?.close();
    super.dispose();
  }

  Color _getStateColor() {
    switch (_currentState) {
      case ScanState.INITIALIZING:
        return Colors.blue;
      case ScanState.READY:
        return Colors.green;
      case ScanState.SCANNING:
        return Colors.orange;
      case ScanState.MATCHING:
        return Colors.purple;
      case ScanState.SUCCESS:
        return Colors.green;
      case ScanState.NOT_ENROLLED:
        return Colors.orange;
      case ScanState.NO_MATCH:
        return Colors.red;
      case ScanState.ERROR:
        return Colors.red;
    }
  }

  IconData _getStateIcon() {
    switch (_currentState) {
      case ScanState.INITIALIZING:
        return Icons.hourglass_empty;
      case ScanState.READY:
        return Icons.face_unlock_outlined;
      case ScanState.SCANNING:
        return Icons.face_retouching_natural;
      case ScanState.MATCHING:
        return Icons.fingerprint;
      case ScanState.SUCCESS:
        return Icons.check_circle;
      case ScanState.NOT_ENROLLED:
        return Icons.person_add_alt_1;
      case ScanState.NO_MATCH:
        return Icons.error_outline;
      case ScanState.ERROR:
        return Icons.error;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        title: Text(
          'Face Recognition Sign-In',
          style: TextStyle(color: Colors.white),
        ),
        actions: [
          IconButton(
            icon: Icon(
              _showDebugPanel ? Icons.bug_report : Icons.bug_report_outlined,
              color: Colors.white,
            ),
            onPressed: () {
              setState(() {
                _showDebugPanel = !_showDebugPanel;
              });
            },
          ),
        ],
      ),
      body: Stack(
        children: [
          // Camera Preview
          if (_isCameraInitialized && _cameraController != null)
            Positioned.fill(child: CameraPreview(_cameraController!))
          else
            Center(child: CircularProgressIndicator(color: Colors.white)),

          // Face Guide
          if (_currentState == ScanState.READY || _currentState == ScanState.SCANNING)
            CustomPaint(
              painter: ScannerGuidePainter(animation: _pulseAnimation),
              child: Container(),
            ),

          // Status Panel
          _buildStatusPanel(),

          // Debug Panel
          if (_showDebugPanel) _buildDebugPanel(),

          // Manual Scan Button
          if (_currentState == ScanState.READY && !_isScanning)
            _buildScanButton(),

          // Success/Error Overlays
          if (_currentState == ScanState.SUCCESS) _buildSuccessOverlay(),
          if (_currentState == ScanState.ERROR) _buildErrorDialog(),
          if (_currentState == ScanState.NO_MATCH) _buildNoMatchOverlay(),
        ],
      ),
    );
  }

  Widget _buildStatusPanel() {
    return Positioned(
      top: 50,
      left: 20,
      right: 20,
      child: Container(
        padding: EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: _getStateColor().withValues(alpha: 0.9),
          borderRadius: BorderRadius.circular(15),
          boxShadow: [
            BoxShadow(
              color: _getStateColor().withValues(alpha: 0.5),
              blurRadius: 10,
              spreadRadius: 2,
            ),
          ],
        ),
        child: Row(
          children: [
            Icon(_getStateIcon(), color: Colors.white, size: 30),
            SizedBox(width: 15),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _currentState.toString().split('.').last,
                    style: TextStyle(
                      color: Colors.white70,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  Text(
                    _statusMessage,
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
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

  Widget _buildDebugPanel() {
    final elapsed = DateTime.now().difference(_startTime);
    final elapsedStr =
        '${elapsed.inMinutes}:${(elapsed.inSeconds % 60).toString().padLeft(2, '0')}';

    return Positioned(
      bottom: 100,
      left: 20,
      right: 20,
      child: Container(
        padding: EdgeInsets.all(15),
        decoration: BoxDecoration(
          color: Colors.black87,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: Colors.green, width: 1),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '🐛 DEBUG PANEL (Scanner)',
              style: TextStyle(
                color: Colors.green,
                fontWeight: FontWeight.bold,
                fontSize: 14,
              ),
            ),
            SizedBox(height: 10),
            _debugRow('State', _currentState.toString().split('.').last),
            _debugRow('Scan Attempts', _scanAttempts.toString()),
            _debugRow('Elapsed', elapsedStr),
            _debugRow('Event', widget.eventModel.title),
            if (_currentUserIdentity != null) ...[
              Divider(color: Colors.white24, height: 20),
              _debugRow('User ID', _currentUserIdentity!.userId),
              _debugRow('User Name', _currentUserIdentity!.userName),
              _debugRow('Identity Source', _currentUserIdentity!.source.name),
              _debugRow('Is Guest', _currentUserIdentity!.isGuest.toString()),
            ],
          ],
        ),
      ),
    );
  }

  Widget _debugRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text('$label:', style: TextStyle(color: Colors.white70, fontSize: 12)),
          Flexible(
            child: Text(
              value,
              style: TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.bold,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildScanButton() {
    return Positioned(
      bottom: 150,
      left: 0,
      right: 0,
      child: Center(
        child: GestureDetector(
          onTap: _scanFace,
          child: AnimatedBuilder(
            animation: _pulseAnimation,
            builder: (context, child) {
              return Transform.scale(
                scale: _pulseAnimation.value,
                child: Container(
                  width: 80,
                  height: 80,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.white,
                    border: Border.all(color: Colors.green, width: 4),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.green.withValues(alpha: 0.5),
                        blurRadius: 20,
                        spreadRadius: 5,
                      ),
                    ],
                  ),
                  child: Icon(Icons.face, size: 40, color: Colors.green),
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _buildSuccessOverlay() {
    return Container(
      color: Colors.green.withValues(alpha: 0.8),
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.check_circle, size: 100, color: Colors.white),
            SizedBox(height: 20),
            Text(
              _statusMessage,
              style: TextStyle(
                color: Colors.white,
                fontSize: 24,
                fontWeight: FontWeight.bold,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildNoMatchOverlay() {
    return Container(
      color: Colors.red.withValues(alpha: 0.7),
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.error_outline, size: 100, color: Colors.white),
            SizedBox(height: 20),
            Text(
              'Face Not Recognized',
              style: TextStyle(
                color: Colors.white,
                fontSize: 24,
                fontWeight: FontWeight.bold,
              ),
            ),
            SizedBox(height: 10),
            Text(
              'Please try again or re-enroll',
              style: TextStyle(color: Colors.white70, fontSize: 16),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildErrorDialog() {
    return Center(
      child: Container(
        margin: EdgeInsets.all(20),
        padding: EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(15),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline, color: Colors.red, size: 60),
            SizedBox(height: 20),
            Text(
              'Scanning Error',
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
            ),
            SizedBox(height: 10),
            Text(
              _errorMessage,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 16, color: Colors.grey[700]),
            ),
            SizedBox(height: 30),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                TextButton(
                  onPressed: _goBack,
                  child: Text('Cancel'),
                  style: TextButton.styleFrom(foregroundColor: Colors.grey),
                ),
                ElevatedButton(
                  onPressed: _retryScanning,
                  child: Text('Retry'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blue,
                    foregroundColor: Colors.white,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Custom Painter for Scanner Guide
class ScannerGuidePainter extends CustomPainter {
  final Animation<double> animation;

  ScannerGuidePainter({required this.animation}) : super(repaint: animation);

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = math.min(size.width, size.height) * 0.35;

    // Draw face guide oval
    final paint = Paint()
      ..color = Colors.green.withValues(alpha: 0.8)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3;

    final rect = Rect.fromCircle(center: center, radius: radius);
    canvas.drawOval(rect, paint);

    // Draw scanning pulse effect
    final pulsePaint = Paint()
      ..color = Colors.green.withValues(alpha: 0.3 * animation.value)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 5;

    final pulseRadius = radius * (1 + (animation.value - 1) * 2);
    final pulseRect = Rect.fromCircle(center: center, radius: pulseRadius);
    canvas.drawOval(pulseRect, pulsePaint);

    // Draw corner markers
    final cornerSize = 30.0;
    final cornerPaint = Paint()
      ..color = Colors.green
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3;

    final left = center.dx - radius;
    final right = center.dx + radius;
    final top = center.dy - radius;
    final bottom = center.dy + radius;

    // Top-left corner
    canvas.drawLine(Offset(left, top), Offset(left + cornerSize, top), cornerPaint);
    canvas.drawLine(Offset(left, top), Offset(left, top + cornerSize), cornerPaint);

    // Top-right corner
    canvas.drawLine(Offset(right, top), Offset(right - cornerSize, top), cornerPaint);
    canvas.drawLine(Offset(right, top), Offset(right, top + cornerSize), cornerPaint);

    // Bottom-left corner
    canvas.drawLine(Offset(left, bottom), Offset(left + cornerSize, bottom), cornerPaint);
    canvas.drawLine(Offset(left, bottom), Offset(left, bottom - cornerSize), cornerPaint);

    // Bottom-right corner
    canvas.drawLine(Offset(right, bottom), Offset(right - cornerSize, bottom), cornerPaint);
    canvas.drawLine(Offset(right, bottom), Offset(right, bottom - cornerSize), cornerPaint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}

