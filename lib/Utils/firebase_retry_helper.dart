import 'dart:async';
import 'dart:math' show Random;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:attendus/Utils/logger.dart';
import 'package:connectivity_plus/connectivity_plus.dart';

/// Helper class for Firebase operations with retry logic and better error handling
class FirebaseRetryHelper {
  static const Duration _baseDelay = Duration(seconds: 1);
  static const int _maxRetries = 3;
  static final Random _random = Random();

  /// Check if the device has network connectivity
  static Future<bool> hasNetworkConnectivity() async {
    try {
      final connectivity = await Connectivity().checkConnectivity().timeout(
        const Duration(milliseconds: 500),
      );

      // In newer versions, checkConnectivity returns List<ConnectivityResult>
      return connectivity.isNotEmpty &&
          !connectivity.every((c) => c == ConnectivityResult.none);
    } catch (e) {
      Logger.warning('Network connectivity check failed: $e');
      // Assume online if check fails
      return true;
    }
  }

  /// Execute a Firestore operation with retry logic
  static Future<T> executeWithRetry<T>(
    Future<T> Function() operation, {
    int maxRetries = _maxRetries,
    Duration timeout = const Duration(seconds: 10),
    String operationName = 'Firestore operation',
  }) async {
    int attempts = 0;

    while (attempts <= maxRetries) {
      try {
        attempts++;

        // Check network connectivity before attempting operation
        if (!await hasNetworkConnectivity()) {
          Logger.warning('$operationName: No network connectivity');
          throw FirebaseException(
            plugin: 'cloud_firestore',
            code: 'network-request-failed',
            message: 'No network connectivity',
          );
        }

        // Execute the operation with timeout
        final result = await operation().timeout(
          timeout,
          onTimeout: () {
            throw TimeoutException(
              '$operationName timed out after ${timeout.inSeconds}s',
              timeout,
            );
          },
        );

        Logger.debug('$operationName completed successfully');
        return result;
      } on TimeoutException catch (e) {
        Logger.warning(
          '$operationName timeout (attempt $attempts/$maxRetries): $e',
        );
        if (attempts > maxRetries) {
          Logger.error(
            '$operationName failed after $maxRetries retries due to timeout',
          );
          rethrow;
        }
        await _exponentialBackoff(attempts);
      } on FirebaseException catch (e) {
        Logger.warning(
          '$operationName Firebase error (attempt $attempts/$maxRetries): ${e.code} - ${e.message}',
        );

        // Don't retry certain errors
        if (_shouldNotRetry(e.code)) {
          Logger.error(
            '$operationName failed with non-retryable error: ${e.code}',
          );
          rethrow;
        }

        if (attempts > maxRetries) {
          Logger.error(
            '$operationName failed after $maxRetries retries: ${e.code}',
          );
          rethrow;
        }
        await _exponentialBackoff(attempts);
      } catch (e) {
        Logger.warning(
          '$operationName error (attempt $attempts/$maxRetries): $e',
        );
        if (attempts > maxRetries) {
          Logger.error('$operationName failed after $maxRetries retries');
          rethrow;
        }
        await _exponentialBackoff(attempts);
      }
    }

    // This should never be reached, but just in case
    throw Exception('$operationName failed after all retry attempts');
  }

  /// Execute a Firestore query with retry logic
  static Future<QuerySnapshot> executeQueryWithRetry(
    Query query, {
    int maxRetries = _maxRetries,
    Duration timeout = const Duration(seconds: 10),
    String operationName = 'Firestore query',
  }) async {
    return executeWithRetry<QuerySnapshot>(
      () => query.get(const GetOptions(source: Source.serverAndCache)),
      maxRetries: maxRetries,
      timeout: timeout,
      operationName: operationName,
    );
  }

  /// Execute a Firestore document get with retry logic
  static Future<DocumentSnapshot> executeDocumentGetWithRetry(
    DocumentReference doc, {
    int maxRetries = _maxRetries,
    Duration timeout = const Duration(seconds: 8),
    String operationName = 'Firestore document get',
  }) async {
    return executeWithRetry<DocumentSnapshot>(
      () => doc.get(const GetOptions(source: Source.serverAndCache)),
      maxRetries: maxRetries,
      timeout: timeout,
      operationName: operationName,
    );
  }

  /// Exponential backoff with jitter
  static Future<void> _exponentialBackoff(int attempt) async {
    final delay = Duration(
      milliseconds:
          (_baseDelay.inMilliseconds * (1 << (attempt - 1)) + // Exponential
                  _random.nextInt(1000)) // Jitter
              .clamp(1000, 5000), // Clamp between 1-5 seconds
    );

    Logger.debug('Retrying in ${delay.inMilliseconds}ms...');
    await Future.delayed(delay);
  }

  /// Check if a Firebase error code should not be retried
  static bool _shouldNotRetry(String errorCode) {
    const nonRetryableErrors = {
      'permission-denied',
      'not-found',
      'invalid-argument',
      'failed-precondition',
      'out-of-range',
      'unauthenticated',
      'already-exists',
    };

    return nonRetryableErrors.contains(errorCode);
  }

  /// Get user-friendly error message
  static String getUserFriendlyErrorMessage(dynamic error) {
    if (error is TimeoutException) {
      return 'Connection timed out. Please check your internet connection and try again.';
    } else if (error is FirebaseException) {
      switch (error.code) {
        case 'network-request-failed':
          return 'Network connection failed. Please check your internet connection.';
        case 'permission-denied':
          return 'Access denied. Please check your permissions.';
        case 'not-found':
          return 'The requested data was not found.';
        case 'unauthenticated':
          return 'Please sign in to continue.';
        default:
          return 'Something went wrong. Please try again later.';
      }
    } else {
      return 'An unexpected error occurred. Please try again.';
    }
  }
}
