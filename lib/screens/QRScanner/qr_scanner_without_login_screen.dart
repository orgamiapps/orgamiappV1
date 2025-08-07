import 'dart:io';

import 'package:flutter/material.dart';
import 'package:orgami/Permissions/permissions_helper.dart';
import 'package:orgami/utils/colors.dart';
import 'package:orgami/Screens/QRScanner/qr_scanner_flow_screen.dart';
import 'package:qr_code_scanner_plus/qr_code_scanner_plus.dart';

class QRScannerWithoutLoginScreen extends StatefulWidget {
  const QRScannerWithoutLoginScreen({super.key});

  @override
  State<StatefulWidget> createState() => _QRScannerWithoutLoginScreenState();
}

class _QRScannerWithoutLoginScreenState
    extends State<QRScannerWithoutLoginScreen> {
  QRViewController? controller;

  // In order to get hot reload to work we need to pause the camera if the platform
  // is android, or resume the camera if the platform is iOS.

  @override
  void initState() {
    PermissionsHelperClass.checkCameraPermission(context: context);
    super.initState();
  }

  @override
  void reassemble() {
    super.reassemble();
    if (Platform.isAndroid) {
      controller!.pauseCamera();
    }
    controller!.resumeCamera();
  }

  @override
  Widget build(BuildContext context) {
    // Redirect to the new modern QR scanner flow
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (context) => const QRScannerFlowScreen()),
      );
    });

    return Scaffold(
      backgroundColor: AppThemeColor.pureBlackColor,
      body: const Center(
        child: CircularProgressIndicator(color: AppThemeColor.darkBlueColor),
      ),
    );
  }

  @override
  void dispose() {
    super.dispose();
  }
}
