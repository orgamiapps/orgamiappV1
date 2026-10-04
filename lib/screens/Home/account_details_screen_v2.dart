import 'dart:async';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:attendus/controller/customer_controller.dart';
import 'package:attendus/models/customer_model.dart';
import 'package:attendus/Utils/toast.dart';
import 'package:attendus/Utils/logger.dart';

class AccountDetailsScreenV2 extends StatefulWidget {
  const AccountDetailsScreenV2({super.key, this.auth, this.firestore});

  final FirebaseAuth? auth;
  final FirebaseFirestore? firestore;

  @override
  State<AccountDetailsScreenV2> createState() => _AccountDetailsScreenV2State();
}

class _AccountDetailsScreenV2State extends State<AccountDetailsScreenV2> {
  FirebaseAuth get _auth => widget.auth ?? FirebaseAuth.instance;
  FirebaseFirestore get _firestore =>
      widget.firestore ?? FirebaseFirestore.instance;
  ProfileEditSnapshot? _profileBaseline;
  String? _loadError;

  // Form Controllers
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _phoneController = TextEditingController();
  final _usernameController = TextEditingController();
  String _loadedUsernameText = '';
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
  StreamSubscription<User?>? _authSubscription;
  String? _ownerUid;
  bool _accountChanged = false;
  bool get _sameAccount =>
      mounted &&
      !_accountChanged &&
      _ownerUid != null &&
      _auth.currentUser?.uid == _ownerUid;
  User? _firebaseUser;
  CustomerModel? _customerModel;
  String? _socialProvider;

  @override
  void initState() {
    super.initState();
    _ownerUid = _auth.currentUser?.uid;
    _authSubscription = _auth.authStateChanges().listen((user) {
      if (mounted && user?.uid != _ownerUid) {
        setState(() => _accountChanged = true);
      }
    });
    _initializeScreen();
  }

  /// Initialize screen and auto-populate data
  Future<void> _initializeScreen() async {
    try {
      setState(() {
        _isLoading = true;
        _loadError = null;
        _profileBaseline = null;
      });

      // Step 1: Get Firebase Auth user
      _firebaseUser = _auth.currentUser;
      if (_firebaseUser == null) {
        Logger.error('No Firebase user found');
        throw StateError('No authenticated user found');
      }

      Logger.info('=== ACCOUNT DETAILS INITIALIZATION ===');
      Logger.info('Firebase UID: ${_firebaseUser!.uid}');
      Logger.info('Firebase Email: ${_firebaseUser!.email}');
      Logger.info('Firebase DisplayName: "${_firebaseUser!.displayName}"');
      Logger.info('Firebase PhotoURL: ${_firebaseUser!.photoURL}');
      Logger.info(
        'Providers: ${_firebaseUser!.providerData.map((p) => p.providerId).toList()}',
      );

      // Step 2: Detect social provider
      _detectSocialProvider();

      // Step 3: Load or create customer model
      await _loadCustomerData(allowCreate: true);
      if (!_sameAccount) return;

      // Step 4: Always try to enhance profile data
      await _enhanceProfileData();
      if (!_sameAccount) return;

      // Step 5: Update UI with data
      _populateFormFields();
    } catch (e) {
      Logger.error('Error initializing account details: $e');
      _profileBaseline = null;
      _loadError = 'Failed to load account details. Please try again.';
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
  Future<void> _loadCustomerData({bool allowCreate = false}) async {
    try {
      final doc = await _firestore
          .collection('Customers')
          .doc(_firebaseUser!.uid)
          .get(const GetOptions(source: Source.server));

      if (!_sameAccount) return;
      if (doc.exists) {
        _customerModel = CustomerModel.fromFirestore(doc);
        Logger.info('Loaded existing customer: ${_customerModel!.name}');
      } else {
        if (!allowCreate) throw StateError('Profile is unavailable');
        // Create new customer model with basic info
        _customerModel = CustomerModel(
          uid: _firebaseUser!.uid,
          name: _firebaseUser!.displayName ?? '',
          email: _firebaseUser!.email ?? '',
          createdAt: DateTime.now(),
        );

        final reference = _firestore.collection('Customers').doc(_ownerUid);
        final initial = _customerModel!;
        _customerModel = await _firestore.runTransaction<CustomerModel>((
          transaction,
        ) async {
          final existing = await transaction.get(reference);
          if (!_sameAccount) throw StateError('Account changed');
          if (existing.exists) return CustomerModel.fromFirestore(existing);
          transaction.set(reference, CustomerModel.getMap(initial));
          return initial;
        });

        Logger.info('Created new customer model');
      }

      // Update controller
      if (_sameAccount) CustomerController.logeInCustomer = _customerModel;
    } catch (e) {
      Logger.error('Error loading customer data: $e');
      rethrow;
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
      if (!_sameAccount) return;
      _firebaseUser = _auth.currentUser;

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
        if ((extractedName == null || extractedName.isEmpty) &&
            _socialProvider != null) {
          for (final provider in _firebaseUser!.providerData) {
            if (provider.displayName != null &&
                provider.displayName!.isNotEmpty) {
              extractedName = provider.displayName!.trim();
              Logger.info(
                'Found name from provider ${provider.providerId}: "$extractedName"',
              );
              break;
            }
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

  /// Read current values in the same transaction as enrichment so an editor or
  /// another session cannot have a newly saved profile replaced by Auth data.
  Future<void> _updateProfileData(String name, String? phone) async {
    if (!_sameAccount) return;
    final reference = _firestore.collection('Customers').doc(_ownerUid);
    await _firestore.runTransaction((transaction) async {
      final current = await transaction.get(reference);
      if (!_sameAccount) throw StateError('Account changed');
      if (!current.exists) throw StateError('Profile is unavailable');
      final updates = CustomerModel.missingAuthProfileFields(
        CustomerModel.fromFirestore(current),
        name: name,
        phoneNumber: phone,
        profilePictureUrl: _firebaseUser?.photoURL,
      );
      if (updates.isNotEmpty) transaction.update(reference, updates);
    });
  }

  /// Populate form fields with current data
  void _populateFormFields() {
    if (!_sameAccount || _customerModel == null) return;

    _nameController.text = _customerModel!.name;
    _emailController.text = _customerModel!.email;
    _phoneController.text = _customerModel!.phoneNumber ?? '';
    _usernameController.text = _customerModel!.username ?? '';
    _loadedUsernameText = _usernameController.text;
    _bioController.text = _customerModel!.bio ?? '';
    _locationController.text = _customerModel!.location ?? '';
    _occupationController.text = _customerModel!.occupation ?? '';
    _companyController.text = _customerModel!.company ?? '';
    _websiteController.text = _customerModel!.website ?? '';

    _profileBaseline = ProfileEditSnapshot.profile(_formValues());
    Logger.info('Form fields populated with current data');
  }

  Map<String, dynamic> _formValues() {
    String? optional(TextEditingController controller) =>
        controller.text.trim().isEmpty ? null : controller.text.trim();
    return {
      'name': _nameController.text.trim(),
      'email': _emailController.text.trim(),
      'phoneNumber': optional(_phoneController),
      'username': _usernameController.text == _loadedUsernameText
          ? _customerModel!.username
          : optional(_usernameController)?.toLowerCase(),
      'bio': optional(_bioController),
      'location': optional(_locationController),
      'occupation': optional(_occupationController),
      'company': optional(_companyController),
      'website': optional(_websiteController),
    };
  }

  String? _validateUsername(String? value) {
    // Historical handles remain untouched during unrelated profile edits.
    if (value == _loadedUsernameText) return null;
    final normalized = (value ?? '').trim().toLowerCase();
    if (normalized.isEmpty) return null;
    if (!RegExp(r'^[a-z0-9_]{3,50}$').hasMatch(normalized)) {
      return 'Use 3 to 50 letters, numbers or underscores';
    }
    return null;
  }

  /// Save only controls changed since this form was loaded.
  Future<void> _saveAccountDetails() async {
    if (!_sameAccount || _isSaving || _profileBaseline == null) return;
    if (!_formKey.currentState!.validate()) return;
    final updates = _profileBaseline!.changes(_formValues());
    setState(() => _isSaving = true);
    bool committed = false;
    try {
      if (updates.isNotEmpty) {
        await _firestore.collection('Customers').doc(_ownerUid).update(updates);
      }
      committed = true;
      if (!_sameAccount) return;
      // Never replace current independent fields with the model opened earlier.
      await _loadCustomerData();
      if (!_sameAccount) return;
      _populateFormFields();
      ShowToast().showNormalToast(msg: 'Profile updated successfully');
    } catch (e) {
      Logger.error('Error saving account details: $e');
      if (!_sameAccount) return;
      if (committed) {
        _profileBaseline = null;
        _loadError =
            'Changes were saved, but the profile could not be reloaded. Please try again.';
      }
      _showError(
        committed
            ? 'Saved. Reload your profile before editing again.'
            : 'Failed to save changes',
      );
    } finally {
      if (mounted) setState(() => _isSaving = false);
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
    _authSubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_accountChanged) {
      return Scaffold(
        appBar: AppBar(title: const Text('Account details')),
        body: const Center(
          child: Text(
            'Your account changed. Reopen account details to continue.',
          ),
        ),
      );
    }
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
                style: TextStyle(fontSize: 16, color: Colors.grey[600]),
              ),
            ],
          ),
        ),
      );
    }

    if (_loadError != null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Account Details')),
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(_loadError!),
              TextButton(
                onPressed: _initializeScreen,
                child: const Text('Try again'),
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
                  validator: _validateUsername,
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
                              valueColor: AlwaysStoppedAnimation<Color>(
                                Colors.white,
                              ),
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
      enabled: enabled && !_isSaving,
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
          borderSide: BorderSide(
            color: Theme.of(context).primaryColor,
            width: 2,
          ),
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
