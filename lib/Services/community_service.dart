import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:uuid/uuid.dart';

typedef CommunityCaller =
    Future<Map<String, dynamic>> Function(Map<String, dynamic> data);

/// Group interactions are validated and applied atomically by the server.
class CommunityService {
  CommunityService({CommunityCaller? caller, String? Function()? currentUid})
    : _caller = caller,
      _uid = currentUid;
  final CommunityCaller? _caller;
  final String? Function()? _uid;
  static bool isPollClosed(Map<String, dynamic> post, {DateTime? now}) {
    if (post['isClosed'] == true || post['isActive'] == false) return true;
    final end = post['endDate'];
    if (end == null) return false;
    final date = end is Timestamp
        ? end.toDate()
        : end is DateTime
        ? end
        : end is num
        ? DateTime.fromMillisecondsSinceEpoch(end.toInt())
        : DateTime.tryParse(end.toString());
    return date == null || !date.isAfter(now ?? DateTime.now());
  }

  static String newId() => const Uuid().v4();
  String? get _currentUid =>
      _uid != null ? _uid() : FirebaseAuth.instance.currentUser?.uid;

  Future<Map<String, dynamic>> mutate(
    String action,
    Map<String, dynamic> fields,
  ) async {
    final uid = _currentUid;
    if (uid == null) throw StateError('Sign in to continue.');
    final data = {'action': action, ...fields};
    Future<Map<String, dynamic>> send() async {
      if (_currentUid != uid) throw StateError('Account changed. Try again.');
      final result = _caller != null
          ? await _caller(data)
          : Map<String, dynamic>.from(
              (await FirebaseFunctions.instance
                          .httpsCallable('communityMutationV1')
                          .call(data)
                          .timeout(const Duration(seconds: 25)))
                      .data
                  as Map,
            );
      if (_currentUid != uid) throw StateError('Account changed. Try again.');
      return result;
    }

    try {
      return await send();
    } on FirebaseFunctionsException catch (error) {
      if (!const {'unavailable', 'deadline-exceeded'}.contains(error.code)) {
        rethrow;
      }
      return send();
    }
  }
}
