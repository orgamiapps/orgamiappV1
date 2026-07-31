import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:attendus/Utils/colors.dart';
import 'package:attendus/Utils/toast.dart';
import 'package:attendus/widgets/attendus_design_system.dart';

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
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
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
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(20),
      child: Row(
        children: [
          GestureDetector(
            onTap: () => Navigator.of(context).pop(),
            child: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                Icons.arrow_back_ios,
                color: theme.colorScheme.onSurface,
                size: 20,
              ),
            ),
          ),
          const Spacer(),
          Text('Check-in QR code', style: theme.textTheme.titleLarge),
          const Spacer(),
          Container(width: 40),
        ],
      ),
    );
  }

  Widget _buildQRCodeContent() {
    final theme = Theme.of(context);
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
                  AttendUsCard(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      children: [
                        Icon(
                          Icons.event,
                          color: theme.colorScheme.primary,
                          size: 40,
                        ),
                        const SizedBox(height: 15),
                        Text(
                          widget.eventName,
                          style: theme.textTheme.titleMedium,
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 10),
                        Text(
                          'Event Code: ${widget.eventId}',
                          style: theme.textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 40),

                  // QR Code Container
                  AttendUsCard(
                    padding: const EdgeInsets.all(30),
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
                          style: theme.textTheme.bodyMedium,
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 30),

                  // Instructions
                  AttendUsCard(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      children: [
                        Row(
                          children: [
                            Icon(
                              Icons.info_outline,
                              color: theme.colorScheme.primary,
                              size: 20,
                            ),
                            const SizedBox(width: 10),
                            Text(
                              'Instructions',
                              style: theme.textTheme.titleSmall,
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
    final theme = Theme.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: theme.colorScheme.primary, size: 16),
        const SizedBox(width: 10),
        Expanded(child: Text(text, style: theme.textTheme.bodySmall)),
      ],
    );
  }

  Widget _buildActionButtons() {
    return Container(
      padding: const EdgeInsets.all(30),
      child: Column(
        children: [
          SizedBox(
            width: double.infinity,
            child: AttendUsButton.primary(
              label: 'Share QR Code',
              icon: Icons.share_outlined,
              onPressed: _shareQRCode,
            ),
          ),
          const SizedBox(height: 15),
          SizedBox(
            width: double.infinity,
            child: AttendUsButton.secondary(
              label: 'Copy Event Code',
              icon: Icons.copy_outlined,
              onPressed: _copyEventCode,
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
