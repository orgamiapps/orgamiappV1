import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:attendus/Utils/toast.dart';
import 'package:attendus/controller/customer_controller.dart';
import 'package:attendus/firebase/firebase_firestore_helper.dart';
import 'package:attendus/models/customer_model.dart';
import 'package:attendus/Services/guest_mode_service.dart';
import 'package:attendus/Services/product_funnel_service.dart';

class CreateAccountViewModel extends ChangeNotifier {
  CreateAccountViewModel({
    FirebaseAuth? auth,
    Future<bool> Function(String)? usernameAvailable,
    Future<CustomerModel> Function(CustomerModel)? saveProfile,
    Future<void> Function(String)? ensureProfile,
    Future<void> Function()? completeSession,
    void Function(String)? showMessage,
  }) : _authOverride = auth,
       _usernameAvailable =
           usernameAvailable ?? FirebaseFirestoreHelper().isUsernameAvailable,
       _saveProfileOverride = saveProfile,
       _ensureProfile =
           ensureProfile ??
           FirebaseFirestoreHelper().ensureUserProfileCompleteness,
       _completeSession = completeSession ?? _finishProductionSession,
       _showMessage =
           showMessage ??
           ((message) => ShowToast().showNormalToast(msg: message));
  final FirebaseAuth? _authOverride;
  FirebaseAuth get _auth => _authOverride ?? FirebaseAuth.instance;
  final Future<bool> Function(String) _usernameAvailable;
  final Future<CustomerModel> Function(CustomerModel)? _saveProfileOverride;
  final Future<void> Function(String) _ensureProfile;
  final Future<void> Function() _completeSession;
  final void Function(String) _showMessage;
  bool _disposed = false;
  User? _createdUser;
  String? _createdEmail;
  Future<CustomerModel> _saveProfile(CustomerModel customer) async {
    if (_saveProfileOverride != null) return _saveProfileOverride(customer);
    final reference = FirebaseFirestore.instance
        .collection(CustomerModel.firebaseKey)
        .doc(customer.uid);
    return FirebaseFirestore.instance.runTransaction<CustomerModel>((
      transaction,
    ) async {
      final existing = await transaction.get(reference);
      _check(customer.uid);
      if (existing.exists) return CustomerModel.fromFirestore(existing);
      transaction.set(reference, CustomerModel.getMap(customer));
      return customer;
    });
  }

  static Future<void> _finishProductionSession() async {
    await GuestModeService().disableGuestMode();
    await GuestModeService().clearGuestDisplayName();
    await ProductFunnelService().record(
      'guest_auth_completed',
      dimensions: {'authChoice': 'create_account', 'result': 'success'},
    );
    await ProductFunnelService().rotateSession();
  }

  String? firstName;
  String? lastName;
  String? username;
  String? phoneNumber;
  String? email;
  DateTime? dateOfBirth;
  String? location;

  bool isCreating = false;

  void setBasicInfo({
    required String firstName,
    required String lastName,
    required String username,
    String? phoneNumber,
    String? email,
    DateTime? dateOfBirth,
    String? location,
  }) {
    this.firstName = firstName.trim();
    this.lastName = lastName.trim();
    this.username = username.trim().toLowerCase();
    this.phoneNumber = phoneNumber?.trim();
    this.email = email?.trim().toLowerCase();
    this.dateOfBirth = dateOfBirth;
    this.location = location?.trim();
    _notify();
  }

  int? _computeAge(DateTime? dob) {
    if (dob == null) return null;
    final now = DateTime.now();
    int age = now.year - dob.year;
    final hadBirthday =
        now.month > dob.month || (now.month == dob.month && now.day >= dob.day);
    if (!hadBirthday) age -= 1;
    return (age >= 13 && age <= 120) ? age : null;
  }

  Future<bool> createAccount(String password) async {
    if (_disposed || isCreating) return false;
    if (email?.trim().isEmpty != false ||
        firstName?.trim().isEmpty != false ||
        lastName?.trim().isEmpty != false ||
        username?.trim().isEmpty != false) {
      _show('Please complete your name, username and email.');
      return false;
    }
    final accountEmail = email!.trim().toLowerCase();
    final fullName = '${firstName!.trim()} ${lastName!.trim()}';
    final requestedUsername = username!.trim().toLowerCase();
    final profilePhone = phoneNumber;
    final profileLocation = location;
    final profileAge = _computeAge(dateOfBirth);
    isCreating = true;
    _notify();
    try {
      var user = _createdUser;
      if (user != null &&
          (_auth.currentUser?.uid != user.uid ||
              _createdEmail != accountEmail)) {
        _show(
          'Your account details changed. Log in with the account you just created to finish your profile.',
        );
        return false;
      }
      if (user == null) {
        user = (await _auth.createUserWithEmailAndPassword(
          email: accountEmail,
          password: password,
        )).user;
        _createdUser = user;
        _createdEmail = accountEmail;
      }
      if (user == null) throw StateError('Account creation was not confirmed.');
      _check(user.uid);
      String? availableUsername;
      for (var index = 0; index <= 50; index++) {
        final candidate = index == 0
            ? requestedUsername
            : '$requestedUsername$index';
        final available = await _usernameAvailable(candidate);
        _check(user.uid);
        if (available) {
          availableUsername = candidate;
          break;
        }
      }
      if (availableUsername == null) {
        throw StateError('Choose another username and retry.');
      }
      final customer = CustomerModel(
        uid: user.uid,
        name: fullName,
        email: accountEmail,
        username: availableUsername,
        phoneNumber: profilePhone,
        age: profileAge,
        location: profileLocation,
        isDiscoverable: true,
        createdAt: DateTime.now(),
      );
      final saved = await _saveProfile(customer);
      _check(user.uid);
      await _ensureProfile(user.uid);
      _check(user.uid);
      await _completeSession();
      _check(user.uid);
      CustomerController.logeInCustomer = saved;
      return true;
    } on FirebaseAuthException catch (error) {
      _show(switch (error.code) {
        'email-already-in-use' =>
          'An account with this email exists. Please log in instead.',
        'weak-password' => 'Please choose a stronger password.',
        'invalid-email' => 'Please enter a valid email address.',
        'network-request-failed' => 'Check your connection and retry.',
        'too-many-requests' => 'Please wait a moment before retrying.',
        _ => 'Could not create your account. Please retry.',
      });
      return false;
    } catch (_) {
      _show('Could not finish creating your account. Reconnect and retry.');
      return false;
    } finally {
      isCreating = false;
      _notify();
    }
  }

  void _check(String uid) {
    if (_disposed || _auth.currentUser?.uid != uid) {
      throw StateError('Account changed');
    }
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  void _show(String text) {
    if (!_disposed) _showMessage(text);
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
