import 'dart:io';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:image_picker/image_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:orgami/Utils/logger.dart';

class FirebaseStorageHelper {
  static final FirebaseStorage _storage = FirebaseStorage.instance;
  static final ImagePicker _picker = ImagePicker();

  // Pick image from gallery
  static Future<File?> pickImageFromGallery() async {
    try {
      final XFile? image = await _picker.pickImage(source: ImageSource.gallery);
      if (image != null) {
        return File(image.path);
      }
      return null;
    } catch (e) {
      if (kDebugMode) {
        Logger.error('Error picking image: $e', e);
      }
      return null;
    }
  }

  // Pick image from camera
  static Future<File?> pickImageFromCamera() async {
    try {
      final XFile? image = await _picker.pickImage(source: ImageSource.camera);
      if (image != null) {
        return File(image.path);
      }
      return null;
    } catch (e) {
      if (kDebugMode) {
        Logger.error('Error picking image: $e', e);
      }
      return null;
    }
  }

  // Upload profile picture
  static Future<String?> uploadProfilePicture(
    String userId,
    File imageFile,
  ) async {
    try {
      final Reference ref = _storage.ref().child(
        'profile_pictures/$userId.jpg',
      );
      final UploadTask uploadTask = ref.putFile(imageFile);
      final TaskSnapshot snapshot = await uploadTask;
      final String downloadUrl = await snapshot.ref.getDownloadURL();
      return downloadUrl;
    } catch (e) {
      if (kDebugMode) {
        Logger.error('Error uploading profile picture: $e', e);
      }
      return null;
    }
  }

  // Delete profile picture
  static Future<bool> deleteProfilePicture(String userId) async {
    try {
      final Reference ref = _storage.ref().child(
        'profile_pictures/$userId.jpg',
      );
      await ref.delete();
      return true;
    } catch (e) {
      if (kDebugMode) {
        Logger.error('Error deleting profile picture: $e', e);
      }
      return false;
    }
  }
}
