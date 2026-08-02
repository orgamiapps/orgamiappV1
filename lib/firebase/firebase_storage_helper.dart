import 'dart:typed_data';

import 'package:attendus/Utils/logger.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:image/image.dart' as img;
import 'package:image_picker/image_picker.dart';

/// An image selected by the user that is safe to use on web and native.
class SelectedImageData {
  const SelectedImageData({
    required this.bytes,
    required this.name,
    this.mimeType,
  });

  final Uint8List bytes;
  final String name;
  final String? mimeType;

  ImageProvider<Object> get imageProvider => MemoryImage(bytes);

  static Future<SelectedImageData> fromXFile(XFile file) async {
    final bytes = await file.readAsBytes();
    if (bytes.isEmpty) {
      throw const FormatException('The selected image is empty.');
    }
    if (bytes.length > FirebaseStorageHelper.maxSelectedImageBytes) {
      throw const FormatException(
        'The selected image exceeds the 10 MB limit.',
      );
    }
    if (img.decodeImage(bytes) == null) {
      throw const FormatException(
        'The selected file is not a supported image.',
      );
    }
    return SelectedImageData(
      bytes: bytes,
      name: file.name,
      mimeType: file.mimeType,
    );
  }
}

class FirebaseStorageHelper {
  static const int maxSelectedImageBytes = 10 * 1024 * 1024;
  static final FirebaseStorage _storage = FirebaseStorage.instance;
  static final ImagePicker _picker = ImagePicker();

  static Future<SelectedImageData?> pickImageFromGallery() =>
      _pickImage(ImageSource.gallery);

  static Future<SelectedImageData?> pickImageFromCamera() =>
      _pickImage(ImageSource.camera);

  static Future<SelectedImageData?> _pickImage(ImageSource source) async {
    try {
      final image = await _picker.pickImage(source: source);
      return image == null ? null : SelectedImageData.fromXFile(image);
    } catch (error, stackTrace) {
      Logger.error('Image selection failed.', error, stackTrace);
      return null;
    }
  }

  static Future<String?> uploadProfilePicture(
    String userId,
    SelectedImageData image,
  ) async {
    try {
      final bytes = _resizeAsJpeg(image.bytes, width: 512, height: 512);
      return _uploadBytes(
        path: 'profile_pictures/$userId.jpg',
        bytes: bytes,
        contentType: 'image/jpeg',
      );
    } catch (error, stackTrace) {
      Logger.error('Profile picture upload failed.', error, stackTrace);
      return null;
    }
  }

  static Future<bool> deleteProfilePicture(String userId) async {
    try {
      await _storage.ref('profile_pictures/$userId.jpg').delete();
      return true;
    } catch (error, stackTrace) {
      Logger.error('Profile picture deletion failed.', error, stackTrace);
      return false;
    }
  }

  static Future<String?> uploadOrganizationImage({
    required String organizationId,
    required SelectedImageData imageFile,
    required bool isBanner,
  }) async {
    try {
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final fileName = isBanner
          ? 'banner_$timestamp.jpg'
          : 'logo_$timestamp.png';
      final bytes = isBanner
          ? _resizeAsJpeg(imageFile.bytes, width: 1600, height: 600)
          : _resizeAsPng(imageFile.bytes, width: 512, height: 512);
      return _uploadBytes(
        path: 'organizations/$organizationId/$fileName',
        bytes: bytes,
        contentType: isBanner ? 'image/jpeg' : 'image/png',
      );
    } catch (error, stackTrace) {
      Logger.error('Organization image upload failed.', error, stackTrace);
      return null;
    }
  }

  static Future<String?> uploadUserBanner({
    required String userId,
    required SelectedImageData imageFile,
  }) async {
    try {
      final bytes = _resizeAsJpeg(imageFile.bytes, width: 1600, height: 600);
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      return _uploadBytes(
        path: 'user_banners/$userId/banner_$timestamp.jpg',
        bytes: bytes,
        contentType: 'image/jpeg',
      );
    } catch (error, stackTrace) {
      Logger.error('User banner upload failed.', error, stackTrace);
      return null;
    }
  }

  static Future<String> uploadGroupPhoto({
    required String organizationId,
    required String userId,
    required String uploadId,
    required int index,
    required SelectedImageData image,
  }) async {
    final bytes = _resizeAsJpeg(image.bytes, width: 1920, height: 1920);
    return _uploadBytes(
      path: 'groups/$organizationId/photos/${userId}_${uploadId}_$index.jpg',
      bytes: bytes,
      contentType: 'image/jpeg',
    );
  }

  static Future<String> _uploadBytes({
    required String path,
    required Uint8List bytes,
    required String contentType,
  }) async {
    final snapshot = await _storage
        .ref(path)
        .putData(bytes, SettableMetadata(contentType: contentType));
    return snapshot.ref.getDownloadURL();
  }

  static Uint8List _resizeAsJpeg(
    Uint8List bytes, {
    required int width,
    required int height,
  }) {
    final decoded = _decode(bytes);
    final resized = img.copyResize(
      decoded,
      width: width,
      height: height,
      interpolation: img.Interpolation.cubic,
    );
    return Uint8List.fromList(img.encodeJpg(resized, quality: 82));
  }

  static Uint8List _resizeAsPng(
    Uint8List bytes, {
    required int width,
    required int height,
  }) {
    final decoded = _decode(bytes);
    final resized = img.copyResize(
      decoded,
      width: width,
      height: height,
      interpolation: img.Interpolation.cubic,
    );
    return Uint8List.fromList(img.encodePng(resized, level: 6));
  }

  static img.Image _decode(Uint8List bytes) {
    final decoded = img.decodeImage(bytes);
    if (decoded == null) {
      throw const FormatException(
        'The selected file is not a supported image.',
      );
    }
    return decoded;
  }
}
