import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:attendus/models/event_model.dart';
import 'package:attendus/Utils/colors.dart';
import 'package:attendus/Utils/toast.dart';
import 'package:attendus/Utils/logger.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:rounded_loading_button_plus/rounded_loading_button.dart';
import 'package:screenshot/screenshot.dart';
import 'package:share_plus/share_plus.dart';

class ShareQRDialog extends StatefulWidget {
  final EventModel singleEvent;

  const ShareQRDialog({super.key, required this.singleEvent});

  @override
  State<ShareQRDialog> createState() => _ShareQRDialogState();
}

class _ShareQRDialogState extends State<ShareQRDialog>
    with TickerProviderStateMixin {
  late final EventModel singleEvent = widget.singleEvent;
  late double _screenWidth;
  late double _screenHeight;
  final _btnCtlr = RoundedLoadingButtonController();
  final _downloadBtnCtlr = RoundedLoadingButtonController();
  final _copyBtnCtlr = RoundedLoadingButtonController();

  File? imageMade;
  ScreenshotController screenshotController = ScreenshotController();
  late AnimationController _animationController;
  late Animation<double> _scaleAnimation;
  late Animation<double> _fadeAnimation;

  String get qrData =>
      'orgami_app_code_${singleEvent.isSignInMethodEnabled('manual_code') ? singleEvent.getManualCode() : singleEvent.id}';
  String get uniqueId => singleEvent.displayId;
  String get rawUniqueId => singleEvent.rawId;
  String get eventTitle => singleEvent.title;
  String get eventLocation => singleEvent.location;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );
    _scaleAnimation = Tween<double>(begin: 0.8, end: 1.0).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeOutBack),
    );
    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeOut),
    );
    _animationController.forward();
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    _screenHeight = MediaQuery.of(context).size.height;
    _screenWidth = MediaQuery.of(context).size.width;

    return Scaffold(
      backgroundColor: Colors.black.withValues(alpha: 0.5),
      body: SafeArea(child: _bodyView(context: context)),
    );
  }

  Widget _bodyView({required BuildContext context}) {
    return AnimatedBuilder(
      animation: _animationController,
      builder: (context, child) {
        return FadeTransition(
          opacity: _fadeAnimation,
          child: ScaleTransition(
            scale: _scaleAnimation,
            child: Center(
              child: Container(
                width: _screenWidth * 0.9,
                constraints: BoxConstraints(
                  maxHeight: _screenHeight * 0.85,
                  minHeight: 400,
                ),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(24),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.1),
                      blurRadius: 20,
                      offset: const Offset(0, 10),
                    ),
                  ],
                ),
                child: Flexible(
                  child: SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _buildHeader(),
                        _buildQRContent(),
                        _buildActionButtons(),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [AppThemeColor.darkBlueColor, AppThemeColor.darkGreenColor],
        ),
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(24),
          topRight: Radius.circular(24),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Share QR Code & Event ID',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  eventTitle,
                  style: const TextStyle(fontSize: 13, color: Colors.white70),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          IconButton(
            onPressed: () => Navigator.pop(context),
            icon: const Icon(Icons.close, color: Colors.white, size: 22),
            style: IconButton.styleFrom(
              backgroundColor: Colors.white.withValues(alpha: 0.2),
              shape: const CircleBorder(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildQRContent() {
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        children: [
          // QR Code Container
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.grey[50],
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.grey[200]!),
            ),
            child: Screenshot(
              controller: screenshotController,
              child: Column(
                children: [
                  // Event Info
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.grey[200]!),
                    ),
                    child: Column(
                      children: [
                        Text(
                          eventTitle,
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                            color: AppThemeColor.darkBlueColor,
                          ),
                          textAlign: TextAlign.center,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 4),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(
                              Icons.location_on,
                              size: 12,
                              color: AppThemeColor.dullFontColor,
                            ),
                            const SizedBox(width: 4),
                            Expanded(
                              child: Text(
                                eventLocation,
                                style: const TextStyle(
                                  fontSize: 11,
                                  color: AppThemeColor.dullFontColor,
                                ),
                                textAlign: TextAlign.center,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  // QR Code
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.grey[200]!),
                    ),
                    child: QrImageView(
                      data: qrData,
                      version: QrVersions.auto,
                      size: 160,
                      gapless: false,
                      backgroundColor: Colors.white,
                      eyeStyle: QrEyeStyle(
                        eyeShape: QrEyeShape.square,
                        color: AppThemeColor.darkBlueColor,
                      ),
                      dataModuleStyle: QrDataModuleStyle(
                        dataModuleShape: QrDataModuleShape.square,
                        color: AppThemeColor.darkBlueColor,
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  // Unique ID
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: AppThemeColor.lightBlueColor,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: AppThemeColor.darkBlueColor.withValues(
                          alpha: 0.3,
                        ),
                      ),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(
                          Icons.fingerprint,
                          size: 14,
                          color: AppThemeColor.darkBlueColor,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          'ID: $uniqueId',
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: AppThemeColor.darkBlueColor,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          // Instructions
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppThemeColor.lightBlueColor.withValues(alpha: 0.3),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.info_outline,
                  color: AppThemeColor.darkBlueColor,
                  size: 18,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Scan this QR code or use the Event ID to join the event',
                    style: TextStyle(
                      fontSize: 13,
                      color: AppThemeColor.darkBlueColor.withValues(alpha: 0.8),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActionButtons() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
      child: Column(
        children: [
          // Primary Share Button
          SizedBox(
            width: double.infinity,
            height: 50,
            child: RoundedLoadingButton(
              animateOnTap: false,
              borderRadius: 16,
              controller: _btnCtlr,
              onPressed: _shareQRCode,
              color: AppThemeColor.darkGreenColor,
              elevation: 0,
              child: const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.share_rounded, color: Colors.white, size: 18),
                  SizedBox(width: 8),
                  Text(
                    'Share QR & ID',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: Colors.white,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 10),
          // Secondary Actions Row
          Row(
            children: [
              Expanded(
                child: SizedBox(
                  height: 44,
                  child: RoundedLoadingButton(
                    animateOnTap: false,
                    borderRadius: 12,
                    controller: _downloadBtnCtlr,
                    onPressed: _downloadQRCode,
                    color: Colors.grey[100]!,
                    elevation: 0,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.download_rounded,
                          color: AppThemeColor.darkBlueColor,
                          size: 16,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          'Save',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: AppThemeColor.darkBlueColor,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: SizedBox(
                  height: 44,
                  child: RoundedLoadingButton(
                    animateOnTap: false,
                    borderRadius: 12,
                    controller: _copyBtnCtlr,
                    onPressed: _copyEventData,
                    color: Colors.grey[100]!,
                    elevation: 0,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.copy_rounded,
                          color: AppThemeColor.darkBlueColor,
                          size: 16,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          'Copy ID',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: AppThemeColor.darkBlueColor,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _shareQRCode() async {
    try {
      HapticFeedback.lightImpact();
      _btnCtlr.start();

      final capturedQR = await screenshotController.capture();
      if (capturedQR == null) {
        _btnCtlr.reset();
        return;
      }

      final directoryPath = (await getTemporaryDirectory()).path;
      final imagePath = '$directoryPath/event_qr_$uniqueId.png';
      final imageFile = await File(imagePath).create(recursive: true);
      imageFile.writeAsBytesSync(capturedQR);

      final file = XFile(imagePath);
      await Share.shareXFiles(
        [file],
        text: 'Join my event: $eventTitle\nLocation: $eventLocation\nEvent ID: $uniqueId',
        subject: 'Event QR Code - $eventTitle',
      );

      _btnCtlr.reset();
    } catch (e) {
      Logger.error('Error sharing QR code: $e');
      _btnCtlr.reset();
    }
  }

  Future<void> _downloadQRCode() async {
    try {
      HapticFeedback.lightImpact();
      _downloadBtnCtlr.start();

      // Check storage permission
      var status = await Permission.storage.status;
      if (status.isDenied) {
        status = await Permission.storage.request();
        if (status.isDenied) {
          if (mounted) {
            ShowToast().showSnackBar(
              'Storage permission is required to save QR code',
              context,
            );
          }
          _downloadBtnCtlr.reset();
          return;
        }
      }

      final capturedQR = await screenshotController.capture();
      if (capturedQR == null) {
        _downloadBtnCtlr.reset();
        return;
      }

      // Save to gallery directory
      final directoryPath = (await getApplicationDocumentsDirectory()).path;
      final imagePath = '$directoryPath/event_qr_$uniqueId.png';
      final imageFile = await File(imagePath).create(recursive: true);
      imageFile.writeAsBytesSync(capturedQR);

      // Show success message
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                Icon(Icons.check_circle, color: Colors.white, size: 20),
                const SizedBox(width: 8),
                const Text('QR code saved successfully'),
              ],
            ),
            backgroundColor: AppThemeColor.darkGreenColor,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
            duration: const Duration(seconds: 2),
          ),
        );
      }

      _downloadBtnCtlr.reset();
    } catch (e) {
      Logger.error('Error downloading QR code: $e');
      if (mounted) {
        ShowToast().showSnackBar(
          'Failed to save QR code. Please try again.',
          context,
        );
      }
      _downloadBtnCtlr.reset();
    }
  }

  Future<void> _copyEventData() async {
    try {
      HapticFeedback.lightImpact();
      _copyBtnCtlr.start();

      final eventData =
          '''
Event: $eventTitle
Location: $eventLocation
Event ID: $rawUniqueId
QR Data: $qrData
      '''
              .trim();

      await Clipboard.setData(ClipboardData(text: eventData));

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                Icon(Icons.check_circle, color: Colors.white, size: 20),
                const SizedBox(width: 8),
                const Text('Event details copied to clipboard'),
              ],
            ),
            backgroundColor: AppThemeColor.darkBlueColor,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
            duration: const Duration(seconds: 2),
          ),
        );
      }

      _copyBtnCtlr.reset();
    } catch (e) {
      Logger.error('Error copying event data: $e');
      _copyBtnCtlr.reset();
    }
  }
}
