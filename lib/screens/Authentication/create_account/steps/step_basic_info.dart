import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:attendus/Utils/app_constants.dart';
import 'package:attendus/Utils/router.dart';
import 'package:attendus/Utils/toast.dart';
import 'package:provider/provider.dart';
import 'package:attendus/screens/Authentication/create_account/create_account_view_model.dart';
import 'package:attendus/screens/Authentication/create_account/dob_input.dart';
import 'package:attendus/firebase/firebase_google_auth_helper.dart';
import 'package:attendus/Services/auth_service.dart';
import 'package:attendus/widgets/attendus_auth_layout.dart';
import 'package:attendus/widgets/attendus_design_system.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';

class StepBasicInfo extends StatefulWidget {
  const StepBasicInfo({
    super.key,
    required this.onNext,
    required this.onSocialSignIn,
  });
  final VoidCallback onNext;
  final ValueChanged<bool> onSocialSignIn;

  @override
  State<StepBasicInfo> createState() => _StepBasicInfoState();
}

class _StepBasicInfoState extends State<StepBasicInfo> {
  final _formKey = GlobalKey<FormState>();
  final TextEditingController _firstNameController = TextEditingController();
  final TextEditingController _lastNameController = TextEditingController();
  final TextEditingController _usernameController = TextEditingController();
  final TextEditingController _phoneController = TextEditingController();
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _dobController = TextEditingController();
  final TextEditingController _locationController = TextEditingController();

  // Skip checking username availability here to avoid Firestore read rules
  // blocking unauthenticated users. We'll check after auth during account
  // creation on the password step.
  // Reserved for future inline username checks
  // bool _isUsernameChecking = false;
  // bool _usernameAvailable = false;
  DateTime? _selectedDob; // used to fill display; age may be computed later

  @override
  void dispose() {
    _firstNameController.dispose();
    _lastNameController.dispose();
    _usernameController.dispose();
    _phoneController.dispose();
    _emailController.dispose();
    _dobController.dispose();
    _locationController.dispose();
    super.dispose();
  }

  Future<void> _pickDob() async {
    final now = DateTime.now();
    final initial = DateTime(now.year - 21, now.month, now.day);
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(1900),
      lastDate: DateTime(now.year - 13, now.month, now.day),
    );
    if (picked != null) {
      setState(() {
        _selectedDob = picked;
        _dobController.text = DateFormat('MM/dd/yyyy').format(picked);
      });
    }
  }

  Future<void> _validateAndNext() async {
    if (!_formKey.currentState!.validate()) return;

    _selectedDob = _dobController.text.trim().isEmpty
        ? null
        : parseDateOfBirth(_dobController.text.trim());

    // Persist basic info to view model for later account creation
    context.read<CreateAccountViewModel>().setBasicInfo(
      firstName: _firstNameController.text.trim(),
      lastName: _lastNameController.text.trim(),
      username: _usernameController.text.trim(),
      phoneNumber: _phoneController.text.trim().isEmpty
          ? null
          : _phoneController.text.trim(),
      email: _emailController.text.trim().isEmpty
          ? null
          : _emailController.text.trim().toLowerCase(),
      dateOfBirth: _selectedDob,
      location: _locationController.text.trim().isEmpty
          ? null
          : _locationController.text.trim(),
    );

    widget.onNext();
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildGoogleSignInButton(context),
            const SizedBox(height: 12),
            if (AppConstants.enableAppleSignIn)
              _buildAppleSignInButton(context),
            const SizedBox(height: 20),
            _buildDivider(),
            const SizedBox(height: 20),
            _rowFields(),
            const SizedBox(height: 16),
            _usernameField(),
            const SizedBox(height: 16),
            _phoneField(),
            const SizedBox(height: 16),
            _emailField(),
            const SizedBox(height: 16),
            _dobField(),
            const SizedBox(height: 16),
            _locationField(),
            const SizedBox(height: 24),
            _nextButton(),
          ],
        ),
      ),
    );
  }

  Widget _rowFields() {
    return Row(
      children: [
        Expanded(
          child: _textField(
            label: 'First name',
            controller: _firstNameController,
            icon: Icons.person_outline,
            validator: (v) {
              if (v == null || v.trim().isEmpty) return 'Required';
              if (v.trim().length < 2) return 'At least 2 characters';
              return null;
            },
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r'[a-zA-Z\s\-]')),
              LengthLimitingTextInputFormatter(30),
            ],
            capitalization: TextCapitalization.words,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _textField(
            label: 'Last name',
            controller: _lastNameController,
            icon: Icons.person_outline,
            validator: (v) {
              if (v == null || v.trim().isEmpty) return 'Required';
              if (v.trim().length < 2) return 'At least 2 characters';
              return null;
            },
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r'[a-zA-Z\s\-]')),
              LengthLimitingTextInputFormatter(30),
            ],
            capitalization: TextCapitalization.words,
          ),
        ),
      ],
    );
  }

  Widget _usernameField() => _textField(
    label: '@ Username',
    controller: _usernameController,
    icon: Icons.alternate_email,
    hint: 'Choose a username',
    validator: (v) {
      if (v == null || v.isEmpty) return 'Please choose a username';
      if (v.length < 3) return 'At least 3 characters';
      if (!RegExp(r'^[a-zA-Z0-9_]+$').hasMatch(v)) {
        return 'Letters, numbers, and _ only';
      }
      return null;
    },
    onChanged: (value) {
      if (value.isNotEmpty && value != value.toLowerCase()) {
        final sel = _usernameController.selection.start;
        _usernameController.value = TextEditingValue(
          text: value.toLowerCase(),
          selection: TextSelection.collapsed(offset: sel),
        );
      }
    },
  );

  Widget _phoneField() => _textField(
    label: 'Phone number',
    controller: _phoneController,
    icon: Icons.phone_outlined,
    hint: 'Enter your phone number',
    validator: (v) {
      if (v == null || v.trim().isEmpty) return null;
      if (!RegExp(r'^\+?[\d\s\-\(\)]+$').hasMatch(v)) {
        return 'Enter a valid phone number';
      }
      return null;
    },
    keyboard: TextInputType.phone,
  );

  Widget _emailField() => _textField(
    label: 'Email',
    controller: _emailController,
    icon: Icons.email_outlined,
    hint: 'Enter your email',
    validator: (v) {
      if (v == null || v.trim().isEmpty) {
        return 'Please enter your email';
      }
      if (!RegExp(r'^[\w\.-]+@[\w\.-]+\.[A-Za-z]{2,}$').hasMatch(v)) {
        return 'Enter a valid email';
      }
      return null;
    },
    keyboard: TextInputType.emailAddress,
  );

  Widget _dobField() => _textField(
    label: 'Date of birth',
    controller: _dobController,
    icon: Icons.cake_outlined,
    hint: 'MM/DD/YYYY',
    keyboard: TextInputType.number,
    inputFormatters: const [DateOfBirthInputFormatter()],
    suffixIcon: IconButton(
      tooltip: 'Choose date of birth',
      icon: const Icon(Icons.calendar_today_outlined),
      onPressed: _pickDob,
    ),
    onChanged: (value) {
      _selectedDob = parseDateOfBirth(value);
    },
    validator: (value) {
      final text = value?.trim() ?? '';
      if (text.isEmpty) return null;
      if (text.length < 10) return 'Enter the complete date as MM/DD/YYYY';

      final parsed = parseDateOfBirth(text);
      if (parsed == null) return 'Enter a valid date of birth';

      final now = DateTime.now();
      final earliest = DateTime(1900);
      final latest = DateTime(now.year - 13, now.month, now.day);
      if (parsed.isBefore(earliest)) {
        return 'Date of birth must be on or after 01/01/1900';
      }
      if (parsed.isAfter(latest)) {
        return 'You must be at least 13 years old';
      }
      return null;
    },
  );

  Widget _locationField() => _textField(
    label: 'Location',
    controller: _locationController,
    icon: Icons.location_on_outlined,
    hint: 'City or region (optional; you can update this later)',
    inputFormatters: [LengthLimitingTextInputFormatter(120)],
  );

  Widget _nextButton() {
    return SizedBox(
      width: double.infinity,
      child: AttendUsButton.primary(
        label: 'Continue',
        icon: Icons.arrow_forward,
        onPressed: _validateAndNext,
      ),
    );
  }

  Widget _buildDivider() {
    return Row(
      children: [
        Expanded(
          child: Divider(
            color: Colors.grey.withValues(alpha: 0.3),
            thickness: 1,
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Text('OR', style: Theme.of(context).textTheme.labelMedium),
        ),
        Expanded(
          child: Divider(
            color: Colors.grey.withValues(alpha: 0.3),
            thickness: 1,
          ),
        ),
      ],
    );
  }

  Widget _buildGoogleSignInButton(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: AttendUsSocialButton(
        icon: const FaIcon(
          FontAwesomeIcons.google,
          size: 18,
          color: Color(0xFF4285F4),
        ),
        label: 'Continue with Google',
        onPressed: () async {
          widget.onSocialSignIn(true);
          try {
            final helper = FirebaseGoogleAuthHelper();
            final profileData = await helper.loginWithGoogle();
            if (profileData != null) {
              try {
                await AuthService().handleSocialLoginSuccessWithProfileData(
                  profileData,
                );
                if (!mounted) return;
                await AuthService().ensureInMemoryUserModel();
                await Future.delayed(const Duration(milliseconds: 120));
                if (!context.mounted) return;
                RouterClass().homeScreenRoute(context: context);
              } catch (e) {
                ShowToast().showNormalToast(msg: 'Login error');
              }
            } else {
              if (!FirebaseGoogleAuthHelper.lastGoogleCancelled &&
                  !FirebaseGoogleAuthHelper.lastGoogleRedirectStarted) {
                ShowToast().showNormalToast(
                  msg:
                      FirebaseGoogleAuthHelper.lastGoogleErrorMessage ??
                      'Google sign-in failed.',
                );
              }
            }
          } finally {
            if (mounted) widget.onSocialSignIn(false);
          }
        },
      ),
    );
  }

  Widget _buildAppleSignInButton(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: AttendUsSocialButton(
        icon: const Icon(Icons.apple, size: 20, color: Colors.black),
        label: 'Continue with Apple',
        onPressed: () async {
          widget.onSocialSignIn(true);
          try {
            final helper = FirebaseGoogleAuthHelper();
            final profileData = await helper.loginWithApple();
            if (profileData != null) {
              try {
                await AuthService().handleSocialLoginSuccessWithProfileData(
                  profileData,
                );
                if (!mounted) return;
                await AuthService().ensureInMemoryUserModel();
                await Future.delayed(const Duration(milliseconds: 120));
                if (!context.mounted) return;
                RouterClass().homeScreenRoute(context: context);
              } catch (e) {
                ShowToast().showNormalToast(msg: 'Login error');
              }
            } else {
              if (!FirebaseGoogleAuthHelper.lastAppleCancelled) {
                ShowToast().showNormalToast(
                  msg:
                      FirebaseGoogleAuthHelper.lastAppleErrorMessage ??
                      'Apple sign-in failed.',
                );
              }
            }
          } finally {
            if (mounted) widget.onSocialSignIn(false);
          }
        },
      ),
    );
  }

  Widget _textField({
    required String label,
    required TextEditingController controller,
    required IconData icon,
    String? hint,
    String? Function(String?)? validator,
    List<TextInputFormatter>? inputFormatters,
    TextInputType? keyboard,
    TextCapitalization capitalization = TextCapitalization.none,
    ValueChanged<String>? onChanged,
    Widget? suffixIcon,
  }) {
    return AttendUsFormTextField(
      controller: controller,
      keyboardType: keyboard,
      inputFormatters: inputFormatters,
      textCapitalization: capitalization,
      labelText: label,
      hintText: hint ?? label,
      prefixIcon: icon,
      validator: validator,
      onChanged: onChanged,
      suffixIcon: suffixIcon,
    );
  }
}
