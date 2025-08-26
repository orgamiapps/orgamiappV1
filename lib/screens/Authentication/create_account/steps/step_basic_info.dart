import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:orgami/Utils/app_constants.dart';
import 'package:orgami/Utils/colors.dart';
import 'package:provider/provider.dart';
import 'package:orgami/screens/Authentication/create_account/create_account_view_model.dart';

class StepBasicInfo extends StatefulWidget {
  const StepBasicInfo({super.key, required this.onNext});
  final VoidCallback onNext;

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

  // Places autocomplete
  List<dynamic> _placeSuggestions = [];
  Timer? _placesDebounce;
  bool _locationSelectedFromSuggestions = false;
  late final String _placesSessionToken = DateTime.now().millisecondsSinceEpoch
      .toString();

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
        _dobController.text = DateFormat('MMM d, yyyy').format(picked);
      });
    }
  }

  void _onLocationChanged(String value) {
    _locationSelectedFromSuggestions = false;
    _placesDebounce?.cancel();
    _placesDebounce = Timer(const Duration(milliseconds: 300), () async {
      final query = value.trim();
      if (query.length < 2) {
        setState(() => _placeSuggestions = []);
        return;
      }
      await _fetchPlaceSuggestions(query);
    });
  }

  Future<void> _fetchPlaceSuggestions(String input) async {
    try {
      final uri = Uri.https(
        'maps.googleapis.com',
        '/maps/api/place/autocomplete/json',
        {
          'input': input,
          'key': AppConstants.googlePlacesApiKey,
          'sessiontoken': _placesSessionToken,
          'types': '(regions)',
        },
      );
      final response = await http.get(uri);
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final List predictions = (data['predictions'] as List?) ?? [];
        setState(() {
          _placeSuggestions = predictions;
        });
      }
    } catch (_) {}
  }

  Future<void> _validateAndNext() async {
    if (!_formKey.currentState!.validate()) return;

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
      padding: const EdgeInsets.all(24),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
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

  Widget _dobField() => GestureDetector(
    onTap: _pickDob,
    child: AbsorbPointer(
      child: _textField(
        label: 'Date of birth',
        controller: _dobController,
        icon: Icons.cake_outlined,
        hint: 'MM/DD/YYYY',
        validator: (_) => null,
      ),
    ),
  );

  Widget _locationField() => Column(
    children: [
      _textField(
        label: 'Location',
        controller: _locationController,
        icon: Icons.location_on_outlined,
        hint: 'Enter your city, state, or country (optional)',
        onChanged: _onLocationChanged,
        validator: (v) {
          if (v != null &&
              v.trim().isNotEmpty &&
              !_locationSelectedFromSuggestions) {
            return 'Please select a location from suggestions';
          }
          return null;
        },
      ),
      if (_placeSuggestions.isNotEmpty)
        Container(
          margin: const EdgeInsets.only(top: 8),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.08),
                blurRadius: 20,
                offset: const Offset(0, 6),
              ),
            ],
            border: Border.all(color: Colors.grey.withValues(alpha: 0.1)),
          ),
          constraints: const BoxConstraints(maxHeight: 220),
          child: ListView.builder(
            itemCount: _placeSuggestions.length,
            shrinkWrap: true,
            itemBuilder: (context, index) {
              final suggestion = _placeSuggestions[index];
              final description = suggestion['description'] as String? ?? '';
              return ListTile(
                leading: const Icon(
                  Icons.location_on_outlined,
                  color: Color(0xFF667EEA),
                ),
                title: Text(description),
                onTap: () {
                  setState(() {
                    _locationController.text = description;
                    _locationSelectedFromSuggestions = true;
                    _placeSuggestions = [];
                  });
                },
              );
            },
          ),
        ),
    ],
  );

  Widget _nextButton() {
    return SizedBox(
      width: double.infinity,
      height: 56,
      child: ElevatedButton(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppThemeColor.darkBlueColor,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          elevation: 0,
        ),
        onPressed: _validateAndNext,
        child: const Text(
          'Next',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
        ),
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
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            color: AppThemeColor.darkBlueColor,
            fontSize: 14,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 8),
        TextFormField(
          controller: controller,
          keyboardType: keyboard,
          inputFormatters: inputFormatters,
          textCapitalization: capitalization,
          decoration: InputDecoration(
            hintText: hint,
            filled: true,
            fillColor: Colors.grey.withValues(alpha: 0.04),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: BorderSide.none,
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: BorderSide(
                color: AppThemeColor.darkBlueColor,
                width: 2,
              ),
            ),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 20,
              vertical: 18,
            ),
            prefixIcon: Icon(icon, color: AppThemeColor.lightGrayColor),
          ),
          validator: validator,
          onChanged: onChanged,
        ),
      ],
    );
  }
}
