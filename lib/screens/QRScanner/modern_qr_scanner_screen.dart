import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:attendus/Permissions/permissions_helper.dart';
import 'package:attendus/Utils/colors.dart';
import 'package:attendus/Utils/toast.dart';
import 'package:attendus/Utils/dimensions.dart';
import 'package:attendus/Utils/qr_debug_helper.dart';
import 'package:qr_code_scanner_plus/qr_code_scanner_plus.dart';

class ModernQRScannerScreen extends StatefulWidget {
  const ModernQRScannerScreen({super.key});

  @override
  State<ModernQRScannerScreen> createState() => _ModernQRScannerScreenState();
}

class _ModernQRScannerScreenState extends State<ModernQRScannerScreen>
    with TickerProviderStateMixin {
  Barcode? result;
  QRViewController? controller;
  final GlobalKey qrKey = GlobalKey(debugLabel: 'QR');
  Future<bool>? _cameraInitFuture;

  final TextEditingController _codeController = TextEditingController();

  bool _isManualEntry = false;
  bool _isFlashOn = false;
  bool _isCameraPermissionGranted = false;

  late AnimationController _animationController;
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;
  late Animation<double> _slideAnimation;

  @override
  void initState() {
    super.initState();
    _initializeAnimations();
    // Memoize camera initialization to avoid recreating the Future on rebuilds
    _cameraInitFuture = _initializeCamera();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Re-check permissions when returning to this screen
    _checkPermissions();
  }

  void _initializeAnimations() {
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );

    _pulseController = AnimationController(
      duration: const Duration(milliseconds: 1500),
      vsync: this,
    );

    _pulseAnimation = Tween<double>(begin: 0.8, end: 1.2).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    _slideAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeOutCubic),
    );

    _pulseController.repeat(reverse: true);
  }

  Future<void> _checkPermissions() async {
    try {
      final hasPermission = await PermissionsHelperClass.checkCameraPermission(
        context: context,
      );
      QRDebugHelper.logCameraPermissionStatus(hasPermission);
      setState(() {
        _isCameraPermissionGranted = hasPermission;
      });
      if (hasPermission) {
        debugPrint('Camera permission granted for QR scanner');
      }
    } catch (e) {
      // Handle permission denied or emulator scenario
      debugPrint('Camera permission check failed in QR scanner: $e');
      QRDebugHelper.logScannerInitialization(false, e.toString());
      setState(() {
        _isCameraPermissionGranted = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppThemeColor.pureBlackColor,
      body: SafeArea(
        child: Stack(
          children: [
            // Camera View
            _buildCameraView(),

            // Overlay UI
            _buildOverlayUI(),

            // App Bar
            _buildAppBar(),
          ],
        ),
      ),
    );
  }

  Widget _buildCameraView() {
    // Always show a fallback UI first, then try to initialize camera
    return Container(
      color: AppThemeColor.pureBlackColor,
      child: FutureBuilder<bool>(
        future: _cameraInitFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  CircularProgressIndicator(color: AppThemeColor.darkBlueColor),
                  const SizedBox(height: 20),
                  Text(
                    'Initializing Camera...',
                    style: TextStyle(
                      color: AppThemeColor.pureWhiteColor,
                      fontSize: Dimensions.fontSizeDefault,
                    ),
                  ),
                ],
              ),
            );
          }

          if (!_isCameraPermissionGranted || snapshot.data == false) {
            return Container(
              color: AppThemeColor.pureBlackColor,
              child: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.camera_alt_outlined,
                      size: 80,
                      color: AppThemeColor.pureWhiteColor.withValues(
                        alpha: 0.5,
                      ),
                    ),
                    const SizedBox(height: 20),
                    Text(
                      'Camera Permission Required',
                      style: TextStyle(
                        color: AppThemeColor.pureWhiteColor,
                        fontSize: Dimensions.fontSizeLarge,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      'Please grant camera permission to scan QR codes',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: AppThemeColor.pureWhiteColor.withValues(
                          alpha: 0.7,
                        ),
                        fontSize: Dimensions.fontSizeDefault,
                      ),
                    ),
                    const SizedBox(height: 30),
                    ElevatedButton(
                      onPressed: () async {
                        await _checkPermissions();
                        if (_isCameraPermissionGranted) {
                          setState(() {
                            // Re-run camera initialization now that permission is granted
                            _cameraInitFuture = _initializeCamera();
                          });
                        } else {
                          // If still no permission, show manual entry option
                          setState(() {
                            _isManualEntry = true;
                          });
                          _animationController.forward();
                        }
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppThemeColor.darkBlueColor,
                        foregroundColor: AppThemeColor.pureWhiteColor,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 30,
                          vertical: 15,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(25),
                        ),
                      ),
                      child: const Text('Grant Permission'),
                    ),
                    const SizedBox(height: 15),
                    TextButton(
                      onPressed: () {
                        setState(() {
                          _isManualEntry = true;
                        });
                        _animationController.forward();
                      },
                      child: Text(
                        'Enter code manually instead',
                        style: TextStyle(
                          color: AppThemeColor.pureWhiteColor.withValues(
                            alpha: 0.8,
                          ),
                          fontSize: Dimensions.fontSizeDefault,
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),
                  ],
                ),
              ),
            );
          }

          // Try to create QR view, but handle errors gracefully
          try {
            return QRView(
              key: qrKey,
              onQRViewCreated: _onQRViewCreated,
              overlay: _buildScannerOverlay(),
            );
          } catch (e) {
            debugPrint('QRView creation failed: $e');
            // Fallback for emulator or camera issues
            return Container(
              color: AppThemeColor.pureBlackColor,
              child: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.qr_code_scanner,
                      size: 80,
                      color: AppThemeColor.pureWhiteColor.withValues(
                        alpha: 0.5,
                      ),
                    ),
                    const SizedBox(height: 20),
                    Text(
                      'QR Scanner Unavailable',
                      style: TextStyle(
                        color: AppThemeColor.pureWhiteColor,
                        fontSize: Dimensions.fontSizeLarge,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      'Camera not available.\nPlease grant camera permission.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: AppThemeColor.pureWhiteColor.withValues(
                          alpha: 0.7,
                        ),
                        fontSize: Dimensions.fontSizeDefault,
                      ),
                    ),
                  ],
                ),
              ),
            );
          }
        },
      ),
    );
  }

  Future<bool> _initializeCamera() async {
    try {
      await _checkPermissions();
      return _isCameraPermissionGranted;
    } catch (e) {
      debugPrint('Camera initialization failed: $e');
      // For emulator, always return false to show demo mode
      return false;
    }
  }

  QrScannerOverlayShape _buildScannerOverlay() {
    return QrScannerOverlayShape(
      borderColor: AppThemeColor.darkBlueColor,
      borderRadius: 20,
      borderLength: 40,
      borderWidth: 8,
      cutOutSize: MediaQuery.of(context).size.width * 0.7,
      cutOutBottomOffset: 100,
    );
  }

  Widget _buildOverlayUI() {
    return AnimatedBuilder(
      animation: _slideAnimation,
      builder: (context, child) {
        return Transform.translate(
          offset: Offset(0, 50 * (1 - _slideAnimation.value)),
          child: Opacity(
            opacity: _slideAnimation.value,
            child: Column(
              children: [
                const Spacer(),
                _buildScannerFrame(),
                const SizedBox(height: 30),
                _buildManualEntrySection(),
                const SizedBox(height: 20),
                _buildActionButtons(),
                const SizedBox(height: 40),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildScannerFrame() {
    return Container(
      padding: const EdgeInsets.all(20),
      child: Column(
        children: [
          // Scanner Frame with Pulse Animation
          AnimatedBuilder(
            animation: _pulseAnimation,
            builder: (context, child) {
              return Transform.scale(
                scale: _pulseAnimation.value,
                child: Container(
                  width: 200,
                  height: 200,
                  decoration: BoxDecoration(
                    border: Border.all(
                      color: AppThemeColor.darkBlueColor.withValues(alpha: 0.3),
                      width: 2,
                    ),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Center(
                    child: Icon(
                      Icons.qr_code_scanner,
                      size: 60,
                      color: AppThemeColor.darkBlueColor.withValues(alpha: 0.5),
                    ),
                  ),
                ),
              );
            },
          ),
          const SizedBox(height: 20),
          Text(
            'Position QR code within frame',
            style: TextStyle(
              color: AppThemeColor.pureWhiteColor,
              fontSize: Dimensions.fontSizeDefault,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            'Or enter code manually below',
            style: TextStyle(
              color: AppThemeColor.pureWhiteColor.withValues(alpha: 0.7),
              fontSize: Dimensions.fontSizeSmall,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildManualEntrySection() {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      height: _isManualEntry ? 135 : 60,
      margin: const EdgeInsets.symmetric(horizontal: 20),
      decoration: BoxDecoration(
        color: AppThemeColor.pureWhiteColor.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(15),
        border: Border.all(
          color: AppThemeColor.pureWhiteColor.withValues(alpha: 0.2),
          width: 1,
        ),
      ),
      child: Column(
        children: [
          // Toggle Button
          InkWell(
            onTap: () {
              setState(() {
                _isManualEntry = !_isManualEntry;
              });
              if (_isManualEntry) {
                _animationController.forward();
              } else {
                _animationController.reverse();
              }
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 15),
              child: Row(
                children: [
                  Icon(
                    _isManualEntry
                        ? Icons.keyboard_arrow_up
                        : Icons.keyboard_arrow_down,
                    color: AppThemeColor.pureWhiteColor,
                    size: 20,
                  ),
                  const SizedBox(width: 10),
                  Text(
                    'Enter Code Manually',
                    style: TextStyle(
                      color: AppThemeColor.pureWhiteColor,
                      fontSize: Dimensions.fontSizeDefault,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const Spacer(),
                  Icon(
                    Icons.edit,
                    color: AppThemeColor.pureWhiteColor.withValues(alpha: 0.7),
                    size: 18,
                  ),
                ],
              ),
            ),
          ),

          // Manual Entry Fields
          if (_isManualEntry) ...[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Column(
                children: [
                  const SizedBox(height: 10),
                  _buildTextField(
                    controller: _codeController,
                    hintText: 'Enter six-character venue code',
                    icon: Icons.qr_code,
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String hintText,
    required IconData icon,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: AppThemeColor.pureWhiteColor,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: AppThemeColor.pureBlackColor.withValues(alpha: 0.1),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: TextFormField(
        controller: controller,
        style: TextStyle(
          color: AppThemeColor.pureBlackColor,
          fontSize: Dimensions.fontSizeDefault,
        ),
        decoration: InputDecoration(
          hintText: hintText,
          hintStyle: TextStyle(
            color: AppThemeColor.dullFontColor,
            fontSize: Dimensions.fontSizeDefault,
          ),
          prefixIcon: Icon(icon, color: AppThemeColor.darkBlueColor, size: 20),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide.none,
          ),
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 14,
          ),
          filled: true,
          fillColor: AppThemeColor.pureWhiteColor,
        ),
      ),
    );
  }

  Widget _buildActionButtons() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Row(
        children: [
          // Flash Toggle
          Expanded(
            child: _buildActionButton(
              icon: _isFlashOn ? Icons.flash_on : Icons.flash_off,
              label: 'Flash',
              onTap: _toggleFlash,
              isActive: _isFlashOn,
            ),
          ),
          const SizedBox(width: 15),
          // Sign In Button
          Expanded(flex: 2, child: _buildSignInButton()),
        ],
      ),
    );
  }

  Widget _buildActionButton({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    bool isActive = false,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: isActive
              ? AppThemeColor.darkBlueColor
              : AppThemeColor.pureWhiteColor.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isActive
                ? AppThemeColor.darkBlueColor
                : AppThemeColor.pureWhiteColor.withValues(alpha: 0.3),
            width: 1,
          ),
        ),
        child: Column(
          children: [
            Icon(
              icon,
              color: isActive
                  ? AppThemeColor.pureWhiteColor
                  : AppThemeColor.pureWhiteColor.withValues(alpha: 0.8),
              size: 20,
            ),
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(
                color: isActive
                    ? AppThemeColor.pureWhiteColor
                    : AppThemeColor.pureWhiteColor.withValues(alpha: 0.8),
                fontSize: Dimensions.fontSizeSmall,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSignInButton() {
    return GestureDetector(
      onTap: _handleSignIn,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 15),
        decoration: BoxDecoration(
          gradient: AppThemeColor.buttonGradient,
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
              color: AppThemeColor.darkBlueColor.withValues(alpha: 0.3),
              blurRadius: 8,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              'Continue',
              style: TextStyle(
                color: AppThemeColor.pureWhiteColor,
                fontSize: Dimensions.fontSizeDefault,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAppBar() {
    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 15),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              AppThemeColor.pureBlackColor.withValues(alpha: 0.8),
              AppThemeColor.pureBlackColor.withValues(alpha: 0.0),
            ],
          ),
        ),
        child: Row(
          children: [
            GestureDetector(
              onTap: () {
                // Safely navigate back without result
                Navigator.of(context).pop();
              },
              child: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppThemeColor.pureWhiteColor.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  Icons.arrow_back_ios,
                  color: AppThemeColor.pureWhiteColor,
                  size: 20,
                ),
              ),
            ),
            const Spacer(),
            Text(
              'QR Scanner',
              style: TextStyle(
                color: AppThemeColor.pureWhiteColor,
                fontSize: Dimensions.fontSizeLarge,
                fontWeight: FontWeight.w600,
              ),
            ),
            const Spacer(),
            Container(width: 40),
          ],
        ),
      ),
    );
  }

  void _toggleFlash() {
    setState(() {
      _isFlashOn = !_isFlashOn;
    });
    controller?.toggleFlash();
  }

  void _onQRViewCreated(QRViewController controller) {
    setState(() {
      this.controller = controller;
    });

    controller.scannedDataStream.listen((scanData) async {
      if (scanData.code != null) {
        final scannedCode = scanData.code!;

        // Use debug helper to log scan results
        QRDebugHelper.logQRScanResult(scannedCode);

        // Handle different QR code formats
        String? eventCode;

        // Attendance 2.0 keeps venue credentials and event-share links
        // distinct. Only the rotating venue credential can record attendance.
        if (scannedCode.startsWith('attendus_checkin:v1:')) {
          eventCode = scannedCode;
          debugPrint('Rotating venue credential detected');
        } else if (scannedCode.startsWith('attendus_event:v1:')) {
          eventCode = scannedCode;
          debugPrint('Permanent event-share QR detected');
        }
        // Legacy static event QRs now open event details and never check in.
        else if (scannedCode.contains('orgami_app_code_')) {
          final legacyId = scannedCode.split('orgami_app_code_').last;
          eventCode = 'attendus_event:v1:$legacyId';
          debugPrint('Legacy event-share QR detected: $legacyId');
        }
        // Check for ticket QR code format
        else if (scannedCode.startsWith('orgami_ticket_')) {
          final parts = scannedCode.split('_');
          if (parts.length >= 4) {
            ShowToast().showNormalToast(
              msg: 'Show this personal ticket to event staff for scanning.',
            );
            return;
          }
        }
        // Check for user badge QR code format
        else if (scannedCode.startsWith('attendus_user_')) {
          ShowToast().showNormalToast(
            msg: 'This is a user badge QR code. Please scan an event QR code.',
          );
          return;
        }

        if (eventCode != null) {
          _codeController.text = eventCode;
          setState(() {
            result = scanData;
          });

          // Haptic feedback
          HapticFeedback.lightImpact();

          // Return the scanned code to the previous screen
          if (!mounted) return;
          Navigator.of(context).pop(eventCode);
        } else {
          ShowToast().showNormalToast(
            msg: 'Invalid QR code format. Please scan a valid event QR code.',
          );
        }
      }
    });
  }

  Future<void> _handleSignIn() async {
    if (_codeController.text.isEmpty) {
      ShowToast().showNormalToast(msg: 'Enter the six-character venue code.');
      return;
    }
    HapticFeedback.lightImpact();
    Navigator.of(context).pop(_codeController.text.trim().toUpperCase());
  }

  @override
  void dispose() {
    _animationController.dispose();
    _pulseController.dispose();
    _codeController.dispose();
    super.dispose();
  }

  @override
  void deactivate() {
    // Pause camera when screen is deactivated
    controller?.pauseCamera();
    super.deactivate();
  }

  @override
  void reassemble() {
    super.reassemble();
    // Resume camera when screen is reassembled
    if (Platform.isAndroid) {
      controller?.pauseCamera();
    }
    controller?.resumeCamera();
  }
}
