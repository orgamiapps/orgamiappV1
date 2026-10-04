import 'dart:async';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:attendus/models/customer_model.dart';

/// Public cards never fetch or cache private Customers documents.
class PublicProfileService {
  PublicProfileService({
    String? Function()? currentUid,
    Stream<String?> Function()? accountChanges,
    Future<Map<String, dynamic>> Function(String, Map<String, dynamic>)? call,
  }) : _currentUid =
           currentUid ?? (() => FirebaseAuth.instance.currentUser?.uid),
       _accountChanges =
           accountChanges ??
           (() => FirebaseAuth.instance.authStateChanges().map(
             (user) => user?.uid,
           )),
       _call = call ?? _productionCall;

  final String? Function() _currentUid;
  final Stream<String?> Function() _accountChanges;
  final Future<Map<String, dynamic>> Function(String, Map<String, dynamic>)
  _call;

  static Future<Map<String, dynamic>> _productionCall(
    String name,
    Map<String, dynamic> data,
  ) async => Map<String, dynamic>.from(
    (await FirebaseFunctions.instance
                .httpsCallable(name)
                .call(data)
                .timeout(const Duration(seconds: 20)))
            .data
        as Map,
  );

  Future<T> _withAccount<T>(
    Future<T> Function(void Function() check) operation,
  ) async {
    final uid = _currentUid();
    if (uid == null) throw StateError('Log in to view people.');
    var changed = false;
    final subscription = _accountChanges().listen((next) {
      if (next != uid) changed = true;
    });
    void check() {
      if (changed || _currentUid() != uid) {
        throw StateError('Your account changed. Try again.');
      }
    }

    try {
      check();
      final result = await operation(check);
      check();
      return result;
    } finally {
      await subscription.cancel();
    }
  }

  /// A private loader is permitted only for the current account; its check must
  /// run before a migration/write as well as after each asynchronous read.
  Future<CustomerModel?> getCustomer(
    String userId, {
    Future<CustomerModel?> Function(void Function() check)? loadSelf,
  }) async {
    if (_currentUid() == userId && loadSelf != null) {
      return _withAccount(loadSelf);
    }
    final profiles = await getByIds([userId]);
    return profiles.isEmpty ? null : profiles.first;
  }

  Future<List<CustomerModel>> getByIds(List<String> userIds) => _withAccount((
    check,
  ) async {
    final ids = userIds.where((id) => id.isNotEmpty).toSet().toList();
    final profiles = <String, CustomerModel>{};
    for (var offset = 0; offset < ids.length; offset += 50) {
      check();
      final batch = ids.skip(offset).take(50).toList();
      final result = await _call('getPublicProfilesV1', {'userIds': batch});
      check();
      for (final profile in _parseProfiles(result)) {
        if (batch.contains(profile.uid)) profiles[profile.uid] = profile;
      }
    }
    return ids.map((id) => profiles[id]).whereType<CustomerModel>().toList();
  });

  Future<List<CustomerModel>> search(String query, {int limit = 20}) =>
      _withAccount((check) async {
        final normalized = query.trim().replaceFirst(RegExp(r'^@'), '');
        if (normalized.length > 80) return <CustomerModel>[];
        final boundedLimit = limit.clamp(1, 50);
        final result = await _call('searchPublicProfilesV1', {
          'query': normalized,
          'limit': boundedLimit,
        });
        check();
        return _parseProfiles(result)
            .where((profile) => profile.isDiscoverable)
            .take(boundedLimit)
            .toList();
      });

  Future<bool> isUsernameAvailable(String username) =>
      _withAccount((check) async {
        final normalized = username
            .trim()
            .replaceFirst(RegExp(r'^@'), '')
            .toLowerCase();
        final result = await _call('checkUsernameAvailabilityV1', {
          'username': normalized,
        });
        check();
        return result['available'] == true && result['username'] == normalized;
      });

  Future<CustomerModel?> lookupEventStaffAccount({
    required String eventId,
    required String email,
  }) => _withAccount((check) async {
    final result = await _call('lookupEventStaffAccountV1', {
      'eventId': eventId,
      'email': email.trim().toLowerCase(),
    });
    check();
    final profile = result['profile'];
    return profile is Map
        ? CustomerModel.fromPublicProfile(Map<String, dynamic>.from(profile))
        : null;
  });

  static List<CustomerModel> _parseProfiles(Map<String, dynamic> result) =>
      (result['profiles'] as List? ?? const [])
          .whereType<Map>()
          .map(
            (profile) => CustomerModel.fromPublicProfile(
              Map<String, dynamic>.from(profile),
            ),
          )
          .where((profile) => profile.uid.isNotEmpty)
          .toList();
}
