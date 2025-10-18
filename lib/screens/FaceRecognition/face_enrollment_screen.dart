import 'dart:async';
import 'dart:math';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import '../../Controller/customer_controller.dart';
import '../../Services/face_recognition_service.dart';
import '../../models/event_model.dart';
import '../../Utils/logger.dart';
import '../../Utils/toast.dart';
import 'face_recognition_scanner_screen.dart';

/// Professional face enrollment screen for event attendance
class FaceEnrollmentScreen extends StatefulWidget {
  final EventModel eventModel;

  const FaceEnrollmentScreen({super.key, required this.eventModel});

  @override
  State<FaceEnrollmentScreen> createState() => _FaceEnrollmentScreenState();
}

class _FaceEnrollmentScreenState extends State<FaceEnrollmentScreen>
    with TickerProviderStateMixin {
  // Camera and face detection
  CameraController? _cameraController;
  List<CameraDescription>? _cameras;
  bool _isCameraInitialized = false;
  bool _isProcessing = false;

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

  // Timers
  Timer? _captureTimer;
  Timer? _stepTimer;

  // Constants
  static const Duration _captureInterval = Duration(milliseconds: 800);

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
      await _faceService.initialize();
    } catch (e) {
      Logger.error('Failed to initialize face recognition service: $e');
      _showErrorAndExit('Failed to initialize face recognition');
    }
  }

  Future<void> _initializeCamera() async {
    try {
      _cameras = await availableCameras();
      if (_cameras == null || _cameras!.isEmpty) {
        _showErrorAndExit('No cameras available on this device');
        return;
      }

      // Prefer front camera for face enrollment
      final frontCamera = _cameras!.firstWhere(
        (camera) => camera.lensDirection == CameraLensDirection.front,
        orElse: () => _cameras!.first,
      );

      _cameraController = CameraController(
        frontCamera,
        ResolutionPreset.high, // Higher resolution for better enrollment
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.nv21,
      );

      await _cameraController!.initialize();

      if (mounted) {
        setState(() {
          _isCameraInitialized = true;
        });

        // Start enrollment process
        _startEnrollmentProcess();
      }
    } catch (e) {
      Logger.error('Camera initialization failed: $e');
      _showErrorAndExit('Failed to access camera. Please check permissions.');
    }
  }

  void _startEnrollmentProcess() {
    _updateStatusMessage('Look straight at the camera');
    _captureTimer = Timer.periodic(_captureInterval, (timer) {
      if (!_isProcessing && mounted && _currentStep < _requiredSteps) {
        _captureStep();
      }
    });
  }

  Future<void> _captureStep() async {
    if (_isProcessing || _cameraController == null || _isEnrollmentComplete) {
      return;
    }

    _isProcessing = true;

    try {
      // Capture image
      final image = await _cameraController!.takePicture();
      final inputImage = InputImage.fromFilePath(image.path);

      // Detect faces
      final faces = await _faceService.detectFaces(inputImage);

      if (faces.isEmpty) {
        _updateStatusMessage(
          'No face detected. Please position yourself in the frame.',
        );
        return;
      }

      final face = faces.first;

      // Check if face is suitable for enrollment
      if (!_faceService.isFaceSuitable(face)) {
        _updateStatusMessage(
          'Please look straight at the camera and keep still.',
        );
        return;
      }

      // Extract features
      final features = _faceService.extractFaceFeatures(face);

      // Check if this sample is significantly different from previous ones
      if (_isFeaturesSimilarToExisting(features)) {
        _updateStatusMessage('Please change your pose slightly.');
        return;
      }

      // Add to collected features
      _collectedFeatures.add(features);
      _currentStep++;

      // Update progress
      _progressAnimationController.animateTo(_currentStep / _requiredSteps);
      _stepAnimationController.forward().then((_) {
        _stepAnimationController.reverse();
      });

      // Haptic feedback
      HapticFeedback.selectionClick();

      // Update status message
      if (_currentStep < _requiredSteps) {
        _updateStatusMessage(
          'Great! ${_requiredSteps - _currentStep} more captures needed.',
        );
      } else {
        await _completeEnrollment();
      }
    } catch (e) {
      Logger.error('Step capture failed: $e');
      _updateStatusMessage('Capture failed. Please try again.');
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
    _captureTimer?.cancel();
    _isEnrollmentComplete = true;

    _updateStatusMessage('Processing enrollment...');

    try {
      final currentUser = CustomerController.logeInCustomer;
      if (currentUser == null) {
        _showErrorAndExit('Please log in to enroll your face.');
        return;
      }

      // Enroll face with collected features
      final success = await _faceService.enrollUserFace(
        userId: currentUser.uid,
        userName: currentUser.name,
        eventId: widget.eventModel.id,
        faceFeatures: _collectedFeatures,
      );

      if (success) {
        _updateStatusMessage(
          'Enrollment successful! You can now use face recognition.',
        );
        ShowToast().showNormalToast(msg: 'Face enrolled successfully!');

        // Navigate to scanner or back
        Future.delayed(const Duration(seconds: 2), () {
          if (mounted) {
            Navigator.pushReplacement(
              context,
              MaterialPageRoute(
                builder: (context) =>
                    FaceRecognitionScannerScreen(eventModel: widget.eventModel),
              ),
            );
          }
        });
      } else {
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
    _captureTimer?.cancel();
    _stepTimer?.cancel();
    _progressAnimationController.dispose();
    _stepAnimationController.dispose();
    _cameraController?.dispose();
    _faceService.dispose();
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
            bottom: 100,
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
