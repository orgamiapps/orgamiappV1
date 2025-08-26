import 'dart:io';

import 'package:flutter/material.dart';
import 'package:orgami/Permissions/permissions_helper.dart';
import 'package:orgami/Utils/colors.dart';
import 'package:orgami/screens/QRScanner/qr_scanner_flow_screen.dart';
import 'package:qr_code_scanner_plus/qr_code_scanner_plus.dart';

class QRScannerScreen extends StatefulWidget {
  const QRScannerScreen({super.key});

  @override
  State<StatefulWidget> createState() => _QRScannerScreenState();
}

class _QRScannerScreenState extends State<QRScannerScreen> {
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
    try {
      if (Platform.isAndroid) {
        controller?.pauseCamera();
      }
      controller?.resumeCamera();
    } catch (_) {
      // Ignore camera errors during hot reload / emulator without camera
    }
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

  // Widget _bodyView() {
  //   return const Column(
  //     children: [
  //       // const Text(
  //       //   'Scan The QR app will detect Event Automatically',
  //       //   textAlign: TextAlign.center,
  //       //   style: TextStyle(
  //       //     color: AppThemeColor.pureWhiteColor,
  //       //     fontSize: 13,
  //       //     fontWeight: FontWeight.w400,
  //       //   ),
  //       // ),
  //     ],
  //   );
  // }

  @override
  void dispose() {
    super.dispose();
  }
}
