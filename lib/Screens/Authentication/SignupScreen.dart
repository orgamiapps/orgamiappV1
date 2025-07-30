import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:orgami/Controller/CustomerController.dart';
import 'package:orgami/Models/CustomerModel.dart';
import 'package:orgami/Utils/AppAppBarView.dart';
import 'package:orgami/Utils/AppConstants.dart';
import 'package:orgami/Utils/Colors.dart';
import 'package:orgami/Utils/Images.dart';
import 'package:orgami/Utils/Router.dart';
import 'package:orgami/Utils/Toast.dart';
import 'package:orgami/Utils/dimensions.dart';
import 'package:rounded_loading_button_plus/rounded_loading_button.dart';

class SignupScreen extends StatefulWidget {
  const SignupScreen({
    super.key,
  });

  @override
  State<SignupScreen> createState() => _SignupScreenState();
}

class _SignupScreenState extends State<SignupScreen>
    with SingleTickerProviderStateMixin {
  late final double _screenWidth = MediaQuery.of(context).size.width;
  late final double _screenHeight = MediaQuery.of(context).size.height;

  final _btnCtlr = RoundedLoadingButtonController();

  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();

  final TextEditingController _userNameEdtController = TextEditingController();
  final TextEditingController _emailEdtController = TextEditingController();
  final TextEditingController _passwordEdtController = TextEditingController();
  final TextEditingController _confirmPasswordEdtController =
      TextEditingController();

  late AnimationController logoAnimation;

  void _signupCalled() async {
    try {
      String name = _userNameEdtController.text,
          email = _emailEdtController.text,
          password = _passwordEdtController.text,
          confirmPassword = _confirmPasswordEdtController.text;

      if (password == confirmPassword) {
        await FirebaseAuth.instance
            .createUserWithEmailAndPassword(email: email, password: password)
            .then((newCreatedCustomer) async {
          if (newCreatedCustomer.user != null) {
            CustomerModel newCustomerModel = CustomerModel(
              uid: newCreatedCustomer.user!.uid,
              name: name,
              email: email,
              createdAt: DateTime.now(),
            );

            await FirebaseFirestore.instance
                .collection(CustomerModel.firebaseKey)
                .doc(newCustomerModel.uid)
                .set(
                  CustomerModel.getMap(newCustomerModel),
                )
                .then((value) {
              ShowToast()
                  .showNormalToast(msg: 'Welcome to ${AppConstants.appName}');
              _btnCtlr.success();
              setState(() {
                CustomerController.logeInCustomer = newCustomerModel;
              });
              RouterClass().homeScreenRoute(context: context);
            });
          }
        });
      } else {
        _btnCtlr.reset();
        ShowToast().showNormalToast(msg: 'Password Not Matched!');
      }
    } catch (e) {
      _btnCtlr.reset();
      print('Error submitting phone number: $e');
    }
  }

  _handleAnimation() {
    logoAnimation = AnimationController(
      upperBound: 180,
      duration: const Duration(milliseconds: 1500),
      vsync: this,
    );
    logoAnimation.forward();
    logoAnimation.addListener(() {
      setState(() {});
    });
  }

  @override
  void initState() {
    _handleAnimation();

    super.initState();
  }

  @override
  void dispose() {
    logoAnimation.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          _bodyView(),
          AppAppBarView.appBarWithOnlyBackButton(
            context: context,
          ),
        ],
      ),
    );
  }

  Widget _bodyView() {
    return Container(
      width: _screenWidth,
      height: _screenHeight,
      decoration: const BoxDecoration(),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(25),
          child: SingleChildScrollView(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  children: [
                    Image.asset(
                      Images.inAppLogo,
                      width: logoAnimation.value,
                    ),
                  ],
                ),
                _labelView(),
                _signupDetailsView(),
                const SizedBox(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _signupDetailsView() {
    return Container(
      width: _screenWidth,
      decoration: BoxDecoration(
        color: AppThemeColor.pureWhiteColor,
        borderRadius: BorderRadius.circular(25),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withValues(alpha: 0.5),
            spreadRadius: 1,
            blurRadius: 7,
            offset: const Offset(0, 7), // changes position of shadow
          ),
        ],
      ),
      padding: const EdgeInsets.all(15),
      child: Form(
        key: _formKey,
        child: Column(
          children: [
            const Text(
              'Enter Your Details',
              style: TextStyle(
                color: AppThemeColor.darkBlueColor,
                fontSize: Dimensions.fontSizeLarge,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(
              height: 15,
            ),
            TextFormField(
              controller: _userNameEdtController,
              keyboardType: TextInputType.name,
              decoration: InputDecoration(
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
                hintText: 'Enter you name here...',
                labelText: 'Name',
                hintStyle: const TextStyle(
                  color: AppThemeColor.lightGrayColor,
                ),
              ),
              validator: (newVal) {
                if (newVal!.isEmpty) {
                  return 'Enter your name first!';
                }
                return null;
              },
            ),
            const SizedBox(
              height: 15,
            ),
            TextFormField(
              controller: _emailEdtController,
              keyboardType: TextInputType.emailAddress,
              decoration: InputDecoration(
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
                hintText: 'example@mail.com',
                labelText: 'Email',
                hintStyle: const TextStyle(
                  color: AppThemeColor.lightGrayColor,
                ),
              ),
              validator: (newVal) {
                if (newVal!.isEmpty) {
                  return 'Enter your Email first!';
                } else if (!RegExp(r'\S+@\S+\.\S+').hasMatch(newVal)) {
                  return "Please Enter a Valid Email";
                }
                return null;
              },
            ),
            const SizedBox(
              height: 15,
            ),
            TextFormField(
              controller: _passwordEdtController,
              keyboardType: TextInputType.visiblePassword,
              obscureText: true,
              decoration: InputDecoration(
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
                hintText: '*******',
                labelText: 'Password',
                hintStyle: const TextStyle(
                  color: AppThemeColor.lightGrayColor,
                ),
              ),
              validator: (value) {
                if (value == null && value!.length < 8) {
                  return 'Enter Valid Password';
                }
                return null;
              },
            ),
            const SizedBox(
              height: 15,
            ),
            TextFormField(
              controller: _confirmPasswordEdtController,
              keyboardType: TextInputType.visiblePassword,
              obscureText: true,
              decoration: InputDecoration(
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
                hintText: '*******',
                labelText: 'Confirm Password',
                hintStyle: const TextStyle(
                  color: AppThemeColor.lightGrayColor,
                ),
              ),
              validator: (value) {
                if (value == null && value!.length < 8) {
                  return 'Enter Valid Password';
                }
                return null;
              },
            ),
            const SizedBox(
              height: 25,
            ),
            RoundedLoadingButton(
              animateOnTap: true,
              borderRadius: 13,
              width: _screenWidth,
              controller: _btnCtlr,
              onPressed: () {
                _btnCtlr.start();
                if (_formKey.currentState!.validate()) {
                  _signupCalled();
                } else {
                  _btnCtlr.reset();
                }
              },
              color: AppThemeColor.darkGreenColor,
              elevation: 0,
              child: const Wrap(
                children: [
                  Text(
                    'Sign Up',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: Colors.white,
                    ),
                  )
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _labelView() {
    return const Column(
      children: [
        Text(
          'Create Account',
          style: TextStyle(
            color: AppThemeColor.darkBlueColor,
            fontSize: 34,
            fontWeight: FontWeight.w700,
          ),
        ),
        Padding(
          padding: EdgeInsets.symmetric(horizontal: 15.0),
          child: Text(
            'Let\'s get started by filling out the form below.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: AppThemeColor.dullFontColor,
              fontSize: Dimensions.fontSizeLarge,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ],
    );
  }
}
