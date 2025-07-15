import 'package:flutter/cupertino.dart';
import 'package:orgami/Utils/Toast.dart';
import 'package:permission_handler/permission_handler.dart';

class PermissionsHelperClass {
  static Future<void> checkCameraPermission(
      {required BuildContext context}) async {
    var status = await Permission.camera.status;
    if (status.isDenied) {
      ShowToast().showSnackBar('Please Give Access to Camera First!', context);
    } else {
      print('else Called');
    }
  }
}
