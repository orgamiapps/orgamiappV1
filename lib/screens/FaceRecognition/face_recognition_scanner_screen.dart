import 'dart:async';
import 'dart:math';
import 'package:camera/camera.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import '../../Services/face_recognition_service.dart';
import '../../models/attendance_model.dart';
import '../../models/event_model.dart';
import '../../Utils/logger.dart';
import '../../Utils/toast.dart';
import '../QRScanner/ans_questions_to_sign_in_event_screen.dart';
import 'face_enrollment_screen.dart';

/// Professional face recognition scanner for event attendance
class FaceRecognitionScannerScreen extends StatefulWidget {
  final EventModel eventModel;
  final bool isEnrollment;

  const FaceRecognitionScannerScreen({
    super.key,
    required this.eventModel,
    this.isEnrollment = false,
  });

  @override
  State<FaceRecognitionScannerScreen> createState() =>
      _FaceRecognitionScannerScreenState();
}

class _FaceRecognitionScannerScreenState
    extends State<FaceRecognitionScannerScreen>
    with TickerProviderStateMixin {
  // Camera and face detection
  CameraController? _cameraController;
  CameraDescription? _camera;
  List<CameraDescription>? _cameras;
  bool _isCameraInitialized = false;
  bool _isProcessing = false;
  bool _isStreamActive = false;

  // Services
  final FaceRecognitionService _faceService = FaceRecognitionService();

  // State management
  FaceDetectionState _detectionState = FaceDetectionState.searching;
  String _statusMessage = 'Position your face in the frame';
  List<Face> _detectedFaces = [];

  // Animation controllers
  late AnimationController _scanAnimationController;
  late AnimationController _pulseAnimationController;
  late Animation<double> _scanAnimation;
  late Animation<double> _pulseAnimation;

  // Timers and throttling
  Timer? _messageTimer;
  DateTime? _lastProcessTime;
  Map<String, List<double>>? _cachedEnrollments;

  // Constants
  static const Duration _processingInterval = Duration(
    milliseconds: 1500,
  ); // Reduced frequency
  static const Duration _successDelay = Duration(seconds: 2);
  static const Duration _enrollmentCacheExpiry = Duration(minutes: 5);

  @override
  void initState() {
    super.initState();
    _initializeAnimations();
    _initializeServices();
    _initializeCamera();
  }

  void _initializeAnimations() {
    _scanAnimationController = AnimationController(
      duration: const Duration(seconds: 2),
      vsync: this,
    );
    _pulseAnimationController = AnimationController(
      duration: const Duration(seconds: 1),
      vsync: this,
    );

    _scanAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _scanAnimationController,
        curve: Curves.easeInOut,
      ),
    );
    _pulseAnimation = Tween<double>(begin: 0.8, end: 1.2).animate(
      CurvedAnimation(
        parent: _pulseAnimationController,
        curve: Curves.easeInOut,
      ),
    );

    _scanAnimationController.repeat();
  }

  Future<void> _initializeServices() async {
    try {
      await _faceService.initialize();
    } catch (e) {
      Logger.error('Failed to initialize face recognition service: $e');
      _showErrorState('Failed to initialize face recognition');
    }
  }

  Future<void> _initializeCamera() async {
    try {
      _cameras = await availableCameras();
      if (_cameras == null || _cameras!.isEmpty) {
        _showErrorState('No cameras available on this device');
        return;
      }

      // Prefer front camera for face recognition
      final frontCamera = _cameras!.firstWhere(
        (camera) => camera.lensDirection == CameraLensDirection.front,
        orElse: () => _cameras!.first,
      );

      _camera = frontCamera;
      _cameraController = CameraController(
        frontCamera,
        ResolutionPreset.low, // Lower resolution for faster processing
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.nv21, // Better for ML processing
      );

      await _cameraController!.initialize();

      if (mounted) {
        setState(() {
          _isCameraInitialized = true;
        });

        // Start face detection with image streaming
        _startImageStream();
      }
    } catch (e) {
      Logger.error('Camera initialization failed: $e');
      _showErrorState('Failed to access camera. Please check permissions.');
    }
  }

  void _startImageStream() {
    if (_cameraController == null ||
        !_cameraController!.value.isInitialized ||
        _isStreamActive) {
      return;
    }

    _isStreamActive = true;
    _cameraController!.startImageStream(_processCameraImage);
  }

  void _stopImageStream() {
    if (_isStreamActive && _cameraController != null) {
      _cameraController!.stopImageStream();
      _isStreamActive = false;
    }
  }

  Future<void> _processCameraImage(CameraImage cameraImage) async {
    // Throttle processing - skip frames if processing or too soon
    if (_isProcessing || _camera == null) return;

    final now = DateTime.now();
    if (_lastProcessTime != null &&
        now.difference(_lastProcessTime!) < _processingInterval) {
      return; // Skip this frame
    }

    _isProcessing = true;
    _lastProcessTime = now;

    try {
      // Convert camera image to ML Kit input image
      final inputImage = _faceService.convertCameraImage(cameraImage, _camera!);

      if (inputImage == null) {
        _isProcessing = false;
        return;
      }

      // Detect faces
      final faces = await _faceService.detectFaces(inputImage);

      if (mounted) {
        setState(() {
          _detectedFaces = faces;
        });

        await _handleFaceDetectionResult(faces);
      }
    } catch (e) {
      Logger.error('Frame processing failed: $e');
    } finally {
      _isProcessing = false;
    }
  }

  Future<void> _handleFaceDetectionResult(List<Face> faces) async {
    if (faces.isEmpty) {
      _updateDetectionState(
        FaceDetectionState.searching,
        'Position your face in the frame',
      );
      return;
    }

    final face = faces.first;

    // Check if face is suitable
    if (!_faceService.isFaceSuitable(face)) {
      _updateDetectionState(
        FaceDetectionState.detected,
        'Look straight at the camera',
      );
      return;
    }

    // Face is good - attempt matching with cached enrollments
    _updateDetectionState(FaceDetectionState.processing, 'Analyzing face...');
    _pulseAnimationController.forward();

    try {
      // Load enrollments into cache if not already cached
      if (_cachedEnrollments == null) {
        await _loadEnrollmentsCache();
      }

      // Perform matching using cached data
      final matchResult = await _matchFaceWithCache(face);

      if (matchResult != null && matchResult.matched) {
        await _handleSuccessfulMatch(matchResult);
      } else {
        await _handleNoMatch(matchResult);
      }
    } catch (e) {
      Logger.error('Recognition failed: $e');
      _updateDetectionState(FaceDetectionState.error, 'Recognition failed');
    }
  }

  Future<void> _handleSuccessfulMatch(FaceMatchResult matchResult) async {
    _updateDetectionState(
      FaceDetectionState.matched,
      'Welcome, ${matchResult.userName}! (${(matchResult.confidence * 100).toStringAsFixed(1)}% match)',
    );

    // Stop image stream
    _stopImageStream();

    // Haptic feedback
    HapticFeedback.selectionClick();

    // Show success animation
    _pulseAnimationController.repeat();

    // Perform sign-in
    await _performSignIn(matchResult.userId!, matchResult.userName!);
  }

  Future<void> _handleNoMatch(FaceMatchResult? matchResult) async {
    if (widget.isEnrollment) {
      _updateDetectionState(
        FaceDetectionState.notMatched,
        'Ready to enroll your face for this event',
      );
    } else {
      _updateDetectionState(
        FaceDetectionState.notMatched,
        'Face not recognized. Please enroll first or try again.',
      );
    }

    // Show enrollment option after a delay
    if (!widget.isEnrollment) {
      _messageTimer = Timer(const Duration(seconds: 3), _showEnrollmentOption);
    }
  }

  void _showEnrollmentOption() {
    if (!mounted) return;

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Face Not Recognized'),
        content: const Text(
          'Would you like to enroll your face for future quick sign-ins to this event?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Not Now'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              _navigateToEnrollment();
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

  Future<void> _performSignIn(String userId, String userName) async {
    try {
      // Create attendance model
      final docId = '${widget.eventModel.id}-$userId';
      final attendanceModel = AttendanceModel(
        id: docId,
        eventId: widget.eventModel.id,
        userName: userName,
        customerUid: userId,
        attendanceDateTime: DateTime.now(),
        answers: [],
        isAnonymous: false,
        signInMethod: 'facial_recognition',
        dwellNotes: 'Facial recognition sign-in',
        entryTimestamp: widget.eventModel.getLocation ? DateTime.now() : null,
        dwellStatus: widget.eventModel.getLocation ? 'active' : null,
      );

      // Check for sign-in questions first
      final eventQuestions = await FirebaseFirestore.instance
          .collection('EventQuestions')
          .where('eventId', isEqualTo: widget.eventModel.id)
          .get();

      if (eventQuestions.docs.isNotEmpty) {
        // Navigate to questions screen
        if (mounted) {
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(
              builder: (context) => AnsQuestionsToSignInEventScreen(
                eventModel: widget.eventModel,
                newAttendance: attendanceModel,
                nextPageRoute: 'event_details',
              ),
            ),
          );
        }
      } else {
        // Direct sign-in
        await FirebaseFirestore.instance
            .collection(AttendanceModel.firebaseKey)
            .doc(docId)
            .set(attendanceModel.toJson());

        ShowToast().showNormalToast(
          msg: 'Signed in successfully with facial recognition!',
        );

        // Navigate back with success
        if (mounted) {
          Future.delayed(_successDelay, () {
            if (mounted) {
              Navigator.pop(context, true);
            }
          });
        }
      }
    } catch (e) {
      Logger.error('Sign-in failed: $e');
      _updateDetectionState(FaceDetectionState.error, 'Sign-in failed: $e');
    }
  }

  void _navigateToEnrollment() {
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (context) =>
            FaceEnrollmentScreen(eventModel: widget.eventModel),
      ),
    );
  }

  void _updateDetectionState(FaceDetectionState state, String message) {
    if (mounted) {
      setState(() {
        _detectionState = state;
        _statusMessage = message;
      });
    }
  }

  void _showErrorState(String message) {
    _updateDetectionState(FaceDetectionState.error, message);
  }

  Color _getStatusColor() {
    switch (_detectionState) {
      case FaceDetectionState.searching:
        return Colors.blue;
      case FaceDetectionState.detected:
        return Colors.orange;
      case FaceDetectionState.processing:
        return Colors.purple;
      case FaceDetectionState.matched:
        return Colors.green;
      case FaceDetectionState.notMatched:
        return Colors.red;
      case FaceDetectionState.error:
        return Colors.red;
    }
  }

  /// Load face enrollments into cache for faster matching
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
        final features = List<double>.from(data['faceFeatures']);
        _cachedEnrollments![userId] = features;
      }

      Logger.debug('Cached ${_cachedEnrollments!.length} face enrollments');
    } catch (e) {
      Logger.error('Failed to load enrollments cache: $e');
      _cachedEnrollments = {};
    }
  }

  /// Match face using cached enrollments (no Firebase query)
  Future<FaceMatchResult?> _matchFaceWithCache(Face detectedFace) async {
    if (_cachedEnrollments == null || _cachedEnrollments!.isEmpty) {
      return FaceMatchResult(
        matched: false,
        confidence: 0.0,
        reason: 'No enrolled faces for this event',
      );
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
    const matchingThreshold = 0.7;

    for (final entry in _cachedEnrollments!.entries) {
      final similarity = _faceService.calculateSimilarity(
        detectedFeatures,
        entry.value,
      );

      if (similarity > highestSimilarity && similarity >= matchingThreshold) {
        highestSimilarity = similarity;

        // Get user name from Firestore (only once when matched)
        final userDoc = await FirebaseFirestore.instance
            .collection('FaceEnrollments')
            .doc('${widget.eventModel.id}-${entry.key}')
            .get();

        final userName = userDoc.data()?['userName'] as String?;

        bestMatch = FaceMatchResult(
          matched: true,
          userId: entry.key,
          userName: userName ?? 'Unknown User',
          confidence: similarity,
          reason: 'Face matched successfully',
        );
      }
    }

    return bestMatch ??
        FaceMatchResult(
          matched: false,
          confidence: highestSimilarity,
          reason: 'No matching face found',
        );
  }

  @override
  void dispose() {
    _stopImageStream();
    _messageTimer?.cancel();
    _scanAnimationController.dispose();
    _pulseAnimationController.dispose();
    _cameraController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: Text(
          widget.isEnrollment ? 'Enroll Face' : 'Face Recognition Sign-In',
        ),
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: Stack(
        children: [
          // Camera preview
          if (_isCameraInitialized && _cameraController != null)
            Positioned.fill(child: CameraPreview(_cameraController!))
          else
            const Center(child: CircularProgressIndicator(color: Colors.white)),

          // Face detection overlay
          if (_isCameraInitialized)
            CustomPaint(
              painter: FaceDetectionPainter(
                faces: _detectedFaces,
                imageSize: _cameraController!.value.previewSize!,
                detectionState: _detectionState,
                scanAnimation: _scanAnimation,
                pulseAnimation: _pulseAnimation,
              ),
              child: Container(),
            ),

          // Status overlay
          Positioned(top: 100, left: 20, right: 20, child: _buildStatusCard()),

          // Instructions
          Positioned(
            bottom: MediaQuery.of(context).padding.bottom + 100,
            left: 20,
            right: 20,
            child: _buildInstructionsCard(),
          ),
        ],
      ),
    );
  }

  Widget _buildStatusCard() {
    return AnimatedBuilder(
      animation: _pulseAnimation,
      builder: (context, child) {
        return Transform.scale(
          scale: _detectionState == FaceDetectionState.processing
              ? _pulseAnimation.value
              : 1.0,
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: _getStatusColor().withValues(alpha: 0.9),
              borderRadius: BorderRadius.circular(12),
              boxShadow: [
                BoxShadow(
                  color: _getStatusColor().withValues(alpha: 0.3),
                  blurRadius: 10,
                  spreadRadius: 2,
                ),
              ],
            ),
            child: Row(
              children: [
                _buildStatusIcon(),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    _statusMessage,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildStatusIcon() {
    switch (_detectionState) {
      case FaceDetectionState.searching:
        return const Icon(Icons.search, color: Colors.white, size: 24);
      case FaceDetectionState.detected:
        return const Icon(Icons.face, color: Colors.white, size: 24);
      case FaceDetectionState.processing:
        return const SizedBox(
          width: 24,
          height: 24,
          child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
        );
      case FaceDetectionState.matched:
        return const Icon(Icons.check_circle, color: Colors.white, size: 24);
      case FaceDetectionState.notMatched:
        return const Icon(Icons.person_off, color: Colors.white, size: 24);
      case FaceDetectionState.error:
        return const Icon(Icons.error, color: Colors.white, size: 24);
    }
  }

  Widget _buildInstructionsCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.8),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withValues(alpha: 0.3)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.face, color: Colors.white, size: 32),
          const SizedBox(height: 8),
          Text(
            widget.eventModel.title,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          const Text(
            '• Position your face in the center\n'
            '• Look straight at the camera\n'
            '• Ensure good lighting\n'
            '• Keep your face steady',
            style: TextStyle(color: Colors.white70, fontSize: 14),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

/// Custom painter for face detection overlay
class FaceDetectionPainter extends CustomPainter {
  final List<Face> faces;
  final Size imageSize;
  final FaceDetectionState detectionState;
  final Animation<double> scanAnimation;
  final Animation<double> pulseAnimation;

  FaceDetectionPainter({
    required this.faces,
    required this.imageSize,
    required this.detectionState,
    required this.scanAnimation,
    required this.pulseAnimation,
  }) : super(repaint: Listenable.merge([scanAnimation, pulseAnimation]));

  @override
  void paint(Canvas canvas, Size size) {
    // Draw face guide frame
    _drawFaceGuideFrame(canvas, size);

    // Draw detected faces
    for (final face in faces) {
      _drawFaceRect(canvas, size, face);
    }

    // Draw scanning line
    if (detectionState == FaceDetectionState.searching) {
      _drawScanningLine(canvas, size);
    }
  }

  void _drawFaceGuideFrame(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = _getGuideColor()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3;

    final center = Offset(size.width / 2, size.height / 2);
    final frameWidth = size.width * 0.7;
    final frameHeight = size.height * 0.5;

    final rect = Rect.fromCenter(
      center: center,
      width: frameWidth,
      height: frameHeight,
    );

    // Draw rounded rectangle with corner indicators
    final cornerLength = 30.0;

    // Top-left corner
    canvas.drawLine(
      rect.topLeft,
      rect.topLeft + Offset(cornerLength, 0),
      paint,
    );
    canvas.drawLine(
      rect.topLeft,
      rect.topLeft + Offset(0, cornerLength),
      paint,
    );

    // Top-right corner
    canvas.drawLine(
      rect.topRight - Offset(cornerLength, 0),
      rect.topRight,
      paint,
    );
    canvas.drawLine(
      rect.topRight,
      rect.topRight + Offset(0, cornerLength),
      paint,
    );

    // Bottom-left corner
    canvas.drawLine(
      rect.bottomLeft - Offset(0, cornerLength),
      rect.bottomLeft,
      paint,
    );
    canvas.drawLine(
      rect.bottomLeft,
      rect.bottomLeft + Offset(cornerLength, 0),
      paint,
    );

    // Bottom-right corner
    canvas.drawLine(
      rect.bottomRight - Offset(cornerLength, 0),
      rect.bottomRight,
      paint,
    );
    canvas.drawLine(
      rect.bottomRight - Offset(0, cornerLength),
      rect.bottomRight,
      paint,
    );
  }

  void _drawFaceRect(Canvas canvas, Size size, Face face) {
    final paint = Paint()
      ..color = _getFaceRectColor()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;

    // Convert face bounds to screen coordinates
    final rect = _scaleRect(face.boundingBox, size);
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, const Radius.circular(8)),
      paint,
    );

    // Draw face landmarks
    _drawFaceLandmarks(canvas, size, face);
  }

  void _drawFaceLandmarks(Canvas canvas, Size size, Face face) {
    final paint = Paint()
      ..color = _getFaceRectColor()
      ..style = PaintingStyle.fill;

    final landmarks = [
      FaceLandmarkType.leftEye,
      FaceLandmarkType.rightEye,
      FaceLandmarkType.noseBase,
      FaceLandmarkType.leftMouth,
      FaceLandmarkType.rightMouth,
    ];

    for (final landmarkType in landmarks) {
      final landmark = face.landmarks[landmarkType];
      if (landmark != null) {
        final point = _scalePoint(landmark.position, size);
        canvas.drawCircle(point, 3, paint);
      }
    }
  }

  void _drawScanningLine(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.cyan.withValues(alpha: 0.8)
      ..strokeWidth = 2;

    final y = size.height * 0.2 + (size.height * 0.6 * scanAnimation.value);
    canvas.drawLine(
      Offset(size.width * 0.15, y),
      Offset(size.width * 0.85, y),
      paint,
    );
  }

  Color _getGuideColor() {
    switch (detectionState) {
      case FaceDetectionState.searching:
        return Colors.blue;
      case FaceDetectionState.detected:
        return Colors.orange;
      case FaceDetectionState.processing:
        return Colors.purple;
      case FaceDetectionState.matched:
        return Colors.green;
      case FaceDetectionState.notMatched:
        return Colors.red;
      case FaceDetectionState.error:
        return Colors.red;
    }
  }

  Color _getFaceRectColor() {
    return _getGuideColor().withValues(alpha: 0.8);
  }

  Rect _scaleRect(Rect rect, Size size) {
    final scaleX = size.width / imageSize.width;
    final scaleY = size.height / imageSize.height;

    return Rect.fromLTRB(
      rect.left * scaleX,
      rect.top * scaleY,
      rect.right * scaleX,
      rect.bottom * scaleY,
    );
  }

  Offset _scalePoint(Point<int> point, Size size) {
    final scaleX = size.width / imageSize.width;
    final scaleY = size.height / imageSize.height;

    return Offset(point.x.toDouble() * scaleX, point.y.toDouble() * scaleY);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}
