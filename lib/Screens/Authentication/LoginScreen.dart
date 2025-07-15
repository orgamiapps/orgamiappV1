import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:orgami/Controller/CustomerController.dart';
import 'package:orgami/Firebase/FirebaseFirestoreHelper.dart';
import 'package:orgami/Screens/Authentication/ForgotPasswordScreen.dart';
import 'package:orgami/Utils/AppAppBarView.dart';
import 'package:orgami/Utils/Colors.dart';
import 'package:orgami/Utils/Images.dart';
import 'package:orgami/Utils/Router.dart';
import 'package:orgami/Utils/Toast.dart';
import 'package:orgami/Utils/dimensions.dart';
import 'package:rounded_loading_button_plus/rounded_loading_button.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({
    super.key,
  });

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen>
    with SingleTickerProviderStateMixin {
  late final double _screenWidth = MediaQuery.of(context).size.width;
  late final double _screenHeight = MediaQuery.of(context).size.height;

  final _btnCtlr = RoundedLoadingButtonController();

  final TextEditingController _emailEdtController = TextEditingController();
  final TextEditingController _passwordEdtController = TextEditingController();

  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();

  late AnimationController logoAnimation;

  void _makeLogin() async {
    try {
      String email = _emailEdtController.text,
          password = _passwordEdtController.text;

      await FirebaseAuth.instance
          .signInWithEmailAndPassword(email: email, password: password)
          .then((signInCustomer) {
        if (signInCustomer.user != null) {
          FirebaseFirestoreHelper()
              .getSingleCustomer(customerId: signInCustomer.user!.uid)
              .then((fireStoreCustomer) {
            setState(() {
              CustomerController.logeInCustomer = fireStoreCustomer;
            });
            RouterClass().homeScreenRoute(context: context);
            _btnCtlr.success();
          });
        }
      });
    } on FirebaseAuthException catch (e) {
      print(e.code);
      switch (e.code) {
        case "invalid-credential":
          ShowToast().showNormalToast(msg: "Your Credentials are invalid.");
          break;
        case "ERROR_WRONG_PASSWORD":
          ShowToast().showNormalToast(msg: "Your password is wrong.");
          break;
        case "ERROR_USER_NOT_FOUND":
          ShowToast()
              .showNormalToast(msg: "User with this email doesn't exist.");
          break;
        case "ERROR_USER_DISABLED":
          ShowToast()
              .showNormalToast(msg: "User with this email has been disabled.");
          break;
        case "ERROR_TOO_MANY_REQUESTS":
          ShowToast()
              .showNormalToast(msg: "Too many requests. Try again later.");
          break;
        case "ERROR_OPERATION_NOT_ALLOWED":
          ShowToast().showNormalToast(
              msg: "Signing in with Email and Password is not enabled.");
          break;
        default:
          ShowToast().showNormalToast(msg: "An undefined Error happened.");
      }
      _btnCtlr.reset();
    } catch (e) {
      _btnCtlr.reset();
      print('Error Making Login: $e');
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
              _loginDetailsView(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _loginDetailsView() {
    return Container(
      width: _screenWidth,
      decoration: BoxDecoration(
        color: AppThemeColor.pureWhiteColor,
        borderRadius: BorderRadius.circular(25),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withOpacity(0.5),
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
                  _makeLogin();
                } else {
                  _btnCtlr.reset();
                }
              },
              color: AppThemeColor.darkGreenColor,
              elevation: 0,
              child: const Wrap(
                children: [
                  Text(
                    'Login',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: Colors.white,
                    ),
                  )
                ],
              ),
            ),
            const SizedBox(
              height: 15,
            ),
            GestureDetector(
              onTap: () => RouterClass.nextScreenNormal(
                context,
                const ForgotPasswordScreen(),
              ),
              child: Container(
                color: Colors.transparent,
                child: const Text(
                  'Forgot Password',
                  style: TextStyle(
                    color: AppThemeColor.pureBlackColor,
                    fontSize: Dimensions.fontSizeLarge,
                    fontWeight: FontWeight.w600,
                  ),
                ),
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
          'Welcome Back!',
          style: TextStyle(
            color: AppThemeColor.darkBlueColor,
            fontSize: 34,
            fontWeight: FontWeight.w700,
          ),
        ),
        Padding(
          padding: EdgeInsets.symmetric(horizontal: 15.0),
          child: Text(
            'Fill out the information below in order to access your account.',
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
