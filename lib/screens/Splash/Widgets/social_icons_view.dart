import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:attendus/controller/customer_controller.dart';
import 'package:attendus/firebase/firebase_firestore_helper.dart';
import 'package:attendus/firebase/firebase_google_auth_helper.dart';
import 'package:attendus/models/customer_model.dart';
import 'package:attendus/Utils/app_constants.dart';
import 'package:attendus/Utils/colors.dart';
import 'package:attendus/Utils/router.dart';
import 'package:attendus/Utils/toast.dart';

class SocialLoginView extends StatefulWidget {
  const SocialLoginView({super.key});

  @override
  State<SocialLoginView> createState() => _SocialLoginViewState();
}

class _SocialLoginViewState extends State<SocialLoginView> {
  bool _googleBtnLoading = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () async {
        try {
          if (!_googleBtnLoading) {
            setState(() {
              _googleBtnLoading = true;
            });
            final navigator = Navigator.of(context);
            await FirebaseGoogleAuthHelper().loginWithGoogle().then((
              googleFirebaseUser,
            ) async {
              if (googleFirebaseUser != null) {
                await FirebaseFirestoreHelper()
                    .getSingleCustomer(customerId: googleFirebaseUser.uid)
                    .then((userData) {
                      if (userData != null) {
                        setState(() {
                          CustomerController.logeInCustomer = userData;
                          _googleBtnLoading = false;
                        });
                        if (!mounted) return;
                        RouterClass().homeScreenRoute(
                          context: navigator.context,
                        );
                      } else {
                        CustomerModel newCustomerModel = CustomerModel(
                          uid: googleFirebaseUser.uid,
                          name: googleFirebaseUser.displayName ?? '',
                          email: googleFirebaseUser.email!,
                          createdAt: DateTime.now(),
                        );
                        _createNewUser(
                          newCustomerModel: newCustomerModel,
                          loading: _googleBtnLoading,
                        );
                      }
                    });
              } else {
                setState(() {
                  _googleBtnLoading = false;
                });
              }
            });
          }
        } catch (e) {
          setState(() {
            _googleBtnLoading = false;
          });
        }
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        width: 50,
        height: 50,
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [AppThemeColor.darkBlueColor, Color(0xFF1E4A8C)],
          ),
          borderRadius: BorderRadius.circular(14),
          boxShadow: [
            BoxShadow(
              color: AppThemeColor.darkBlueColor.withValues(alpha: 0.3),
              blurRadius: 12,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Center(
          child: _googleBtnLoading
              ? SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor: AlwaysStoppedAnimation<Color>(
                      AppThemeColor.pureWhiteColor,
                    ),
                  ),
                )
              : Icon(
                  FontAwesomeIcons.google,
                  color: AppThemeColor.pureWhiteColor,
                  size: 20,
                ),
        ),
      ),
    );
  }

  Future<void> _createNewUser({
    required CustomerModel newCustomerModel,
    required bool loading,
  }) async {
    await FirebaseFirestore.instance
        .collection(CustomerModel.firebaseKey)
        .doc(newCustomerModel.uid)
        .set(CustomerModel.getMap(newCustomerModel))
        .then((value) {
          ShowToast().showNormalToast(
            msg: 'Welcome to ${AppConstants.appName}',
          );

          setState(() {
            CustomerController.logeInCustomer = newCustomerModel;
            loading = false;
          });
          if (!mounted) return;
          RouterClass().homeScreenRoute(context: context);
        });
  }
}
