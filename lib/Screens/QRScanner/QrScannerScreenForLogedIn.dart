import 'dart:io';

import 'package:flutter/material.dart';
import 'package:orgami/Controller/CustomerController.dart';
import 'package:orgami/Firebase/FirebaseFirestoreHelper.dart';
import 'package:orgami/Models/AttendanceModel.dart';
import 'package:orgami/Models/EventModel.dart';
import 'package:orgami/Permissions/PermssionsHelper.dart';
import 'package:orgami/Screens/QRScanner/AnsQuestionsToSignInEventScreen.dart';
import 'package:orgami/Utils/AppAppBarView.dart';
import 'package:orgami/Utils/AppButtons.dart';
import 'package:orgami/Utils/Colors.dart';
import 'package:orgami/Utils/Router.dart';
import 'package:orgami/Utils/Toast.dart';
import 'package:orgami/Utils/dimensions.dart';
import 'package:qr_code_scanner_plus/qr_code_scanner_plus.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:orgami/Screens/Events/SingleEventScreen.dart';

import 'package:orgami/Screens/QRScanner/QRScannerFlowScreen.dart';

class QrScannerScreenForLogedIn extends StatefulWidget {
  const QrScannerScreenForLogedIn({super.key});

  @override
  State<StatefulWidget> createState() => _QrScannerScreenForLogedInState();
}

class _QrScannerScreenForLogedInState extends State<QrScannerScreenForLogedIn> {
  Barcode? result;
  QRViewController? controller;
  final GlobalKey qrKey = GlobalKey(debugLabel: 'QR');

  final TextEditingController _codeController = TextEditingController();
  bool _isAnonymousSignIn = false;
  bool _isLoading = false; // Add loading state

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
    // Redirect to the new modern QR scanner flow
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (context) => const QRScannerFlowScreen()),
      );
    });

    return Scaffold(
      backgroundColor: AppThemeColor.pureBlackColor,
      body: const Center(
        child: CircularProgressIndicator(color: AppThemeColor.darkBlueColor),
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
              const SizedBox(height: 20),
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
                    contentPadding: EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 10,
                    ),
                    border: OutlineInputBorder(),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  Checkbox(
                    value: _isAnonymousSignIn,
                    onChanged: (value) {
                      setState(() {
                        _isAnonymousSignIn = value ?? false;
                      });
                    },
                    activeColor: AppThemeColor.darkGreenColor,
                  ),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Text(
                      'Sign In anonymously to public',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w500,
                        color: AppThemeColor.pureWhiteColor,
                      ),
                    ),
                  ),
                ],
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
        onTap: _isLoading
            ? null
            : () async {
                if (_codeController.text.isEmpty) {
                  ShowToast().showNormalToast(
                    msg: 'Please enter an event code!',
                  );
                  return;
                }

                setState(() {
                  _isLoading = true;
                });

                try {
                  // Ensure user is properly authenticated
                  if (CustomerController.logeInCustomer == null) {
                    ShowToast().showNormalToast(
                      msg: 'Please log in to sign in to events.',
                    );
                    setState(() {
                      _isLoading = false;
                    });
                    return;
                  }

                  print('=== QR Code Debug ===');
                  print('QR Code text: ${_codeController.text}');
                  print('User ID: ${CustomerController.logeInCustomer!.uid}');

                  String docId =
                      '${_codeController.text}-${CustomerController.logeInCustomer!.uid}';
                  print('Document ID: $docId');

                  AttendanceModel newAttendanceModel = AttendanceModel(
                    id: docId,
                    eventId: _codeController.text,
                    userName: _isAnonymousSignIn
                        ? 'Anonymous'
                        : CustomerController.logeInCustomer!.name,
                    customerUid: CustomerController.logeInCustomer!.uid,
                    attendanceDateTime: DateTime.now(),
                    answers: [],
                    isAnonymous: _isAnonymousSignIn,
                    realName: _isAnonymousSignIn
                        ? CustomerController.logeInCustomer!.name
                        : null,
                  );

                  // Try to find event by ID or manual code
                  EventModel? eventExist = await FirebaseFirestoreHelper()
                      .getSingleEvent(newAttendanceModel.eventId);

                  // If not found by ID, try to find by manual code
                  if (eventExist == null) {
                    eventExist = await _findEventByManualCode(
                      newAttendanceModel.eventId,
                    );
                  }

                  if (eventExist != null) {
                    // Check for sign-in prompts
                    final questions = await FirebaseFirestoreHelper()
                        .getEventQuestions(eventId: eventExist.id);
                    if (questions.isNotEmpty) {
                      _codeController.text = '';
                      RouterClass.nextScreenAndReplacement(
                        context,
                        AnsQuestionsToSignInEventScreen(
                          eventModel: eventExist!,
                          newAttendance: newAttendanceModel,
                          nextPageRoute: 'qrScannerForLogedIn',
                        ),
                      );
                    } else {
                      // No prompts, sign in directly
                      try {
                        print(
                          'Recording attendance for event: ${newAttendanceModel.eventId}',
                        );
                        print(
                          'Attendance data: ${newAttendanceModel.toJson()}',
                        );

                        await FirebaseFirestore.instance
                            .collection(AttendanceModel.firebaseKey)
                            .doc(newAttendanceModel.id)
                            .set(newAttendanceModel.toJson());

                        print('Attendance recorded successfully');
                        ShowToast().showNormalToast(
                          msg: 'Signed In Successfully!',
                        );
                        // Navigate to event details after a short delay
                        Future.delayed(const Duration(seconds: 1), () {
                          RouterClass.nextScreenAndReplacement(
                            context,
                            SingleEventScreen(eventModel: eventExist!),
                          );
                        });
                      } catch (firestoreError) {
                        print(
                          'Firestore error during sign-in: $firestoreError',
                        );
                        ShowToast().showNormalToast(
                          msg: 'Failed to save attendance. Please try again.',
                        );
                      }
                    }
                  } else {
                    ShowToast().showNormalToast(
                      msg: 'Entered an incorrect code!',
                    );
                  }
                } catch (e) {
                  print('Error signing in: $e');
                  ShowToast().showNormalToast(
                    msg: 'Failed to sign in. Please try again.',
                  );
                } finally {
                  setState(() {
                    _isLoading = false;
                  });
                }
              },
        child: AppButtons.button1(
          width: _screenWidth,
          height: 50,
          buttonLoading: _isLoading,
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
    var scanArea =
        (MediaQuery.of(context).size.width < 400 ||
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
        cutOutSize: scanArea,
      ),
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

  @override
  void dispose() {
    controller?.dispose();
    super.dispose();
  }

  Future<EventModel?> _findEventByManualCode(String manualCode) async {
    try {
      final querySnapshot = await FirebaseFirestore.instance
          .collection(EventModel.firebaseKey)
          .where('manualCode', isEqualTo: manualCode)
          .get();

      if (querySnapshot.docs.isNotEmpty) {
        return EventModel.fromJson(querySnapshot.docs.first.data());
      }
      return null;
    } catch (e) {
      print('Error finding event by manual code: $e');
      return null;
    }
  }
}
