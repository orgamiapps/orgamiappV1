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
        ShowToast().showSnackBar('Unable to check camera permission', context);
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

  static Future<bool> checkLocationPermission({
    required BuildContext context,
    bool showMessage = true,
  }) async {
    try {
      var status = await Permission.location.status;

      if (status.isDenied || status.isRestricted) {
        // Request permission
        status = await Permission.location.request();
      }

      if (status.isDenied || status.isRestricted) {
        if (context.mounted && showMessage) {
          ShowToast().showSnackBar(
            'Location permission is required for location-based features',
            context,
          );
        }
        if (kDebugMode) {
          debugPrint('Location permission denied');
        }
        return false;
      } else if (status.isPermanentlyDenied) {
        if (context.mounted && showMessage) {
          ShowToast().showSnackBar(
            'Location permission permanently denied. Please enable in settings.',
            context,
          );
        }
        if (kDebugMode) {
          debugPrint('Location permission permanently denied');
        }
        // Optionally open app settings
        await openAppSettings();
        return false;
      }

      if (kDebugMode) {
        debugPrint('Location permission granted');
      }
      return true;
    } catch (e) {
      if (kDebugMode) {
        debugPrint('Error checking location permission: $e');
      }
      if (context.mounted && showMessage) {
        ShowToast().showSnackBar(
          'Unable to check location permission',
          context,
        );
      }
      return false;
    }
  }

  static Future<bool> requestLocationPermission() async {
    try {
      var status = await Permission.location.status;

      if (status.isDenied || status.isRestricted) {
        status = await Permission.location.request();
      }

      if (kDebugMode) {
        debugPrint('Location permission status: $status');
      }

      return status.isGranted;
    } catch (e) {
      if (kDebugMode) {
        debugPrint('Error requesting location permission: $e');
      }
      return false;
    }
  }
}
