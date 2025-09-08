import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:attendus/Utils/toast.dart';
import 'package:permission_handler/permission_handler.dart';

class PermissionsHelperClass {
  static Future<bool> checkCameraPermission({
    required BuildContext context,
  }) async {
    try {
      var status = await Permission.camera.status;
      
      if (status.isDenied || status.isRestricted) {
        // Request permission
        status = await Permission.camera.request();
      }
      
      if (status.isDenied || status.isRestricted) {
        if (context.mounted) {
          ShowToast().showSnackBar(
            'Camera permission is required to scan QR codes',
            context,
          );
        }
        return false;
      } else if (status.isPermanentlyDenied) {
        if (context.mounted) {
          ShowToast().showSnackBar(
            'Camera permission permanently denied. Please enable in settings.',
            context,
          );
        }
        // Optionally open app settings
        await openAppSettings();
        return false;
      }
      
      if (kDebugMode) {
        debugPrint('Camera permission granted');
      }
      return true;
    } catch (e) {
      if (kDebugMode) {
        debugPrint('Error checking camera permission: $e');
      }
      if (context.mounted) {
        ShowToast().showSnackBar(
          'Unable to check camera permission',
          context,
        );
      }
      return false;
    }
  }
  
  static Future<bool> requestCameraPermission() async {
    try {
      var status = await Permission.camera.status;
      
      if (status.isDenied || status.isRestricted) {
        status = await Permission.camera.request();
      }
      
      return status.isGranted;
    } catch (e) {
      if (kDebugMode) {
        debugPrint('Error requesting camera permission: $e');
      }
      return false;
    }
  }
}
