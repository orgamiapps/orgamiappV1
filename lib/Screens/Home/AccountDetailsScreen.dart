import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:orgami/Controller/CustomerController.dart';
import 'package:orgami/Models/CustomerModel.dart';
import 'package:orgami/Utils/AppAppBarView.dart';
import 'package:orgami/Utils/Colors.dart';
import 'package:orgami/Utils/Toast.dart';
import 'package:orgami/Utils/dimensions.dart';
import 'package:rounded_loading_button_plus/rounded_loading_button.dart';

class AccountDetailsScreen extends StatefulWidget {
  const AccountDetailsScreen({super.key});

  @override
  State<AccountDetailsScreen> createState() => _AccountDetailsScreenState();
}

class _AccountDetailsScreenState extends State<AccountDetailsScreen> {
  late final double _screenWidth = MediaQuery.of(context).size.width;
  late final double _screenHeight = MediaQuery.of(context).size.height;

  final _btnCtlr = RoundedLoadingButtonController();
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();

  // Controllers for form fields
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _phoneController = TextEditingController();
  final TextEditingController _ageController = TextEditingController();
  final TextEditingController _locationController = TextEditingController();
  final TextEditingController _occupationController = TextEditingController();
  final TextEditingController _companyController = TextEditingController();
  final TextEditingController _websiteController = TextEditingController();
  final TextEditingController _bioController = TextEditingController();

  // Focus nodes for better UX
  final FocusNode _nameFocus = FocusNode();
  final FocusNode _emailFocus = FocusNode();
  final FocusNode _phoneFocus = FocusNode();
  final FocusNode _ageFocus = FocusNode();
  final FocusNode _locationFocus = FocusNode();
  final FocusNode _occupationFocus = FocusNode();
  final FocusNode _companyFocus = FocusNode();
  final FocusNode _websiteFocus = FocusNode();
  final FocusNode _bioFocus = FocusNode();

  String? _selectedGender;
  bool _isLoading = false;

  final List<String> _genderOptions = ['Male', 'Female', 'Other', 'Prefer not to say'];

  @override
  void initState() {
    super.initState();
    _loadUserData();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _phoneController.dispose();
    _ageController.dispose();
    _locationController.dispose();
    _occupationController.dispose();
    _companyController.dispose();
    _websiteController.dispose();
    _bioController.dispose();
    
    _nameFocus.dispose();
    _emailFocus.dispose();
    _phoneFocus.dispose();
    _ageFocus.dispose();
    _locationFocus.dispose();
    _occupationFocus.dispose();
    _companyFocus.dispose();
    _websiteFocus.dispose();
    _bioFocus.dispose();
    super.dispose();
  }

  void _loadUserData() {
    if (CustomerController.logeInCustomer != null) {
      final customer = CustomerController.logeInCustomer!;
      _nameController.text = customer.name;
      _emailController.text = customer.email;
      _phoneController.text = customer.phoneNumber ?? '';
      _ageController.text = customer.age?.toString() ?? '';
      _locationController.text = customer.location ?? '';
      _occupationController.text = customer.occupation ?? '';
      _companyController.text = customer.company ?? '';
      _websiteController.text = customer.website ?? '';
      _bioController.text = customer.bio ?? '';
      _selectedGender = customer.gender;
    }
  }

  Future<void> _saveAccountDetails() async {
    if (!_formKey.currentState!.validate()) {
      _btnCtlr.reset();
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      final customer = CustomerController.logeInCustomer!;
      
      // Update customer model with new data
      customer.name = _nameController.text.trim();
      customer.email = _emailController.text.trim();
      customer.phoneNumber = _phoneController.text.trim().isEmpty ? null : _phoneController.text.trim();
      customer.age = _ageController.text.trim().isEmpty ? null : int.tryParse(_ageController.text.trim());
      customer.gender = _selectedGender;
      customer.location = _locationController.text.trim().isEmpty ? null : _locationController.text.trim();
      customer.occupation = _occupationController.text.trim().isEmpty ? null : _occupationController.text.trim();
      customer.company = _companyController.text.trim().isEmpty ? null : _companyController.text.trim();
      customer.website = _websiteController.text.trim().isEmpty ? null : _websiteController.text.trim();
      customer.bio = _bioController.text.trim().isEmpty ? null : _bioController.text.trim();

      // Update in Firestore
      await FirebaseFirestore.instance
          .collection(CustomerModel.firebaseKey)
          .doc(customer.uid)
          .update(CustomerModel.getMap(customer));

      _btnCtlr.success();
      ShowToast().showNormalToast(msg: 'Account details updated successfully!');
      
      // Update the local customer data
      CustomerController.logeInCustomer = customer;
      
      // Navigate back after a short delay
      Future.delayed(const Duration(seconds: 1), () {
        Navigator.pop(context);
      });

    } catch (e) {
      _btnCtlr.reset();
      setState(() {
        _isLoading = false;
      });
      ShowToast().showNormalToast(msg: 'Failed to update account details: $e');
    }
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
              _headerSection(),
              const SizedBox(height: 32),
              _accountDetailsForm(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _headerSection() {
    return Column(
      children: [
        Container(
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
          child: Icon(
            Icons.account_circle,
            size: 60,
            color: AppThemeColor.darkBlueColor,
          ),
        ),
        const SizedBox(height: 24),
        Text(
          'Account Details',
          style: TextStyle(
            color: AppThemeColor.darkBlueColor,
            fontSize: 28,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.5,
          ),
        ),
        const SizedBox(height: 12),
        Text(
          'Update your personal information and preferences',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: AppThemeColor.dullFontColor,
            fontSize: 16,
            fontWeight: FontWeight.w400,
            height: 1.5,
          ),
        ),
      ],
    );
  }

  Widget _accountDetailsForm() {
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
              'Personal Information',
              style: TextStyle(
                color: AppThemeColor.darkBlueColor,
                fontSize: 20,
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
            const SizedBox(height: 32),
            
            // Professional Information Section
            _buildSectionHeader('Professional Information', Icons.work, Colors.green),
            const SizedBox(height: 16),
            _buildOccupationField(),
            const SizedBox(height: 20),
            _buildCompanyField(),
            const SizedBox(height: 20),
            _buildWebsiteField(),
            const SizedBox(height: 32),
            
            // Bio Section
            _buildSectionHeader('About You', Icons.person_outline, Colors.purple),
            const SizedBox(height: 16),
            _buildBioField(),
            const SizedBox(height: 32),
            
            _buildSaveButton(),
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
    return _buildTextField(
      controller: _nameController,
      focusNode: _nameFocus,
      label: 'Full Name',
      hint: 'Enter your full name',
      icon: Icons.person_outline,
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
      textCapitalization: TextCapitalization.words,
      inputFormatters: [
        FilteringTextInputFormatter.allow(RegExp(r'[a-zA-Z\s]')),
        LengthLimitingTextInputFormatter(50),
      ],
    );
  }

  Widget _buildEmailField() {
    return _buildTextField(
      controller: _emailController,
      focusNode: _emailFocus,
      label: 'Email Address',
      hint: 'Enter your email',
      icon: Icons.email_outlined,
      keyboardType: TextInputType.emailAddress,
      validator: (value) {
        if (value == null || value.isEmpty) {
          return 'Please enter your email';
        }
        if (!RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$').hasMatch(value)) {
          return 'Please enter a valid email address';
        }
        return null;
      },
    );
  }

  Widget _buildPhoneField() {
    return _buildTextField(
      controller: _phoneController,
      focusNode: _phoneFocus,
      label: 'Phone Number',
      hint: 'Enter your phone number (optional)',
      icon: Icons.phone_outlined,
      keyboardType: TextInputType.phone,
      validator: (value) {
        if (value != null && value.isNotEmpty) {
          if (!RegExp(r'^\+?[\d\s\-\(\)]+$').hasMatch(value)) {
            return 'Please enter a valid phone number';
          }
        }
        return null;
      },
    );
  }

  Widget _buildAgeField() {
    return _buildTextField(
      controller: _ageController,
      focusNode: _ageFocus,
      label: 'Age',
      hint: 'Enter your age (optional)',
      icon: Icons.cake_outlined,
      keyboardType: TextInputType.number,
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
    return _buildTextField(
      controller: _locationController,
      focusNode: _locationFocus,
      label: 'Location',
      hint: 'Enter your city, state, or country (optional)',
      icon: Icons.location_on_outlined,
      textCapitalization: TextCapitalization.words,
    );
  }

  Widget _buildOccupationField() {
    return _buildTextField(
      controller: _occupationController,
      focusNode: _occupationFocus,
      label: 'Occupation',
      hint: 'Enter your job title or profession (optional)',
      icon: Icons.work_outline,
      textCapitalization: TextCapitalization.words,
    );
  }

  Widget _buildCompanyField() {
    return _buildTextField(
      controller: _companyController,
      focusNode: _companyFocus,
      label: 'Company',
      hint: 'Enter your company name (optional)',
      icon: Icons.business_outlined,
      textCapitalization: TextCapitalization.words,
    );
  }

  Widget _buildWebsiteField() {
    return _buildTextField(
      controller: _websiteController,
      focusNode: _websiteFocus,
      label: 'Website',
      hint: 'Enter your website URL (optional)',
      icon: Icons.language_outlined,
      keyboardType: TextInputType.url,
             validator: (value) {
         if (value != null && value.isNotEmpty) {
           final uri = Uri.tryParse(value);
           if (uri == null || !uri.hasAbsolutePath) {
             return 'Please enter a valid URL';
           }
         }
         return null;
       },
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
            setState(() {});
          },
          child: TextFormField(
            controller: _bioController,
            focusNode: _bioFocus,
            maxLines: 4,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w400),
            decoration: InputDecoration(
              hintText: 'Tell us a bit about yourself (optional)',
              hintStyle: TextStyle(
                color: AppThemeColor.lightGrayColor,
                fontSize: 16,
              ),
              filled: true,
              fillColor: _bioFocus.hasFocus
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
                padding: const EdgeInsets.only(bottom: 40),
                child: Icon(
                  Icons.edit_note_outlined,
                  color: _bioFocus.hasFocus
                      ? AppThemeColor.darkBlueColor
                      : AppThemeColor.lightGrayColor,
                  size: 20,
                ),
              ),
            ),
            inputFormatters: [
              LengthLimitingTextInputFormatter(500),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required FocusNode focusNode,
    required String label,
    required String hint,
    required IconData icon,
    TextInputType? keyboardType,
    String? Function(String?)? validator,
    TextCapitalization? textCapitalization,
    List<TextInputFormatter>? inputFormatters,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            color: AppThemeColor.darkBlueColor,
            fontSize: 14,
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 8),
        Focus(
          onFocusChange: (hasFocus) {
            setState(() {});
          },
          child: TextFormField(
            controller: controller,
            focusNode: focusNode,
            keyboardType: keyboardType,
            textCapitalization: textCapitalization ?? TextCapitalization.none,
            inputFormatters: inputFormatters,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w400),
            decoration: InputDecoration(
              hintText: hint,
              hintStyle: TextStyle(
                color: AppThemeColor.lightGrayColor,
                fontSize: 16,
              ),
              filled: true,
              fillColor: focusNode.hasFocus
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
                icon,
                color: focusNode.hasFocus
                    ? AppThemeColor.darkBlueColor
                    : AppThemeColor.lightGrayColor,
                size: 20,
              ),
            ),
            validator: validator,
          ),
        ),
      ],
    );
  }

  Widget _buildSaveButton() {
    return SizedBox(
      width: double.infinity,
      height: 56,
      child: RoundedLoadingButton(
        animateOnTap: true,
        borderRadius: 12,
        controller: _btnCtlr,
        onPressed: _saveAccountDetails,
        color: AppThemeColor.darkBlueColor,
        elevation: 0,
        child: const Text(
          'Save Changes',
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