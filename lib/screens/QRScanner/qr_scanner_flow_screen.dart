import 'package:flutter/material.dart';
import 'package:attendus/screens/QRScanner/modern_sign_in_flow_screen.dart';

/// Legacy QRScannerFlowScreen - redirects to modern flow
/// Maintained for backward compatibility
class QRScannerFlowScreen extends StatelessWidget {
  const QRScannerFlowScreen({super.key});

  @override
  Widget build(BuildContext context) {
    // Redirect to new modern sign-in flow
    return const ModernSignInFlowScreen();
  }
}