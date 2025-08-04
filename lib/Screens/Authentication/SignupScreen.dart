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

  // Controllers for form fields
  final TextEditingController _userNameEdtController = TextEditingController();
  final TextEditingController _emailEdtController = TextEditingController();
  final TextEditingController _passwordEdtController = TextEditingController();
  final TextEditingController _confirmPasswordEdtController = TextEditingController();
  final TextEditingController _phoneController = TextEditingController();
  final TextEditingController _ageController = TextEditingController();
  final TextEditingController _locationController = TextEditingController();
  final TextEditingController _occupationController = TextEditingController();
  final TextEditingController _companyController = TextEditingController();
  final TextEditingController _websiteController = TextEditingController();
  final TextEditingController _bioController = TextEditingController();

  // Focus states
  bool _obscurePassword = true;
  bool _obscureConfirmPassword = true;
  bool _isNameFocused = false;
  bool _isEmailFocused = false;
  bool _isPasswordFocused = false;
  bool _isConfirmPasswordFocused = false;
  bool _isPhoneFocused = false;
  bool _isAgeFocused = false;
  bool _isLocationFocused = false;
  bool _isOccupationFocused = false;
  bool _isCompanyFocused = false;
  bool _isWebsiteFocused = false;
  bool _isBioFocused = false;
  
  String? _selectedGender;
  final List<String> _genderOptions = ['Male', 'Female', 'Other', 'Prefer not to say'];

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
                  phoneNumber: _phoneController.text.trim().isEmpty ? null : _phoneController.text.trim(),
                  age: _ageController.text.trim().isEmpty ? null : int.tryParse(_ageController.text.trim()),
                  gender: _selectedGender,
                  location: _locationController.text.trim().isEmpty ? null : _locationController.text.trim(),
                  occupation: _occupationController.text.trim().isEmpty ? null : _occupationController.text.trim(),
                  company: _companyController.text.trim().isEmpty ? null : _companyController.text.trim(),
                  website: _websiteController.text.trim().isEmpty ? null : _websiteController.text.trim(),
                  bio: _bioController.text.trim().isEmpty ? null : _bioController.text.trim(),
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
            
            // Required Fields Section
            _buildSectionHeader('Required Information', Icons.star, Colors.orange),
            const SizedBox(height: 16),
            _buildNameField(),
            const SizedBox(height: 20),
            _buildEmailField(),
            const SizedBox(height: 20),
            _buildPasswordField(),
            const SizedBox(height: 20),
            _buildConfirmPasswordField(),
            const SizedBox(height: 32),
            
            // Optional Fields Section
            _buildSectionHeader('Additional Information (Optional)', Icons.info_outline, AppThemeColor.darkBlueColor),
            const SizedBox(height: 16),
            _buildPhoneField(),
            const SizedBox(height: 20),
            _buildAgeField(),
            const SizedBox(height: 20),
            _buildGenderField(),
            const SizedBox(height: 20),
            _buildLocationField(),
            const SizedBox(height: 20),
            _buildOccupationField(),
            const SizedBox(height: 20),
            _buildCompanyField(),
            const SizedBox(height: 20),
            _buildWebsiteField(),
            const SizedBox(height: 20),
            _buildBioField(),
            const SizedBox(height: 32),
            
            _buildSignupButton(),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionHeader(String title, IconData icon, Color color) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: color.withOpacity(0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, color: color, size: 16),
        ),
        const SizedBox(width: 12),
        Text(
          title,
          style: TextStyle(
            color: AppThemeColor.darkBlueColor,
            fontSize: 16,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
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
              if (!value.contains(' ')) {
                return 'Please enter your full name (first and last name)';
              }
              return null;
            },
            onChanged: (value) {
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
              if (!RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$').hasMatch(value)) {
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

  Widget _buildPhoneField() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Phone Number',
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
              _isPhoneFocused = hasFocus;
            });
          },
          child: TextFormField(
            controller: _phoneController,
            keyboardType: TextInputType.phone,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w400),
            decoration: InputDecoration(
              hintText: 'Enter your phone number (optional)',
              hintStyle: TextStyle(
                color: AppThemeColor.lightGrayColor,
                fontSize: 16,
              ),
              filled: true,
              fillColor: _isPhoneFocused
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
                Icons.phone_outlined,
                color: _isPhoneFocused
                    ? AppThemeColor.darkBlueColor
                    : AppThemeColor.lightGrayColor,
                size: 20,
              ),
            ),
            validator: (value) {
              if (value != null && value.isNotEmpty) {
                if (!RegExp(r'^\+?[\d\s\-\(\)]+$').hasMatch(value)) {
                  return 'Please enter a valid phone number';
                }
              }
              return null;
            },
          ),
        ),
      ],
    );
  }

  Widget _buildAgeField() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Age',
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
              _isAgeFocused = hasFocus;
            });
          },
          child: TextFormField(
            controller: _ageController,
            keyboardType: TextInputType.number,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w400),
            decoration: InputDecoration(
              hintText: 'Enter your age (optional)',
              hintStyle: TextStyle(
                color: AppThemeColor.lightGrayColor,
                fontSize: 16,
              ),
              filled: true,
              fillColor: _isAgeFocused
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
                Icons.cake_outlined,
                color: _isAgeFocused
                    ? AppThemeColor.darkBlueColor
                    : AppThemeColor.lightGrayColor,
                size: 20,
              ),
            ),
            validator: (value) {
              if (value != null && value.isNotEmpty) {
                final age = int.tryParse(value);
                if (age == null || age < 13 || age > 120) {
                  return 'Please enter a valid age (13-120)';
                }
              }
              return null;
            },
            inputFormatters: [
              FilteringTextInputFormatter.digitsOnly,
              LengthLimitingTextInputFormatter(3),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildGenderField() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Gender',
          style: TextStyle(
            color: AppThemeColor.darkBlueColor,
            fontSize: 14,
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 8),
        Container(
          decoration: BoxDecoration(
            color: Colors.grey.withOpacity(0.05),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.grey.withOpacity(0.2)),
          ),
          child: DropdownButtonFormField<String>(
            value: _selectedGender,
            decoration: InputDecoration(
              hintText: 'Select your gender (optional)',
              hintStyle: TextStyle(
                color: AppThemeColor.lightGrayColor,
                fontSize: 16,
              ),
              border: InputBorder.none,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 16,
              ),
              prefixIcon: Icon(
                Icons.person_outline,
                color: AppThemeColor.lightGrayColor,
                size: 20,
              ),
            ),
            items: _genderOptions.map((String gender) {
              return DropdownMenuItem<String>(
                value: gender,
                child: Text(gender),
              );
            }).toList(),
            onChanged: (String? newValue) {
              setState(() {
                _selectedGender = newValue;
              });
            },
          ),
        ),
      ],
    );
  }

  Widget _buildLocationField() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Location',
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
              _isLocationFocused = hasFocus;
            });
          },
          child: TextFormField(
            controller: _locationController,
            textCapitalization: TextCapitalization.words,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w400),
            decoration: InputDecoration(
              hintText: 'Enter your city, state, or country (optional)',
              hintStyle: TextStyle(
                color: AppThemeColor.lightGrayColor,
                fontSize: 16,
              ),
              filled: true,
              fillColor: _isLocationFocused
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
                Icons.location_on_outlined,
                color: _isLocationFocused
                    ? AppThemeColor.darkBlueColor
                    : AppThemeColor.lightGrayColor,
                size: 20,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildOccupationField() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Occupation',
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
              _isOccupationFocused = hasFocus;
            });
          },
          child: TextFormField(
            controller: _occupationController,
            textCapitalization: TextCapitalization.words,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w400),
            decoration: InputDecoration(
              hintText: 'Enter your job title or profession (optional)',
              hintStyle: TextStyle(
                color: AppThemeColor.lightGrayColor,
                fontSize: 16,
              ),
              filled: true,
              fillColor: _isOccupationFocused
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
                Icons.work_outline,
                color: _isOccupationFocused
                    ? AppThemeColor.darkBlueColor
                    : AppThemeColor.lightGrayColor,
                size: 20,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildCompanyField() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Company',
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
              _isCompanyFocused = hasFocus;
            });
          },
          child: TextFormField(
            controller: _companyController,
            textCapitalization: TextCapitalization.words,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w400),
            decoration: InputDecoration(
              hintText: 'Enter your company name (optional)',
              hintStyle: TextStyle(
                color: AppThemeColor.lightGrayColor,
                fontSize: 16,
              ),
              filled: true,
              fillColor: _isCompanyFocused
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
                Icons.business_outlined,
                color: _isCompanyFocused
                    ? AppThemeColor.darkBlueColor
                    : AppThemeColor.lightGrayColor,
                size: 20,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildWebsiteField() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Website',
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
              _isWebsiteFocused = hasFocus;
            });
          },
          child: TextFormField(
            controller: _websiteController,
            keyboardType: TextInputType.url,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w400),
            decoration: InputDecoration(
              hintText: 'Enter your website URL (optional)',
              hintStyle: TextStyle(
                color: AppThemeColor.lightGrayColor,
                fontSize: 16,
              ),
              filled: true,
              fillColor: _isWebsiteFocused
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
                Icons.language_outlined,
                color: _isWebsiteFocused
                    ? AppThemeColor.darkBlueColor
                    : AppThemeColor.lightGrayColor,
                size: 20,
              ),
            ),
            validator: (value) {
              if (value != null && value.isNotEmpty) {
                final uri = Uri.tryParse(value);
                if (uri == null || !uri.hasAbsolutePath) {
                  return 'Please enter a valid URL';
                }
              }
              return null;
            },
          ),
        ),
      ],
    );
  }

  Widget _buildBioField() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Bio',
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
              _isBioFocused = hasFocus;
            });
          },
          child: TextFormField(
            controller: _bioController,
            maxLines: 3,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w400),
            decoration: InputDecoration(
              hintText: 'Tell us a bit about yourself (optional)',
              hintStyle: TextStyle(
                color: AppThemeColor.lightGrayColor,
                fontSize: 16,
              ),
              filled: true,
              fillColor: _isBioFocused
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
              prefixIcon: Padding(
                padding: const EdgeInsets.only(bottom: 20),
                child: Icon(
                  Icons.edit_note_outlined,
                  color: _isBioFocused
                      ? AppThemeColor.darkBlueColor
                      : AppThemeColor.lightGrayColor,
                  size: 20,
                ),
              ),
            ),
            inputFormatters: [
              LengthLimitingTextInputFormatter(200),
            ],
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
