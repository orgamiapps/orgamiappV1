import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:attendus/Utils/toast.dart';
import 'package:permission_handler/permission_handler.dart';

class PermissionsHelperClass {
  static Future<void> checkCameraPermission({
    required BuildContext context,
  }) async {
    var status = await Permission.camera.status;
    if (status.isDenied) {
      if (context.mounted) {
        ShowToast().showSnackBar(
          'Please Give Access to Camera First!',
          context,
        );
      }
    } else {
      if (kDebugMode) {
        debugPrint('else Called');
      }
    }
  }
}
