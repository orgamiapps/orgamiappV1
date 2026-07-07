import 'dart:io';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:image/image.dart' as img;
import 'package:path_provider/path_provider.dart';
import 'package:image_picker/image_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:attendus/Utils/logger.dart';

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

  // Upload organization asset (logo or banner)
  static Future<String?> uploadOrganizationImage({
    required String organizationId,
    required File imageFile,
    required bool isBanner,
  }) async {
    try {
      // Decode and compress
      final bytes = await imageFile.readAsBytes();
      img.Image? decoded = img.decodeImage(bytes);
      if (decoded == null) return null;

      // Target sizes
      final int targetW = isBanner ? 1600 : 512;
      final int targetH = isBanner ? 600 : 512;
      decoded = img.copyResize(decoded, width: targetW, height: targetH, interpolation: img.Interpolation.cubic);

      // Encode
      final List<int> outBytes = isBanner
          ? img.encodeJpg(decoded, quality: 80)
          : img.encodePng(decoded, level: 6);

      // Write to temp file
      final dir = await getTemporaryDirectory();
      final String fileName = isBanner ? 'banner' : 'logo';
      final String tmpPath = '${dir.path}/${fileName}_${DateTime.now().millisecondsSinceEpoch}.${isBanner ? 'jpg' : 'png'}';
      final File tmpFile = File(tmpPath)..writeAsBytesSync(outBytes);

      final Reference ref = _storage.ref().child(
        'organizations/$organizationId/${fileName}_${DateTime.now().millisecondsSinceEpoch}.${isBanner ? 'jpg' : 'png'}',
      );
      final UploadTask uploadTask = ref.putFile(tmpFile);
      final TaskSnapshot snapshot = await uploadTask;
      final String downloadUrl = await snapshot.ref.getDownloadURL();
      return downloadUrl;
    } catch (e) {
      if (kDebugMode) {
        Logger.error('Error uploading organization image: $e', e);
      }
      return null;
    }
  }

  // Upload user banner
  static Future<String?> uploadUserBanner({
    required String userId,
    required File imageFile,
  }) async {
    try {
      // Decode and compress for banner aspect
      final bytes = await imageFile.readAsBytes();
      img.Image? decoded = img.decodeImage(bytes);
      if (decoded == null) return null;
      final int targetW = 1600;
      final int targetH = 600;
      decoded = img.copyResize(
        decoded,
        width: targetW,
        height: targetH,
        interpolation: img.Interpolation.cubic,
      );

      final List<int> outBytes = img.encodeJpg(decoded, quality: 80);

      final dir = await getTemporaryDirectory();
      final String tmpPath = '${dir.path}/user_banner_${DateTime.now().millisecondsSinceEpoch}.jpg';
      final File tmpFile = File(tmpPath)..writeAsBytesSync(outBytes);

      final Reference ref = _storage.ref().child(
        'user_banners/$userId/banner_${DateTime.now().millisecondsSinceEpoch}.jpg',
      );
      final UploadTask uploadTask = ref.putFile(tmpFile);
      final TaskSnapshot snapshot = await uploadTask;
      final String downloadUrl = await snapshot.ref.getDownloadURL();
      return downloadUrl;
    } catch (e) {
      if (kDebugMode) {
        Logger.error('Error uploading user banner: $e', e);
      }
      return null;
    }
  }
}
