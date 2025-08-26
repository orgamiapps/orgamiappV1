import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:orgami/Utils/toast.dart';
import 'package:orgami/controller/customer_controller.dart';
import 'package:orgami/firebase/firebase_firestore_helper.dart';
import 'package:orgami/models/customer_model.dart';

class CreateAccountViewModel extends ChangeNotifier {
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
    notifyListeners();
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
    if ((email == null || email!.isEmpty)) {
      ShowToast().showNormalToast(
        msg: 'Email is required to create an account',
      );
      return false;
    }
    if (firstName == null || lastName == null || username == null) {
      ShowToast().showNormalToast(
        msg: 'Please complete your basic information',
      );
      return false;
    }

    try {
      isCreating = true;
      notifyListeners();

      final auth = FirebaseAuth.instance;
      final newUserCred = await auth.createUserWithEmailAndPassword(
        email: email!.trim().toLowerCase(),
        password: password,
      );

      if (newUserCred.user == null) {
        ShowToast().showNormalToast(msg: 'Account creation failed');
        isCreating = false;
        notifyListeners();
        return false;
      }

      // Now that we're authenticated, check username availability safely.
      // If taken or an error occurs, auto-adjust by appending a number.
      String desired = username!.toLowerCase();
      bool available = false;
      try {
        available = await FirebaseFirestoreHelper().isUsernameAvailable(
          desired,
        );
      } catch (_) {
        available = true; // don't block on transient errors
      }
      if (!available) {
        // try suffixed variants
        int counter = 1;
        while (counter <= 50) {
          final candidate = '$desired$counter';
          bool ok = false;
          try {
            ok = await FirebaseFirestoreHelper().isUsernameAvailable(candidate);
          } catch (_) {
            ok = true;
          }
          if (ok) {
            desired = candidate;
            break;
          }
          counter++;
        }
      }

      final fullName = '${firstName!} ${lastName!}'.trim();
      final age = _computeAge(dateOfBirth);

      final newCustomerModel = CustomerModel(
        uid: newUserCred.user!.uid,
        name: fullName,
        email: email!.trim().toLowerCase(),
        username: desired,
        phoneNumber: (phoneNumber != null && phoneNumber!.isNotEmpty)
            ? phoneNumber
            : null,
        age: age,
        gender: null,
        location: (location != null && location!.isNotEmpty) ? location : null,
        occupation: null,
        company: null,
        website: null,
        bio: null,
        isDiscoverable: true,
        createdAt: DateTime.now(),
      );

      await FirebaseFirestore.instance
          .collection(CustomerModel.firebaseKey)
          .doc(newCustomerModel.uid)
          .set(CustomerModel.getMap(newCustomerModel));

      await FirebaseFirestoreHelper().ensureUserProfileCompleteness(
        newCustomerModel.uid,
      );

      CustomerController.logeInCustomer = newCustomerModel;

      isCreating = false;
      notifyListeners();
      return true;
    } on FirebaseAuthException catch (e) {
      isCreating = false;
      notifyListeners();

      switch (e.code) {
        case 'email-already-in-use':
          ShowToast().showNormalToast(
            msg:
                'An account with this email already exists. Please try signing in instead.',
          );
          break;
        case 'weak-password':
          ShowToast().showNormalToast(
            msg: 'The password is too weak. Please choose a stronger password.',
          );
          break;
        case 'invalid-email':
          ShowToast().showNormalToast(
            msg: 'Please enter a valid email address.',
          );
          break;
        case 'network-request-failed':
          ShowToast().showNormalToast(
            msg:
                'Network error. Please check your internet connection and try again.',
          );
          break;
        case 'too-many-requests':
          ShowToast().showNormalToast(
            msg: 'Too many requests. Please try again later.',
          );
          break;
        case 'operation-not-allowed':
          ShowToast().showNormalToast(
            msg:
                'Email and password sign-up is not enabled. Please contact support.',
          );
          break;
        default:
          ShowToast().showNormalToast(
            msg:
                'Failed to create account: ${e.message ?? 'An error occurred'}',
          );
      }
      return false;
    } catch (e) {
      isCreating = false;
      notifyListeners();
      ShowToast().showNormalToast(msg: 'Failed to create account: $e');
      return false;
    }
  }
}
