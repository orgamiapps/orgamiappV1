import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
  const SignupScreen({super.key});

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

  bool _obscurePassword = true;
  bool _obscureConfirmPassword = true;
  bool _isNameFocused = false;
  bool _isEmailFocused = false;
  bool _isPasswordFocused = false;
  bool _isConfirmPasswordFocused = false;

  late AnimationController logoAnimation;
  late Animation<double> fadeAnimation;
  late Animation<Offset> slideAnimation;

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
                    .set(CustomerModel.getMap(newCustomerModel))
                    .then((value) {
                      ShowToast().showNormalToast(
                        msg: 'Welcome to ${AppConstants.appName}',
                      );
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
      duration: const Duration(milliseconds: 2000),
      vsync: this,
    );

    fadeAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(parent: logoAnimation, curve: Curves.easeInOut));

    slideAnimation =
        Tween<Offset>(begin: const Offset(0, 0.3), end: Offset.zero).animate(
          CurvedAnimation(parent: logoAnimation, curve: Curves.easeOutCubic),
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
      backgroundColor: Colors.white,
      body: Stack(
        children: [
          _bodyView(),
          AppAppBarView.appBarWithOnlyBackButton(context: context),
        ],
      ),
    );
  }

  Widget _bodyView() {
    return Container(
      width: _screenWidth,
      height: _screenHeight,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Colors.white, AppThemeColor.lightBlueColor.withOpacity(0.3)],
        ),
      ),
      child: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
          child: Column(
            children: [
              const SizedBox(height: 60),
              _logoSection(),
              const SizedBox(height: 40),
              _welcomeSection(),
              const SizedBox(height: 40),
              _signupFormSection(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _logoSection() {
    return FadeTransition(
      opacity: fadeAnimation,
      child: SlideTransition(
        position: slideAnimation,
        child: Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.05),
                blurRadius: 20,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: Image.asset(Images.inAppLogo, width: 120, height: 120),
        ),
      ),
    );
  }

  Widget _welcomeSection() {
    return FadeTransition(
      opacity: fadeAnimation,
      child: Column(
        children: [
          Text(
            'Create Account',
            style: TextStyle(
              color: AppThemeColor.darkBlueColor,
              fontSize: 32,
              fontWeight: FontWeight.w700,
              letterSpacing: -0.5,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'Join us and start your journey today',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: AppThemeColor.dullFontColor,
              fontSize: 16,
              fontWeight: FontWeight.w400,
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }

  Widget _signupFormSection() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.08),
            blurRadius: 25,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Sign Up',
              style: TextStyle(
                color: AppThemeColor.darkBlueColor,
                fontSize: 24,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 24),
            _buildNameField(),
            const SizedBox(height: 20),
            _buildEmailField(),
            const SizedBox(height: 20),
            _buildPasswordField(),
            const SizedBox(height: 20),
            _buildConfirmPasswordField(),
            const SizedBox(height: 32),
            _buildSignupButton(),
          ],
        ),
      ),
    );
  }

  Widget _buildNameField() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Full Name',
          style: TextStyle(
            color: AppThemeColor.darkBlueColor,
            fontSize: 14,
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 8),
        Focus(
          onFocusChange: (hasFocus) {
            setState(() {
              _isNameFocused = hasFocus;
            });
          },
          child: TextFormField(
            controller: _userNameEdtController,
            keyboardType: TextInputType.name,
            textCapitalization: TextCapitalization.words,
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r'[a-zA-Z\s]')),
              LengthLimitingTextInputFormatter(50),
            ],
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w400),
            decoration: InputDecoration(
              hintText: 'Enter your full name',
              hintStyle: TextStyle(
                color: AppThemeColor.lightGrayColor,
                fontSize: 16,
              ),
              filled: true,
              fillColor: _isNameFocused
                  ? AppThemeColor.lightBlueColor.withOpacity(0.1)
                  : Colors.grey.withOpacity(0.05),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none,
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(
                  color: AppThemeColor.darkBlueColor,
                  width: 2,
                ),
              ),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 16,
              ),
              prefixIcon: Icon(
                Icons.person_outline,
                color: _isNameFocused
                    ? AppThemeColor.darkBlueColor
                    : AppThemeColor.lightGrayColor,
                size: 20,
              ),
            ),
            validator: (value) {
              if (value == null || value.isEmpty) {
                return 'Please enter your name';
              }
              if (value.length < 2) {
                return 'Name must be at least 2 characters';
              }
              // Check if name contains at least one space (first and last name)
              if (!value.contains(' ')) {
                return 'Please enter your full name (first and last name)';
              }
              return null;
            },
            onChanged: (value) {
              // Ensure proper capitalization for each word
              if (value.isNotEmpty) {
                final words = value.split(' ');
                final capitalizedWords = words
                    .map((word) {
                      if (word.isNotEmpty) {
                        return word[0].toUpperCase() +
                            word.substring(1).toLowerCase();
                      }
                      return word;
                    })
                    .join(' ');

                // Only update if the formatted text is different to avoid cursor jumping
                if (capitalizedWords != value) {
                  final cursorPosition = _userNameEdtController.selection.start;
                  _userNameEdtController.value = TextEditingValue(
                    text: capitalizedWords,
                    selection: TextSelection.collapsed(offset: cursorPosition),
                  );
                }
              }
            },
          ),
        ),
      ],
    );
  }

  Widget _buildEmailField() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Email Address',
          style: TextStyle(
            color: AppThemeColor.darkBlueColor,
            fontSize: 14,
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 8),
        Focus(
          onFocusChange: (hasFocus) {
            setState(() {
              _isEmailFocused = hasFocus;
            });
          },
          child: TextFormField(
            controller: _emailEdtController,
            keyboardType: TextInputType.emailAddress,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w400),
            decoration: InputDecoration(
              hintText: 'Enter your email',
              hintStyle: TextStyle(
                color: AppThemeColor.lightGrayColor,
                fontSize: 16,
              ),
              filled: true,
              fillColor: _isEmailFocused
                  ? AppThemeColor.lightBlueColor.withOpacity(0.1)
                  : Colors.grey.withOpacity(0.05),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none,
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(
                  color: AppThemeColor.darkBlueColor,
                  width: 2,
                ),
              ),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 16,
              ),
              prefixIcon: Icon(
                Icons.email_outlined,
                color: _isEmailFocused
                    ? AppThemeColor.darkBlueColor
                    : AppThemeColor.lightGrayColor,
                size: 20,
              ),
            ),
            validator: (value) {
              if (value == null || value.isEmpty) {
                return 'Please enter your email';
              }
              if (!RegExp(
                r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$',
              ).hasMatch(value)) {
                return 'Please enter a valid email address';
              }
              return null;
            },
          ),
        ),
      ],
    );
  }

  Widget _buildPasswordField() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Password',
          style: TextStyle(
            color: AppThemeColor.darkBlueColor,
            fontSize: 14,
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 8),
        Focus(
          onFocusChange: (hasFocus) {
            setState(() {
              _isPasswordFocused = hasFocus;
            });
          },
          child: TextFormField(
            controller: _passwordEdtController,
            obscureText: _obscurePassword,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w400),
            decoration: InputDecoration(
              hintText: 'Create a password',
              hintStyle: TextStyle(
                color: AppThemeColor.lightGrayColor,
                fontSize: 16,
              ),
              filled: true,
              fillColor: _isPasswordFocused
                  ? AppThemeColor.lightBlueColor.withOpacity(0.1)
                  : Colors.grey.withOpacity(0.05),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none,
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(
                  color: AppThemeColor.darkBlueColor,
                  width: 2,
                ),
              ),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 16,
              ),
              prefixIcon: Icon(
                Icons.lock_outline,
                color: _isPasswordFocused
                    ? AppThemeColor.darkBlueColor
                    : AppThemeColor.lightGrayColor,
                size: 20,
              ),
              suffixIcon: IconButton(
                icon: Icon(
                  _obscurePassword ? Icons.visibility_off : Icons.visibility,
                  color: AppThemeColor.lightGrayColor,
                  size: 20,
                ),
                onPressed: () {
                  setState(() {
                    _obscurePassword = !_obscurePassword;
                  });
                },
              ),
            ),
            validator: (value) {
              if (value == null || value.isEmpty) {
                return 'Please enter a password';
              }
              if (value.length < 6) {
                return 'Password must be at least 6 characters';
              }
              return null;
            },
          ),
        ),
      ],
    );
  }

  Widget _buildConfirmPasswordField() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Confirm Password',
          style: TextStyle(
            color: AppThemeColor.darkBlueColor,
            fontSize: 14,
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 8),
        Focus(
          onFocusChange: (hasFocus) {
            setState(() {
              _isConfirmPasswordFocused = hasFocus;
            });
          },
          child: TextFormField(
            controller: _confirmPasswordEdtController,
            obscureText: _obscureConfirmPassword,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w400),
            decoration: InputDecoration(
              hintText: 'Confirm your password',
              hintStyle: TextStyle(
                color: AppThemeColor.lightGrayColor,
                fontSize: 16,
              ),
              filled: true,
              fillColor: _isConfirmPasswordFocused
                  ? AppThemeColor.lightBlueColor.withOpacity(0.1)
                  : Colors.grey.withOpacity(0.05),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none,
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(
                  color: AppThemeColor.darkBlueColor,
                  width: 2,
                ),
              ),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 16,
              ),
              prefixIcon: Icon(
                Icons.lock_outline,
                color: _isConfirmPasswordFocused
                    ? AppThemeColor.darkBlueColor
                    : AppThemeColor.lightGrayColor,
                size: 20,
              ),
              suffixIcon: IconButton(
                icon: Icon(
                  _obscureConfirmPassword
                      ? Icons.visibility_off
                      : Icons.visibility,
                  color: AppThemeColor.lightGrayColor,
                  size: 20,
                ),
                onPressed: () {
                  setState(() {
                    _obscureConfirmPassword = !_obscureConfirmPassword;
                  });
                },
              ),
            ),
            validator: (value) {
              if (value == null || value.isEmpty) {
                return 'Please confirm your password';
              }
              if (value != _passwordEdtController.text) {
                return 'Passwords do not match';
              }
              return null;
            },
          ),
        ),
      ],
    );
  }

  Widget _buildSignupButton() {
    return SizedBox(
      width: double.infinity,
      height: 56,
      child: RoundedLoadingButton(
        animateOnTap: true,
        borderRadius: 12,
        controller: _btnCtlr,
        onPressed: () {
          _btnCtlr.start();
          if (_formKey.currentState!.validate()) {
            _signupCalled();
          } else {
            _btnCtlr.reset();
          }
        },
        color: AppThemeColor.darkBlueColor,
        elevation: 0,
        child: const Text(
          'Create Account',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            color: Colors.white,
          ),
        ),
      ),
    );
  }
}
