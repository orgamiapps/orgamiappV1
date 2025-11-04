import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import '../../Controller/customer_controller.dart';
import '../../Permissions/permissions_helper.dart';
import '../../Services/face_recognition_service.dart';
import '../../models/event_model.dart';
import '../../Utils/logger.dart';
import '../../Utils/toast.dart';
import 'face_recognition_scanner_screen.dart';

/// Simplified Face Enrollment Screen with State Machine Pattern
/// This implementation prioritizes reliability over complexity
class SimpleFaceEnrollmentScreen extends StatefulWidget {
  final EventModel eventModel;
  final String? guestUserId;
  final String? guestUserName;
  final bool simulationMode; // For testing without actual face detection

  const SimpleFaceEnrollmentScreen({
    super.key,
    required this.eventModel,
    this.guestUserId,
    this.guestUserName,
    this.simulationMode = false, // Default to real mode
  });

  @override
  State<SimpleFaceEnrollmentScreen> createState() =>
      _SimpleFaceEnrollmentScreenState();
}

// State Machine States
enum EnrollmentState {
  INITIALIZING,
  READY,
  CAPTURING,
  PROCESSING,
  COMPLETE,
  ERROR,
}

class _SimpleFaceEnrollmentScreenState extends State<SimpleFaceEnrollmentScreen>
    with TickerProviderStateMixin {
  // State Management
  EnrollmentState _currentState = EnrollmentState.INITIALIZING;
  String _statusMessage = 'Initializing camera...';
  String _debugInfo = '';
  String _errorMessage = '';

  // Camera Related
  CameraController? _cameraController;
  List<CameraDescription>? _cameras;
  CameraDescription? _selectedCamera;
  bool _isCameraInitialized = false;
  bool _isStreamActive = false;

  // Face Detection
  final FaceRecognitionService _faceService = FaceRecognitionService();
  FaceDetector? _faceDetector;
  bool _isProcessingFrame = false;
  int _frameCounter = 0;
  int _frameSkipCounter = 0;
  static const int FRAME_SKIP_COUNT = 10; // Process every 10th frame

  // Enrollment Progress
  int _capturedSamples = 0;
  static const int REQUIRED_SAMPLES = 5;
  final List<List<double>> _faceFeatures = [];
  DateTime? _lastCaptureTime;
  static const Duration CAPTURE_INTERVAL = Duration(milliseconds: 1500);

  // Timers and Timeouts
  Timer? _timeoutTimer;
  Timer? _simulationTimer;
  static const Duration ENROLLMENT_TIMEOUT = Duration(seconds: 30);
  static const Duration SIMULATION_DELAY = Duration(seconds: 1);

  // UI Elements
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;
  bool _showDebugPanel = true; // Show by default for debugging
  bool _useManualCapture = false;

  // Statistics
  int _facesDetected = 0;
  int _facesNotSuitable = 0;
  DateTime _startTime = DateTime.now();
  
  // Navigation state for smooth transitions
  bool _isNavigating = false;

  @override
  void initState() {
    super.initState();
    _logWithTimestamp('SimpleFaceEnrollmentScreen: initState called');
    _initializeAnimations();
    _startEnrollmentProcess();
  }

  void _initializeAnimations() {
    _pulseController = AnimationController(
      duration: const Duration(milliseconds: 1000),
      vsync: this,
    );
    _pulseAnimation = Tween<double>(begin: 1.0, end: 1.2).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
    _pulseController.repeat(reverse: true);
  }

  void _startEnrollmentProcess() async {
    _logWithTimestamp('Starting enrollment process...');
    _updateState(EnrollmentState.INITIALIZING);

    // Set enrollment timeout
    _timeoutTimer = Timer(ENROLLMENT_TIMEOUT, () {
      _logWithTimestamp('Enrollment timeout reached');
      _handleTimeout();
    });

    if (widget.simulationMode) {
      _logWithTimestamp('SIMULATION MODE ENABLED');
      _startSimulation();
    } else {
      _initializeRealMode();
    }
  }

  void _startSimulation() {
    _updateState(EnrollmentState.READY);
    _updateStatus('SIMULATION MODE - Face detection simulated');
    _updateDebugInfo('Running in simulation mode for testing');

    // Initialize dummy camera for visual feedback
    _initializeDummyCamera();

    // Simulate face captures
    int simulatedCaptures = 0;
    _simulationTimer = Timer.periodic(SIMULATION_DELAY, (timer) {
      if (simulatedCaptures < REQUIRED_SAMPLES) {
        simulatedCaptures++;
        _capturedSamples = simulatedCaptures;

        setState(() {
          _updateStatus(
            'Simulated capture $simulatedCaptures of $REQUIRED_SAMPLES',
          );
          _frameCounter++;
          _facesDetected++;
        });

        _logWithTimestamp('Simulated capture: $simulatedCaptures');

        // Provide haptic feedback
        HapticFeedback.mediumImpact();

        if (simulatedCaptures >= REQUIRED_SAMPLES) {
          timer.cancel();
          _completeEnrollment();
        }
      }
    });
  }

  Future<void> _initializeDummyCamera() async {
    try {
      _cameras = await availableCameras();
      if (_cameras!.isNotEmpty) {
        _selectedCamera = _cameras!.firstWhere(
          (cam) => cam.lensDirection == CameraLensDirection.front,
          orElse: () => _cameras!.first,
        );

        _cameraController = CameraController(
          _selectedCamera!,
          ResolutionPreset.low,
          enableAudio: false,
        );

        await _cameraController!.initialize();

        if (mounted) {
          setState(() {
            _isCameraInitialized = true;
          });
        }
      }
    } catch (e) {
      _logWithTimestamp('Dummy camera init error (non-critical): $e');
    }
  }

  void _initializeRealMode() async {
    try {
      _logWithTimestamp('Initializing real face detection mode...');

      // Step 1: Check camera permission
      _updateStatus('Checking camera permission...');
      final hasPermission = await PermissionsHelperClass.checkCameraPermission(
        context: context,
      );

      if (!hasPermission) {
        _logWithTimestamp('Camera permission denied');
        _handleError('Camera permission is required for face enrollment');
        return;
      }

      _logWithTimestamp('Camera permission granted');

      // Step 2: Initialize ML Kit Face Detection
      _updateStatus('Initializing face detection...');
      await _initializeFaceDetection();

      // Step 3: Initialize Camera
      _updateStatus('Setting up camera...');
      await _initializeCamera();

      // Step 4: Start Image Stream
      if (_isCameraInitialized) {
        _updateState(EnrollmentState.READY);
        _updateStatus('Position your face in the frame');
        _startImageStream();
      }
    } catch (e, stack) {
      _logWithTimestamp('Initialization error: $e\n$stack');
      _handleError('Failed to initialize: ${e.toString()}');
    }
  }

  Future<void> _initializeFaceDetection() async {
    try {
      _logWithTimestamp('Initializing ML Kit face detector...');

      final options = FaceDetectorOptions(
        enableContours: false,
        enableLandmarks: true,
        enableClassification: true,
        enableTracking: false,
        minFaceSize: 0.1,
        performanceMode: FaceDetectorMode.fast,
      );

      _faceDetector = FaceDetector(options: options);
      await _faceService.initialize(useFastMode: true);

      _logWithTimestamp('Face detector initialized successfully');
    } catch (e) {
      _logWithTimestamp('Face detector initialization failed: $e');
      throw Exception('Failed to initialize face detection: $e');
    }
  }

  Future<void> _initializeCamera() async {
    try {
      _logWithTimestamp('Getting available cameras...');
      _cameras = await availableCameras();

      if (_cameras == null || _cameras!.isEmpty) {
        throw Exception('No cameras found on device');
      }

      _logWithTimestamp('Found ${_cameras!.length} camera(s)');

      // Select front camera
      _selectedCamera = _cameras!.firstWhere(
        (camera) => camera.lensDirection == CameraLensDirection.front,
        orElse: () => _cameras!.first,
      );

      _logWithTimestamp('Selected camera: ${_selectedCamera!.name}');

      // Determine image format based on platform
      final imageFormat = Platform.isIOS
          ? ImageFormatGroup.bgra8888
          : ImageFormatGroup.yuv420; // Use YUV420 instead of NV21

      _logWithTimestamp(
        'Using image format: $imageFormat on ${Platform.operatingSystem}',
      );

      // Initialize camera controller with low resolution
      _cameraController = CameraController(
        _selectedCamera!,
        ResolutionPreset.low, // Low resolution for faster processing
        enableAudio: false,
        imageFormatGroup: imageFormat,
      );

      await _cameraController!.initialize();

      _logWithTimestamp('Camera initialized successfully');
      _logWithTimestamp(
        'Preview size: ${_cameraController!.value.previewSize}',
      );

      if (mounted) {
        setState(() {
          _isCameraInitialized = true;
        });
      }
    } catch (e) {
      _logWithTimestamp('Camera initialization failed: $e');
      throw Exception('Camera setup failed: $e');
    }
  }

  void _startImageStream() {
    if (!_isCameraInitialized || _cameraController == null || _isStreamActive) {
      _logWithTimestamp('Cannot start image stream - camera not ready');
      return;
    }

    try {
      _logWithTimestamp('Starting camera image stream...');
      _isStreamActive = true;
      _updateState(EnrollmentState.CAPTURING);

      _cameraController!.startImageStream((CameraImage image) {
        _frameCounter++;
        _frameSkipCounter++;

        // Process only every FRAME_SKIP_COUNT frames
        if (_frameSkipCounter >= FRAME_SKIP_COUNT) {
          _frameSkipCounter = 0;
          _processCameraFrame(image);
        }

        // Update frame counter display
        if (_frameCounter % 30 == 0) {
          // Update UI every 30 frames
          setState(() {
            _updateDebugInfo(
              'Frames: $_frameCounter | Faces: $_facesDetected | Unsuitable: $_facesNotSuitable',
            );
          });
        }
      });

      _logWithTimestamp('Image stream started successfully');
    } catch (e) {
      _logWithTimestamp('Failed to start image stream: $e');
      _offerManualCapture();
    }
  }

  void _processCameraFrame(CameraImage image) async {
    if (_isProcessingFrame || _capturedSamples >= REQUIRED_SAMPLES) {
      return;
    }

    // Throttle captures
    final now = DateTime.now();
    if (_lastCaptureTime != null &&
        now.difference(_lastCaptureTime!) < CAPTURE_INTERVAL) {
      return;
    }

    _isProcessingFrame = true;

    try {
      // Convert camera image for ML Kit
      final inputImage = _faceService.convertCameraImage(
        image,
        _selectedCamera!,
      );

      if (inputImage == null) {
        _updateStatus('Processing image...');
        return;
      }

      // Detect faces
      final faces = await _faceDetector!.processImage(inputImage);

      if (faces.isEmpty) {
        _updateStatus('No face detected - please position your face');
        return;
      }

      _facesDetected++;
      final face = faces.first;

      // Check if face is suitable
      if (!_faceService.isFaceSuitable(face)) {
        _facesNotSuitable++;
        _updateStatus('Please look straight at the camera');
        return;
      }

      // Capture face sample
      _captureFaceSample(face);
    } catch (e) {
      _logWithTimestamp('Frame processing error: $e');
    } finally {
      _isProcessingFrame = false;
    }
  }

  void _captureFaceSample(Face face) {
    try {
      final features = _faceService.extractFaceFeatures(face);
      _faceFeatures.add(features);
      _capturedSamples++;
      _lastCaptureTime = DateTime.now();

      _logWithTimestamp(
        'Captured sample $_capturedSamples of $REQUIRED_SAMPLES',
      );
      _updateStatus('Captured $_capturedSamples of $REQUIRED_SAMPLES samples');

      // Haptic feedback
      HapticFeedback.mediumImpact();

      // Animate capture
      setState(() {});

      if (_capturedSamples >= REQUIRED_SAMPLES) {
        _completeEnrollment();
      }
    } catch (e) {
      _logWithTimestamp('Failed to capture face sample: $e');
    }
  }

  void _offerManualCapture() {
    setState(() {
      _useManualCapture = true;
      _updateStatus('Stream failed - use manual capture button');
    });
  }

  void _manualCapture() async {
    if (!_isCameraInitialized || _cameraController == null) return;

    try {
      _logWithTimestamp('Manual capture triggered');

      // Simulate a capture
      _capturedSamples++;
      _updateStatus('Manual capture $_capturedSamples of $REQUIRED_SAMPLES');

      HapticFeedback.heavyImpact();

      if (_capturedSamples >= REQUIRED_SAMPLES) {
        _completeEnrollment();
      }
    } catch (e) {
      _logWithTimestamp('Manual capture failed: $e');
    }
  }

  void _completeEnrollment() async {
    _logWithTimestamp('Completing enrollment...');
    _updateState(EnrollmentState.PROCESSING);
    _updateStatus('Processing enrollment...');

    // Stop camera stream
    if (_isStreamActive && _cameraController != null) {
      try {
        _cameraController!.stopImageStream();
        _isStreamActive = false;
      } catch (e) {
        _logWithTimestamp('Error stopping stream: $e');
      }
    }

    // Cancel timers
    _timeoutTimer?.cancel();
    _simulationTimer?.cancel();

    try {
      // Simulate enrollment processing
      await Future.delayed(Duration(seconds: 1));

      if (widget.simulationMode) {
        _logWithTimestamp('Simulation enrollment completed');
      } else {
        // Save face data
        final userId =
            widget.guestUserId ??
            CustomerController.logeInCustomer?.uid ??
            'test_user';
        final userName =
            widget.guestUserName ??
            CustomerController.logeInCustomer?.name ??
            'Test User';

        final success = await _faceService.enrollUserFace(
          userId: userId,
          userName: userName,
          eventId: widget.eventModel.id,
          faceFeatures: _faceFeatures.isNotEmpty ? _faceFeatures : [[]],
        );

        if (!success) {
          throw Exception('Failed to save enrollment data');
        }
      }

      _updateState(EnrollmentState.COMPLETE);
      _updateStatus('Enrollment successful!');
      _logWithTimestamp('Enrollment completed successfully');

      // Show success animation
      ShowToast().showNormalToast(msg: 'Face enrolled successfully!');

      // Stop stream and show loading overlay
      if (_isStreamActive && _cameraController != null) {
        try {
          _cameraController!.stopImageStream();
          _isStreamActive = false;
        } catch (e) {
          _logWithTimestamp('Error stopping stream: $e');
        }
      }
      
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
            pageBuilder: (context, animation, secondaryAnimation) => FaceRecognitionScannerScreen(
              eventModel: widget.eventModel,
              guestUserId: widget.guestUserId,
              guestUserName: widget.guestUserName,
            ),
            transitionDuration: Duration(milliseconds: 400),
            reverseTransitionDuration: Duration(milliseconds: 300),
            transitionsBuilder: (context, animation, secondaryAnimation, child) {
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
      _logWithTimestamp('Enrollment completion failed: $e');
      _handleError('Failed to complete enrollment: $e');
    }
  }

  void _handleTimeout() {
    _updateState(EnrollmentState.ERROR);
    _updateStatus('Enrollment timeout - please try again');
    _errorMessage = 'The enrollment process took too long. Please try again.';
  }

  void _handleError(String message) {
    _updateState(EnrollmentState.ERROR);
    _updateStatus('Error occurred');
    _errorMessage = message;

    ShowToast().showNormalToast(msg: message);
  }

  void _updateState(EnrollmentState newState) {
    setState(() {
      _currentState = newState;
      _logWithTimestamp('State changed to: $newState');
    });
  }

  void _updateStatus(String message) {
    setState(() {
      _statusMessage = message;
    });
  }

  void _updateDebugInfo(String info) {
    setState(() {
      _debugInfo = info;
    });
  }

  void _logWithTimestamp(String message) {
    final timestamp = DateTime.now().toIso8601String();
    Logger.info('[$timestamp] $message');
  }

  void _retryEnrollment() {
    _logWithTimestamp('Retrying enrollment...');

    // Reset state
    setState(() {
      _currentState = EnrollmentState.INITIALIZING;
      _capturedSamples = 0;
      _faceFeatures.clear();
      _frameCounter = 0;
      _facesDetected = 0;
      _facesNotSuitable = 0;
      _errorMessage = '';
      _startTime = DateTime.now();
    });

    _startEnrollmentProcess();
  }

  void _skipEnrollment() {
    _logWithTimestamp('User chose to skip enrollment');
    ShowToast().showNormalToast(msg: 'Face enrollment skipped');
    Navigator.pop(context);
  }

  @override
  void dispose() {
    _logWithTimestamp('Disposing SimpleFaceEnrollmentScreen');
    _timeoutTimer?.cancel();
    _simulationTimer?.cancel();
    _pulseController.dispose();

    if (_isStreamActive && _cameraController != null) {
      try {
        _cameraController!.stopImageStream();
      } catch (e) {
        _logWithTimestamp('Error stopping stream in dispose: $e');
      }
    }

    // Only dispose if not already disposed (prevents double disposal during navigation)
    if (_cameraController != null && _isCameraInitialized) {
      _cameraController!.dispose().then((_) {
        _logWithTimestamp('Camera controller disposed');
      }).catchError((e) {
        _logWithTimestamp('Error disposing camera: $e');
      });
    }
    
    // Close face detector
    _faceDetector?.close().then((_) {
      _logWithTimestamp('Face detector closed');
    }).catchError((e) {
      _logWithTimestamp('Error closing face detector: $e');
    });

    super.dispose();
  }

  // UI Building Methods

  Color _getStateColor() {
    switch (_currentState) {
      case EnrollmentState.INITIALIZING:
        return Colors.blue;
      case EnrollmentState.READY:
        return Colors.orange;
      case EnrollmentState.CAPTURING:
        return Colors.green;
      case EnrollmentState.PROCESSING:
        return Colors.purple;
      case EnrollmentState.COMPLETE:
        return Colors.green;
      case EnrollmentState.ERROR:
        return Colors.red;
    }
  }

  IconData _getStateIcon() {
    switch (_currentState) {
      case EnrollmentState.INITIALIZING:
        return Icons.hourglass_empty;
      case EnrollmentState.READY:
        return Icons.face;
      case EnrollmentState.CAPTURING:
        return Icons.camera_alt;
      case EnrollmentState.PROCESSING:
        return Icons.autorenew;
      case EnrollmentState.COMPLETE:
        return Icons.check_circle;
      case EnrollmentState.ERROR:
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
          widget.simulationMode
              ? 'Face Enrollment (Simulation)'
              : 'Face Enrollment',
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
          // Camera Preview or Placeholder
          if (!_isNavigating) _buildCameraView(),

          // Face Guide Overlay
          if (!_isNavigating && (_currentState == EnrollmentState.CAPTURING ||
              _currentState == EnrollmentState.READY))
            _buildFaceGuide(),

          // Status Panel
          if (!_isNavigating) _buildStatusPanel(),

          // Debug Panel
          if (!_isNavigating && _showDebugPanel) _buildDebugPanel(),

          // Progress Indicator
          if (!_isNavigating) _buildProgressIndicator(),

          // Manual Capture Button
          if (!_isNavigating && _useManualCapture) _buildManualCaptureButton(),

          // Error Dialog
          if (!_isNavigating && _currentState == EnrollmentState.ERROR) _buildErrorDialog(),
          
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
                      style: TextStyle(
                        color: Colors.white70,
                        fontSize: 14,
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildCameraView() {
    if (_isCameraInitialized && _cameraController != null) {
      return Positioned.fill(child: CameraPreview(_cameraController!));
    } else if (_currentState == EnrollmentState.INITIALIZING) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(color: Colors.white),
            SizedBox(height: 20),
            Text(
              'Initializing camera...',
              style: TextStyle(color: Colors.white),
            ),
          ],
        ),
      );
    } else {
      return Container(
        color: Colors.grey[900],
        child: Center(
          child: Icon(Icons.camera_alt, size: 100, color: Colors.grey[700]),
        ),
      );
    }
  }

  Widget _buildFaceGuide() {
    return CustomPaint(
      painter: FaceGuidePainter(
        animation: _pulseAnimation,
        capturedSamples: _capturedSamples,
        requiredSamples: REQUIRED_SAMPLES,
      ),
      child: Container(),
    );
  }

  Widget _buildStatusPanel() {
    return Positioned(
      top: 50,
      left: 20,
      right: 20,
      child: AnimatedBuilder(
        animation: _pulseAnimation,
        builder: (context, child) {
          return Container(
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
                Row(
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
                if (_currentState == EnrollmentState.CAPTURING) ...[
                  SizedBox(height: 15),
                  LinearProgressIndicator(
                    value: _capturedSamples / REQUIRED_SAMPLES,
                    backgroundColor: Colors.white30,
                    valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                    minHeight: 6,
                  ),
                  SizedBox(height: 10),
                  Text(
                    '$_capturedSamples / $REQUIRED_SAMPLES samples captured',
                    style: TextStyle(color: Colors.white, fontSize: 14),
                  ),
                ],
              ],
            ),
          );
        },
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
              '🐛 DEBUG PANEL',
              style: TextStyle(
                color: Colors.green,
                fontWeight: FontWeight.bold,
                fontSize: 14,
              ),
            ),
            SizedBox(height: 10),
            _debugRow('State', _currentState.toString().split('.').last),
            _debugRow('Frames', _frameCounter.toString()),
            _debugRow('Faces Detected', _facesDetected.toString()),
            _debugRow('Unsuitable', _facesNotSuitable.toString()),
            _debugRow('Samples', '$_capturedSamples / $REQUIRED_SAMPLES'),
            _debugRow('Elapsed', elapsedStr),
            if (_debugInfo.isNotEmpty) ...[
              SizedBox(height: 5),
              Text(
                _debugInfo,
                style: TextStyle(color: Colors.white70, fontSize: 11),
              ),
            ],
            if (widget.simulationMode) ...[
              SizedBox(height: 5),
              Container(
                padding: EdgeInsets.all(5),
                decoration: BoxDecoration(
                  color: Colors.orange,
                  borderRadius: BorderRadius.circular(5),
                ),
                child: Text(
                  'SIMULATION MODE',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 10,
                  ),
                ),
              ),
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
          Text(
            '$label:',
            style: TextStyle(color: Colors.white70, fontSize: 12),
          ),
          Text(
            value,
            style: TextStyle(
              color: Colors.white,
              fontSize: 12,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProgressIndicator() {
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
            width: 12,
            height: 12,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: isComplete
                  ? Colors.green
                  : isCurrent
                  ? Colors.orange
                  : Colors.grey,
              border: Border.all(color: Colors.white, width: isCurrent ? 2 : 1),
            ),
          );
        }),
      ),
    );
  }

  Widget _buildManualCaptureButton() {
    return Positioned(
      bottom: 150,
      left: 0,
      right: 0,
      child: Center(
        child: ElevatedButton.icon(
          onPressed: _manualCapture,
          icon: Icon(Icons.camera_alt, size: 30),
          label: Text(
            'MANUAL CAPTURE',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.blue,
            foregroundColor: Colors.white,
            padding: EdgeInsets.symmetric(horizontal: 30, vertical: 15),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(30),
            ),
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
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: Colors.black,
              ),
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

// Custom Painter for Face Guide
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

    // Draw capture indicators
    final indicatorRadius = radius + 30;
    for (int i = 0; i < requiredSamples; i++) {
      final angle = (2 * math.pi * i / requiredSamples) - (math.pi / 2);
      final indicatorCenter = Offset(
        center.dx + indicatorRadius * math.cos(angle),
        center.dy + indicatorRadius * math.sin(angle),
      );

      final indicatorPaint = Paint()
        ..color = i < capturedSamples ? Colors.green : Colors.grey
        ..style = PaintingStyle.fill;

      canvas.drawCircle(indicatorCenter, 8, indicatorPaint);

      if (i < capturedSamples) {
        // Draw checkmark
        final checkPath = Path()
          ..moveTo(indicatorCenter.dx - 3, indicatorCenter.dy)
          ..lineTo(indicatorCenter.dx - 1, indicatorCenter.dy + 2)
          ..lineTo(indicatorCenter.dx + 3, indicatorCenter.dy - 2);

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
