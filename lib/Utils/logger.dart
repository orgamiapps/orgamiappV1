import 'package:flutter/foundation.dart';

typedef ErrorTelemetrySink = void Function(Map<String, Object?> event);

class Logger {
  static const String releaseId = String.fromEnvironment(
    'ATTENDUS_RELEASE_ID',
    defaultValue: 'development',
  );

  static ErrorTelemetrySink? _errorTelemetrySink;

  static void installErrorTelemetrySink(ErrorTelemetrySink? sink) {
    _errorTelemetrySink = sink;
  }

  static void debug(String message) {
    if (kDebugMode) debugPrint('DEBUG: ${sanitize(message)}');
  }

  static void info(String message) {
    if (kDebugMode) debugPrint('INFO: ${sanitize(message)}');
  }

  static void warning(String message) {
    if (kDebugMode) debugPrint('WARNING: ${sanitize(message)}');
  }

  static void error(String message, [Object? error, StackTrace? stackTrace]) {
    final safeMessage = sanitize(message);
    final safeError = error == null ? null : sanitize(error.toString());
    final safeStack = stackTrace == null
        ? null
        : sanitize(stackTrace.toString(), maxLength: 8000);
    final event = <String, Object?>{
      'releaseId': releaseId,
      'message': safeMessage,
    };
    if (safeError != null) {
      event['error'] = safeError;
    }
    if (safeStack != null) {
      event['stackTrace'] = safeStack;
    }

    // Errors remain visible in production diagnostics even when a remote
    // telemetry provider is not configured. Sensitive patterns are removed
    // before either output path receives the event.
    debugPrint('ERROR [$releaseId]: $safeMessage');
    if (kDebugMode && safeError != null) {
      debugPrint('Error details: $safeError');
    }
    if (kDebugMode && safeStack != null) {
      debugPrint('Stack trace: $safeStack');
    }
    try {
      _errorTelemetrySink?.call(event);
    } catch (telemetryError) {
      // A diagnostics provider must never turn an application error into a
      // second unhandled failure.
      debugPrint(
        'ERROR [$releaseId]: telemetry delivery failed: '
        '${sanitize(telemetryError.toString())}',
      );
    }
  }

  static void success(String message) {
    if (kDebugMode) debugPrint('SUCCESS: ${sanitize(message)}');
  }

  @visibleForTesting
  static String sanitize(String value, {int maxLength = 2000}) {
    var safe = value
        .replaceAll(
          RegExp(
            r'[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}',
            caseSensitive: false,
          ),
          '[redacted-email]',
        )
        .replaceAllMapped(
          RegExp(
            r'((?:api[_-]?key|token|authorization|password|secret)\s*[:=]\s*)[^\s,;]+',
            caseSensitive: false,
          ),
          (match) => '${match.group(1)}[redacted]',
        )
        .replaceAll(
          RegExp(r'Bearer\s+[A-Za-z0-9._~+/=-]+', caseSensitive: false),
          'Bearer [redacted]',
        )
        .replaceAllMapped(
          RegExp(
            r'([?&](?:key|token|signature|code)=)[^&#\s]+',
            caseSensitive: false,
          ),
          (match) => '${match.group(1)}[redacted]',
        );
    if (safe.length > maxLength) {
      safe = '${safe.substring(0, maxLength)}...';
    }
    return safe;
  }
}
