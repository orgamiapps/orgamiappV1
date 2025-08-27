import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:orgami/controller/customer_controller.dart';
import 'package:orgami/models/customer_model.dart';
import 'package:orgami/Utils/app_app_bar_view.dart';
import 'package:orgami/Utils/toast.dart';
import 'package:rounded_loading_button_plus/rounded_loading_button.dart';
import 'package:orgami/firebase/firebase_firestore_helper.dart';
import 'dart:convert';
import 'package:orgami/firebase/firebase_storage_helper.dart';
import 'package:orgami/screens/Authentication/forgot_password_screen.dart';
import 'package:orgami/Utils/full_screen_image_viewer.dart';

class AccountDetailsScreen extends StatefulWidget {
  const AccountDetailsScreen({super.key});

  @override
  State<AccountDetailsScreen> createState() => _AccountDetailsScreenState();
}

class _AccountDetailsScreenState extends State<AccountDetailsScreen>
    with SingleTickerProviderStateMixin {
  late final double _screenWidth = MediaQuery.of(context).size.width;
  late final double _screenHeight = MediaQuery.of(context).size.height;

  final _btnCtlr = RoundedLoadingButtonController();
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();

  // Controllers for form fields
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _usernameController =
      TextEditingController(); // New username controller
  final TextEditingController _phoneController = TextEditingController();
  final TextEditingController _ageController = TextEditingController();
  final TextEditingController _locationController = TextEditingController();
  final TextEditingController _occupationController = TextEditingController();
  final TextEditingController _companyController = TextEditingController();
  final TextEditingController _websiteController = TextEditingController();
  final TextEditingController _bioController = TextEditingController();
  // Social links controllers
  final TextEditingController _twitterController = TextEditingController();
  final TextEditingController _instagramController = TextEditingController();
  final TextEditingController _linkedinController = TextEditingController();
  final TextEditingController _facebookController = TextEditingController();
  final TextEditingController _youtubeController = TextEditingController();
  final TextEditingController _tiktokController = TextEditingController();

  // Focus nodes for better UX
  final FocusNode _nameFocus = FocusNode();
  final FocusNode _emailFocus = FocusNode();
  final FocusNode _usernameFocus = FocusNode(); // New username focus
  final FocusNode _phoneFocus = FocusNode();
  final FocusNode _ageFocus = FocusNode();
  final FocusNode _locationFocus = FocusNode();
  final FocusNode _occupationFocus = FocusNode();
  final FocusNode _companyFocus = FocusNode();
  final FocusNode _websiteFocus = FocusNode();
  final FocusNode _bioFocus = FocusNode();
  final FocusNode _twitterFocus = FocusNode();
  final FocusNode _instagramFocus = FocusNode();
  final FocusNode _linkedinFocus = FocusNode();
  final FocusNode _facebookFocus = FocusNode();
  final FocusNode _youtubeFocus = FocusNode();
  final FocusNode _tiktokFocus = FocusNode();

  String? _selectedGender;
  // bool _isLoading = false; // Unused field

  // UI micro-interactions
  bool _isCameraPressed = false;

  final List<String> _genderOptions = [
    'Male',
    'Female',
    'Other',
    'Prefer not to say',
  ];

  // Privacy & notification preferences
  bool _isDiscoverable = true;
  bool _notifyEventReminders = true;
  bool _notifyMessages = true;
  bool _notifyAnnouncements = true;

  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    // Tabs removed; keep controller only if referenced elsewhere
    _tabController = TabController(length: 1, vsync: this);
    _loadUserData();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _nameController.dispose();
    _emailController.dispose();
    _usernameController.dispose(); // Dispose new username controller
    _phoneController.dispose();
    _ageController.dispose();
    _locationController.dispose();
    _occupationController.dispose();
    _companyController.dispose();
    _websiteController.dispose();
    _bioController.dispose();
    _twitterController.dispose();
    _instagramController.dispose();
    _linkedinController.dispose();
    _facebookController.dispose();
    _youtubeController.dispose();
    _tiktokController.dispose();

    _nameFocus.dispose();
    _emailFocus.dispose();
    _usernameFocus.dispose(); // Dispose new username focus
    _phoneFocus.dispose();
    _ageFocus.dispose();
    _locationFocus.dispose();
    _occupationFocus.dispose();
    _companyFocus.dispose();
    _websiteFocus.dispose();
    _bioFocus.dispose();
    _twitterFocus.dispose();
    _instagramFocus.dispose();
    _linkedinFocus.dispose();
    _facebookFocus.dispose();
    _youtubeFocus.dispose();
    _tiktokFocus.dispose();
    super.dispose();
  }

  Future<void> _loadUserData() async {
    if (CustomerController.logeInCustomer != null) {
      final customer = CustomerController.logeInCustomer!;
      _nameController.text = customer.name;
      _emailController.text = customer.email;

      // Ensure username exists; if not, generate
      if (customer.username == null || customer.username!.isEmpty) {
        final firestoreHelper = FirebaseFirestoreHelper();
        final newUsername = await firestoreHelper
            .generateUsernameForExistingUser(customer.name);
        customer.username = newUsername;
        await firestoreHelper.updateUsername(
          userId: customer.uid,
          newUsername: newUsername,
        );
        CustomerController.logeInCustomer = customer;
      }

      _usernameController.text = customer.username ?? '';
      _phoneController.text = customer.phoneNumber ?? '';
      _ageController.text = customer.age?.toString() ?? '';
      _locationController.text = customer.location ?? '';
      _occupationController.text = customer.occupation ?? '';
      _companyController.text = customer.company ?? '';
      _websiteController.text = customer.website ?? '';
      _bioController.text = customer.bio ?? '';
      _selectedGender = customer.gender;
      _isDiscoverable = customer.isDiscoverable;

      // Parse social links (stored as JSON string or map)
      try {
        final raw = customer.socialMediaLinks;
        if (raw != null && raw.isNotEmpty) {
          Map<String, dynamic> m;
          try {
            m = json.decode(raw) as Map<String, dynamic>;
          } catch (_) {
            // If the field was accidentally stored as a map
            m = {};
          }
          _twitterController.text = (m['twitter'] ?? '').toString();
          _instagramController.text = (m['instagram'] ?? '').toString();
          _linkedinController.text = (m['linkedin'] ?? '').toString();
          _facebookController.text = (m['facebook'] ?? '').toString();
          _youtubeController.text = (m['youtube'] ?? '').toString();
          _tiktokController.text = (m['tiktok'] ?? '').toString();
        }
      } catch (_) {}

      // Load notification preferences from Firestore if present
      try {
        final doc = await FirebaseFirestore.instance
            .collection(CustomerModel.firebaseKey)
            .doc(customer.uid)
            .get();
        final data = doc.data();
        if (data != null && data['notificationPreferences'] is Map) {
          final prefs = Map<String, dynamic>.from(
            data['notificationPreferences'],
          );
          _notifyEventReminders = (prefs['eventReminders'] ?? true) == true;
          _notifyMessages = (prefs['messages'] ?? true) == true;
          _notifyAnnouncements = (prefs['announcements'] ?? true) == true;
        }
      } catch (_) {}

      if (mounted) setState(() {});
    }
  }

  Future<void> _saveAccountDetails() async {
    if (!_formKey.currentState!.validate()) {
      _btnCtlr.reset();
      return;
    }

    try {
      final customer = CustomerController.logeInCustomer!;

      // Update customer model with new data
      customer.name = _nameController.text.trim();
      customer.email = _emailController.text.trim();
      customer.username = _usernameController.text.trim().isEmpty
          ? null
          : _usernameController.text.trim().toLowerCase(); // Update username
      customer.phoneNumber = _phoneController.text.trim().isEmpty
          ? null
          : _phoneController.text.trim();
      customer.age = _ageController.text.trim().isEmpty
          ? null
          : int.tryParse(_ageController.text.trim());
      customer.gender = _selectedGender;
      customer.location = _locationController.text.trim().isEmpty
          ? null
          : _locationController.text.trim();
      customer.occupation = _occupationController.text.trim().isEmpty
          ? null
          : _occupationController.text.trim();
      customer.company = _companyController.text.trim().isEmpty
          ? null
          : _companyController.text.trim();
      customer.website = _websiteController.text.trim().isEmpty
          ? null
          : _websiteController.text.trim();
      customer.bio = _bioController.text.trim().isEmpty
          ? null
          : _bioController.text.trim();
      customer.isDiscoverable = _isDiscoverable;

      // Build social links JSON for storage
      final social = <String, String>{};
      void putIfNotEmpty(String key, String value) {
        if (value.trim().isNotEmpty) social[key] = value.trim();
      }

      putIfNotEmpty('twitter', _twitterController.text);
      putIfNotEmpty('instagram', _instagramController.text);
      putIfNotEmpty('linkedin', _linkedinController.text);
      putIfNotEmpty('facebook', _facebookController.text);
      putIfNotEmpty('youtube', _youtubeController.text);
      putIfNotEmpty('tiktok', _tiktokController.text);
      customer.socialMediaLinks = social.isEmpty ? null : json.encode(social);

      // Prepare update map (merge in notification preferences)
      final Map<String, dynamic> updateData = CustomerModel.getMap(customer);
      updateData['notificationPreferences'] = {
        'eventReminders': _notifyEventReminders,
        'messages': _notifyMessages,
        'announcements': _notifyAnnouncements,
      };

      // Update in Firestore
      await FirebaseFirestore.instance
          .collection(CustomerModel.firebaseKey)
          .doc(customer.uid)
          .update(updateData);

      _btnCtlr.success();
      // Haptic + snackbar style feedback
      if (mounted) {
        HapticFeedback.mediumImpact();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            behavior: SnackBarBehavior.floating,
            backgroundColor: Theme.of(context).colorScheme.primary,
            content: Row(
              children: const [
                Icon(Icons.check_circle, color: Colors.white),
                SizedBox(width: 8),
                Expanded(child: Text('Account details updated successfully!')),
              ],
            ),
            duration: const Duration(seconds: 2),
          ),
        );
      }

      // Update the local customer data
      CustomerController.logeInCustomer = customer;

      // Navigate back after a short delay
      Future.delayed(const Duration(seconds: 1), () {
        if (!mounted) return;
        Navigator.pop(context);
      });
    } catch (e) {
      _btnCtlr.reset();
      ShowToast().showNormalToast(msg: 'Failed to update account details: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: Stack(
        children: [
          _bodyView(),
          AppAppBarView.appBarWithOnlyBackButton(
            context: context,
            backButtonColor: Theme.of(context).colorScheme.primary,
          ),
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
          colors: [
            Theme.of(context).colorScheme.surface,
            Theme.of(context).colorScheme.surfaceContainerHighest,
          ],
        ),
      ),
      child: SafeArea(
        child: RefreshIndicator(
          onRefresh: _loadUserData,
          color: Theme.of(context).colorScheme.primary,
          backgroundColor: Theme.of(context).colorScheme.surface,
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
            physics: const AlwaysScrollableScrollPhysics(),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 60),
                _headerSection(),
                const SizedBox(height: 24),
                // Only Account Details remain; tabs removed
                _accountDetailsForm(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _headerSection() {
    final user = CustomerController.logeInCustomer;
    final cs = Theme.of(context).colorScheme;
    return Column(
      children: [
        Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                cs.primary.withValues(alpha: 0.12),
                cs.secondary.withValues(alpha: 0.12),
              ],
            ),
            borderRadius: BorderRadius.circular(24),
          ),
          padding: const EdgeInsets.fromLTRB(20, 24, 20, 16),
          child: Column(
            children: [
              SizedBox(
                width: 112,
                height: 112,
                child: Stack(
                  children: [
                    Positioned.fill(
                      child: GestureDetector(
                        onTap: () {
                          final url = user?.profilePictureUrl;
                          if (url == null || url.isEmpty) return;
                          Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => FullScreenImageViewer(
                                imageUrl: url,
                                heroTag: 'profile-hero',
                              ),
                            ),
                          );
                        },
                        child: Container(
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            gradient: LinearGradient(
                              colors: [cs.primary, cs.secondary],
                            ),
                          ),
                          padding: const EdgeInsets.all(3),
                          child: Hero(
                            tag: 'profile-hero',
                            child: ClipOval(
                              child:
                                  (user?.profilePictureUrl != null &&
                                      (user!.profilePictureUrl!.isNotEmpty))
                                  ? Image.network(
                                      user.profilePictureUrl!,
                                      fit: BoxFit.cover,
                                    )
                                  : Container(
                                      color: cs.outlineVariant,
                                      child: Icon(
                                        Icons.person,
                                        size: 44,
                                        color: cs.outline,
                                      ),
                                    ),
                            ),
                          ),
                        ),
                      ),
                    ),
                    Positioned(
                      bottom: 0,
                      right: 0,
                      child: GestureDetector(
                        onTapDown: (_) =>
                            setState(() => _isCameraPressed = true),
                        onTapCancel: () =>
                            setState(() => _isCameraPressed = false),
                        onTapUp: (_) =>
                            setState(() => _isCameraPressed = false),
                        onTap: _changeProfilePhoto,
                        child: AnimatedScale(
                          scale: _isCameraPressed ? 0.92 : 1.0,
                          duration: const Duration(milliseconds: 120),
                          curve: Curves.easeOut,
                          child: Container(
                            width: 34,
                            height: 34,
                            decoration: BoxDecoration(
                              color: cs.primary,
                              shape: BoxShape.circle,
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: 0.12),
                                  blurRadius: 8,
                                  offset: const Offset(0, 2),
                                ),
                              ],
                            ),
                            child: Icon(
                              Icons.camera_alt,
                              color: cs.onPrimary,
                              size: 16,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              Wrap(
                alignment: WrapAlignment.center,
                spacing: 12,
                children: [
                  FilledButton.tonal(
                    onPressed: _changeProfilePhoto,
                    child: const Text('Change Photo'),
                  ),
                  TextButton(
                    onPressed: _removeProfilePhoto,
                    child: const Text('Remove'),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),
        Text(
          'Account Details',
          style: TextStyle(
            color: cs.primary,
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
            color: cs.onSurfaceVariant,
            fontSize: 16,
            fontWeight: FontWeight.w400,
            height: 1.5,
          ),
        ),
      ],
    );
  }

  Widget _accountDetailsForm() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Form(
          key: _formKey,
          child: AnimatedSize(
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeInOut,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Personal Information',
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.primary,
                    fontSize: 20,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 24),

                // Required Fields Section
                _buildSectionHeader(
                  'Required Information',
                  Icons.star,
                  Colors.orange,
                ),
                const SizedBox(height: 16),
                _buildNameField(),
                const SizedBox(height: 20),
                _buildEmailField(),
                const SizedBox(height: 32),

                // Optional Fields Section
                _buildSectionHeader(
                  'Additional Information (Optional)',
                  Icons.info_outline,
                  Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(height: 16),
                _buildUsernameField(), // Add new username field
                const SizedBox(height: 20),
                _buildPhoneField(),
                const SizedBox(height: 20),
                _buildAgeField(),
                const SizedBox(height: 20),
                _buildGenderField(),
                const SizedBox(height: 20),
                _buildLocationField(),
                const SizedBox(height: 32),

                // Professional Information Section
                _buildSectionHeader(
                  'Professional Information',
                  Icons.work,
                  Colors.green,
                ),
                const SizedBox(height: 16),
                _buildOccupationField(),
                const SizedBox(height: 20),
                _buildCompanyField(),
                const SizedBox(height: 20),
                _buildWebsiteField(),
                const SizedBox(height: 32),

                // Bio Section
                _buildSectionHeader(
                  'About You',
                  Icons.person_outline,
                  Colors.purple,
                ),
                const SizedBox(height: 16),
                _buildBioField(),
                const SizedBox(height: 32),

                // Social Links
                _buildSectionHeader(
                  'Social Links',
                  Icons.link,
                  Colors.blueGrey,
                ),
                const SizedBox(height: 16),
                _buildSocialLinksFields(),
                const SizedBox(height: 32),

                // Privacy
                _buildSectionHeader('Privacy', Icons.lock_outline, Colors.teal),
                const SizedBox(height: 12),
                _buildSwitchTile(
                  title: 'Make my profile discoverable',
                  subtitle: 'Allow others to find me by name or username',
                  value: _isDiscoverable,
                  onChanged: (v) => setState(() => _isDiscoverable = v),
                  icon: Icons.search,
                ),
                const SizedBox(height: 24),

                // Notifications
                _buildSectionHeader(
                  'Notifications',
                  Icons.notifications_outlined,
                  Colors.indigo,
                ),
                const SizedBox(height: 12),
                _buildSwitchTile(
                  title: 'Event reminders',
                  subtitle: 'Get reminders for upcoming events',
                  value: _notifyEventReminders,
                  onChanged: (v) => setState(() => _notifyEventReminders = v),
                  icon: Icons.event,
                ),
                const SizedBox(height: 12),
                _buildSwitchTile(
                  title: 'Messages',
                  subtitle: 'Receive notifications for new messages',
                  value: _notifyMessages,
                  onChanged: (v) => setState(() => _notifyMessages = v),
                  icon: Icons.message,
                ),
                const SizedBox(height: 12),
                _buildSwitchTile(
                  title: 'Announcements',
                  subtitle: 'Important updates and news',
                  value: _notifyAnnouncements,
                  onChanged: (v) => setState(() => _notifyAnnouncements = v),
                  icon: Icons.campaign_outlined,
                ),
                const SizedBox(height: 32),

                // Security
                _buildSectionHeader(
                  'Security',
                  Icons.security,
                  Colors.redAccent,
                ),
                const SizedBox(height: 12),
                _buildChangePasswordButton(),
                const SizedBox(height: 32),

                _buildSaveButton(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSectionHeader(String title, IconData icon, Color color) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              gradient: LinearGradient(colors: [cs.primary, cs.secondary]),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, color: cs.onPrimary, size: 16),
          ),
          const SizedBox(width: 12),
          Text(
            title,
            style: TextStyle(
              color: cs.onSurface,
              fontSize: 16,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
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

  Widget _buildUsernameField() {
    return _buildTextField(
      controller: _usernameController,
      focusNode: _usernameFocus,
      label: 'Username',
      hint: 'Enter your username (optional)',
      icon: Icons.alternate_email,
      textCapitalization: TextCapitalization.none,
      inputFormatters: [
        FilteringTextInputFormatter.allow(RegExp(r'[a-zA-Z0-9_]')),
        LengthLimitingTextInputFormatter(20),
      ],
      validator: (value) {
        if (value != null && value.isNotEmpty) {
          if (value.length < 3) {
            return 'Username must be at least 3 characters';
          }
          if (!RegExp(r'^[a-zA-Z0-9_]+$').hasMatch(value)) {
            return 'Username can only contain letters, numbers, and underscores';
          }
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
            color: Theme.of(context).colorScheme.onSurface,
            fontSize: 14,
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 8),
        DropdownButtonFormField<String>(
          value: _selectedGender,
          decoration: InputDecoration(
            hintText: 'Select your gender (optional)',
            prefixIcon: const Icon(Icons.person_outline),
          ),
          items: _genderOptions.map((String gender) {
            return DropdownMenuItem<String>(value: gender, child: Text(gender));
          }).toList(),
          onChanged: (String? newValue) {
            setState(() {
              _selectedGender = newValue;
            });
          },
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
            color: Theme.of(context).colorScheme.onSurface,
            fontSize: 14,
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 8),
        TextFormField(
          controller: _bioController,
          focusNode: _bioFocus,
          maxLines: 4,
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w400),
          decoration: const InputDecoration(
            hintText: 'Tell us a bit about yourself (optional)',
            prefixIcon: Icon(Icons.edit_note_outlined),
          ),
          inputFormatters: [LengthLimitingTextInputFormatter(500)],
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
            color: Theme.of(context).colorScheme.onSurface,
            fontSize: 14,
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 8),
        TextFormField(
          controller: controller,
          focusNode: focusNode,
          keyboardType: keyboardType,
          textCapitalization: textCapitalization ?? TextCapitalization.none,
          inputFormatters: inputFormatters,
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w400),
          decoration: InputDecoration(
            hintText: hint,
            prefixIcon: Icon(
              icon,
              color: focusNode.hasFocus
                  ? Theme.of(context).colorScheme.primary
                  : Theme.of(context).colorScheme.outline,
              size: 20,
            ),
          ),
          validator: validator,
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
        color: Theme.of(context).colorScheme.primary,
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

  // New: social links composite widget
  Widget _buildSocialLinksFields() {
    return Column(
      children: [
        _buildTextField(
          controller: _twitterController,
          focusNode: _twitterFocus,
          label: 'Twitter / X',
          hint: 'https://x.com/your-handle',
          icon: Icons.alternate_email,
          keyboardType: TextInputType.url,
        ),
        const SizedBox(height: 16),
        _buildTextField(
          controller: _instagramController,
          focusNode: _instagramFocus,
          label: 'Instagram',
          hint: 'https://instagram.com/your-handle',
          icon: Icons.camera_alt_outlined,
          keyboardType: TextInputType.url,
        ),
        const SizedBox(height: 16),
        _buildTextField(
          controller: _linkedinController,
          focusNode: _linkedinFocus,
          label: 'LinkedIn',
          hint: 'https://linkedin.com/in/your-id',
          icon: Icons.business_center_outlined,
          keyboardType: TextInputType.url,
        ),
        const SizedBox(height: 16),
        _buildTextField(
          controller: _facebookController,
          focusNode: _facebookFocus,
          label: 'Facebook',
          hint: 'https://facebook.com/your-id',
          icon: Icons.facebook,
          keyboardType: TextInputType.url,
        ),
        const SizedBox(height: 16),
        _buildTextField(
          controller: _youtubeController,
          focusNode: _youtubeFocus,
          label: 'YouTube',
          hint: 'https://youtube.com/@your-channel',
          icon: Icons.ondemand_video,
          keyboardType: TextInputType.url,
        ),
        const SizedBox(height: 16),
        _buildTextField(
          controller: _tiktokController,
          focusNode: _tiktokFocus,
          label: 'TikTok',
          hint: 'https://tiktok.com/@your-handle',
          icon: Icons.music_note,
          keyboardType: TextInputType.url,
        ),
      ],
    );
  }

  // New: switch tile
  Widget _buildSwitchTile({
    required String title,
    required String subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
    required IconData icon,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Theme.of(
          context,
        ).colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.primaryContainer,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(
              icon,
              color: Theme.of(context).colorScheme.onPrimaryContainer,
              size: 18,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          Switch(
            value: value,
            onChanged: onChanged,
            activeColor: Theme.of(context).colorScheme.primary,
          ),
        ],
      ),
    );
  }

  // New: change password
  Widget _buildChangePasswordButton() {
    return SizedBox(
      width: double.infinity,
      child: OutlinedButton.icon(
        onPressed: () {
          Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const ForgotPasswordScreen()),
          );
        },
        icon: const Icon(Icons.password),
        label: const Text('Change password'),
      ),
    );
  }

  // New: photo actions
  Future<void> _changeProfilePhoto() async {
    final user = CustomerController.logeInCustomer;
    if (user == null) return;
    final file = await FirebaseStorageHelper.pickImageFromGallery();
    if (file == null) return;

    final url = await FirebaseStorageHelper.uploadProfilePicture(
      user.uid,
      file,
    );
    if (url == null) {
      ShowToast().showNormalToast(msg: 'Failed to upload photo');
      return;
    }

    await FirebaseFirestore.instance
        .collection(CustomerModel.firebaseKey)
        .doc(user.uid)
        .update({'profilePictureUrl': url});

    setState(() {
      CustomerController.logeInCustomer = CustomerController.logeInCustomer!
        ..profilePictureUrl = url;
    });
    ShowToast().showNormalToast(msg: 'Profile photo updated');
  }

  Future<void> _removeProfilePhoto() async {
    final user = CustomerController.logeInCustomer;
    if (user == null) return;
    await FirebaseStorageHelper.deleteProfilePicture(user.uid);

    await FirebaseFirestore.instance
        .collection(CustomerModel.firebaseKey)
        .doc(user.uid)
        .update({'profilePictureUrl': FieldValue.delete()});

    setState(() {
      CustomerController.logeInCustomer = CustomerController.logeInCustomer!
        ..profilePictureUrl = null;
    });
    ShowToast().showNormalToast(msg: 'Profile photo removed');
  }

  // Tabs removed; public profile editing now accessed from profile screen modal.
}
