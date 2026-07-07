import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:flutter/foundation.dart';

class FileStorage {
  // Save file to local storage
  static Future<String?> saveFile(File file, String fileName) async {
    try {
      Directory? directory = await getApplicationDocumentsDirectory();
      String exPath = '${directory.path}/$fileName';

      if (kDebugMode) {
        debugPrint("Saved Path: $exPath");
      }

      File savedFile = await file.copy(exPath);
      return savedFile.path;
    } catch (e) {
      if (kDebugMode) {
        debugPrint('Error saving file: $e');
      }
      return null;
    }
  }

  // Save bytes data to file
  static Future<String?> writeCounter(Uint8List bytes, String fileName) async {
    try {
      Directory? directory = await getApplicationDocumentsDirectory();
      String filePath = '${directory.path}/$fileName';

      if (kDebugMode) {
        debugPrint("Saved Path: $filePath");
      }

      File file = File(filePath);
      await file.writeAsBytes(bytes);
      return file.path;
    } catch (e) {
      if (kDebugMode) {
        debugPrint('Error saving bytes to file: $e');
      }
      return null;
    }
  }

  // Get file from local storage
  static Future<File?> getFile(String fileName) async {
    try {
      Directory? directory = await getApplicationDocumentsDirectory();
      String filePath = '${directory.path}/$fileName';
      File file = File(filePath);

      if (await file.exists()) {
        if (kDebugMode) {
          debugPrint("Save file");
        }
        return file;
      }
      return null;
    } catch (e) {
      if (kDebugMode) {
        debugPrint('Error getting file: $e');
      }
      return null;
    }
  }

  // Delete file from local storage
  static Future<bool> deleteFile(String fileName) async {
    try {
      Directory? directory = await getApplicationDocumentsDirectory();
      String filePath = '${directory.path}/$fileName';
      File file = File(filePath);

      if (await file.exists()) {
        await file.delete();
        return true;
      }
      return false;
    } catch (e) {
      if (kDebugMode) {
        debugPrint('Error deleting file: $e');
      }
      return false;
    }
  }

  // Check if file exists
  static Future<bool> fileExists(String fileName) async {
    try {
      Directory? directory = await getApplicationDocumentsDirectory();
      String filePath = '${directory.path}/$fileName';
      File file = File(filePath);
      return await file.exists();
    } catch (e) {
      if (kDebugMode) {
        debugPrint('Error checking file existence: $e');
      }
      return false;
    }
  }
}
