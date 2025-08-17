import 'package:flutter/material.dart';
import 'package:orgami/screens/QRScanner/qr_scanner_flow_screen.dart';
import 'package:orgami/screens/Authentication/create_account/create_account_screen.dart';
import 'package:orgami/screens/Authentication/login_screen.dart';
import 'package:orgami/Utils/routes.dart';

class SecondSplashScreen extends StatefulWidget {
  const SecondSplashScreen({super.key});

  @override
  State<SecondSplashScreen> createState() => _SecondSplashScreenState();
}

class _SecondSplashScreenState extends State<SecondSplashScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _fadeAnimation;

  @override
  void initState() {
    super.initState();
    _controller =
        AnimationController(vsync: this, duration: const Duration(seconds: 1));
    _fadeAnimation =
        CurvedAnimation(parent: _controller, curve: Curves.easeInOut);
    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: FadeTransition(
        opacity: _fadeAnimation,
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              GestureDetector(
                onTap: () => Nav.toEvent(context, 'QR'),
                child: RepaintBoundary(
                  child: Container(
                    height: 160,
                    width: 160,
                    decoration: BoxDecoration(
                      color: const Color(0xFF667EEA).withAlpha(25),
                      borderRadius: BorderRadius.circular(24),
                    ),
                    child: const Icon(Icons.qr_code_scanner,
                        size: 72, color: Color(0xFF667EEA)),
                  ),
                ),
              ),
              const SizedBox(height: 32),
              _buildPrimaryButton(
                label: 'Create Account',
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => const CreateAccountScreen(),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              _buildPrimaryButton(
                label: 'Login',
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const LoginScreen()),
                ),
                isPrimary: false,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPrimaryButton({
    required String label,
    required VoidCallback onTap,
    bool isPrimary = true,
  }) {
    return SizedBox(
      width: double.infinity,
      height: 54,
      child: ElevatedButton(
        onPressed: onTap,
        style: ElevatedButton.styleFrom(
          backgroundColor: isPrimary ? const Color(0xFF667EEA) : Colors.white,
          foregroundColor: isPrimary ? Colors.white : const Color(0xFF667EEA),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          side: isPrimary
              ? null
              : const BorderSide(color: Color(0xFF667EEA), width: 2),
        ),
        child: Text(label, style: const TextStyle(fontWeight: FontWeight.bold)),
      ),
    );
  }
}
