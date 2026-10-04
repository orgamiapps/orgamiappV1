import 'package:flutter/material.dart';
import 'package:attendus/screens/QRScanner/qr_scanner_flow_screen.dart';

/// Compatibility route; the modern flow owns camera permission and lifecycle.
class QRScannerWithoutLoginScreen extends StatelessWidget {
  const QRScannerWithoutLoginScreen({super.key});
  @override
  Widget build(BuildContext context) => const QRScannerFlowScreen();
}
