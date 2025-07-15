import 'dart:developer';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:orgami/Firebase/FirebaseFirestoreHelper.dart';
import 'package:orgami/Models/AttendanceModel.dart';
import 'package:orgami/Permissions/PermssionsHelper.dart';
import 'package:orgami/Screens/QRScanner/AnsQuestionsToSignInEventScreen.dart';
import 'package:orgami/Screens/Splash/SecondSplashScreen.dart';
import 'package:orgami/Utils/AppAppBarView.dart';
import 'package:orgami/Utils/AppButtons.dart';
import 'package:orgami/Utils/Colors.dart';
import 'package:orgami/Utils/Router.dart';
import 'package:orgami/Utils/Toast.dart';
import 'package:orgami/Utils/dimensions.dart';
import 'package:qr_code_scanner_plus/qr_code_scanner_plus.dart';

class QRScannerWithoutLoginScreen extends StatefulWidget {
  const QRScannerWithoutLoginScreen({super.key});

  @override
  State<StatefulWidget> createState() => _QRScannerWithoutLoginScreenState();
}

class _QRScannerWithoutLoginScreenState
    extends State<QRScannerWithoutLoginScreen> {
  Barcode? result;
  QRViewController? controller;
  final GlobalKey qrKey = GlobalKey(debugLabel: 'QR');

  final TextEditingController _codeController = TextEditingController();
  final TextEditingController _nameController = TextEditingController();

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
    if (Platform.isAndroid) {
      controller!.pauseCamera();
    }
    controller!.resumeCamera();
  }

  late double _screenWidth;
  late double _screenHeight;

  @override
  Widget build(BuildContext context) {
    _screenWidth = MediaQuery.of(context).size.width;
    _screenHeight = MediaQuery.of(context).size.height;
    return Scaffold(
      body: Stack(
        children: [
          SizedBox(
            height: _screenHeight,
            width: _screenWidth,
            child: _buildQrView(context),
          ),
          _bodyView(),
          _fieldsView(),
          AppAppBarView.appBarWithOnlyBackButton(context: context),
        ],
      ),
    );
  }

  Widget _fieldsView() {
    return Container(
      height: _screenHeight - 50,
      width: _screenWidth,
      padding: const EdgeInsets.symmetric(horizontal: 20),
      margin: const EdgeInsets.only(top: 40),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Column(
            mainAxisAlignment: MainAxisAlignment.start,
            children: [
              const Text(
                'Sign In to your Event',
                style: TextStyle(
                  color: AppThemeColor.darkBlueColor,
                  fontSize: Dimensions.paddingSizeLarge,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(
                height: 20,
              ),
              const Text(
                'Input Code',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: AppThemeColor.pureWhiteColor,
                  fontSize: 13,
                  fontWeight: FontWeight.w400,
                ),
              ),
              Container(
                decoration: BoxDecoration(
                  color: AppThemeColor.pureWhiteColor,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: TextFormField(
                  controller: _codeController,
                  decoration: const InputDecoration(
                    hintText: 'Input Code here...',
                    contentPadding:
                        EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                    border: OutlineInputBorder(),
                  ),
                ),
              ),
              const Text(
                'Enter Your First and Last Name',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: AppThemeColor.pureWhiteColor,
                  fontSize: 13,
                  fontWeight: FontWeight.w400,
                ),
              ),
              Container(
                decoration: BoxDecoration(
                  color: AppThemeColor.pureWhiteColor,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: TextFormField(
                  controller: _nameController,
                  decoration: const InputDecoration(
                    hintText: 'type here....',
                    contentPadding:
                        EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                    border: OutlineInputBorder(),
                  ),
                ),
              ),
            ],
          ),
          _signinToEventButton(),
        ],
      ),
    );
  }

  Widget _signinToEventButton() {
    return Padding(
      padding: const EdgeInsets.all(20.0),
      child: GestureDetector(
        onTap: () {
          String docId = FirebaseFirestore.instance
              .collection(AttendanceModel.firebaseKey)
              .doc()
              .id;
          AttendanceModel newAttendanceModel = AttendanceModel(
            id: docId,
            eventId: _codeController.text,
            userName: _nameController.text,
            customerUid: 'without_login',
            attendanceDateTime: DateTime.now(),
            answers: [],
          );

          FirebaseFirestoreHelper()
              .getSingleEvent(newAttendanceModel.eventId)
              .then((eventExist) {
            if (eventExist != null) {
              _codeController.text = '';
              RouterClass.nextScreenAndReplacement(
                context,
                AnsQuestionsToSignInEventScreen(
                  eventModel: eventExist,
                  newAttendance: newAttendanceModel,
                  nextPageRoute: 'withoutLogin',
                  //   nextPageRoute: () => RouterClass.nextScreenAndReplacement(
                  //       context, SingleEventScreen(eventModel: eventExist)),
                ),
              );

              // FirebaseFirestore.instance
              //     .collection(AttendanceModel.firebaseKey)
              //     .doc(docId)
              //     .set(newAttendanceMode.toJson())
              //     .then((value) {
              //   ShowToast().showSnackBar('Signed In Successful!', context);
              //   RouterClass.nextScreenNormal(
              //       context, SingleEventScreen(eventModel: eventExist));
              // });
            } else {
              ShowToast().showNormalToast(msg: 'Entered an incorrect code!');
            }
          });
        },
        child: AppButtons.button1(
          width: _screenWidth,
          height: 50,
          buttonLoading: false,
          label: 'Sign In',
          labelSize: Dimensions.fontSizeLarge,
        ),
      ),
    );
  }

  Widget _bodyView() {
    return const Column(
      children: [
        // const Text(
        //   'Scan The QR app will detect Event Automatically',
        //   textAlign: TextAlign.center,
        //   style: TextStyle(
        //     color: AppThemeColor.pureWhiteColor,
        //     fontSize: 13,
        //     fontWeight: FontWeight.w400,
        //   ),
        // ),
      ],
    );
  }

  Widget _buildQrView(BuildContext context) {
    // For this example we check how width or tall the device is and change the scanArea and overlay accordingly.
    var scanArea = (MediaQuery.of(context).size.width < 400 ||
            MediaQuery.of(context).size.height < 400)
        ? 150.0
        : 300.0;
    // To ensure the Scanner view is properly sizes after rotation
    // we need to listen for Flutter SizeChanged notification and update controller
    return QRView(
      key: qrKey,
      onQRViewCreated: _onQRViewCreated,
      overlay: QrScannerOverlayShape(
          borderColor: Colors.red,
          borderRadius: 10,
          borderLength: 30,
          borderWidth: 10,
          cutOutSize: scanArea),
      // onPermissionSet: (ctrl, p) => _onPermissionSet(context, ctrl, p),
    );
  }

  void _onQRViewCreated(QRViewController controller) {
    setState(() {
      this.controller = controller;
    });
    controller.scannedDataStream.listen((scanData) async {
      print('scan Data is ${scanData.code}');

      if (scanData.code!.contains('orgami_app_code_')) {
        _codeController.text = scanData.code!.split('orgami_app_code_').last;
        setState(() {
          result = scanData;
        });
      }
    });
  }

  void _onPermissionSet(BuildContext context, QRViewController ctrl, bool p) {
    log('${DateTime.now().toIso8601String()}_onPermissionSet $p');
    int indexInt = 0;
    if (!p) {
      if (indexInt == 0) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text(
                  'Don\'t have camera permission  Please Allow that First')),
        );
        RouterClass.nextScreenAndReplacementAndRemoveUntil(
          context: context,
          page: const SecondSplashScreen(),
        );
        indexInt++;
      }
    }
  }

  @override
  void dispose() {
    controller?.dispose();
    super.dispose();
  }
}
