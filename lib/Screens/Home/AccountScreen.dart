import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import 'package:orgami/Controller/CustomerController.dart';
import 'package:orgami/Firebase/FirebaseFirestoreHelper.dart';
import 'package:orgami/Firebase/FirebaseStorageHelper.dart';
import 'package:orgami/Screens/Feedback/FeedbackScreen.dart';

import 'package:orgami/Screens/Home/AnalyticsDashboardScreen.dart';
import 'package:orgami/Utils/AppConstants.dart';
import 'package:orgami/Utils/Colors.dart';
import 'package:orgami/Utils/Images.dart';
import 'package:orgami/Utils/Router.dart';
import 'package:orgami/Utils/ThemeProvider.dart';
import 'package:orgami/Utils/Toast.dart';
import 'package:orgami/Utils/WebViewPage.dart';
import 'package:orgami/Utils/dimensions.dart';
import 'dart:io';
import 'package:orgami/Screens/MyProfile/MyProfileScreen.dart';
import 'package:orgami/Screens/MyProfile/UserProfileScreen.dart';
import 'package:orgami/Screens/Home/AccountDetailsScreen.dart';

class AccountScreen extends StatefulWidget {
  const AccountScreen({super.key});

  @override
  State<AccountScreen> createState() => _AccountScreenState();
}

class _AccountScreenState extends State<AccountScreen> {
  late final double _screenWidth = MediaQuery.of(context).size.width;
  late final double _screenHeight = MediaQuery.of(context).size.height;
  final FirebaseStorageHelper _storageHelper = FirebaseStorageHelper();
  final FirebaseFirestoreHelper _firestoreHelper = FirebaseFirestoreHelper();
  final ImagePicker _imagePicker = ImagePicker();
  bool _isUploading = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: SafeArea(child: _bodyView()),
    );
  }

  Widget _bodyView() {
    return SingleChildScrollView(
      child: Column(
        children: [
          _buildProfileHeader(),
          _buildSettingsSection(),
          _buildSocialMediaSection(),
        ],
      ),
    );
  }

  Widget _buildProfileHeader() {
    final user = CustomerController.logeInCustomer;

    return Container(
      width: double.infinity,
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF667EEA), Color(0xFF764BA2)],
        ),
      ),
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
      child: Column(
        children: [
          // Header Row with Title and Profile Picture
          Row(
            children: [
              // Account Title
              const Text(
                'Account',
                style: TextStyle(
                  color: AppThemeColor.pureWhiteColor,
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  fontFamily: 'Roboto',
                ),
              ),
              const Spacer(),
              // Profile Picture
              GestureDetector(
                onTap: () {
                  // Navigate to UserProfileScreen
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) =>
                          UserProfileScreen(user: user!, isOwnProfile: true),
                    ),
                  );
                },
                child: Container(
                  width: 50,
                  height: 50,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 2),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.15),
                        blurRadius: 8,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: ClipOval(
                    child: user?.profilePictureUrl != null
                        ? Image.network(
                            user!.profilePictureUrl!,
                            fit: BoxFit.cover,
                            errorBuilder: (context, error, stackTrace) {
                              return _buildDefaultProfilePicture();
                            },
                          )
                        : _buildDefaultProfilePicture(),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildDefaultProfilePicture() {
    return Container(
      color: const Color(0xFFE1E5E9),
      child: const Icon(Icons.person, size: 25, color: Color(0xFF9CA3AF)),
    );
  }

  Widget _buildSettingsSection() {
    return Container(
      margin: const EdgeInsets.fromLTRB(24, 24, 24, 24),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            spreadRadius: 0,
            blurRadius: 20,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: [
          _buildSettingsItem(
            icon: Icons.person,
            title: 'My Profile',
            subtitle: 'View and edit your profile',
            onTap: () =>
                RouterClass.nextScreenNormal(context, MyProfileScreen()),
          ),
          _buildDivider(),
          _buildSettingsItem(
            icon: Icons.account_circle,
            title: 'Account Details',
            subtitle: 'Manage your personal information',
            onTap: () =>
                RouterClass.nextScreenNormal(context, AccountDetailsScreen()),
          ),
          _buildDivider(),
          _buildSettingsItem(
            icon: Icons.analytics_rounded,
            title: 'Analytics Dashboard',
            subtitle: 'Comprehensive insights across all events',
            onTap: () => RouterClass.nextScreenNormal(
              context,
              const AnalyticsDashboardScreen(),
            ),
          ),
          _buildDivider(),
          _buildSettingsItem(
            icon: CupertinoIcons.info,
            title: 'About Us',
            subtitle: 'Learn more about our app',
            onTap: () => {},
          ),
          _buildDivider(),
          _buildSettingsItem(
            icon: Icons.help,
            title: 'Help',
            subtitle: 'Get help and support',
            onTap: () => {},
          ),
          _buildDivider(),
          _buildDarkModeToggle(),
          _buildDivider(),
          _buildSettingsItem(
            icon: FontAwesomeIcons.feed,
            title: 'Feedback',
            subtitle: 'Share your thoughts with us',
            onTap: () =>
                RouterClass.nextScreenNormal(context, FeedbackScreen()),
          ),
          _buildDivider(),
          _buildSettingsItem(
            icon: Icons.privacy_tip,
            title: 'Privacy Policy',
            subtitle: 'Read our privacy policy',
            onTap: () => RouterClass.nextScreenNormal(
              context,
              WebViewScreen(
                url: AppConstants.privacyPolicyUrl,
                title: 'Privacy Policy',
              ),
            ),
          ),
          _buildDivider(),
          _buildSettingsItem(
            icon: CupertinoIcons.question_diamond,
            title: 'Terms & Conditions',
            subtitle: 'Read our terms of service',
            onTap: () => RouterClass.nextScreenNormal(
              context,
              WebViewScreen(
                url: AppConstants.termsConditionsUrl,
                title: 'Terms & Conditions',
              ),
            ),
          ),
          _buildDivider(),
          _buildSettingsItem(
            icon: Icons.logout,
            title: 'Logout',
            subtitle: 'Sign out of your account',
            onTap: () {
              FirebaseAuth.instance.signOut().then((value) {
                setState(() {
                  CustomerController.logeInCustomer = null;
                });
                RouterClass().appRest(context: context);
              });
            },
            isDestructive: true,
          ),
        ],
      ),
    );
  }

  Widget _buildSettingsHeader() {
    return Container(
      padding: const EdgeInsets.all(24),
      child: Row(
        children: [
          Icon(Icons.person, color: const Color(0xFF667EEA), size: 20),
          const SizedBox(width: 12),
          Text(
            'Account',
            style: TextStyle(
              color:
                  Theme.of(context).textTheme.titleLarge?.color ??
                  const Color(0xFF1A1A1A),
              fontWeight: FontWeight.w600,
              fontSize: 18,
              fontFamily: 'Roboto',
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSettingsItem({
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
    bool isDestructive = false,
  }) {
    return ListTile(
      onTap: onTap,
      leading: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: isDestructive
              ? const Color(0xFFEF4444).withValues(alpha: 0.1)
              : const Color(0xFF667EEA).withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Icon(
          icon,
          color: isDestructive
              ? const Color(0xFFEF4444)
              : const Color(0xFF667EEA),
          size: 20,
        ),
      ),
      title: Text(
        title,
        style: TextStyle(
          color: isDestructive
              ? const Color(0xFFEF4444)
              : Theme.of(context).textTheme.titleMedium?.color ??
                    const Color(0xFF1A1A1A),
          fontWeight: FontWeight.w600,
          fontSize: 16,
          fontFamily: 'Roboto',
        ),
      ),
      subtitle: Text(
        subtitle,
        style: TextStyle(
          color:
              Theme.of(context).textTheme.bodyMedium?.color ??
              const Color(0xFF9CA3AF),
          fontSize: 14,
          fontFamily: 'Roboto',
        ),
      ),
      trailing: Icon(
        Icons.arrow_forward_ios,
        color: const Color(0xFF9CA3AF),
        size: 16,
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
    );
  }

  Widget _buildDivider() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 24),
      height: 1,
      color: const Color(0xFFE1E5E9),
    );
  }

  Widget _buildDarkModeToggle() {
    return Consumer<ThemeProvider>(
      builder: (context, themeProvider, child) {
        return ListTile(
          leading: Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: const Color(0xFF667EEA).withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(
              _getThemeIcon(themeProvider.themeMode),
              color: const Color(0xFF667EEA),
              size: 20,
            ),
          ),
          title: Text(
            'Theme',
            style: TextStyle(
              color:
                  Theme.of(context).textTheme.titleMedium?.color ??
                  const Color(0xFF1A1A1A),
              fontWeight: FontWeight.w600,
              fontSize: 16,
              fontFamily: 'Roboto',
            ),
          ),
          subtitle: Text(
            _getThemeModeText(themeProvider.themeMode),
            style: const TextStyle(
              color: Color(0xFF9CA3AF),
              fontSize: 14,
              fontFamily: 'Roboto',
            ),
          ),
          trailing: Icon(
            Icons.arrow_forward_ios,
            color: const Color(0xFF9CA3AF),
            size: 16,
          ),
          onTap: () => _showThemeSelector(context, themeProvider),
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 24,
            vertical: 8,
          ),
        );
      },
    );
  }

  String _getThemeModeText(AppThemeMode mode) {
    switch (mode) {
      case AppThemeMode.light:
        return 'Light mode enabled';
      case AppThemeMode.dark:
        return 'Dark mode enabled';
      default:
        return 'Light mode enabled';
    }
  }

  void _showThemeSelector(BuildContext context, ThemeProvider themeProvider) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        decoration: BoxDecoration(
          color: Theme.of(context).cardColor,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.1),
              blurRadius: 10,
              offset: const Offset(0, -2),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              margin: const EdgeInsets.only(top: 12),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey[300],
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(24),
              child: Text(
                'Choose Theme',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: Theme.of(context).textTheme.titleLarge?.color,
                ),
              ),
            ),
            _buildThemeOption(
              context,
              themeProvider,
              AppThemeMode.light,
              Icons.light_mode,
              'Light',
              'Use light theme',
            ),
            _buildThemeOption(
              context,
              themeProvider,
              AppThemeMode.dark,
              Icons.dark_mode,
              'Dark',
              'Use dark theme',
            ),

            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  Widget _buildThemeOption(
    BuildContext context,
    ThemeProvider themeProvider,
    AppThemeMode mode,
    IconData icon,
    String title,
    String subtitle,
  ) {
    final isSelected = themeProvider.themeMode == mode;
    return ListTile(
      leading: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: isSelected
              ? const Color(0xFF667EEA)
              : const Color(0xFF667EEA).withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Icon(
          icon,
          color: isSelected ? Colors.white : const Color(0xFF667EEA),
          size: 20,
        ),
      ),
      title: Text(
        title,
        style: TextStyle(
          color: isSelected
              ? const Color(0xFF667EEA)
              : Theme.of(context).textTheme.titleMedium?.color ??
                    const Color(0xFF1A1A1A),
          fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
          fontSize: 16,
          fontFamily: 'Roboto',
        ),
      ),
      subtitle: Text(
        subtitle,
        style: TextStyle(
          color:
              Theme.of(context).textTheme.bodyMedium?.color ??
              const Color(0xFF9CA3AF),
          fontSize: 14,
          fontFamily: 'Roboto',
        ),
      ),
      trailing: isSelected
          ? const Icon(Icons.check, color: Color(0xFF667EEA), size: 20)
          : null,
      onTap: () {
        themeProvider.setThemeMode(mode);
        Navigator.pop(context);
      },
      contentPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
    );
  }

  IconData _getThemeIcon(AppThemeMode mode) {
    switch (mode) {
      case AppThemeMode.light:
        return Icons.light_mode;
      case AppThemeMode.dark:
        return Icons.dark_mode;
      default:
        return Icons.light_mode;
    }
  }

  Widget _buildSocialMediaSection() {
    return Container(
      margin: const EdgeInsets.fromLTRB(24, 0, 24, 24),
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            spreadRadius: 0,
            blurRadius: 20,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: [
          Row(
            children: [
              Icon(Icons.share, color: const Color(0xFF667EEA), size: 18),
              const SizedBox(width: 8),
              Text(
                'Follow Us On',
                style: TextStyle(
                  color:
                      Theme.of(context).textTheme.titleMedium?.color ??
                      const Color(0xFF1A1A1A),
                  fontWeight: FontWeight.w600,
                  fontSize: 16,
                  fontFamily: 'Roboto',
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _buildSocialMediaIcon(
                FontAwesomeIcons.youtube,
                const Color(0xFFFF0000),
              ),
              _buildSocialMediaIcon(
                FontAwesomeIcons.instagram,
                const Color(0xFFE4405F),
              ),
              _buildSocialMediaIcon(
                FontAwesomeIcons.facebookF,
                const Color(0xFF1877F2),
              ),
              _buildSocialMediaIcon(
                FontAwesomeIcons.linkedinIn,
                const Color(0xFF0A66C2),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSocialMediaIcon(IconData icon, Color color) {
    return GestureDetector(
      onTap: () {
        // TODO: Add social media links
      },
      child: Container(
        width: 50,
        height: 50,
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Icon(icon, color: color, size: 24),
      ),
    );
  }

  void _showImagePickerDialog() {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Profile Picture'),
          content: SingleChildScrollView(
            child: ListBody(
              children: <Widget>[
                const Text('Choose an option:'),
                ListTile(
                  leading: const Icon(Icons.photo_library),
                  title: const Text('Choose from Gallery'),
                  onTap: () {
                    Navigator.of(context).pop();
                    _pickImageFromGallery();
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.camera_alt),
                  title: const Text('Take Photo'),
                  onTap: () {
                    Navigator.of(context).pop();
                    _pickImageFromCamera();
                  },
                ),
                if (CustomerController.logeInCustomer?.profilePictureUrl !=
                    null)
                  ListTile(
                    leading: const Icon(Icons.delete, color: Colors.red),
                    title: const Text(
                      'Remove Profile Picture',
                      style: TextStyle(color: Colors.red),
                    ),
                    onTap: () {
                      Navigator.of(context).pop();
                      _removeProfilePicture();
                    },
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _pickImageFromGallery() async {
    try {
      final pickedFile = await _imagePicker.pickImage(
        source: ImageSource.gallery,
      );
      if (pickedFile != null) {
        setState(() {
          _isUploading = true;
        });
        await _uploadImage(pickedFile.path);
      }
    } catch (e) {
      ShowToast().showNormalToast(msg: e.toString());
    }
  }

  Future<void> _pickImageFromCamera() async {
    try {
      final pickedFile = await _imagePicker.pickImage(
        source: ImageSource.camera,
      );
      if (pickedFile != null) {
        setState(() {
          _isUploading = true;
        });
        await _uploadImage(pickedFile.path);
      }
    } catch (e) {
      ShowToast().showNormalToast(msg: e.toString());
    }
  }

  Future<void> _uploadImage(String filePath) async {
    try {
      final file = File(filePath);
      final url = await _storageHelper.uploadProfilePicture(
        file,
        CustomerController.logeInCustomer!.uid,
      );
      if (url != null) {
        await _firestoreHelper.updateCustomerProfile(
          customerId: CustomerController.logeInCustomer!.uid,
          profilePictureUrl: url,
        );
        // Update the local customer data
        CustomerController.logeInCustomer!.profilePictureUrl = url;
        setState(() {
          _isUploading = false;
        });
        ShowToast().showNormalToast(
          msg: 'Profile picture updated successfully!',
        );
      } else {
        setState(() {
          _isUploading = false;
        });
        ShowToast().showNormalToast(msg: 'Failed to upload image.');
      }
    } catch (e) {
      setState(() {
        _isUploading = false;
      });
      ShowToast().showNormalToast(msg: e.toString());
    }
  }

  Future<void> _removeProfilePicture() async {
    try {
      setState(() {
        _isUploading = true;
      });

      // Delete from Firebase Storage
      await _storageHelper.deleteProfilePicture(
        CustomerController.logeInCustomer!.uid,
      );

      // Update Firestore
      await _firestoreHelper.updateCustomerProfile(
        customerId: CustomerController.logeInCustomer!.uid,
        profilePictureUrl: null,
      );

      // Update local data
      CustomerController.logeInCustomer!.profilePictureUrl = null;

      setState(() {
        _isUploading = false;
      });

      ShowToast().showNormalToast(msg: 'Profile picture removed successfully!');
    } catch (e) {
      setState(() {
        _isUploading = false;
      });
      ShowToast().showNormalToast(
        msg: 'Failed to remove profile picture: ${e.toString()}',
      );
    }
  }
}
