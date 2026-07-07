import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import '../../Permissions/permissions_helper.dart';
import '../../Services/face_recognition_service.dart';
import '../../Services/user_identity_service.dart';
import '../../models/event_model.dart';
import '../../Utils/logger.dart';
import '../../Utils/toast.dart';
import 'picture_face_scanner_screen.dart';

/// Picture-based Face Enrollment Screen
/// Uses takePicture() instead of image streaming for better ML Kit compatibility
class PictureFaceEnrollmentScreen extends StatefulWidget {
  final EventModel eventModel;
  final String? guestUserId;
  final String? guestUserName;

  const PictureFaceEnrollmentScreen({
    super.key,
    required this.eventModel,
    this.guestUserId,
    this.guestUserName,
  });

  @override
  State<PictureFaceEnrollmentScreen> createState() =>
      _PictureFaceEnrollmentScreenState();
}

enum EnrollmentState {
  INITIALIZING,
  READY,
  CAPTURING,
  PROCESSING,
  COMPLETE,
  ERROR,
}

class _PictureFaceEnrollmentScreenState
    extends State<PictureFaceEnrollmentScreen>
    with TickerProviderStateMixin {
  // State Management
  EnrollmentState _currentState = EnrollmentState.INITIALIZING;
  String _statusMessage = 'Initializing camera...';
  String _errorMessage = '';

  // Camera
  CameraController? _cameraController;
  CameraDescription? _selectedCamera;
  bool _isCameraInitialized = false;

  // Face Detection
  final FaceRecognitionService _faceService = FaceRecognitionService();
  FaceDetector? _faceDetector;

  // Enrollment Progress
  int _capturedSamples = 0;
  static const int REQUIRED_SAMPLES = 5;
  final List<List<double>> _faceFeatures = [];
  bool _isCapturing = false;

  // Timers
  Timer? _timeoutTimer;
  static const Duration ENROLLMENT_TIMEOUT = Duration(seconds: 45);

  // Animation
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  // Debug counters (no UI)
  int _attempts = 0;

  // Navigation state for smooth transitions
  bool _isNavigating = false;

  @override
  void initState() {
    super.initState();
    _logTimestamp('PictureFaceEnrollmentScreen: initState');
    _initializeAnimations();
    _startEnrollment();
  }

  void _initializeAnimations() {
    _pulseController = AnimationController(
      duration: const Duration(milliseconds: 1000),
      vsync: this,
    );
    _pulseAnimation = Tween<double>(begin: 1.0, end: 1.1).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
    _pulseController.repeat(reverse: true);
  }

  void _startEnrollment() async {
    _updateState(EnrollmentState.INITIALIZING);

    // Set timeout
    _timeoutTimer = Timer(ENROLLMENT_TIMEOUT, () {
      _logTimestamp('Enrollment timeout');
      _handleError('Enrollment took too long. Please try again.');
    });

    try {
      // Step 1: Request camera permission
      _updateStatus('Requesting camera permission...');
      final hasPermission = await PermissionsHelperClass.checkCameraPermission(
        context: context,
      );

      if (!hasPermission) {
        _handleError('Camera permission required');
        return;
      }

      _logTimestamp('Camera permission granted');

      // Step 2: Initialize Face Detector
      _updateStatus('Initializing face detection...');
      await _initializeFaceDetector();

      // Step 3: Initialize Camera
      _updateStatus('Setting up camera...');
      await _initializeCamera();

      // Step 4: Ready to capture
      _updateState(EnrollmentState.READY);
      _updateStatus('Tap the capture button when ready');

      // Auto-capture after 2 seconds
      Future.delayed(Duration(seconds: 2), () {
        if (mounted && _currentState == EnrollmentState.READY) {
          _capturePhoto();
        }
      });
    } catch (e, stack) {
      _logTimestamp('Initialization error: $e\n$stack');
      _handleError('Initialization failed: $e');
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
        performanceMode:
            FaceDetectorMode.accurate, // Use accurate mode for enrollment
      );

      _faceDetector = FaceDetector(options: options);
      await _faceService.initialize(useFastMode: false);

      _logTimestamp('Face detector initialized');
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

      _logTimestamp('Selected camera: ${_selectedCamera!.name}');

      // Initialize with high resolution for better face detection
      _cameraController = CameraController(
        _selectedCamera!,
        ResolutionPreset.medium,
        enableAudio: false,
      );

      await _cameraController!.initialize();

      _logTimestamp(
        'Camera initialized: ${_cameraController!.value.previewSize}',
      );

      if (mounted) {
        setState(() {
          _isCameraInitialized = true;
        });
      }
    } catch (e) {
      throw Exception('Camera setup failed: $e');
    }
  }

  Future<void> _capturePhoto() async {
    if (_isCapturing || !_isCameraInitialized || _cameraController == null) {
      return;
    }

    if (_capturedSamples >= REQUIRED_SAMPLES) {
      _completeEnrollment();
      return;
    }

    setState(() {
      _isCapturing = true;
      _attempts++;
    });

    _updateState(EnrollmentState.CAPTURING);
    _updateStatus('Capturing... Hold still');

    try {
      _logTimestamp('Taking picture ${_attempts}...');

      // Take picture
      final XFile imageFile = await _cameraController!.takePicture();
      _logTimestamp('Picture taken: ${imageFile.path}');

      // Process the image with ML Kit
      await _processCapturedImage(imageFile);

      // Schedule next capture if needed
      if (_capturedSamples < REQUIRED_SAMPLES && mounted) {
        Future.delayed(Duration(milliseconds: 1500), () {
          if (mounted && _capturedSamples < REQUIRED_SAMPLES) {
            _updateState(EnrollmentState.READY);
            _updateStatus('Preparing next capture...');

            Future.delayed(Duration(milliseconds: 500), () {
              if (mounted) _capturePhoto();
            });
          }
        });
      }
    } catch (e) {
      _logTimestamp('Capture error: $e');
      setState(() {
        _updateStatus('Capture failed, retrying...');
      });

      // Retry after delay
      Future.delayed(Duration(milliseconds: 1000), () {
        if (mounted && _capturedSamples < REQUIRED_SAMPLES) {
          _capturePhoto();
        }
      });
    } finally {
      setState(() {
        _isCapturing = false;
      });
    }
  }

  Future<void> _processCapturedImage(XFile imageFile) async {
    try {
      _logTimestamp('Processing image: ${imageFile.path}');

      // Create InputImage from file path
      final inputImage = InputImage.fromFilePath(imageFile.path);
      _logTimestamp('InputImage created from file');

      // Detect faces
      final faces = await _faceDetector!.processImage(inputImage);
      _logTimestamp('Faces detected: ${faces.length}');

      if (faces.isEmpty) {
        _logTimestamp('No face detected in image');
        _updateStatus('No face detected - please position your face');
        return;
      }

      final face = faces.first;
      _logTimestamp('Face boundingBox: ${face.boundingBox}');

      // Check if face is suitable
      if (!_faceService.isFaceSuitable(face)) {
        _logTimestamp('Face not suitable');
        _updateStatus('Please look straight at the camera');
        return;
      }

      // Extract features
      final features = _faceService.extractFaceFeatures(face);
      _faceFeatures.add(features);
      _capturedSamples++;

      _logTimestamp('Sample $_capturedSamples captured successfully');
      _updateStatus('Captured $_capturedSamples of $REQUIRED_SAMPLES samples');

      // Haptic feedback
      HapticFeedback.mediumImpact();

      // Delete the temporary image file
      try {
        await File(imageFile.path).delete();
      } catch (e) {
        _logTimestamp('Could not delete temp file: $e');
      }

      if (_capturedSamples >= REQUIRED_SAMPLES) {
        _completeEnrollment();
      }
    } catch (e, stack) {
      _logTimestamp('Image processing error: $e\n$stack');
      _updateStatus('Processing failed, retrying...');
    }
  }

  Future<void> _completeEnrollment() async {
    _logTimestamp('Completing enrollment...');
    _updateState(EnrollmentState.PROCESSING);
    _updateStatus('Saving enrollment data...');

    _timeoutTimer?.cancel();

    try {
      // Get user identity using centralized service
      final userIdentity = await UserIdentityService.getCurrentUserIdentity(
        guestUserId: widget.guestUserId,
        guestUserName: widget.guestUserName,
      );

      if (userIdentity == null) {
        _logTimestamp('ERROR: No user identity available');
        throw Exception('User not logged in. Please sign in first.');
      }

      // Log identity details for debugging
      UserIdentityService.logIdentityDetails(userIdentity, 'Enrollment');

      final enrollmentDocId = UserIdentityService.generateEnrollmentDocumentId(
        widget.eventModel.id,
        userIdentity.userId,
      );
      _logTimestamp(
        'Enrollment will be saved to: FaceEnrollments/$enrollmentDocId',
      );

      final success = await _faceService.enrollUserFace(
        userId: userIdentity.userId,
        userName: userIdentity.userName,
        eventId: widget.eventModel.id,
        faceFeatures: _faceFeatures,
      );

      if (!success) {
        throw Exception('Failed to save enrollment to Firestore');
      }

      _logTimestamp('✅ Enrollment saved and verified successfully!');

      _updateState(EnrollmentState.COMPLETE);
      _updateStatus('Enrollment successful!');
      _logTimestamp('Enrollment completed successfully');

      ShowToast().showNormalToast(msg: 'Face enrolled successfully!');

      // Show loading overlay and hide camera preview
      if (mounted) {
        setState(() {
          _isNavigating = true;
          _isCameraInitialized = false;
        });
      }

      // Short delay to show the "Preparing scanner..." message
      await Future.delayed(Duration(milliseconds: 500));

      // Navigate with smooth fade transition - disposal will happen in background
      if (mounted) {
        Navigator.pushReplacement(
          context,
          PageRouteBuilder(
            pageBuilder: (context, animation, secondaryAnimation) =>
                PictureFaceScannerScreen(
                  eventModel: widget.eventModel,
                  guestUserId: widget.guestUserId,
                  guestUserName: widget.guestUserName,
                ),
            transitionDuration: Duration(milliseconds: 400),
            reverseTransitionDuration: Duration(milliseconds: 300),
            transitionsBuilder:
                (context, animation, secondaryAnimation, child) {
                  return FadeTransition(
                    opacity: CurvedAnimation(
                      parent: animation,
                      curve: Curves.easeInOut,
                    ),
                    child: child,
                  );
                },
          ),
        ).then((_) {
          // Dispose camera after navigation starts
          _cameraController?.dispose();
          _cameraController = null;
        });
      }
    } catch (e) {
      _logTimestamp('Enrollment failed: $e');
      _handleError('Failed to complete enrollment: $e');
    }
  }

  void _handleError(String message) {
    _updateState(EnrollmentState.ERROR);
    _errorMessage = message;
    ShowToast().showNormalToast(msg: message);
  }

  void _updateState(EnrollmentState newState) {
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

  void _retryEnrollment() {
    setState(() {
      _currentState = EnrollmentState.INITIALIZING;
      _capturedSamples = 0;
      _faceFeatures.clear();
      _attempts = 0;
      _errorMessage = '';
    });
    _startEnrollment();
  }

  void _skipEnrollment() {
    _logTimestamp('User skipped enrollment');
    Navigator.pop(context);
  }

  @override
  void dispose() {
    _logTimestamp('Disposing enrollment screen');
    _timeoutTimer?.cancel();
    _pulseController.dispose();

    // Only dispose if not already disposed (prevents double disposal during navigation)
    if (_cameraController != null && _isCameraInitialized) {
      _cameraController!
          .dispose()
          .then((_) {
            _logTimestamp('Camera controller disposed');
          })
          .catchError((e) {
            _logTimestamp('Error disposing camera: $e');
          });
    }

    // Close face detector
    _faceDetector
        ?.close()
        .then((_) {
          _logTimestamp('Face detector closed');
        })
        .catchError((e) {
          _logTimestamp('Error closing face detector: $e');
        });

    super.dispose();
  }

  Color _getStateColor() {
    switch (_currentState) {
      case EnrollmentState.INITIALIZING:
        return Colors.blue;
      case EnrollmentState.READY:
        return Colors.green;
      case EnrollmentState.CAPTURING:
        return Colors.orange;
      case EnrollmentState.PROCESSING:
        return Colors.purple;
      case EnrollmentState.COMPLETE:
        return Colors.green;
      case EnrollmentState.ERROR:
        return Colors.red;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        title: Text(
          'Face Enrollment (Picture Mode)',
          style: TextStyle(color: Colors.white),
        ),
        actions: const [],
      ),
      body: Stack(
        children: [
          // Camera Preview
          if (!_isNavigating &&
              _isCameraInitialized &&
              _cameraController != null)
            Positioned.fill(child: CameraPreview(_cameraController!))
          else if (!_isNavigating)
            Center(child: CircularProgressIndicator(color: Colors.white)),

          // Face Guide
          if (!_isNavigating && _currentState != EnrollmentState.ERROR)
            CustomPaint(
              painter: FaceGuidePainter(
                animation: _pulseAnimation,
                capturedSamples: _capturedSamples,
                requiredSamples: REQUIRED_SAMPLES,
              ),
              child: Container(),
            ),

          // Status Panel
          if (!_isNavigating) _buildStatusPanel(),

          // Progress Indicators
          if (!_isNavigating) _buildProgressIndicators(),

          // Capture Button
          if (!_isNavigating &&
              _currentState == EnrollmentState.READY &&
              !_isCapturing)
            _buildCaptureButton(),

          // Error Dialog
          if (!_isNavigating && _currentState == EnrollmentState.ERROR)
            _buildErrorDialog(),

          // Loading overlay during navigation
          if (_isNavigating)
            Container(
              color: Colors.black,
              child: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    CircularProgressIndicator(
                      color: Colors.white,
                      strokeWidth: 3,
                    ),
                    SizedBox(height: 24),
                    Text(
                      'Preparing scanner...',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    SizedBox(height: 12),
                    Text(
                      'This will only take a moment',
                      style: TextStyle(color: Colors.white70, fontSize: 14),
                    ),
                  ],
                ),
              ),
            ),
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
        child: Column(
          children: [
            Text(
              _statusMessage,
              style: TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
              textAlign: TextAlign.center,
            ),
            if (_currentState == EnrollmentState.CAPTURING ||
                _currentState == EnrollmentState.READY) ...[
              SizedBox(height: 15),
              LinearProgressIndicator(
                value: _capturedSamples / REQUIRED_SAMPLES,
                backgroundColor: Colors.white.withValues(alpha: 0.3),
                valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                minHeight: 6,
              ),
              SizedBox(height: 10),
              Text(
                '$_capturedSamples / $REQUIRED_SAMPLES samples',
                style: TextStyle(color: Colors.white, fontSize: 14),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildProgressIndicators() {
    return Positioned(
      bottom: 40,
      left: 20,
      right: 20,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: List.generate(REQUIRED_SAMPLES, (index) {
          final isComplete = index < _capturedSamples;
          final isCurrent = index == _capturedSamples;

          return Container(
            margin: EdgeInsets.symmetric(horizontal: 5),
            width: 15,
            height: 15,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: isComplete
                  ? Colors.green
                  : isCurrent
                  ? Colors.orange
                  : Colors.grey,
              border: Border.all(color: Colors.white, width: isCurrent ? 2 : 1),
            ),
            child: isComplete
                ? Icon(Icons.check, size: 10, color: Colors.white)
                : null,
          );
        }),
      ),
    );
  }

  Widget _buildCaptureButton() {
    return Positioned(
      bottom: 150,
      left: 0,
      right: 0,
      child: Center(
        child: GestureDetector(
          onTap: _capturePhoto,
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
                  child: Icon(Icons.camera_alt, size: 40, color: Colors.green),
                ),
              );
            },
          ),
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
              'Enrollment Failed',
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
                  onPressed: _skipEnrollment,
                  child: Text('Skip'),
                  style: TextButton.styleFrom(foregroundColor: Colors.grey),
                ),
                ElevatedButton(
                  onPressed: _retryEnrollment,
                  child: Text('Try Again'),
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

/// Custom Painter for Face Guide
class FaceGuidePainter extends CustomPainter {
  final Animation<double> animation;
  final int capturedSamples;
  final int requiredSamples;

  FaceGuidePainter({
    required this.animation,
    required this.capturedSamples,
    required this.requiredSamples,
  }) : super(repaint: animation);

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = math.min(size.width, size.height) * 0.35;

    // Draw face guide oval
    final paint = Paint()
      ..color = Colors.white.withValues(alpha: 0.8)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3;

    final rect = Rect.fromCircle(center: center, radius: radius);
    canvas.drawOval(rect, paint);

    // Draw pulse effect
    final pulsePaint = Paint()
      ..color = Colors.green.withValues(alpha: 0.3 * (1.0 - animation.value))
      ..style = PaintingStyle.stroke
      ..strokeWidth = 5;

    final pulseRadius = radius * animation.value;
    final pulseRect = Rect.fromCircle(center: center, radius: pulseRadius);
    canvas.drawOval(pulseRect, pulsePaint);

    // Draw sample indicators
    final indicatorRadius = radius + 40;
    for (int i = 0; i < requiredSamples; i++) {
      final angle = (2 * math.pi * i / requiredSamples) - (math.pi / 2);
      final indicatorCenter = Offset(
        center.dx + indicatorRadius * math.cos(angle),
        center.dy + indicatorRadius * math.sin(angle),
      );

      final indicatorPaint = Paint()
        ..color = i < capturedSamples ? Colors.green : Colors.grey
        ..style = PaintingStyle.fill;

      canvas.drawCircle(indicatorCenter, 10, indicatorPaint);

      if (i < capturedSamples) {
        final checkPath = Path()
          ..moveTo(indicatorCenter.dx - 4, indicatorCenter.dy)
          ..lineTo(indicatorCenter.dx - 2, indicatorCenter.dy + 3)
          ..lineTo(indicatorCenter.dx + 4, indicatorCenter.dy - 3);

        final checkPaint = Paint()
          ..color = Colors.white
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2;

        canvas.drawPath(checkPath, checkPaint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}
