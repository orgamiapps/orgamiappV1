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
import '../../firebase/firebase_firestore_helper.dart';
import '../QRScanner/ans_questions_to_sign_in_event_screen.dart';
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
  Timer? _initializationTimeout;
  
  // Caching enrollments with user names for faster matching
  Map<String, EnrollmentCache>? _cachedEnrollments;
  
  // Constants
  static const SCANNER_INIT_TIMEOUT = Duration(seconds: 30);

  // Animation
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  

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
    
    // Start initialization timeout
    _initializationTimeout = Timer(SCANNER_INIT_TIMEOUT, () {
      _handleInitializationTimeout();
    });

    try {
      _updateStatus('Initializing scanner...');
      
      // Run enrollment check and face detector initialization in parallel
      final results = await Future.wait([
        _checkEnrollmentStatus(),
        _initializeFaceDetector().then((_) => true).catchError((e) {
          _logTimestamp('Face detector init failed: $e');
          return false;
        }),
      ]);
      
      final isEnrolled = results[0];
      final faceDetectorReady = results[1];
      
      if (!isEnrolled) {
        _initializationTimeout?.cancel();
        _updateState(ScanState.NOT_ENROLLED);
        _updateStatus('Face not enrolled for this event');
        _showEnrollmentPrompt();
        return;
      }
      
      if (!faceDetectorReady) {
        _initializationTimeout?.cancel();
        _handleError('Failed to initialize face detection');
        return;
      }

      // Initialize camera after parallel operations complete
      _updateStatus('Setting up camera...');
      await _initializeCamera();

      // Cancel timeout - initialization succeeded
      _initializationTimeout?.cancel();

      // Ready to scan
      _updateState(ScanState.READY);
      _updateStatus('Position your face to sign in');

      // Start auto-scan
      _startAutoScan();
    } catch (e, stack) {
      _initializationTimeout?.cancel();
      _logTimestamp('Initialization error: $e\n$stack');
      _handleError('Initialization failed: $e');
    }
  }

  Future<bool> _checkEnrollmentStatus() async {
    try {
      // Add overall timeout for enrollment check
      return await Future.any([
        _performEnrollmentCheck(),
        Future.delayed(Duration(seconds: 15), () {
          _logTimestamp('Enrollment check timeout after 15 seconds');
          return false;
        }),
      ]);
    } catch (e) {
      _logTimestamp('Error checking enrollment: $e');
      return false;
    }
  }
  
  Future<bool> _performEnrollmentCheck() async {
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
      
      // Identity resolved; proceed to enrollment check
      
      return isEnrolled;
    } catch (e) {
      _logTimestamp('Error in enrollment check: $e');
      return false;
    }
  }

  Future<void> _initializeFaceDetector() async {
    final options = FaceDetectorOptions(
      enableContours: false,
      enableLandmarks: true,
      enableClassification: true,
      enableTracking: false,
      minFaceSize: 0.1,
      performanceMode: FaceDetectorMode.accurate,
    );

    _faceDetector = FaceDetector(options: options);
    
    // Initialize with progress updates
    await _faceService.initialize(
      useFastMode: false,
      onProgress: (message) {
        _logTimestamp('ML Kit: $message');
        if (mounted) {
          _updateStatus(message);
        }
      },
    );

    _logTimestamp('Face detector initialized for scanning');
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

      // Initialize with medium resolution for better balance of speed and quality
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
    // Auto-scan every 1.5 seconds for faster recognition (reduced from 2 seconds)
    _autoScanTimer = Timer.periodic(Duration(milliseconds: 1500), (timer) {
      if (mounted && _currentState == ScanState.READY && !_isScanning) {
        _scanFace();
      }
    });

    // Also scan immediately after initialization
    Future.delayed(Duration(milliseconds: 300), () {
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
        _updateStatus('No face detected - position your face in the frame');
        return;
      }

      final face = faces.first;

      // Check if face is suitable with helpful feedback
      if (!_faceService.isFaceSuitable(face)) {
        _updateState(ScanState.READY);
        _updateStatus('Please look straight at the camera');
        return;
      }

      // Match face - use cached enrollments if available
      _updateState(ScanState.MATCHING);
      _updateStatus('Matching face...');

      // Load enrollments cache if not already loaded
      if (_cachedEnrollments == null) {
        await _loadEnrollmentsCache();
      }

      FaceMatchResult? matchResult;
      
      // Try matching with cache first for faster performance
      if (_cachedEnrollments != null && _cachedEnrollments!.isNotEmpty) {
        matchResult = await _matchFaceWithCache(face);
      }
      
      // Fallback to service method if cache matching fails
      if (matchResult == null || !matchResult.matched) {
        matchResult = await _faceService.matchFace(
          detectedFace: face,
          eventId: widget.eventModel.id,
        );
      }

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

    // Haptic feedback - use medium impact for smoother feel
    HapticFeedback.mediumImpact();

    try {
      // Sign in the user - this will handle questions if needed and save attendance
      _logTimestamp('Recording attendance for ${matchResult.userName}...');
      await _signInUser(matchResult.userId!, matchResult.userName!);

      // Only show success toast and navigate if we're still on this screen
      // (if questions exist, we'll have navigated away)
      if (mounted && _currentState == ScanState.SUCCESS) {
        ShowToast().showNormalToast(
          msg: 'Welcome, ${matchResult.userName}! Signed in successfully.',
        );

        // Wait a moment to show success, then navigate back
        await Future.delayed(Duration(milliseconds: 1500));

        if (mounted) {
          Navigator.pop(context, true);
        }
      }
    } catch (e) {
      _logTimestamp('Sign-in error: $e');
      _handleError('Failed to complete sign-in: $e');
    }
  }

  void _handleNoMatch(FaceMatchResult? matchResult) {
    _updateState(ScanState.NO_MATCH);
    
    // Provide helpful feedback based on similarity score
    if (matchResult != null && matchResult.confidence > 0.5) {
      _updateStatus('Almost there! Please adjust your position.');
    } else {
      _updateStatus('Face not recognized. Please try again.');
    }

    _logTimestamp('No match found: ${matchResult?.reason}');

    // Reset to ready after shorter delay for faster retry
    Future.delayed(Duration(milliseconds: 1500), () {
      if (mounted && _currentState == ScanState.NO_MATCH) {
        _updateState(ScanState.READY);
        _updateStatus('Position your face to sign in');
      }
    });
  }

  Future<void> _signInUser(String userId, String userName) async {
    try {
      final now = DateTime.now();
      // Use consistent ID format for better tracking
      final attendanceId = '${widget.eventModel.id}-$userId';

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
        answers: [], // Will be populated if questions exist
        isAnonymous: false,
        signInMethod: 'facial_recognition',
        entryTimestamp: widget.eventModel.getLocation ? now : null,
        dwellStatus: widget.eventModel.getLocation ? 'active' : null,
        dwellNotes: 'Facial recognition sign-in',
      );

      // Check for sign-in questions first
      final eventQuestions = await FirebaseFirestore.instance
          .collection('EventQuestions')
          .where('eventId', isEqualTo: widget.eventModel.id)
          .get();

      if (eventQuestions.docs.isNotEmpty) {
        // Navigate to questions screen - it will handle saving attendance
        _logTimestamp('Event has questions, navigating to questions screen');
        if (mounted) {
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(
              builder: (context) => AnsQuestionsToSignInEventScreen(
                eventModel: widget.eventModel,
                newAttendance: attendance,
                nextPageRoute: 'event_details',
              ),
            ),
          );
        }
        return; // Exit early - questions screen will handle saving
      }

      // No questions - save attendance directly
      _logTimestamp('No event questions, saving attendance directly');
      
      // Save with retry logic for reliability
      const maxRetries = 3;
      int attempts = 0;
      bool saved = false;
      
      while (!saved && attempts < maxRetries) {
        attempts++;
        try {
          await FirebaseFirestore.instance
              .collection(AttendanceModel.firebaseKey)
              .doc(attendanceId)
              .set(attendance.toJson(), SetOptions(merge: false));
          
          // Verify the save was successful
          final savedDoc = await FirebaseFirestore.instance
              .collection(AttendanceModel.firebaseKey)
              .doc(attendanceId)
              .get();
          
          if (savedDoc.exists) {
            saved = true;
            final savedData = savedDoc.data();
            _logTimestamp('✅ Attendance saved to Firestore: ${AttendanceModel.firebaseKey}/$attendanceId (attempt $attempts)');
            _logTimestamp('✅ Verified - UserName in saved doc: ${savedData?['userName']}');
            _logTimestamp('✅ Verified - EventID in saved doc: ${savedData?['eventId']}');
          } else {
            throw Exception('Document was not saved - verification failed');
          }
        } catch (e) {
          _logTimestamp('⚠️ Failed to save attendance (attempt $attempts/$maxRetries): $e');
          if (attempts < maxRetries) {
            await Future.delayed(Duration(milliseconds: 500 * attempts));
          }
        }
      }
      
      if (!saved) {
        throw Exception('Failed to save attendance after $maxRetries attempts');
      }

      // Clear attendance cache so the attendance sheet updates immediately
      try {
        FirebaseFirestoreHelper().clearAttendanceCache(widget.eventModel.id);
        _logTimestamp('Cleared attendance cache for event');
      } catch (e) {
        _logTimestamp('Warning: Failed to clear attendance cache: $e');
      }

      _logTimestamp('✅ User $userName signed in successfully via facial recognition');
    } catch (e) {
      _logTimestamp('❌ Failed to record attendance: $e');
      throw e;
    }
  }
  
  /// Load enrollments into cache with user names for faster matching
  Future<void> _loadEnrollmentsCache() async {
    try {
      final enrolledSnapshot = await FirebaseFirestore.instance
          .collection('FaceEnrollments')
          .where('eventId', isEqualTo: widget.eventModel.id)
          .get();

      _cachedEnrollments = {};
      for (final doc in enrolledSnapshot.docs) {
        final data = doc.data();
        final userId = data['userId'] as String;
        final userName = data['userName'] as String?;
        final features = List<double>.from(data['faceFeatures']);
        _cachedEnrollments![userId] = EnrollmentCache(
          userId: userId,
          userName: userName ?? 'Unknown User',
          features: features,
        );
      }

      _logTimestamp('Cached ${_cachedEnrollments!.length} enrollments with user names');
    } catch (e) {
      _logTimestamp('Failed to load enrollments cache: $e');
      _cachedEnrollments = {};
    }
  }
  
  /// Match face using cached enrollments (faster than querying Firebase)
  Future<FaceMatchResult?> _matchFaceWithCache(Face detectedFace) async {
    if (_cachedEnrollments == null || _cachedEnrollments!.isEmpty) {
      return null;
    }

    if (!_faceService.isFaceSuitable(detectedFace)) {
      return FaceMatchResult(
        matched: false,
        confidence: 0.0,
        reason: 'Face not suitable for recognition',
      );
    }

    // Extract features from detected face
    final detectedFeatures = _faceService.extractFaceFeatures(detectedFace);

    // Find best match from cache
    FaceMatchResult? bestMatch;
    double highestSimilarity = 0.0;
    const matchingThreshold = 0.65;

    for (final entry in _cachedEnrollments!.entries) {
      final cache = entry.value;
      final similarity = _faceService.calculateSimilarity(
        detectedFeatures,
        cache.features,
      );

      if (similarity > highestSimilarity) {
        highestSimilarity = similarity;
        
        if (similarity >= matchingThreshold) {
          bestMatch = FaceMatchResult(
            matched: true,
            userId: cache.userId,
            userName: cache.userName,
            confidence: similarity,
            reason: 'Face matched successfully',
          );
        }
      }
    }

    return bestMatch ??
        FaceMatchResult(
          matched: false,
          confidence: highestSimilarity,
          reason: highestSimilarity > 0
              ? 'No matching face found (highest similarity: ${(highestSimilarity * 100).toStringAsFixed(1)}%)'
              : 'No enrolled faces for this event',
        );
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
  
  void _handleInitializationTimeout() {
    _logTimestamp('Initialization timeout after 30 seconds');
    _updateState(ScanState.ERROR);
    _errorMessage = 'Initialization took too long. Please try again.';
    _updateStatus('Timeout: Please go back and try again');
    ShowToast().showNormalToast(
      msg: 'Face scanner initialization timeout. Please try again.',
    );
    
    // Clean up resources
    _cameraController?.dispose();
    _faceDetector?.close();
    _autoScanTimer?.cancel();
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
    });
    _startScanning();
  }

  void _goBack() {
    Navigator.pop(context);
  }

  @override
  void dispose() {
    _logTimestamp('Disposing scanner screen');
    _initializationTimeout?.cancel();
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
        actions: const [],
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

/// Cache entry for enrollment data
class EnrollmentCache {
  final String userId;
  final String userName;
  final List<double> features;

  EnrollmentCache({
    required this.userId,
    required this.userName,
    required this.features,
  });
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

