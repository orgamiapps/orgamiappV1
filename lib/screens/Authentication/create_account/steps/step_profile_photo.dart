import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:orgami/Utils/colors.dart';
import 'package:orgami/controller/customer_controller.dart';
import 'package:orgami/firebase/firebase_storage_helper.dart';
import 'package:orgami/models/customer_model.dart';

class StepProfilePhoto extends StatefulWidget {
  const StepProfilePhoto({super.key, required this.onSkip, required this.onNext});
  final VoidCallback onSkip;
  final VoidCallback onNext;

  @override
  State<StepProfilePhoto> createState() => _StepProfilePhotoState();
}

class _StepProfilePhotoState extends State<StepProfilePhoto> {
  File? _image;
  bool _isUploading = false;
  String? _error;

  Future<void> _pickFromGallery() async {
    final file = await FirebaseStorageHelper.pickImageFromGallery();
    if (file != null) setState(() => _image = file);
  }

  Future<void> _pickFromCamera() async {
    final file = await FirebaseStorageHelper.pickImageFromCamera();
    if (file != null) setState(() => _image = file);
  }

  Future<void> _uploadIfNeededAndContinue() async {
    if (_image == null) {
      widget.onNext();
      return;
    }

    if (CustomerController.logeInCustomer == null) {
      widget.onNext();
      return;
    }

    try {
      setState(() {
        _isUploading = true;
        _error = null;
      });

      final userId = CustomerController.logeInCustomer!.uid;
      final url = await FirebaseStorageHelper.uploadProfilePicture(userId, _image!);
      if (url != null) {
        // Save to Firestore
        await FirebaseFirestore.instance
            .collection(CustomerModel.firebaseKey)
            .doc(userId)
            .update({'profilePictureUrl': url});

        // Update local cache
        CustomerController.logeInCustomer!.profilePictureUrl = url;
      }

      widget.onNext();
    } catch (e) {
      setState(() {
        _error = 'Failed to upload photo. You can try again or skip.';
      });
    } finally {
      if (mounted) {
        setState(() {
          _isUploading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              const SizedBox(height: 8),
              Text(
                'Set profile picture',
                style: TextStyle(
                  color: AppThemeColor.darkBlueColor,
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Add a clear photo of yourself so friends can recognize you. '
                'You can change this anytime from your profile.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: AppThemeColor.dullFontColor,
                  fontSize: 14,
                ),
              ),
              const SizedBox(height: 24),
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(
                    colors: [
                      AppThemeColor.lightBlueColor.withOpacity(0.2),
                      Colors.white,
                    ],
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.05),
                      blurRadius: 20,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                child: CircleAvatar(
                  radius: 72,
                  backgroundColor:
                      AppThemeColor.lightBlueColor.withOpacity(0.15),
                  backgroundImage: _image != null ? FileImage(_image!) : null,
                  child: _image == null
                      ? Icon(Icons.person, size: 72, color: AppThemeColor.darkBlueColor)
                      : null,
                ),
              ),
              const SizedBox(height: 24),
              Wrap(
                spacing: 12,
                runSpacing: 12,
                alignment: WrapAlignment.center,
                children: [
                  OutlinedButton.icon(
                    onPressed: _isUploading ? null : _pickFromCamera,
                    icon: const Icon(Icons.photo_camera),
                    label: const Text('Camera'),
                  ),
                  OutlinedButton.icon(
                    onPressed: _isUploading ? null : _pickFromGallery,
                    icon: const Icon(Icons.photo_library),
                    label: const Text('Gallery'),
                  ),
                ],
              ),
              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(
                  _error!,
                  style: const TextStyle(color: Colors.red),
                  textAlign: TextAlign.center,
                ),
              ],
              const Spacer(),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: _isUploading ? null : widget.onSkip,
                      child: const Text('Skip for now'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppThemeColor.darkBlueColor,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16)),
                        elevation: 0,
                      ),
                      onPressed: _isUploading ? null : _uploadIfNeededAndContinue,
                      child: const Text(
                        'Next',
                        style: TextStyle(color: Colors.white),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        if (_isUploading)
          Container(
            color: Colors.black.withOpacity(0.05),
            child: const Center(child: CircularProgressIndicator()),
          ),
      ],
    );
  }
}


