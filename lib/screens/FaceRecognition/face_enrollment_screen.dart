import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../Permissions/permissions_helper.dart';
import '../../Services/face_recognition_service.dart';
import '../../Services/user_identity_service.dart';
import '../../models/event_model.dart';
import '../../Utils/logger.dart';
import '../../Utils/toast.dart';
import 'face_recognition_scanner_screen.dart';

/// Professional face enrollment screen for event attendance
class FaceEnrollmentScreen extends StatefulWidget {
  final EventModel eventModel;
  final String? guestUserId;
  final String? guestUserName;

  const FaceEnrollmentScreen({
    super.key,
    required this.eventModel,
    this.guestUserId,
    this.guestUserName,
  });

  @override
  State<FaceEnrollmentScreen> createState() => _FaceEnrollmentScreenState();
}

class _FaceEnrollmentScreenState extends State<FaceEnrollmentScreen>
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

  // Enrollment state
  int _currentStep = 0;
  final int _requiredSteps = 5;
  final List<List<double>> _collectedFeatures = [];
  bool _isEnrollmentComplete = false;
  String _statusMessage = 'Position your face in the frame';

  // Animation controllers
  late AnimationController _progressAnimationController;
  late AnimationController _stepAnimationController;
  late Animation<double> _progressAnimation;
  late Animation<double> _stepAnimation;

  // Timers and throttling
  Timer? _stepTimer;
  DateTime? _lastCaptureTime;

  // Constants
  static const Duration _captureInterval = Duration(milliseconds: 1200); // Reduced frequency

  @override
  void initState() {
    super.initState();
    _initializeAnimations();
    _initializeServices();
    _initializeCamera();
  }

  void _initializeAnimations() {
    _progressAnimationController = AnimationController(
      duration: const Duration(milliseconds: 800),
      vsync: this,
    );
    _stepAnimationController = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );

    _progressAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _progressAnimationController,
        curve: Curves.easeInOut,
      ),
    );
    _stepAnimation = Tween<double>(begin: 0.8, end: 1.2).animate(
      CurvedAnimation(
        parent: _stepAnimationController,
        curve: Curves.elasticOut,
      ),
    );
  }

  Future<void> _initializeServices() async {
    try {
      Logger.info('Initializing face recognition service...');
      await _faceService.initialize();
      Logger.info('Face recognition service initialized successfully');
    } catch (e) {
      Logger.error('Failed to initialize face recognition service: $e');
      _showErrorAndExit('Failed to initialize face recognition');
    }
  }

  Future<void> _initializeCamera() async {
    try {
      // Request camera permission first
      Logger.info('Requesting camera permission...');
      final hasPermission = await PermissionsHelperClass.checkCameraPermission(
        context: context,
      );
      
      if (!hasPermission) {
        Logger.error('Camera permission denied');
        _showErrorAndExit('Camera permission is required for face enrollment');
        return;
      }
      
      Logger.info('Camera permission granted, initializing camera...');
      _cameras = await availableCameras();
      if (_cameras == null || _cameras!.isEmpty) {
        Logger.error('No cameras available on this device');
        _showErrorAndExit('No cameras available on this device');
        return;
      }

      Logger.info('Found ${_cameras!.length} camera(s)');

      // Prefer front camera for face enrollment
      final frontCamera = _cameras!.firstWhere(
        (camera) => camera.lensDirection == CameraLensDirection.front,
        orElse: () => _cameras!.first,
      );

      Logger.info('Using camera: ${frontCamera.name} (${frontCamera.lensDirection})');

      _camera = frontCamera;
      final imageFormat = Platform.isIOS ? ImageFormatGroup.bgra8888 : ImageFormatGroup.nv21;
      Logger.info('Using image format: $imageFormat for platform: ${Platform.operatingSystem}');
      
      _cameraController = CameraController(
        frontCamera,
        ResolutionPreset.medium, // Balance between quality and performance
        enableAudio: false,
        imageFormatGroup: imageFormat,
      );

      await _cameraController!.initialize();
      Logger.info('Camera initialized successfully');

      if (mounted) {
        setState(() {
          _isCameraInitialized = true;
        });

        // Start enrollment process with image streaming
        _startImageStream();
      }
    } catch (e) {
      Logger.error('Camera initialization failed: $e');
      _showErrorAndExit('Failed to access camera. Please check permissions.');
    }
  }

  void _startImageStream() {
    if (_cameraController == null || !_cameraController!.value.isInitialized || _isStreamActive) {
      Logger.warning('Cannot start image stream: camera=${_cameraController != null}, initialized=${_cameraController?.value.isInitialized}, streamActive=$_isStreamActive');
      return;
    }

    Logger.info('Starting image stream for face enrollment');
    Logger.info('Camera info: width=${_cameraController!.value.previewSize?.width}, height=${_cameraController!.value.previewSize?.height}');
    _isStreamActive = true;
    _updateStatusMessage('Look straight at the camera');
    
    try {
      _cameraController!.startImageStream(_processCameraImage);
      Logger.info('Image stream started successfully');
    } catch (e) {
      Logger.error('Failed to start image stream: $e');
      _showErrorAndExit('Failed to start camera stream');
    }
  }

  void _stopImageStream() {
    if (_isStreamActive && _cameraController != null) {
      try {
        _cameraController!.stopImageStream();
        _isStreamActive = false;
      } catch (e) {
        Logger.error('Error stopping image stream: $e');
      }
    }
  }

  Future<void> _processCameraImage(CameraImage cameraImage) async {
    // Throttle processing
    if (_isProcessing || _camera == null || _isEnrollmentComplete || _currentStep >= _requiredSteps) {
      return;
    }

    final now = DateTime.now();
    if (_lastCaptureTime != null &&
        now.difference(_lastCaptureTime!) < _captureInterval) {
      return; // Skip this frame
    }

    _isProcessing = true;
    _lastCaptureTime = now;

    try {
      Logger.debug('Processing camera image: format=${cameraImage.format.group}, width=${cameraImage.width}, height=${cameraImage.height}, planes=${cameraImage.planes.length}');
      
      // Convert camera image to ML Kit input image
      final inputImage = _faceService.convertCameraImage(cameraImage, _camera!);
      
      if (inputImage == null) {
        Logger.warning('Failed to convert camera image to InputImage - trying next frame');
        // Don't show error to user, just try next frame
        return;
      }
      
      Logger.debug('Successfully converted to InputImage');

      // Detect faces
      Logger.debug('Attempting face detection...');
      final faces = await _faceService.detectFaces(inputImage);
      Logger.debug('Face detection complete: found ${faces.length} face(s)');

      if (faces.isEmpty) {
        if (mounted) {
          _updateStatusMessage(
            'No face detected. Please position yourself in the frame.',
          );
        }
        return;
      }

      final face = faces.first;
      Logger.debug('Face detected: boundingBox=${face.boundingBox}, headAngleY=${face.headEulerAngleY}, headAngleZ=${face.headEulerAngleZ}');

      // Check if face is suitable for enrollment
      if (!_faceService.isFaceSuitable(face)) {
        Logger.debug('Face not suitable for enrollment - checking requirements');
        Logger.debug('Face area: ${face.boundingBox.width * face.boundingBox.height}');
        Logger.debug('Head angles: Y=${face.headEulerAngleY}, Z=${face.headEulerAngleZ}');
        Logger.debug('Eye open probability: left=${face.leftEyeOpenProbability}, right=${face.rightEyeOpenProbability}');
        if (mounted) {
          _updateStatusMessage(
            'Please look straight at the camera and keep still.',
          );
        }
        return;
      }
      
      Logger.debug('Face is suitable for enrollment');

      // Extract features
      final features = _faceService.extractFaceFeatures(face);

      // Check if this sample is significantly different from previous ones
      if (_isFeaturesSimilarToExisting(features)) {
        if (mounted) {
          _updateStatusMessage('Please change your pose slightly.');
        }
        return;
      }

      // Add to collected features
      _collectedFeatures.add(features);
      _currentStep++;

      Logger.info('Face sample $_currentStep/$_requiredSteps captured successfully');

      // Update progress
      _progressAnimationController.animateTo(_currentStep / _requiredSteps);
      _stepAnimationController.forward().then((_) {
        _stepAnimationController.reverse();
      });

      // Haptic feedback
      HapticFeedback.selectionClick();

      // Update status message
      if (_currentStep < _requiredSteps) {
        if (mounted) {
          _updateStatusMessage(
            'Great! ${_requiredSteps - _currentStep} more captures needed.',
          );
        }
      } else {
        // Complete enrollment after collecting all steps
        Logger.info('All $_requiredSteps face samples collected, completing enrollment');
        _stopImageStream();
        await _completeEnrollment();
      }
    } catch (e) {
      Logger.error('Step capture failed: $e');
      if (mounted) {
        _updateStatusMessage('Capture failed. Please try again.');
      }
    } finally {
      _isProcessing = false;
    }
  }

  bool _isFeaturesSimilarToExisting(List<double> newFeatures) {
    if (_collectedFeatures.isEmpty) return false;

    for (final existingFeatures in _collectedFeatures) {
      final similarity = _faceService.calculateSimilarity(
        newFeatures,
        existingFeatures,
      );
      if (similarity > 0.9) {
        // Too similar
        return true;
      }
    }
    return false;
  }

  Future<void> _completeEnrollment() async {
    _stopImageStream();
    _isEnrollmentComplete = true;

    _updateStatusMessage('Processing enrollment...');

    try {
      // Get user identity using centralized service
      final userIdentity = await UserIdentityService.getCurrentUserIdentity(
        guestUserId: widget.guestUserId,
        guestUserName: widget.guestUserName,
      );

      if (userIdentity == null) {
        Logger.error('No user identity available');
        _showErrorAndExit('Please log in to enroll your face.');
        return;
      }

      // Log identity details for debugging
      UserIdentityService.logIdentityDetails(userIdentity, 'Face Enrollment');
      
      final enrollmentDocId = UserIdentityService.generateEnrollmentDocumentId(
        widget.eventModel.id,
        userIdentity.userId,
      );
      Logger.info('Enrollment will be saved to: FaceEnrollments/$enrollmentDocId');

      Logger.info('Enrolling face for event: ${widget.eventModel.id} (${widget.eventModel.title})');
      Logger.info('Collected ${_collectedFeatures.length} face feature samples');

      // Enroll face with collected features
      final success = await _faceService.enrollUserFace(
        userId: userIdentity.userId,
        userName: userIdentity.userName,
        eventId: widget.eventModel.id,
        faceFeatures: _collectedFeatures,
      );

      if (success) {
        Logger.info('Face enrollment completed successfully!');
        _updateStatusMessage(
          'Enrollment successful! You can now use face recognition.',
        );
        ShowToast().showNormalToast(msg: 'Face enrolled successfully!');

        // Navigate to scanner or back
        Future.delayed(const Duration(seconds: 2), () {
          if (mounted) {
            Logger.info('Navigating to face recognition scanner');
            Navigator.pushReplacement(
              context,
              MaterialPageRoute(
                builder: (context) => FaceRecognitionScannerScreen(
                  eventModel: widget.eventModel,
                  guestUserId: userIdentity.isGuest ? userIdentity.userId : null,
                  guestUserName: userIdentity.isGuest ? userIdentity.userName : null,
                ),
              ),
            );
          }
        });
      } else {
        Logger.error('Face enrollment failed - service returned false');
        _showErrorAndExit('Failed to enroll face. Please try again.');
      }
    } catch (e) {
      Logger.error('Enrollment completion failed: $e');
      _showErrorAndExit('Enrollment failed: $e');
    }
  }

  void _updateStatusMessage(String message) {
    if (mounted) {
      setState(() {
        _statusMessage = message;
      });
    }
  }

  void _showErrorAndExit(String message) {
    ShowToast().showNormalToast(msg: message);
    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) {
        Navigator.pop(context);
      }
    });
  }

  @override
  void dispose() {
    _stopImageStream();
    _stepTimer?.cancel();
    _progressAnimationController.dispose();
    _stepAnimationController.dispose();
    _cameraController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: const Text('Enroll Your Face'),
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

          // Face guide overlay
          if (_isCameraInitialized)
            CustomPaint(
              painter: EnrollmentGuidePainter(
                currentStep: _currentStep,
                totalSteps: _requiredSteps,
                stepAnimation: _stepAnimation,
              ),
              child: Container(),
            ),

          // Progress card
          Positioned(
            top: 100,
            left: 20,
            right: 20,
            child: _buildProgressCard(),
          ),

          // Instructions card
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

  Widget _buildProgressCard() {
    return AnimatedBuilder(
      animation: _stepAnimation,
      builder: (context, child) {
        return Transform.scale(
          scale: _isProcessing ? _stepAnimation.value : 1.0,
          child: Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: const Color(0xFFFF6B6B).withValues(alpha: 0.9),
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFFFF6B6B).withValues(alpha: 0.3),
                  blurRadius: 10,
                  spreadRadius: 2,
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    const Icon(Icons.face, color: Colors.white, size: 24),
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
                const SizedBox(height: 16),

                // Progress bar
                AnimatedBuilder(
                  animation: _progressAnimation,
                  builder: (context, child) {
                    return Column(
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              'Step $_currentStep of $_requiredSteps',
                              style: const TextStyle(
                                color: Colors.white70,
                                fontSize: 14,
                              ),
                            ),
                            Text(
                              '${(_progressAnimation.value * 100).toInt()}%',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 14,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        LinearProgressIndicator(
                          value: _progressAnimation.value,
                          backgroundColor: Colors.white.withValues(alpha: 0.3),
                          valueColor: const AlwaysStoppedAnimation<Color>(
                            Colors.white,
                          ),
                          minHeight: 6,
                        ),
                      ],
                    );
                  },
                ),

                const SizedBox(height: 16),

                // Step indicators
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: List.generate(_requiredSteps, (index) {
                    final isCompleted = index < _currentStep;
                    final isCurrent = index == _currentStep;

                    return Container(
                      width: 12,
                      height: 12,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: isCompleted
                            ? Colors.white
                            : isCurrent
                            ? Colors.white.withValues(alpha: 0.7)
                            : Colors.white.withValues(alpha: 0.3),
                        border: Border.all(
                          color: Colors.white,
                          width: isCurrent ? 2 : 1,
                        ),
                      ),
                      child: isCompleted
                          ? const Icon(
                              Icons.check,
                              size: 8,
                              color: Color(0xFFFF6B6B),
                            )
                          : null,
                    );
                  }),
                ),
              ],
            ),
          ),
        );
      },
    );
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
          Row(
            children: [
              const Icon(Icons.info_outline, color: Colors.white70, size: 20),
              const SizedBox(width: 8),
              Text(
                'Enrollment for ${widget.eventModel.title}',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          const Text(
            '• Look directly at the camera\n'
            '• Change your expression slightly between captures\n'
            '• Ensure good lighting on your face\n'
            '• Stay within the frame throughout the process',
            style: TextStyle(color: Colors.white70, fontSize: 13),
            textAlign: TextAlign.left,
          ),
        ],
      ),
    );
  }
}

/// Custom painter for enrollment guide overlay
class EnrollmentGuidePainter extends CustomPainter {
  final int currentStep;
  final int totalSteps;
  final Animation<double> stepAnimation;

  EnrollmentGuidePainter({
    required this.currentStep,
    required this.totalSteps,
    required this.stepAnimation,
  }) : super(repaint: stepAnimation);

  @override
  void paint(Canvas canvas, Size size) {
    // Draw main face guide
    _drawFaceGuide(canvas, size);

    // Draw step indicators around the frame
    _drawStepIndicators(canvas, size);
  }

  void _drawFaceGuide(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0xFFFF6B6B)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3;

    final center = Offset(size.width / 2, size.height / 2);
    final frameWidth = size.width * 0.65;
    final frameHeight = size.height * 0.45;

    final rect = Rect.fromCenter(
      center: center,
      width: frameWidth,
      height: frameHeight,
    );

    // Draw face oval
    canvas.drawOval(rect, paint);

    // Draw pulsing effect for current capture
    if (currentStep < totalSteps) {
      final pulsePaint = Paint()
        ..color = const Color(
          0xFFFF6B6B,
        ).withValues(alpha: 0.3 * stepAnimation.value)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 6;

      canvas.drawOval(
        Rect.fromCenter(
          center: center,
          width: frameWidth * stepAnimation.value,
          height: frameHeight * stepAnimation.value,
        ),
        pulsePaint,
      );
    }
  }

  void _drawStepIndicators(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width * 0.4;

    for (int i = 0; i < totalSteps; i++) {
      final angle = (2 * 3.14159 * i / totalSteps) - (3.14159 / 2);
      final indicatorCenter = Offset(
        center.dx + radius * cos(angle),
        center.dy + radius * sin(angle),
      );

      final isCompleted = i < currentStep;
      final isCurrent = i == currentStep;

      final paint = Paint()
        ..color = isCompleted
            ? Colors.green
            : isCurrent
            ? const Color(0xFFFF6B6B)
            : Colors.white.withValues(alpha: 0.5)
        ..style = PaintingStyle.fill;

      canvas.drawCircle(indicatorCenter, isCurrent ? 8 : 6, paint);

      if (isCompleted) {
        final checkPaint = Paint()
          ..color = Colors.white
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2;

        // Draw checkmark
        final checkPath = Path();
        checkPath.moveTo(indicatorCenter.dx - 3, indicatorCenter.dy);
        checkPath.lineTo(indicatorCenter.dx - 1, indicatorCenter.dy + 2);
        checkPath.lineTo(indicatorCenter.dx + 3, indicatorCenter.dy - 2);

        canvas.drawPath(checkPath, checkPaint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}
