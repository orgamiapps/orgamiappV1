import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:image_picker/image_picker.dart';
import 'package:orgami/Controller/CustomerController.dart';
import 'package:orgami/Firebase/FirebaseFirestoreHelper.dart';
import 'package:orgami/Firebase/FirebaseStorageHelper.dart';
import 'package:orgami/Screens/Feedback/FeedbackScreen.dart';
import 'package:orgami/Screens/MyEvents/MyEventsScreen.dart';
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
      body: _bodyView(),
    );
  }

  Widget _bodyView() {
    return SizedBox(
      height: MediaQuery.of(context).size.height,
      child: SingleChildScrollView(
        child: Column(
          children: [
            // Profile Picture Section
            Container(
              margin: const EdgeInsets.only(
                top: 24.0,
                bottom: 20.0,
              ),
              child: Stack(
                children: [
                  // Profile Picture - Make entire area clickable
                  GestureDetector(
                    onTap: _showImagePickerDialog,
                    child: Container(
                      width: 120,
                      height: 120,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: AppThemeColor.darkGreenColor,
                          width: 3,
                        ),
                      ),
                      child: ClipOval(
                        child: CustomerController
                                    .logeInCustomer?.profilePictureUrl !=
                                null
                            ? Image.network(
                                CustomerController
                                    .logeInCustomer!.profilePictureUrl!,
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
                        color: Colors.black.withOpacity(0.5),
                      ),
                      child: const Center(
                        child: CircularProgressIndicator(
                          color: Colors.white,
                        ),
                      ),
                    ),
                  // Camera Icon Button - Keep for visual indication
                  if (!_isUploading)
                    Positioned(
                      bottom: 0,
                      right: 0,
                      child: Container(
                        width: 35,
                        height: 35,
                        decoration: BoxDecoration(
                          color: AppThemeColor.darkGreenColor,
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: Colors.white,
                            width: 2,
                          ),
                        ),
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
            // User Name
            Container(
              width: _screenWidth,
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Text(
                'Hi ${CustomerController.logeInCustomer != null ? CustomerController.logeInCustomer!.name : ''}',
                style: const TextStyle(
                  color: AppThemeColor.darkGreenColor,
                  fontSize: Dimensions.fontSizeExtraLarge,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            // My Profile Button
            ListTile(
              onTap: () => RouterClass.nextScreenNormal(
                context,
                MyProfileScreen(),
              ),
              leading: const Icon(Icons.person),
              title: const Text('My Profile'),
              minVerticalPadding: 0,
            ),
            ListTile(
              onTap: () => RouterClass.nextScreenNormal(
                context,
                const MyEventsScreen(),
              ),
              leading: const Icon(Icons.event_note_rounded),
              title: const Text('My Events'),
              minVerticalPadding: 0,
            ),
            ListTile(
              onTap: () => {},
              leading: const Icon(CupertinoIcons.info),
              title: const Text('About Us'),
              minVerticalPadding: 0,
            ),
            ListTile(
              onTap: () => {},
              leading: const Icon(Icons.help),
              title: const Text('Help'),
              minVerticalPadding: 0,
            ),
            ListTile(
              onTap: () => RouterClass.nextScreenNormal(
                context,
                FeedbackScreen(),
              ),
              leading: const Icon(FontAwesomeIcons.feed),
              title: const Text('Feedback'),
              minVerticalPadding: 0,
            ),

            ListTile(
              onTap: () => RouterClass.nextScreenNormal(
                context,
                WebViewScreen(
                  url: AppConstants.privacyPolicyUrl,
                  title: 'Privacy Policy',
                ),
              ),
              leading: const Icon(Icons.privacy_tip),
              title: const Text('Privacy Policy'),
              minVerticalPadding: 0,
            ),
            ListTile(
              onTap: () => RouterClass.nextScreenNormal(
                context,
                WebViewScreen(
                  url: AppConstants.termsConditionsUrl,
                  title: 'Terms & Conditions',
                ),
              ),
              leading: const Icon(CupertinoIcons.question_diamond),
              title: const Text('Terms & Conditions'),
              minVerticalPadding: 0,
            ),

            ListTile(
              onTap: () {
                FirebaseAuth.instance.signOut().then((value) {
                  setState(() {
                    CustomerController.logeInCustomer = null;
                  });
                  RouterClass().appRest(context: context);
                });
              },
              leading: Icon(Icons.logout),
              title: const Text('Logout'),
              minVerticalPadding: 0,
            ),

            const Text(
              'Follow Us On',
              maxLines: 1,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: AppThemeColor.dullFontColor,
                fontWeight: FontWeight.w400,
                fontSize: Dimensions.fontSizeSmall,
              ),
            ),
            const Padding(
              padding: EdgeInsets.all(20.0),
              child: Row(
                children: [
                  Icon(
                    FontAwesomeIcons.youtube,
                    color: AppThemeColor.darkBlueColor,
                    size: 33,
                  ),
                  SizedBox(
                    width: 10,
                  ),
                  Icon(
                    FontAwesomeIcons.instagram,
                    color: AppThemeColor.darkBlueColor,
                    size: 33,
                  ),
                  SizedBox(
                    width: 10,
                  ),
                  Icon(
                    FontAwesomeIcons.facebookF,
                    color: AppThemeColor.darkBlueColor,
                    size: 33,
                  ),
                  SizedBox(
                    width: 10,
                  ),
                  Icon(
                    FontAwesomeIcons.linkedinIn,
                    color: AppThemeColor.darkBlueColor,
                    size: 33,
                  ),
                  SizedBox(
                    width: 10,
                  ),
                ],
              ),
            ),
            // DefaultTextStyle(
            //   style: TextStyle(
            //     fontSize: 12,
            //     color: Colors.white54,
            //   ),
            //   child: Container(
            //     margin: const EdgeInsets.symmetric(
            //       vertical: 16.0,
            //     ),
            //     child: Text('Terms of Service | Privacy Policy'),
            //   ),
            // ),
          ],
        ),
      ),
    );
  }

  Widget _buildDefaultProfilePicture() {
    return Container(
      color: Colors.grey[300],
      child: const Icon(
        Icons.person,
        size: 60,
        color: Colors.grey,
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
                    title: const Text('Remove Profile Picture',
                        style: TextStyle(color: Colors.red)),
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
      final pickedFile =
          await _imagePicker.pickImage(source: ImageSource.gallery);
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
      final pickedFile =
          await _imagePicker.pickImage(source: ImageSource.camera);
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
          file, CustomerController.logeInCustomer!.uid);
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
        ShowToast()
            .showNormalToast(msg: 'Profile picture updated successfully!');
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
      await _storageHelper
          .deleteProfilePicture(CustomerController.logeInCustomer!.uid);

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
          msg: 'Failed to remove profile picture: ${e.toString()}');
    }
  }
}
