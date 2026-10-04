import 'dart:convert';
import 'dart:math';
import 'package:cryptography/cryptography.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'guest_mode_service.dart';

class PublicRegistrationService {
  final _functions = FirebaseFunctions.instanceFor(region: 'us-central1');
  static const _storage = FlutterSecureStorage();

  Future<Map<String, dynamic>> status(
    String eventId, {
    String? registrationId,
    String? ticketId,
  }) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return {'status': 'none'};
    final result = await _functions
        .httpsCallable('getPublicRegistrationStatusV2')
        .call({
          'eventId': eventId,
          'registrationId': ?registrationId,
          'ticketId': ?ticketId,
        })
        .timeout(const Duration(seconds: 15));
    if (FirebaseAuth.instance.currentUser?.uid != uid) {
      throw StateError('Account changed. Reload your registrations.');
    }
    return Map<String, dynamic>.from(result.data as Map);
  }

  Future<Map<String, dynamic>> register(
    String eventId,
    String fullName,
    String email,
    Map<String, dynamic> answers,
  ) async {
    final user = await GuestModeService().ensureGuestSession().timeout(
      const Duration(seconds: 15),
    );
    if (user == null) {
      throw StateError('Could not start a secure registration session.');
    }
    final payload = {
      'eventId': eventId,
      'fullName': fullName.trim(),
      'email': email.trim(),
      'answers': answers,
    };
    final storageKey = 'registration-attempt-${user.uid}-$eventId';
    final fingerprint = base64UrlEncode(
      (await Sha256().hash(utf8.encode(jsonEncode(payload)))).bytes,
    );
    final previous = await _storage.read(key: storageKey);
    final saved = previous == null ? null : jsonDecode(previous) as Map;
    final key = saved?['fingerprint'] == fingerprint
        ? saved!['key'] as String
        : List.generate(
            24,
            (_) =>
                Random.secure().nextInt(256).toRadixString(16).padLeft(2, '0'),
          ).join();
    await _storage.write(
      key: storageKey,
      value: jsonEncode({'fingerprint': fingerprint, 'key': key}),
    );
    if (FirebaseAuth.instance.currentUser?.uid != user.uid) {
      throw StateError(
        'Account changed. Review the registration and submit again.',
      );
    }
    final result = await _functions
        .httpsCallable('startPublicRegistrationV3')
        .call({...payload, 'idempotencyKey': key})
        .timeout(const Duration(seconds: 25));
    if (FirebaseAuth.instance.currentUser?.uid != user.uid) {
      throw StateError('Account changed. Reload your registrations.');
    }
    // Retain the attempt across response loss, reloads and retries; do not store manage tokens.
    return Map<String, dynamic>.from(result.data as Map);
  }
}
