import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:attendus/controller/customer_controller.dart';
import 'package:attendus/models/customer_model.dart';
import 'package:attendus/Utils/toast.dart';
import 'package:attendus/Utils/logger.dart';
import 'package:attendus/firebase/firebase_google_auth_helper.dart';

class AccountDetailsScreenV2 extends StatefulWidget {
  const AccountDetailsScreenV2({super.key});

  @override
  State<AccountDetailsScreenV2> createState() => _AccountDetailsScreenV2State();
}

class _AccountDetailsScreenV2State extends State<AccountDetailsScreenV2> {
  // Form Controllers
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _phoneController = TextEditingController();
  final _usernameController = TextEditingController();
  final _bioController = TextEditingController();
  final _locationController = TextEditingController();
  final _occupationController = TextEditingController();
  final _companyController = TextEditingController();
  final _websiteController = TextEditingController();
  
  // Loading states
  bool _isLoading = true;
  bool _isSaving = false;
  bool _hasAttemptedPopulation = false;
  
  // User data
  User? _firebaseUser;
  CustomerModel? _customerModel;
  String? _socialProvider;
  
  @override
  void initState() {
    super.initState();
    _initializeScreen();
  }
  
  /// Initialize screen and auto-populate data
  Future<void> _initializeScreen() async {
    try {
      setState(() => _isLoading = true);
      
      // Step 1: Get Firebase Auth user
      _firebaseUser = FirebaseAuth.instance.currentUser;
      if (_firebaseUser == null) {
        Logger.error('No Firebase user found');
        _showError('No authenticated user found');
        return;
      }
      
      Logger.info('=== ACCOUNT DETAILS INITIALIZATION ===');
      Logger.info('Firebase UID: ${_firebaseUser!.uid}');
      Logger.info('Firebase Email: ${_firebaseUser!.email}');
      Logger.info('Firebase DisplayName: "${_firebaseUser!.displayName}"');
      Logger.info('Firebase PhotoURL: ${_firebaseUser!.photoURL}');
      Logger.info('Providers: ${_firebaseUser!.providerData.map((p) => p.providerId).toList()}');
      
      // Step 2: Detect social provider
      _detectSocialProvider();
      
      // Step 3: Load or create customer model
      await _loadCustomerData();
      
      // Step 4: Always try to enhance profile data
      await _enhanceProfileData();
      
      // Step 5: Update UI with data
      _populateFormFields();
      
    } catch (e) {
      Logger.error('Error initializing account details: $e');
      _showError('Failed to load account details');
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }
  
  /// Detect which social provider was used
  void _detectSocialProvider() {
    if (_firebaseUser == null) return;
    
    for (final provider in _firebaseUser!.providerData) {
      if (provider.providerId == 'google.com') {
        _socialProvider = 'google';
        Logger.info('Detected Google provider');
        break;
      } else if (provider.providerId == 'apple.com') {
        _socialProvider = 'apple';
        Logger.info('Detected Apple provider');
        break;
      }
    }
    
    if (_socialProvider == null) {
      Logger.info('No social provider detected - email/password user');
    }
  }
  
  /// Load customer data from Firestore
  Future<void> _loadCustomerData() async {
    try {
      final doc = await FirebaseFirestore.instance
          .collection('Customers')
          .doc(_firebaseUser!.uid)
          .get();
      
      if (doc.exists) {
        _customerModel = CustomerModel.fromFirestore(doc);
        Logger.info('Loaded existing customer: ${_customerModel!.name}');
      } else {
        // Create new customer model with basic info
        _customerModel = CustomerModel(
          uid: _firebaseUser!.uid,
          name: _firebaseUser!.displayName ?? '',
          email: _firebaseUser!.email ?? '',
          createdAt: DateTime.now(),
        );
        
        // Save to Firestore
        await FirebaseFirestore.instance
            .collection('Customers')
            .doc(_customerModel!.uid)
            .set(CustomerModel.getMap(_customerModel!));
        
        Logger.info('Created new customer model');
      }
      
      // Update controller
      CustomerController.logeInCustomer = _customerModel;
      
    } catch (e) {
      Logger.error('Error loading customer data: $e');
    }
  }
  
  
  /// Enhanced profile data extraction
  Future<void> _enhanceProfileData() async {
    if (_hasAttemptedPopulation) return;
    _hasAttemptedPopulation = true;
    
    try {
      Logger.info('=== ENHANCING PROFILE DATA ===');
      
      // Strategy 1: Force reload Firebase user
      await _firebaseUser!.reload();
      _firebaseUser = FirebaseAuth.instance.currentUser;
      
      // Strategy 2: Extract from Firebase Auth
      if (_firebaseUser != null) {
        String? extractedName;
        String? extractedPhone = _firebaseUser!.phoneNumber;
        
        // Try display name first
        if (_firebaseUser!.displayName != null && 
            _firebaseUser!.displayName!.trim().isNotEmpty) {
          extractedName = _firebaseUser!.displayName!.trim();
          Logger.info('Found displayName: "$extractedName"');
        }
        
        // If no display name but email exists, try to extract from provider data
        if ((extractedName == null || extractedName.isEmpty) && _socialProvider != null) {
          for (final provider in _firebaseUser!.providerData) {
            if (provider.displayName != null && provider.displayName!.isNotEmpty) {
              extractedName = provider.displayName!.trim();
              Logger.info('Found name from provider ${provider.providerId}: "$extractedName"');
              break;
            }
          }
        }
        
        // Strategy 3: If Google user, try silent re-authentication
        if (_socialProvider == 'google' && (extractedName == null || _needsNameUpdate(extractedName))) {
          await _silentGoogleSignIn(extractedName);
          // Reload after Google sign-in
          await _firebaseUser!.reload();
          _firebaseUser = FirebaseAuth.instance.currentUser;
          if (_firebaseUser?.displayName != null) {
            extractedName = _firebaseUser!.displayName;
          }
        }
        
        // Update profile with any extracted data
        if (extractedName != null && extractedName.isNotEmpty) {
          await _updateProfileData(extractedName, extractedPhone);
        }
      }
      
      // Reload customer data after updates
      await _loadCustomerData();
      
    } catch (e) {
      Logger.error('Profile enhancement error: $e');
    }
  }
  
  /// Check if name needs updating
  bool _needsNameUpdate(String? currentName) {
    if (currentName == null || currentName.isEmpty) return true;
    if (_customerModel == null) return true;
    
    return currentName == _customerModel!.email.split('@')[0] ||
           currentName.toLowerCase().contains('user') ||
           currentName.contains('@');
  }
  
  /// Update profile with extracted data
  Future<void> _updateProfileData(String name, String? phone) async {
    if (_customerModel == null) return;
    
    try {
      Map<String, dynamic> updates = {};
      
      // Update name if better than current
      if (name.isNotEmpty && 
          (name != _customerModel!.name || _needsNameUpdate(_customerModel!.name))) {
        updates['name'] = name;
        _customerModel!.name = name;
        Logger.info('Updating name to: "$name"');
      }
      
      // Update phone if available and not set
      if (phone != null && 
          phone.isNotEmpty && 
          (_customerModel!.phoneNumber == null || _customerModel!.phoneNumber!.isEmpty)) {
        updates['phoneNumber'] = phone;
        _customerModel!.phoneNumber = phone;
        Logger.info('Updating phone to: "$phone"');
      }
      
      // Update profile picture if available
      if (_firebaseUser?.photoURL != null && 
          (_customerModel!.profilePictureUrl == null || _customerModel!.profilePictureUrl!.isEmpty)) {
        updates['profilePictureUrl'] = _firebaseUser!.photoURL;
        _customerModel!.profilePictureUrl = _firebaseUser!.photoURL;
      }
      
      // Apply updates to Firestore
      if (updates.isNotEmpty) {
        await FirebaseFirestore.instance
            .collection('Customers')
            .doc(_customerModel!.uid)
            .update(updates);
        
        // Update controller
        CustomerController.logeInCustomer = _customerModel;
        
        Logger.info('✅ Profile updated with: ${updates.keys.join(', ')}');
      }
      
    } catch (e) {
      Logger.error('Error updating profile data: $e');
    }
  }
  
  /// Silent Google sign-in to get fresh data
  Future<void> _silentGoogleSignIn(String? currentName) async {
    try {
      Logger.info('Attempting silent Google sign-in for fresh data...');
      
      // Use the Google Auth Helper to silently sign in
      final helper = FirebaseGoogleAuthHelper();
      final profileData = await helper.loginWithGoogle();
      
      if (profileData != null) {
        final extractedName = profileData['fullName'] ?? profileData['firstName'];
        final extractedPhone = profileData['phoneNumber'];
        
        if (extractedName != null && extractedName.toString().isNotEmpty) {
          Logger.info('Google provided name: "$extractedName"');
          
          // Update Firebase Auth display name if needed
          if (_firebaseUser?.displayName != extractedName) {
            try {
              await _firebaseUser!.updateDisplayName(extractedName.toString());
              Logger.info('Updated Firebase displayName');
            } catch (e) {
              Logger.warning('Could not update Firebase displayName: $e');
            }
          }
        }
        
        if (extractedPhone != null) {
          Logger.info('Google provided phone: "$extractedPhone"');
        }
      }
    } catch (e) {
      Logger.warning('Silent Google sign-in failed: $e');
    }
  }
  
  /// Populate form fields with current data
  void _populateFormFields() {
    if (_customerModel == null) return;
    
    _nameController.text = _customerModel!.name;
    _emailController.text = _customerModel!.email;
    _phoneController.text = _customerModel!.phoneNumber ?? '';
    _usernameController.text = _customerModel!.username ?? '';
    _bioController.text = _customerModel!.bio ?? '';
    _locationController.text = _customerModel!.location ?? '';
    _occupationController.text = _customerModel!.occupation ?? '';
    _companyController.text = _customerModel!.company ?? '';
    _websiteController.text = _customerModel!.website ?? '';
    
    Logger.info('Form fields populated with current data');
  }
  
  /// Save account details
  Future<void> _saveAccountDetails() async {
    if (!_formKey.currentState!.validate()) return;
    
    setState(() => _isSaving = true);
    
    try {
      if (_customerModel == null) throw Exception('No customer model');
      
      // Update customer model
      _customerModel!.name = _nameController.text.trim();
      _customerModel!.email = _emailController.text.trim();
      _customerModel!.phoneNumber = _phoneController.text.trim().isEmpty 
          ? null : _phoneController.text.trim();
      _customerModel!.username = _usernameController.text.trim().isEmpty
          ? null : _usernameController.text.trim();
      _customerModel!.bio = _bioController.text.trim().isEmpty
          ? null : _bioController.text.trim();
      _customerModel!.location = _locationController.text.trim().isEmpty
          ? null : _locationController.text.trim();
      _customerModel!.occupation = _occupationController.text.trim().isEmpty
          ? null : _occupationController.text.trim();
      _customerModel!.company = _companyController.text.trim().isEmpty
          ? null : _companyController.text.trim();
      _customerModel!.website = _websiteController.text.trim().isEmpty
          ? null : _websiteController.text.trim();
      
      // Save to Firestore
      await FirebaseFirestore.instance
          .collection('Customers')
          .doc(_customerModel!.uid)
          .update(CustomerModel.getMap(_customerModel!));
      
      // Update controller
      CustomerController.logeInCustomer = _customerModel;
      
      if (mounted) {
        ShowToast().showNormalToast(msg: 'Profile updated successfully');
      }
      
    } catch (e) {
      Logger.error('Error saving account details: $e');
      _showError('Failed to save changes');
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }
  
  /// Show error message
  void _showError(String message) {
    if (mounted) {
      ShowToast().showNormalToast(msg: message);
    }
  }
  
  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _phoneController.dispose();
    _usernameController.dispose();
    _bioController.dispose();
    _locationController.dispose();
    _occupationController.dispose();
    _companyController.dispose();
    _websiteController.dispose();
    super.dispose();
  }
  
  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Scaffold(
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const CircularProgressIndicator(),
              const SizedBox(height: 16),
              Text(
                'Loading your profile...',
                style: TextStyle(
                  fontSize: 16,
                  color: Colors.grey[600],
                ),
              ),
            ],
          ),
        ),
      );
    }
    
    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FA),
      appBar: AppBar(
        elevation: 0,
        backgroundColor: Colors.white,
        title: const Text(
          'Account Details',
          style: TextStyle(
            color: Colors.black87,
            fontSize: 20,
            fontWeight: FontWeight.w600,
          ),
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios, color: Colors.black87),
          onPressed: () => Navigator.pop(context),
        ),
        actions: const [],
      ),
      body: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                
                // Profile Picture Section
                Center(
                  child: Stack(
                    children: [
                      CircleAvatar(
                        radius: 50,
                        backgroundColor: Colors.grey[200],
                        backgroundImage: _firebaseUser?.photoURL != null
                            ? NetworkImage(_firebaseUser!.photoURL!)
                            : null,
                        child: _firebaseUser?.photoURL == null
                            ? Text(
                                _customerModel?.name.isNotEmpty == true
                                    ? _customerModel!.name[0].toUpperCase()
                                    : '?',
                                style: const TextStyle(fontSize: 40),
                              )
                            : null,
                      ),
                      Positioned(
                        bottom: 0,
                        right: 0,
                        child: Container(
                          decoration: BoxDecoration(
                            color: Theme.of(context).primaryColor,
                            shape: BoxShape.circle,
                          ),
                          padding: const EdgeInsets.all(4),
                          child: const Icon(
                            Icons.camera_alt,
                            color: Colors.white,
                            size: 20,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 32),
                
                // Basic Information Section
                _buildSectionTitle('Basic Information'),
                const SizedBox(height: 16),
                
                // Full Name Field
                _buildTextField(
                  controller: _nameController,
                  label: 'Full Name',
                  icon: Icons.person,
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return 'Please enter your name';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16),
                
                // Email Field
                _buildTextField(
                  controller: _emailController,
                  label: 'Email',
                  icon: Icons.email,
                  enabled: false,
                ),
                const SizedBox(height: 16),
                
                // Phone Field
                _buildTextField(
                  controller: _phoneController,
                  label: 'Phone Number',
                  icon: Icons.phone,
                  keyboardType: TextInputType.phone,
                ),
                const SizedBox(height: 16),
                
                // Username Field
                _buildTextField(
                  controller: _usernameController,
                  label: 'Username',
                  icon: Icons.alternate_email,
                  prefixText: '@',
                ),
                const SizedBox(height: 32),
                
                // Additional Information Section
                _buildSectionTitle('Additional Information'),
                const SizedBox(height: 16),
                
                // Bio Field
                _buildTextField(
                  controller: _bioController,
                  label: 'Bio',
                  icon: Icons.description,
                  maxLines: 3,
                ),
                const SizedBox(height: 16),
                
                // Location Field
                _buildTextField(
                  controller: _locationController,
                  label: 'Location',
                  icon: Icons.location_on,
                ),
                const SizedBox(height: 16),
                
                // Occupation Field
                _buildTextField(
                  controller: _occupationController,
                  label: 'Occupation',
                  icon: Icons.work,
                ),
                const SizedBox(height: 16),
                
                // Company Field
                _buildTextField(
                  controller: _companyController,
                  label: 'Company',
                  icon: Icons.business,
                ),
                const SizedBox(height: 16),
                
                // Website Field
                _buildTextField(
                  controller: _websiteController,
                  label: 'Website',
                  icon: Icons.link,
                  keyboardType: TextInputType.url,
                ),
                const SizedBox(height: 32),
                
                // Save Button
                SizedBox(
                  width: double.infinity,
                  height: 54,
                  child: ElevatedButton(
                    onPressed: _isSaving ? null : _saveAccountDetails,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Theme.of(context).primaryColor,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      elevation: 0,
                    ),
                    child: _isSaving
                        ? const SizedBox(
                            width: 24,
                            height: 24,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                            ),
                          )
                        : const Text(
                            'Save Changes',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                              color: Colors.white,
                            ),
                          ),
                  ),
                ),
                const SizedBox(height: 32),
              ],
            ),
          ),
        ),
      ),
    );
  }
  
  Widget _buildSectionTitle(String title) {
    return Text(
      title,
      style: const TextStyle(
        fontSize: 18,
        fontWeight: FontWeight.w600,
        color: Colors.black87,
      ),
    );
  }
  
  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    String? prefixText,
    TextInputType? keyboardType,
    int maxLines = 1,
    bool enabled = true,
    String? Function(String?)? validator,
  }) {
    return TextFormField(
      controller: controller,
      enabled: enabled,
      keyboardType: keyboardType,
      maxLines: maxLines,
      validator: validator,
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon, size: 20),
        prefixText: prefixText,
        filled: true,
        fillColor: enabled ? Colors.white : Colors.grey[100],
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Colors.grey[300]!),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Colors.grey[300]!),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Theme.of(context).primaryColor, width: 2),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Colors.red),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Colors.red, width: 2),
        ),
      ),
    );
  }
}
