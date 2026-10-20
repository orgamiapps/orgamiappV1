import 'package:cloud_functions/cloud_functions.dart';

enum DeniedEventRead { restricted, notFound, connectionError }

/// Firestore rules can deny a missing document. Resolve existence on the
/// server before offering access requests for a genuinely restricted event.
Future<DeniedEventRead> resolveDeniedEventRead(
  String eventId, {
  Future<void> Function(String)? checkCapabilities,
}) async {
  try {
    if (checkCapabilities != null) {
      await checkCapabilities(eventId);
    } else {
      await FirebaseFunctions.instance
          .httpsCallable('getEventCapabilitiesV1')
          .call({'eventId': eventId})
          .timeout(const Duration(seconds: 20));
    }
    return DeniedEventRead.restricted;
  } on FirebaseFunctionsException catch (error) {
    return switch (error.code) {
      'not-found' when error.message == 'Event not found.' =>
        DeniedEventRead.notFound,
      _ => DeniedEventRead.connectionError,
    };
  } catch (_) {
    return DeniedEventRead.connectionError;
  }
}
