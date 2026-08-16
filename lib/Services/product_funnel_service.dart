import 'dart:math';

import 'package:attendus/Utils/logger.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class ProductFunnelService {
  static final ProductFunnelService _instance = ProductFunnelService._();
  factory ProductFunnelService() => _instance;
  ProductFunnelService._();

  static const _sessionKey = 'guest_funnel_session_id';
  static const _sessionExpiryKey = 'guest_funnel_session_expiry';
  static const _storage = FlutterSecureStorage();
  Future<void> record(
    String event, {
    Map<String, String> dimensions = const {},
  }) async {
    try {
      final sessionId = await _sessionId();
      final functions = FirebaseFunctions.instanceFor(region: 'us-central1');
      await functions.httpsCallable('recordProductFunnelEvent').call({
        'event': event,
        'sessionId': sessionId,
        'dimensions': dimensions.map((key, value) {
          final normalized = value.replaceAll(RegExp('[^a-zA-Z0-9_.:-]'), '_');
          final safe = normalized.substring(0, min(64, normalized.length));
          return MapEntry(key, safe);
        }),
      });
    } catch (error) {
      Logger.warning('Funnel analytics was not recorded: $error');
    }
  }

  Future<void> rotateSession() async {
    await _storage.delete(key: _sessionKey);
    await _storage.delete(key: _sessionExpiryKey);
  }

  Future<String> _sessionId() async {
    final stored = await _storage.read(key: _sessionKey);
    final expiryRaw = await _storage.read(key: _sessionExpiryKey);
    final expiry = DateTime.tryParse(expiryRaw ?? '');
    if (stored != null &&
        RegExp(r'^[a-f0-9]{32}$').hasMatch(stored) &&
        expiry != null &&
        expiry.isAfter(DateTime.now())) {
      return stored;
    }
    final random = Random.secure();
    final id = List.generate(
      16,
      (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'),
    ).join();
    await _storage.write(key: _sessionKey, value: id);
    await _storage.write(
      key: _sessionExpiryKey,
      value: DateTime.now().add(const Duration(hours: 24)).toIso8601String(),
    );
    return id;
  }
}
