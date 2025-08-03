import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:image_picker/image_picker.dart';
import 'package:orgami/Controller/CustomerController.dart';
import 'package:orgami/Firebase/FirebaseFirestoreHelper.dart';
import 'package:orgami/Firebase/FirebaseStorageHelper.dart';
import 'package:orgami/Screens/Feedback/FeedbackScreen.dart';

import 'package:orgami/Screens/Home/AnalyticsDashboardScreen.dart';
import 'package:orgami/Utils/AppConstants.dart';
import 'package:orgami/Utils/Colors.dart';
import 'package:orgami/Utils/Images.dart';
import 'package:orgami/Utils/Router.dart';
import 'package:orgami/Utils/Toast.dart';
import 'package:orgami/Utils/WebViewPage.dart';
import 'package:orgami/Utils/dimensions.dart';
import 'dart:io';
import 'package:orgami/Screens/MyProfile/MyProfileScreen.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late final double _screenWidth = MediaQuery.of(context).size.width;
  late final double _screenHeight = MediaQuery.of(context).size.height;
  final FirebaseStorageHelper _storageHelper = FirebaseStorageHelper();
  final FirebaseFirestoreHelper _firestoreHelper = FirebaseFirestoreHelper();
  final ImagePicker _imagePicker = ImagePicker();
  bool _isUploading = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFFAFBFC),
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
    return Container(
      width: double.infinity,
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF667EEA), Color(0xFF764BA2)],
        ),
      ),
      padding: const EdgeInsets.fromLTRB(24, 32, 24, 40),
      child: Column(
        children: [
          // Profile Picture Section
          Container(
            margin: const EdgeInsets.only(bottom: 24),
            child: Stack(
              children: [
                GestureDetector(
                  onTap: _showImagePickerDialog,
                  child: Container(
                    width: 120,
                    height: 120,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white, width: 4),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.2),
                          blurRadius: 20,
                          offset: const Offset(0, 8),
                        ),
                      ],
                    ),
                    child: ClipOval(
                      child:
                          CustomerController
                                  .logeInCustomer
                                  ?.profilePictureUrl !=
                              null
                          ? Image.network(
                              CustomerController
                                  .logeInCustomer!
                                  .profilePictureUrl!,
                              fit: BoxFit.cover,
                              errorBuilder: (context, error, stackTrace) {
                                return _buildDefaultProfilePicture();
                              },
                            )
                          : _buildDefaultProfilePicture(),
                    ),
                  ),
                ),
                // Loading Overlay
                if (_isUploading)
                  Container(
                    width: 120,
                    height: 120,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.black.withValues(alpha: 0.5),
                    ),
                    child: const Center(
                      child: CircularProgressIndicator(color: Colors.white),
                    ),
                  ),
                // Camera Icon Button
                if (!_isUploading)
                  Positioned(
                    bottom: 0,
                    right: 0,
                    child: Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.1),
                            blurRadius: 8,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: const Icon(
                        Icons.camera_alt,
                        color: Color(0xFF667EEA),
                        size: 18,
                      ),
                    ),
                  ),
              ],
            ),
          ),

          // User Name
          Text(
            'Hi ${CustomerController.logeInCustomer != null ? CustomerController.logeInCustomer!.name : 'User'}',
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w600,
              fontSize: 24,
              fontFamily: 'Roboto',
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Manage your account settings',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.8),
              fontWeight: FontWeight.w400,
              fontSize: 16,
              fontFamily: 'Roboto',
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDefaultProfilePicture() {
    return Container(
      color: const Color(0xFFE1E5E9),
      child: const Icon(Icons.person, size: 60, color: Color(0xFF9CA3AF)),
    );
  }

  Widget _buildSettingsSection() {
    return Container(
      margin: const EdgeInsets.fromLTRB(24, 24, 24, 24),
      decoration: BoxDecoration(
        color: Colors.white,
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
          _buildSettingsHeader(),
          _buildSettingsItem(
            icon: Icons.person,
            title: 'My Profile',
            subtitle: 'View and edit your profile',
            onTap: () =>
                RouterClass.nextScreenNormal(context, MyProfileScreen()),
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
          Icon(Icons.settings, color: const Color(0xFF667EEA), size: 20),
          const SizedBox(width: 12),
          const Text(
            'Settings',
            style: TextStyle(
              color: Color(0xFF1A1A1A),
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
              : const Color(0xFF1A1A1A),
          fontWeight: FontWeight.w600,
          fontSize: 16,
          fontFamily: 'Roboto',
        ),
      ),
      subtitle: Text(
        subtitle,
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

  Widget _buildSocialMediaSection() {
    return Container(
      margin: const EdgeInsets.fromLTRB(24, 0, 24, 24),
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
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
              const Text(
                'Follow Us On',
                style: TextStyle(
                  color: Color(0xFF1A1A1A),
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
