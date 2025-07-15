import 'dart:io';

import 'package:flutter/material.dart';
import 'package:orgami/Controller/CustomerController.dart';
import 'package:orgami/Firebase/FirebaseFirestoreHelper.dart';
import 'package:orgami/Models/AttendanceModel.dart';
import 'package:orgami/Permissions/PermssionsHelper.dart';
import 'package:orgami/Screens/QRScanner/AnsQuestionsToSignInEventScreen.dart';
import 'package:orgami/Utils/AppButtons.dart';
import 'package:orgami/Utils/Colors.dart';
import 'package:orgami/Utils/Router.dart';
import 'package:orgami/Utils/Toast.dart';
import 'package:orgami/Utils/dimensions.dart';
import 'package:qr_code_scanner_plus/qr_code_scanner_plus.dart';

class QRScannerScreen extends StatefulWidget {
  const QRScannerScreen({super.key});

  @override
  State<StatefulWidget> createState() => _QRScannerScreenState();
}

class _QRScannerScreenState extends State<QRScannerScreen> {
  Barcode? result;
  QRViewController? controller;
  final GlobalKey qrKey = GlobalKey(debugLabel: 'QR');

  final TextEditingController _codeController = TextEditingController();

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
      body: SafeArea(
        child: Column(
          children: [
            Stack(
              children: [
                SizedBox(
                  height: _screenHeight - 110,
                  width: _screenWidth,
                  child: _buildQrView(context),
                ),
                // _bodyView(),
                _fieldsView(),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _fieldsView() {
    return Container(
      height: _screenHeight - 210,
      width: _screenWidth,
      padding: const EdgeInsets.symmetric(horizontal: 20),
      margin: const EdgeInsets.only(top: 20),
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
          String docId =
              '${_codeController.text}-${CustomerController.logeInCustomer!.uid}';
          AttendanceModel newAttendanceModel = AttendanceModel(
              id: docId,
              eventId: _codeController.text,
              userName: CustomerController.logeInCustomer!.name,
              customerUid: CustomerController.logeInCustomer!.uid,
              attendanceDateTime: DateTime.now(),
              answers: []);

          FirebaseFirestoreHelper()
              .getSingleEvent(newAttendanceModel.eventId)
              .then((eventExist) {
            if (eventExist != null) {
              _codeController.text = '';
              RouterClass.nextScreenNormal(
                context,
                AnsQuestionsToSignInEventScreen(
                  eventModel: eventExist,
                  newAttendance: newAttendanceModel,
                  // nextPageRoute: () => RouterClass.nextScreenNormal(
                  //     context, SingleEventScreen(eventModel: eventExist)),
                  nextPageRoute: 'dashboardQrScanner',
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

  // Widget _bodyView() {
  //   return const Column(
  //     children: [
  //       // const Text(
  //       //   'Scan The QR app will detect Event Automatically',
  //       //   textAlign: TextAlign.center,
  //       //   style: TextStyle(
  //       //     color: AppThemeColor.pureWhiteColor,
  //       //     fontSize: 13,
  //       //     fontWeight: FontWeight.w400,
  //       //   ),
  //       // ),
  //     ],
  //   );
  // }

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

  @override
  void dispose() {
    controller?.dispose();
    super.dispose();
  }
}
