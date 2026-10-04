import 'package:cloud_functions/cloud_functions.dart';

/// The retry scope ends when the read returns. Later admissions, exports and
/// lifecycle operations must never re-enter this loop after their own errors.
Future<T> waitForRoster<T>(
  Future<T> Function() load, {
  int maxAttempts = 30,
  Future<void> Function()? retryDelay,
}) async {
  if (maxAttempts < 1) throw ArgumentError.value(maxAttempts, 'maxAttempts');
  for (var attempt = 0; attempt < maxAttempts; attempt++) {
    try {
      return await load();
    } on FirebaseFunctionsException catch (error) {
      if (error.code != 'unavailable' || attempt == maxAttempts - 1) rethrow;
      if (retryDelay != null) {
        await retryDelay();
      } else {
        await Future<void>.delayed(const Duration(seconds: 1));
      }
    }
  }
  throw StateError('Roster readiness retry budget exhausted');
}
