import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:orgami/Controller/CustomerController.dart';
import 'package:orgami/Firebase/FirebaseFirestoreHelper.dart';
import 'package:orgami/Firebase/FirebaseGoogleAuthHelper.dart';
import 'package:orgami/Models/CustomerModel.dart';
import 'package:orgami/Utils/AppButtons.dart';
import 'package:orgami/Utils/AppConstants.dart';
import 'package:orgami/Utils/Colors.dart';
import 'package:orgami/Utils/Router.dart';
import 'package:orgami/Utils/Toast.dart';

class SocialLoginView extends StatefulWidget {
  const SocialLoginView({super.key});

  @override
  State<SocialLoginView> createState() => _SocialLoginViewState();
}

class _SocialLoginViewState extends State<SocialLoginView> {
  bool _googleBtnLoading = false;
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          GestureDetector(
            onTap: () async {
              try {
                if (!_googleBtnLoading) {
                  setState(() {
                    _googleBtnLoading = true;
                  });
                  await FirebaseGoogleAuthHelper()
                      .loginWithGoogle()
                      .then((googleFirebaseUser) async {
                    if (googleFirebaseUser != null) {
                      await FirebaseFirestoreHelper()
                          .getSingleCustomer(customerId: googleFirebaseUser.uid)
                          .then((userData) {
                        if (userData != null) {
                          setState(() {
                            CustomerController.logeInCustomer = userData;
                            _googleBtnLoading = false;
                          });
                          RouterClass().homeScreenRoute(context: context);
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
            child: AppButtons.roundedButton(
              iconData: _googleBtnLoading
                  ? FontAwesomeIcons.arrowsRotate
                  : FontAwesomeIcons.google,
              iconColor: AppThemeColor.pureWhiteColor,
              backgroundColor: AppThemeColor.darkBlueColor,
            ),
          )
        ],
      ),
    );
  }

  Future<void> _createNewUser(
      {required CustomerModel newCustomerModel, required bool loading}) async {
    await FirebaseFirestore.instance
        .collection(CustomerModel.firebaseKey)
        .doc(newCustomerModel.uid)
        .set(
          CustomerModel.getMap(newCustomerModel),
        )
        .then((value) {
      ShowToast().showNormalToast(msg: 'Welcome to ${AppConstants.appName}');

      setState(() {
        CustomerController.logeInCustomer = newCustomerModel;
        loading = false;
      });
      RouterClass().homeScreenRoute(context: context);
    });
  }
}
