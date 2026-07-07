import 'dart:io';

import 'package:flutter/material.dart';
import 'package:attendus/Permissions/permissions_helper.dart';
import 'package:attendus/Utils/colors.dart';
import 'package:attendus/screens/QRScanner/qr_scanner_flow_screen.dart';
import 'package:qr_code_scanner_plus/qr_code_scanner_plus.dart';

class QrScannerScreenForLogedIn extends StatefulWidget {
  const QrScannerScreenForLogedIn({super.key});

  @override
  State<StatefulWidget> createState() => _QrScannerScreenForLogedInState();
}

class _QrScannerScreenForLogedInState extends State<QrScannerScreenForLogedIn> {
  QRViewController? controller;

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
