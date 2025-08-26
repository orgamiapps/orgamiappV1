import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:orgami/Utils/colors.dart';
import 'package:orgami/Utils/dimensions.dart';
import 'package:orgami/Utils/toast.dart';

class QRCodeGeneratorScreen extends StatefulWidget {
  final String eventId;
  final String eventName;

  const QRCodeGeneratorScreen({
    super.key,
    required this.eventId,
    required this.eventName,
  });

  @override
  State<QRCodeGeneratorScreen> createState() => _QRCodeGeneratorScreenState();
}

class _QRCodeGeneratorScreenState extends State<QRCodeGeneratorScreen>
    with TickerProviderStateMixin {
  late AnimationController _animationController;
  late Animation<double> _scaleAnimation;
  late Animation<double> _fadeAnimation;

  @override
  void initState() {
    super.initState();
    _initializeAnimations();
  }

  void _initializeAnimations() {
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 800),
      vsync: this,
    );

    _scaleAnimation = Tween<double>(begin: 0.5, end: 1.0).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.elasticOut),
    );

    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeInOut),
    );

    _animationController.forward();
  }

  String get _qrCodeData => 'orgami_app_code_${widget.eventId}';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppThemeColor.pureBlackColor,
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(),
            Expanded(child: _buildQRCodeContent()),
            _buildActionButtons(),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.all(20),
      child: Row(
        children: [
          GestureDetector(
            onTap: () => Navigator.of(context).pop(),
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
            'QR Code',
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
    );
  }

  Widget _buildQRCodeContent() {
    return AnimatedBuilder(
      animation: _animationController,
      builder: (context, child) {
        return Transform.scale(
          scale: _scaleAnimation.value,
          child: Opacity(
            opacity: _fadeAnimation.value,
            child: Container(
              padding: const EdgeInsets.all(30),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // Event Info Card
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: AppThemeColor.pureWhiteColor.withValues(
                        alpha: 0.1,
                      ),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: AppThemeColor.pureWhiteColor.withValues(
                          alpha: 0.2,
                        ),
                      ),
                    ),
                    child: Column(
                      children: [
                        Icon(
                          Icons.event,
                          color: AppThemeColor.darkBlueColor,
                          size: 40,
                        ),
                        const SizedBox(height: 15),
                        Text(
                          widget.eventName,
                          style: TextStyle(
                            color: AppThemeColor.pureWhiteColor,
                            fontSize: Dimensions.fontSizeLarge,
                            fontWeight: FontWeight.w600,
                          ),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 10),
                        Text(
                          'Event Code: ${widget.eventId}',
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
                  const SizedBox(height: 40),

                  // QR Code Container
                  Container(
                    padding: const EdgeInsets.all(30),
                    decoration: BoxDecoration(
                      color: AppThemeColor.pureWhiteColor,
                      borderRadius: BorderRadius.circular(25),
                      boxShadow: [
                        BoxShadow(
                          color: AppThemeColor.pureBlackColor.withValues(
                            alpha: 0.2,
                          ),
                          blurRadius: 20,
                          offset: const Offset(0, 10),
                        ),
                      ],
                    ),
                    child: Column(
                      children: [
                        QrImageView(
                          data: _qrCodeData,
                          version: QrVersions.auto,
                          size: 200,
                          backgroundColor: AppThemeColor.pureWhiteColor,
                          eyeStyle: QrEyeStyle(
                            eyeShape: QrEyeShape.square,
                            color: AppThemeColor.pureBlackColor,
                          ),
                          dataModuleStyle: QrDataModuleStyle(
                            dataModuleShape: QrDataModuleShape.square,
                            color: AppThemeColor.pureBlackColor,
                          ),
                          errorCorrectionLevel: QrErrorCorrectLevel.H,
                        ),
                        const SizedBox(height: 20),
                        Text(
                          'Scan this QR code to sign in',
                          style: TextStyle(
                            color: AppThemeColor.pureBlackColor,
                            fontSize: Dimensions.fontSizeDefault,
                            fontWeight: FontWeight.w500,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 30),

                  // Instructions
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: AppThemeColor.darkBlueColor.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(15),
                      border: Border.all(
                        color: AppThemeColor.darkBlueColor.withValues(
                          alpha: 0.3,
                        ),
                      ),
                    ),
                    child: Column(
                      children: [
                        Row(
                          children: [
                            Icon(
                              Icons.info_outline,
                              color: AppThemeColor.darkBlueColor,
                              size: 20,
                            ),
                            const SizedBox(width: 10),
                            Text(
                              'Instructions',
                              style: TextStyle(
                                color: AppThemeColor.darkBlueColor,
                                fontSize: Dimensions.fontSizeDefault,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 15),
                        _buildInstructionItem(
                          icon: Icons.qr_code_scanner,
                          text:
                              'Attendees can scan this QR code with their phone camera',
                        ),
                        const SizedBox(height: 8),
                        _buildInstructionItem(
                          icon: Icons.phone_android,
                          text:
                              'Or they can enter the event code manually in the app',
                        ),
                        const SizedBox(height: 8),
                        _buildInstructionItem(
                          icon: Icons.check_circle,
                          text:
                              'Once scanned, they\'ll be automatically signed in',
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildInstructionItem({required IconData icon, required String text}) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(
          icon,
          color: AppThemeColor.darkBlueColor.withValues(alpha: 0.7),
          size: 16,
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            text,
            style: TextStyle(
              color: AppThemeColor.darkBlueColor.withValues(alpha: 0.8),
              fontSize: Dimensions.fontSizeSmall,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildActionButtons() {
    return Container(
      padding: const EdgeInsets.all(30),
      child: Column(
        children: [
          // Share QR Code Button
          GestureDetector(
            onTap: _shareQRCode,
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 18),
              decoration: BoxDecoration(
                gradient: AppThemeColor.buttonGradient,
                borderRadius: BorderRadius.circular(15),
                boxShadow: [
                  BoxShadow(
                    color: AppThemeColor.darkBlueColor.withValues(alpha: 0.3),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.share,
                    color: AppThemeColor.pureWhiteColor,
                    size: 20,
                  ),
                  const SizedBox(width: 10),
                  Text(
                    'Share QR Code',
                    style: TextStyle(
                      color: AppThemeColor.pureWhiteColor,
                      fontSize: Dimensions.fontSizeLarge,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 15),

          // Copy Event Code Button
          GestureDetector(
            onTap: _copyEventCode,
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 16),
              decoration: BoxDecoration(
                color: AppThemeColor.pureWhiteColor.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(15),
                border: Border.all(
                  color: AppThemeColor.pureWhiteColor.withValues(alpha: 0.3),
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.copy,
                    color: AppThemeColor.pureWhiteColor,
                    size: 20,
                  ),
                  const SizedBox(width: 10),
                  Text(
                    'Copy Event Code',
                    style: TextStyle(
                      color: AppThemeColor.pureWhiteColor,
                      fontSize: Dimensions.fontSizeDefault,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _shareQRCode() {
    // In a real implementation, you would use a sharing plugin
    // For now, we'll just copy the QR code data to clipboard
    Clipboard.setData(ClipboardData(text: _qrCodeData));
    ShowToast().showNormalToast(msg: 'QR code data copied to clipboard!');
  }

  void _copyEventCode() {
    Clipboard.setData(ClipboardData(text: widget.eventId));
    ShowToast().showNormalToast(msg: 'Event code copied to clipboard!');
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }
}
