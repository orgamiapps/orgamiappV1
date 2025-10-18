import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'package:camera/camera.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import '../Utils/logger.dart';

/// Professional facial recognition service for event attendance
/// Handles face detection, enrollment, matching, and secure storage
class FaceRecognitionService {
  static final FaceRecognitionService _instance =
      FaceRecognitionService._internal();
  factory FaceRecognitionService() => _instance;
  FaceRecognitionService._internal();

  late FaceDetector _faceDetector;
  bool _isInitialized = false;

  // Face detection configuration
  static const double _minFaceSize = 0.15;
  static const double _matchingThreshold = 0.7;
  static const int _requiredFacesForEnrollment = 3;

  /// Initialize the face detection service
  Future<void> initialize() async {
    if (_isInitialized) return;

    try {
      final options = FaceDetectorOptions(
        enableContours: true,
        enableLandmarks: true,
        enableClassification: true,
        enableTracking: true,
        minFaceSize: _minFaceSize,
        performanceMode: FaceDetectorMode.accurate,
      );

      _faceDetector = FaceDetector(options: options);
      _isInitialized = true;
      Logger.debug('FaceRecognitionService initialized successfully');
    } catch (e) {
      Logger.error('Failed to initialize FaceRecognitionService: $e');
      rethrow;
    }
  }

  /// Detect faces in the provided image
  Future<List<Face>> detectFaces(InputImage inputImage) async {
    if (!_isInitialized) await initialize();

    try {
      final faces = await _faceDetector.processImage(inputImage);
      Logger.debug('Detected ${faces.length} faces');
      return faces;
    } catch (e) {
      Logger.error('Face detection failed: $e');
      return [];
    }
  }

  /// Check if a face is suitable for enrollment/recognition
  bool isFaceSuitable(Face face) {
    // Check face size
    final faceArea = face.boundingBox.width * face.boundingBox.height;
    if (faceArea < 10000) return false; // Too small

    // Check if face is looking forward (head angles)
    final headEulerAngleY = face.headEulerAngleY;
    final headEulerAngleZ = face.headEulerAngleZ;

    if (headEulerAngleY != null && headEulerAngleY.abs() > 30) return false;
    if (headEulerAngleZ != null && headEulerAngleZ.abs() > 30) return false;

    // Check if eyes are open (if classification available)
    final leftEyeOpen = face.leftEyeOpenProbability;
    final rightEyeOpen = face.rightEyeOpenProbability;

    if (leftEyeOpen != null && leftEyeOpen < 0.5) return false;
    if (rightEyeOpen != null && rightEyeOpen < 0.5) return false;

    return true;
  }

  /// Extract facial features for comparison
  List<double> extractFaceFeatures(Face face) {
    List<double> features = [];

    // Normalize bounding box relative to image size (assumed 1000x1000 for normalization)
    features.add(face.boundingBox.left / 1000.0);
    features.add(face.boundingBox.top / 1000.0);
    features.add(face.boundingBox.width / 1000.0);
    features.add(face.boundingBox.height / 1000.0);

    // Add landmark positions if available
    final landmarks = [
      FaceLandmarkType.leftEye,
      FaceLandmarkType.rightEye,
      FaceLandmarkType.noseBase,
      FaceLandmarkType.leftMouth,
      FaceLandmarkType.rightMouth,
      FaceLandmarkType.leftEar,
      FaceLandmarkType.rightEar,
      FaceLandmarkType.leftCheek,
      FaceLandmarkType.rightCheek,
    ];

    for (final landmarkType in landmarks) {
      final landmark = face.landmarks[landmarkType];
      if (landmark != null) {
        features.add(landmark.position.x / 1000.0);
        features.add(landmark.position.y / 1000.0);
      } else {
        features.addAll([0.0, 0.0]); // Fill missing landmarks with zeros
      }
    }

    // Add head pose angles
    features.add((face.headEulerAngleX ?? 0.0) / 90.0); // Normalize to [-1, 1]
    features.add((face.headEulerAngleY ?? 0.0) / 90.0);
    features.add((face.headEulerAngleZ ?? 0.0) / 90.0);

    // Add face classification scores
    features.add(face.leftEyeOpenProbability ?? 0.5);
    features.add(face.rightEyeOpenProbability ?? 0.5);
    features.add(face.smilingProbability ?? 0.5);

    return features;
  }

  /// Calculate similarity between two face feature vectors
  double calculateSimilarity(List<double> features1, List<double> features2) {
    if (features1.length != features2.length) {
      Logger.warning('Feature vectors have different lengths');
      return 0.0;
    }

    // Calculate cosine similarity
    double dotProduct = 0.0;
    double norm1 = 0.0;
    double norm2 = 0.0;

    for (int i = 0; i < features1.length; i++) {
      dotProduct += features1[i] * features2[i];
      norm1 += features1[i] * features1[i];
      norm2 += features2[i] * features2[i];
    }

    if (norm1 == 0.0 || norm2 == 0.0) return 0.0;

    final similarity = dotProduct / (sqrt(norm1) * sqrt(norm2));
    return similarity.clamp(0.0, 1.0);
  }

  /// Enroll a user's face for an event
  Future<bool> enrollUserFace({
    required String userId,
    required String userName,
    required String eventId,
    required List<List<double>> faceFeatures, // Multiple face samples
  }) async {
    try {
      if (faceFeatures.length < _requiredFacesForEnrollment) {
        Logger.warning('Insufficient face samples for enrollment');
        return false;
      }

      // Calculate average features for better accuracy
      final avgFeatures = _calculateAverageFeatures(faceFeatures);

      // Store in Firestore
      await FirebaseFirestore.instance
          .collection('FaceEnrollments')
          .doc('$eventId-$userId')
          .set({
            'userId': userId,
            'userName': userName,
            'eventId': eventId,
            'faceFeatures': avgFeatures,
            'sampleCount': faceFeatures.length,
            'enrolledAt': FieldValue.serverTimestamp(),
            'version': '1.0', // For future compatibility
          });

      Logger.info('User $userId enrolled successfully for event $eventId');
      return true;
    } catch (e) {
      Logger.error('Face enrollment failed: $e');
      return false;
    }
  }

  /// Find matching user for detected face
  Future<FaceMatchResult?> matchFace({
    required Face detectedFace,
    required String eventId,
  }) async {
    try {
      if (!isFaceSuitable(detectedFace)) {
        return FaceMatchResult(
          matched: false,
          confidence: 0.0,
          reason: 'Face not suitable for recognition',
        );
      }

      // Extract features from detected face
      final detectedFeatures = extractFaceFeatures(detectedFace);

      // Get all enrolled faces for this event
      final enrolledSnapshot = await FirebaseFirestore.instance
          .collection('FaceEnrollments')
          .where('eventId', isEqualTo: eventId)
          .get();

      if (enrolledSnapshot.docs.isEmpty) {
        return FaceMatchResult(
          matched: false,
          confidence: 0.0,
          reason: 'No enrolled faces for this event',
        );
      }

      // Find best match
      FaceMatchResult? bestMatch;
      double highestSimilarity = 0.0;

      for (final doc in enrolledSnapshot.docs) {
        final data = doc.data();
        final enrolledFeatures = List<double>.from(data['faceFeatures']);
        final similarity = calculateSimilarity(
          detectedFeatures,
          enrolledFeatures,
        );

        Logger.debug('Similarity with ${data['userName']}: $similarity');

        if (similarity > highestSimilarity &&
            similarity >= _matchingThreshold) {
          highestSimilarity = similarity;
          bestMatch = FaceMatchResult(
            matched: true,
            userId: data['userId'],
            userName: data['userName'],
            confidence: similarity,
            reason: 'Face matched successfully',
          );
        }
      }

      return bestMatch ??
          FaceMatchResult(
            matched: false,
            confidence: highestSimilarity,
            reason:
                'No matching face found (highest similarity: ${(highestSimilarity * 100).toStringAsFixed(1)}%)',
          );
    } catch (e) {
      Logger.error('Face matching failed: $e');
      return FaceMatchResult(
        matched: false,
        confidence: 0.0,
        reason: 'Error during face matching: $e',
      );
    }
  }

  /// Check if user is enrolled for specific event
  Future<bool> isUserEnrolled({
    required String userId,
    required String eventId,
  }) async {
    try {
      final doc = await FirebaseFirestore.instance
          .collection('FaceEnrollments')
          .doc('$eventId-$userId')
          .get();
      return doc.exists;
    } catch (e) {
      Logger.error('Failed to check enrollment status: $e');
      return false;
    }
  }

  /// Delete user enrollment for specific event
  Future<bool> deleteUserEnrollment({
    required String userId,
    required String eventId,
  }) async {
    try {
      await FirebaseFirestore.instance
          .collection('FaceEnrollments')
          .doc('$eventId-$userId')
          .delete();
      Logger.info('Deleted enrollment for user $userId in event $eventId');
      return true;
    } catch (e) {
      Logger.error('Failed to delete enrollment: $e');
      return false;
    }
  }

  /// Convert CameraImage to InputImage for ML Kit processing
  InputImage? convertCameraImage(
    CameraImage cameraImage,
    CameraDescription camera,
  ) {
    try {
      // Get image rotation
      final sensorOrientation = camera.sensorOrientation;
      InputImageRotation? rotation;

      if (Platform.isIOS) {
        rotation = InputImageRotationValue.fromRawValue(sensorOrientation);
      } else if (Platform.isAndroid) {
        var rotationCompensation = _orientations[camera.lensDirection]!;
        rotationCompensation += sensorOrientation;
        rotation = InputImageRotationValue.fromRawValue(
          rotationCompensation % 360,
        );
      }

      if (rotation == null) return null;

      // Get image format
      final format = InputImageFormatValue.fromRawValue(cameraImage.format.raw);
      if (format == null) return null;

      // Create plane data
      final allBytes = <Uint8List>[];
      for (final plane in cameraImage.planes) {
        allBytes.add(plane.bytes);
      }
      final imageBytes = Uint8List.fromList(allBytes.expand((x) => x).toList());

      return InputImage.fromBytes(
        bytes: imageBytes,
        metadata: InputImageMetadata(
          size: Size(
            cameraImage.width.toDouble(),
            cameraImage.height.toDouble(),
          ),
          rotation: rotation,
          format: format,
          bytesPerRow: cameraImage.planes[0].bytesPerRow,
        ),
      );
    } catch (e) {
      Logger.error('Failed to convert camera image: $e');
      return null;
    }
  }

  /// Calculate average features from multiple samples
  List<double> _calculateAverageFeatures(List<List<double>> featuresList) {
    if (featuresList.isEmpty) return [];

    final featureLength = featuresList.first.length;
    final avgFeatures = List<double>.filled(featureLength, 0.0);

    for (final features in featuresList) {
      for (int i = 0; i < features.length; i++) {
        avgFeatures[i] += features[i];
      }
    }

    for (int i = 0; i < avgFeatures.length; i++) {
      avgFeatures[i] /= featuresList.length;
    }

    return avgFeatures;
  }

  /// Dispose of resources
  Future<void> dispose() async {
    if (_isInitialized) {
      try {
        await _faceDetector.close();
        _isInitialized = false;
        Logger.debug('FaceRecognitionService disposed');
      } catch (e) {
        Logger.error('Error disposing FaceRecognitionService: $e');
      }
    }
  }

  // Camera rotation mappings
  static const _orientations = {
    CameraLensDirection.back: 90,
    CameraLensDirection.front: 270,
    CameraLensDirection.external: 0,
  };
}

/// Result of a face matching operation
class FaceMatchResult {
  final bool matched;
  final String? userId;
  final String? userName;
  final double confidence;
  final String reason;

  FaceMatchResult({
    required this.matched,
    this.userId,
    this.userName,
    required this.confidence,
    required this.reason,
  });

  @override
  String toString() {
    return 'FaceMatchResult{matched: $matched, userId: $userId, userName: $userName, confidence: ${(confidence * 100).toStringAsFixed(1)}%, reason: $reason}';
  }
}

/// Enum for face detection states
enum FaceDetectionState {
  searching,
  detected,
  processing,
  matched,
  notMatched,
  error,
}
