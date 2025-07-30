import 'dart:io';

import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:orgami/Models/EventModel.dart';
import 'package:orgami/Utils/Colors.dart';
import 'package:orgami/Utils/dimensions.dart';
import 'package:path_provider/path_provider.dart';
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

class _ShareQRDialogState extends State<ShareQRDialog> {
  late final EventModel singleEvent = widget.singleEvent;
  late double _screenWidth;
  late double _screenHeight;
  final _btnCtlr = RoundedLoadingButtonController();
  File? imageMade;
  ScreenshotController screenshotController = ScreenshotController();

  @override
  Widget build(BuildContext context) {
    _screenHeight = MediaQuery.of(context).size.height;
    _screenWidth = MediaQuery.of(context).size.width;

    return Scaffold(
        backgroundColor: const Color(0x998F8F8F),
        body: SafeArea(
          child: _bodyView(context: context),
        ));
  }

  Widget _bodyView({required BuildContext context}) {
    return Center(
      child: Container(
        width: _screenWidth / 1.1,
        height: 490,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(24),
        ),
        padding: const EdgeInsets.all(20),
        child: Stack(
          children: [
            Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(24),
              ),
              width: _screenWidth / 1.3,
              padding: const EdgeInsets.only(
                  top: 40, bottom: 15, left: 20, right: 20),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  // Image.asset(
                  //   Images.successfulImage,
                  //   width: 180,
                  // ),
                  Screenshot(
                    controller: screenshotController,
                    child: SizedBox(
                      width: 180,
                      height: 180,
                      child: QrImageView(
                        data: 'orgami_app_code_${singleEvent.id}',
                        version: QrVersions.auto,
                        size: 320,
                        gapless: false,
                      ),
                    ),
                  ),
                  const SizedBox(
                    height: 20,
                  ),
                  const Text(
                    'Share QR',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.w700,
                      color: Colors.purple,
                    ),
                  ),
                  const SizedBox(
                    height: 10,
                  ),
                  Text(
                    'Unique ID:${singleEvent.id}',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: Dimensions.fontSizeDefault,
                      fontWeight: FontWeight.w400,
                      color: Colors.purple,
                    ),
                  ),
                  const SizedBox(
                    height: 10,
                  ),
                  const Text(
                    'You can Download and Share this QR',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w400,
                      color: Colors.black,
                    ),
                  ),
                  SizedBox(
                    height: 15,
                    child:
                        imageMade != null ? Image.file(imageMade!) : SizedBox(),
                  ),
                  RoundedLoadingButton(
                    animateOnTap: false,
                    borderRadius: 5,
                    controller: _btnCtlr,
                    onPressed: () {
                      try {
                        _btnCtlr.start();
                        screenshotController.capture().then((capturedQR) async {
                          final directoryPath =
                              (await getTemporaryDirectory()).path;
                          final imagePath = '$directoryPath/qrimg.png';
                          final imageFile =
                              await File(imagePath).create(recursive: true);
                          imageFile.writeAsBytesSync(capturedQR!);

                          final file = XFile(imagePath);
                          await Share.shareXFiles([file]).then((value) {
                            _btnCtlr.reset();
                          });
                        }).catchError((onError) {
                          print(onError);
                          _btnCtlr.reset();
                        });
                      } catch (e) {
                        _btnCtlr.reset();
                      }
                    },
                    color: AppThemeColor.darkGreenColor,
                    elevation: 0,
                    child: const Wrap(
                      children: [
                        Text(
                          'Share',
                          style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                              color: Colors.white),
                        )
                      ],
                    ),
                  ),
                ],
              ),
            ),
            Positioned(
              right: 20,
              child: IconButton(
                icon: const Icon(FontAwesomeIcons.xmark),
                onPressed: () {
                  Navigator.pop(context);
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
