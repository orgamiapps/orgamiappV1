import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:attendus/controller/customer_controller.dart';

class OnboardingProfileService {
  OnboardingProfileService({
    String? Function()? currentUid,
    Future<void> Function(String, Map<String, dynamic>)? saveFields,
  }) : _currentUid =
           currentUid ?? (() => FirebaseAuth.instance.currentUser?.uid),
       _saveFields =
           saveFields ??
           ((uid, fields) => FirebaseFirestore.instance
               .collection('Customers')
               .doc(uid)
               .update(fields));
  final String? Function() _currentUid;
  final Future<void> Function(String, Map<String, dynamic>) _saveFields;
  Future<void> save(
    Map<String, dynamic> fields, {
    required String expectedUid,
  }) async {
    void check() {
      if (_currentUid() != expectedUid ||
          CustomerController.logeInCustomer?.uid != expectedUid) {
        throw StateError('Account changed. Reopen your profile.');
      }
    }

    check();
    final patch = Map<String, dynamic>.unmodifiable(fields);
    await _saveFields(expectedUid, patch);
    check();
    final customer = CustomerController.logeInCustomer!;
    if (patch.containsKey('occupation')) {
      customer.occupation = patch['occupation'] as String?;
    }
    if (patch.containsKey('company')) {
      customer.company = patch['company'] as String?;
    }
    if (patch.containsKey('bio')) customer.bio = patch['bio'] as String?;
    if (patch.containsKey('profilePictureUrl')) {
      customer.profilePictureUrl = patch['profilePictureUrl'] as String?;
    }
  }
}
