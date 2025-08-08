import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:orgami/Utils/logger.dart';

/// Global error handler for the app
class ErrorHandler {
  /// Initialize global error handling
  static void initialize() {
    // Handle Flutter framework errors
    FlutterError.onError = (FlutterErrorDetails details) {
      Logger.error('Flutter Error: ${details.exception}');
      if (kDebugMode) {
        FlutterError.presentError(details);
      }
    };

    // Handle other Dart errors
    PlatformDispatcher.instance.onError = (error, stack) {
      Logger.error('Unhandled Error: $error');
      Logger.error('Stack trace: $stack');
      return true;
    };
  }

  /// Handle Firebase errors gracefully
  static String handleFirebaseError(dynamic error) {
    if (error.toString().contains('network-request-failed')) {
      return 'Network connection failed. Please check your internet connection.';
    } else if (error.toString().contains('permission-denied')) {
      return 'Access denied. Please check your permissions.';
    } else if (error.toString().contains('timeout')) {
      return 'Request timed out. Please try again.';
    } else {
      return 'Something went wrong. Please try again later.';
    }
  }

  /// Handle location errors gracefully
  static String handleLocationError(dynamic error) {
    if (error.toString().contains('denied')) {
      return 'Location permission denied. Please grant location access in settings.';
    } else if (error.toString().contains('disabled')) {
      return 'Location services are disabled. Please enable location services.';
    } else if (error.toString().contains('timeout')) {
      return 'Location request timed out. Please try again.';
    } else {
      return 'Unable to get your location. Please try again.';
    }
  }

  /// Show error snackbar
  static void showErrorSnackbar(BuildContext context, String message) {
    if (!context.mounted) return;
    
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red,
        duration: const Duration(seconds: 4),
        action: SnackBarAction(
          label: 'Dismiss',
          textColor: Colors.white,
          onPressed: () {
            ScaffoldMessenger.of(context).hideCurrentSnackBar();
          },
        ),
      ),
    );
  }

  /// Build error widget
  static Widget buildErrorWidget(String message, {VoidCallback? onRetry}) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(
            Icons.error_outline,
            color: Colors.red,
            size: 64,
          ),
          const SizedBox(height: 16),
          Text(
            'Oops! Something went wrong',
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            message,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 14,
              color: Colors.grey,
            ),
          ),
          if (onRetry != null) ...[
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: onRetry,
              child: const Text('Try Again'),
            ),
          ],
        ],
      ),
    );
  }

  /// Wrap widget with error boundary
  static Widget withErrorBoundary(Widget child, {String? fallbackMessage}) {
    return Builder(
      builder: (context) {
        try {
          return child;
        } catch (error, stackTrace) {
          Logger.error('Widget error: $error');
          Logger.error('Stack trace: $stackTrace');
          
          return buildErrorWidget(
            fallbackMessage ?? 'This section is temporarily unavailable.',
          );
        }
      },
    );
  }
}
