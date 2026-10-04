import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

/// Server-managed allowances, independent of subscriptions and profile fields.
class EventCreationEntitlementService extends ChangeNotifier {
  static final instance = EventCreationEntitlementService._();
  EventCreationEntitlementService._();

  @visibleForTesting
  EventCreationEntitlementService.testing();

  StreamSubscription<String?>? _authSubscription;
  StreamSubscription<bool>? _grantSubscription;
  String? _uid;
  bool _unlimited = false;
  int _generation = 0;
  String? Function()? _currentUid;

  bool get unlimited =>
      _uid != null && _uid == _currentUid?.call() && _unlimited;

  void initialize() {
    if (_authSubscription != null) return;
    bind(
      FirebaseAuth.instance.authStateChanges().map((user) => user?.uid),
      () => FirebaseAuth.instance.currentUser?.uid,
      (uid) => FirebaseFirestore.instance
          .collection('account_entitlements')
          .doc(uid)
          .snapshots()
          .map((doc) => doc.data()?['unlimitedEventCreation'] == true),
    );
  }

  @visibleForTesting
  void bind(
    Stream<String?> accounts,
    String? Function() currentUid,
    Stream<bool> Function(String) grants,
  ) {
    _currentUid = currentUid;
    _authSubscription?.cancel();
    _authSubscription = accounts.listen((uid) {
      final generation = ++_generation;
      _grantSubscription?.cancel();
      _uid = uid;
      _unlimited = false;
      notifyListeners();
      if (uid == null) return;
      _grantSubscription = grants(uid).listen(
        (value) {
          if (generation != _generation || uid != _currentUid?.call()) return;
          _unlimited = value;
          notifyListeners();
        },
        onError: (Object error) {
          if (generation != _generation) return;
          _unlimited = false;
          notifyListeners();
        },
      );
    });
  }

  void clear() {
    ++_generation;
    _grantSubscription?.cancel();
    _authSubscription?.cancel();
    _authSubscription = null;
    _uid = null;
    _unlimited = false;
    notifyListeners();
  }

  @override
  void dispose() {
    _grantSubscription?.cancel();
    _authSubscription?.cancel();
    super.dispose();
  }
}
