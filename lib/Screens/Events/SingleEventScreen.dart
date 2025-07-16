import 'dart:async';
import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:intl/intl.dart';
import 'package:orgami/Controller/CustomerController.dart';
import 'package:orgami/Firebase/FirebaseFirestoreHelper.dart';
import 'package:orgami/Models/AttendanceModel.dart';
import 'package:orgami/Models/EventModel.dart';
import 'package:orgami/Screens/Events/AddQuestionsToEventScreen.dart';
import 'package:orgami/Screens/Events/Attendance/AttendanceSheetScreen.dart';
import 'package:orgami/Screens/Events/Widget/AttendeesHorizontalList.dart';
import 'package:orgami/Screens/Events/Widget/PreRegisteredHorizontalList.dart';
import 'package:orgami/Screens/Events/Widget/CommentsSection.dart';
import 'package:orgami/Screens/Events/Widget/DeleteEventDialouge.dart';
import 'package:orgami/Screens/Events/Widget/QRDialouge.dart';
import 'package:orgami/Screens/QRScanner/AnsQuestionsToSignInEventScreen.dart';
import 'package:orgami/Screens/QRScanner/QrScannerScreenForLogedIn.dart';
import 'package:orgami/Utils/AppButtons.dart';
import 'package:orgami/Utils/Colors.dart';
import 'package:orgami/Utils/Router.dart';
import 'package:orgami/Utils/Toast.dart';
import 'package:orgami/Utils/dimensions.dart';
import 'package:rounded_loading_button_plus/rounded_loading_button.dart';
import 'package:orgami/Screens/Events/FeatureEventScreen.dart';

class SingleEventScreen extends StatefulWidget {
  final EventModel eventModel;
  const SingleEventScreen({
    super.key,
    required this.eventModel,
  });

  @override
  State<SingleEventScreen> createState() => _SingleEventScreenState();
}

class _SingleEventScreenState extends State<SingleEventScreen> {
  late final EventModel eventModel = widget.eventModel;
  late final double _screenWidth = MediaQuery.of(context).size.width;
  late final double _screenHeight = MediaQuery.of(context).size.height;
  bool? signedIn;
  bool? registered;
  final _btnCtlr = RoundedLoadingButtonController();

  double radians(double degrees) {
    return degrees * pi / 180.0;
  }

  int preRegisteredCount = 0;

  Future<void> getPreRegisterCount() async {
    await FirebaseFirestoreHelper()
        .getPreRegisterAttendanceCount(eventId: eventModel.id)
        .then((countValue) {
      setState(() {
        preRegisteredCount = countValue;
      });
    });
  }

  bool isInRadius(LatLng center, double radiusInFeet, LatLng point) {
    double radiusInMeters = radiusInFeet * 0.3048; // Convert feet to meters
    double earthRadius = 6378137; // Earth's radius in meters

    double dLat = radians(point.latitude - center.latitude);
    double dLng = radians(point.longitude - center.longitude);
    double a = sin(dLat / 2) * sin(dLat / 2) +
        cos(radians(center.latitude)) *
            cos(radians(point.latitude)) *
            sin(dLng / 2) *
            sin(dLng / 2);
    double c = 2 * atan2(sqrt(a), sqrt(1 - a));
    double distance = earthRadius * c;

    return distance <= radiusInMeters;
  }

  Future<void> getAttendance() async {
    await FirebaseFirestoreHelper()
        .getAttendanceExist(eventId: eventModel.id)
        .then((value) {
      print('Exist value is $value');
      setState(() {
        signedIn = value;
      });

      if (!signedIn! &&
          eventModel.getLocation &&
          eventModel.customerUid != CustomerController.logeInCustomer!.uid &&
          isEventInTime()) {
        _getCurrentLocation();
      }
    });
  }

  Future<void> getRegisterAttendance() async {
    await FirebaseFirestoreHelper()
        .getRegisterAttendanceExist(eventId: eventModel.id)
        .then((value) {
      print('Register Exist value is $value');
      setState(() {
        registered = value;
      });
    });
  }

  bool isEventInTime() {
    DateTime eventTime = eventModel.selectedDateTime;
    DateTime eventTimeHourBefore = eventTime.subtract(const Duration(hours: 1));
    DateTime eventTimeHourAfter = eventTime.add(const Duration(hours: 1));
    DateTime nowTime = DateTime.now();

    bool eventIsAfter = eventTimeHourBefore.isBefore(nowTime);

    print('$eventTimeHourBefore.isAfter($nowTime)');
    bool eventIsBefore = eventTimeHourAfter.isAfter(nowTime);

    print('$eventTimeHourAfter.isBefore($nowTime)');
    bool eventIsNow = eventTime.isAtSameMomentAs(nowTime);

    bool answer = false;
    if (eventIsNow || (eventIsBefore && eventIsAfter)) {
      answer = true;
    }

    print(
        'answer Is $answer  $eventIsNow || ($eventIsBefore && $eventIsAfter $nowTime -- $eventTimeHourBefore -- $eventTimeHourAfter');

    return answer;
  }

  Future<void> _getCurrentLocation() async {
    bool serviceEnabled;
    LocationPermission permission;

    serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      return Future.error('Location services are disabled.');
    }

    permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        return Future.error('Location permissions are denied');
      }
    }

    if (permission == LocationPermission.deniedForever) {
      // Permissions are denied forever, handle appropriately.
      return Future.error(
          'Location permissions are permanently denied, we cannot request permissions.');
    }

    await Geolocator.getCurrentPosition().then((value) {
      LatLng newLatLng = LatLng(
        value.latitude,
        value.longitude,
      );
      bool inRadius =
          isInRadius(eventModel.getLatLng(), eventModel.radius, newLatLng);
      if (inRadius) {
        showDialog(
          context: context,
          builder: (BuildContext context) {
            return Dialog(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10.0),
              ),
              elevation: 0,
              backgroundColor: Colors.transparent,
              child: contentBox(context),
            );
          },
        );
      }
      print(
          'Current Location is  $inRadius and radius is ${widget.eventModel.radius}');
    });
  }

  contentBox(context) {
    return Stack(
      children: <Widget>[
        Container(
          padding: const EdgeInsets.all(20.0),
          decoration: BoxDecoration(
            shape: BoxShape.rectangle,
            color: Colors.white,
            borderRadius: BorderRadius.circular(10.0),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              const Icon(
                Icons.celebration,
                color: AppThemeColor.darkBlueColor,
                size: 50.0,
              ),
              const SizedBox(height: 20),
              Text(
                "Welcome to ${eventModel.title}! Tap 'Sign In' to confirm your attendance.",
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 20),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: <Widget>[
                  MaterialButton(
                    onPressed: () {
                      Navigator.of(context).pop();
                    },
                    child: const Text(
                      'Close',
                      style: TextStyle(
                        color: Colors.black,
                        fontSize: 16,
                      ),
                    ),
                  ),
                  SizedBox(
                    width: _screenWidth / 2.8,
                    child: RoundedLoadingButton(
                      animateOnTap: false,
                      borderRadius: 5,
                      controller: _btnCtlr,
                      onPressed: makeSignInToEvent,
                      color: AppThemeColor.darkGreenColor,
                      elevation: 0,
                      child: const Wrap(
                        children: [
                          Text(
                            'Sign In',
                            style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                                color: Colors.white),
                          )
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  void makeSignInToEvent() async {
    try {
      _btnCtlr.start();

      String docId =
          '${eventModel.id}-${CustomerController.logeInCustomer!.uid}';
      AttendanceModel newAttendanceModel = AttendanceModel(
        id: docId,
        eventId: eventModel.id,
        userName: CustomerController.logeInCustomer!.name,
        customerUid: CustomerController.logeInCustomer!.uid,
        attendanceDateTime: DateTime.now(),
        answers: [],
      );

      RouterClass.nextScreenAndReplacement(
        context,
        AnsQuestionsToSignInEventScreen(
          eventModel: eventModel,
          newAttendance: newAttendanceModel,
          // nextPageRoute: () => Navigator.pop(context),
          nextPageRoute: 'singleEventPopup',
        ),
      );
      // await FirebaseFirestoreHelper()
      //     .makeEventSignIn(eventId: eventModel.id)
      //     .then((value) {
      //   _btnCtlr.success();
      //   Timer(const Duration(seconds: 2), () {
      //     Navigator.pop(context);
      //   });
      // });
    } catch (e) {
      print('Eroor is ${e.toString()}');
      _btnCtlr.reset();
    }
  }

  @override
  void initState() {
    getAttendance();
    getRegisterAttendance();
    getPreRegisterCount();
    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: _bodyView(),
      ),
    );
  }

  Widget _bodyView() {
    return SizedBox(
      width: _screenWidth,
      height: _screenHeight,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(10.0),
            child: _appBarViewWithQrButton(
              context: context,
              title: eventModel.title,
              eventModel: eventModel,
            ),
          ),
          Expanded(
            child: SingleChildScrollView(
              child: Column(
                children: [
                  _imageView(),
                  _categoriesView(),
                  if (eventModel.customerUid ==
                      FirebaseAuth.instance.currentUser!.uid)
                    Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 20.0, vertical: 10),
                      child: eventModel.isFeatured
                          ? Container(
                              alignment: Alignment.center,
                              width: _screenWidth,
                              height: 50,
                              decoration: BoxDecoration(
                                color: AppThemeColor.orangeColor,
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Text(
                                'Featured',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: Dimensions.fontSizeLarge,
                                  color: Colors.white,
                                ),
                              ),
                            )
                          : GestureDetector(
                              onTap: () {
                                RouterClass.nextScreenNormal(
                                  context,
                                  FeatureEventScreen(eventModel: eventModel),
                                );
                              },
                              child: AppButtons.button1(
                                width: _screenWidth,
                                height: 50,
                                buttonLoading: false,
                                label: 'Feature This Event',
                                labelSize: Dimensions.fontSizeLarge,
                              ),
                            ),
                    ),
                  if (eventModel.customerUid !=
                      FirebaseAuth.instance.currentUser!.uid)
                    if (signedIn != null)
                      if (!signedIn!) _signInToEventButton(),
                  _detailsView(),
                  // Attendees List
                  AttendeesHorizontalList(eventModel: eventModel),
                  // Pre-Registered List
                  PreRegisteredHorizontalList(eventModel: eventModel),
                  // Comments Section
                  CommentsSection(eventModel: eventModel),
                ],
              ),
            ),
          ),
          if (eventModel.customerUid == FirebaseAuth.instance.currentUser!.uid)
            _attendanceEventButton(),
          if (eventModel.customerUid == FirebaseAuth.instance.currentUser!.uid)
            _addQuestionsButton(),
          // if (eventModel.customerUid != FirebaseAuth.instance.currentUser!.uid)
          //   if (signedIn != null)
          //     if (!signedIn!) _signinToEventButton(),
          if (eventModel.customerUid != FirebaseAuth.instance.currentUser!.uid)
            if (registered != null)
              if (!registered!) _registerToEventButton(),
        ],
      ),
    );
  }

  Widget _addQuestionsButton() {
    return GestureDetector(
      onTap: () => RouterClass.nextScreenNormal(
        context,
        AddQuestionsToEventScreen(eventModel: eventModel),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 10),
        child: AppButtons.button1(
          width: _screenWidth,
          height: 50,
          buttonLoading: false,
          label: 'Add Sign-In Prompts',
          labelSize: Dimensions.fontSizeLarge,
        ),
      ),
    );
  }

  Widget _attendanceEventButton() {
    return GestureDetector(
      onTap: () => RouterClass.nextScreenNormal(
        context,
        AttendanceSheetScreen(eventModel: eventModel),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 10),
        child: AppButtons.button1(
          width: _screenWidth,
          height: 50,
          buttonLoading: false,
          label: 'View Attendance Sheet',
          labelSize: Dimensions.fontSizeLarge,
        ),
      ),
    );
  }

  Widget _registerToEventButton() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 10),
      child: RoundedLoadingButton(
        animateOnTap: false,
        borderRadius: 5,
        controller: _btnCtlr,
        onPressed: () {
          try {
            _btnCtlr.start();
            String docId = FirebaseFirestore.instance
                .collection(AttendanceModel.registerFirebaseKey)
                .doc()
                .id;
            AttendanceModel newAttendanceMode = AttendanceModel(
              id: docId,
              eventId: eventModel.id,
              userName: CustomerController.logeInCustomer!.name,
              customerUid: CustomerController.logeInCustomer!.uid,
              attendanceDateTime: DateTime.now(),
              answers: [],
            );
            FirebaseFirestore.instance
                .collection(AttendanceModel.registerFirebaseKey)
                .doc(docId)
                .set(newAttendanceMode.toJson())
                .then((value) {
              _btnCtlr.success();
              ShowToast().showSnackBar('Register Successful!', context);
              Navigator.pop(context);
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
              'Pre Register',
              style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: Colors.white),
            )
          ],
        ),
      ),
    );
  }

  Widget _signInToEventButton() {
    return Column(
      children: [
        const SizedBox(
          height: 10,
        ),
        const Text(
          'Enable location to auto sign-in when near the event.',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: AppThemeColor.dullFontColor,
            fontSize: Dimensions.fontSizeSmall,
          ),
        ),
        const SizedBox(
          height: 10,
        ),
        const Text(
          'OR',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: AppThemeColor.pureBlackColor,
            fontSize: Dimensions.fontSizeSmall,
          ),
        ),
        const SizedBox(
          height: 5,
        ),
        GestureDetector(
          onTap: () {
            RouterClass.nextScreenAndReplacement(
              context,
              QrScannerScreenForLogedIn(),
            );
          },
          child: Container(
            margin: const EdgeInsets.symmetric(vertical: 10),
            width: 130,
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              color: AppThemeColor.darkGreenColor,
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Row(
              children: [
                Icon(
                  CupertinoIcons.qrcode_viewfinder,
                  color: AppThemeColor.pureWhiteColor,
                  size: 44,
                ),
                SizedBox(
                  width: 10,
                ),
                Text(
                  'Sign In',
                  style: TextStyle(
                    color: AppThemeColor.pureWhiteColor,
                    fontSize: Dimensions.fontSizeLarge,
                    fontWeight: FontWeight.w700,
                  ),
                )
              ],
            ),
          ),
        ),
      ],
    );

    // return Padding(
    //   padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 10),
    //   child: RoundedLoadingButton(
    //     animateOnTap: false,
    //     borderRadius: 5,
    //     controller: _btnCtlr,
    //     onPressed: () {
    //       RouterClass.nextScreenAndReplacement(
    //         context,
    //         QrScannerScreenForLogedIn(),
    //       );
    //       // try {
    //       //   _btnCtlr.start();
    //       //   String docId = FirebaseFirestore.instance
    //       //       .collection(AttendanceModel.firebaseKey)
    //       //       .doc()
    //       //       .id;
    //       //   AttendanceModel newAttendanceMode = AttendanceModel(
    //       //     id: docId,
    //       //     eventId: eventModel.id,
    //       //     userName: CustomerController.logeInCustomer!.name,
    //       //     customerUid: CustomerController.logeInCustomer!.uid,
    //       //     attendanceDateTime: DateTime.now(),
    //       //   );
    //       //   FirebaseFirestore.instance
    //       //       .collection(AttendanceModel.firebaseKey)
    //       //       .doc(docId)
    //       //       .set(newAttendanceMode.toJson())
    //       //       .then((value) {
    //       //     _btnCtlr.success();
    //       //     ShowToast().showSnackBar('Signed In Successful!', context);
    //       //     Navigator.pop(context);
    //       //   });
    //       // } catch (e) {
    //       //   _btnCtlr.reset();
    //       // }
    //     },
    //     color: AppThemeColor.darkGreenColor,
    //     elevation: 0,
    //     child: const Wrap(
    //       children: [
    //         Text(
    //           'Sign In',
    //           style: TextStyle(
    //               fontSize: 16,
    //               fontWeight: FontWeight.w600,
    //               color: Colors.white),
    //         )
    //       ],
    //     ),
    //   ),
    // );
  }

  Widget _detailsView() {
    return Container(
      padding: const EdgeInsets.all(20.0),
      width: _screenWidth,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (eventModel.isFeatured)
                Padding(
                  padding: const EdgeInsets.only(right: 6.0),
                  child: Icon(
                    Icons.star,
                    color: AppThemeColor.orangeColor,
                    size: Dimensions.fontSizeExtraLarge + 4,
                  ),
                ),
              Flexible(
                child: Text(
                  eventModel.title,
                  maxLines: 1,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: AppThemeColor.pureBlackColor,
                    fontWeight: FontWeight.w700,
                    fontSize: Dimensions.fontSizeExtraLarge,
                  ),
                ),
              ),
            ],
          ),
          Text(
            eventModel.groupName,
            maxLines: 1,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: AppThemeColor.dullFontColor,
              fontWeight: FontWeight.w700,
              fontSize: Dimensions.fontSizeLarge,
            ),
          ),
          _singleWithIconValue(
            iconData: Icons.groups_rounded,
            value: 'Pre-Registered: $preRegisteredCount',
          ),
          _singleWithIconValue(
            iconData: Icons.calendar_month_rounded,
            value: DateFormat('EEEE, MMMM dd yyyy').format(
              eventModel.selectedDateTime,
            ),
          ),
          _singleWithIconValue(
            iconData: Icons.access_time_rounded,
            value: DateFormat('KK:mm a').format(
              eventModel.selectedDateTime,
            ),
          ),
          _singleWithIconValue(
            iconData: Icons.location_on,
            value: eventModel.location,
          ),
          const SizedBox(
            height: 20,
          ),
          Text(
            eventModel.description,
            style: const TextStyle(
              color: AppThemeColor.pureBlackColor,
              fontWeight: FontWeight.w400,
              fontSize: Dimensions.fontSizeLarge,
            ),
          ),
        ],
      ),
    );
  }

  Widget _singleWithIconValue(
      {required IconData iconData, required String value}) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Icon(
            iconData,
            size: 33,
            color: AppThemeColor.dullFontColor,
          ),
          const SizedBox(
            width: 10,
          ),
          Text(
            value,
            style: const TextStyle(
              color: AppThemeColor.pureBlackColor,
              fontWeight: FontWeight.w500,
              fontSize: Dimensions.fontSizeLarge,
            ),
          )
        ],
      ),
    );
  }

  Widget _imageView() {
    return Image.network(eventModel.imageUrl);
  }

  Widget _categoriesView() {
    if (eventModel.categories.isEmpty) {
      return const SizedBox.shrink();
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 10.0),
      child: Wrap(
        spacing: 8.0,
        runSpacing: 8.0,
        children: eventModel.categories.map((category) {
          return Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 12.0, vertical: 6.0),
            decoration: BoxDecoration(
              color: AppThemeColor.darkGreenColor.withOpacity(0.1),
              borderRadius: BorderRadius.circular(20.0),
              border: Border.all(
                color: AppThemeColor.darkGreenColor,
                width: 1.0,
              ),
            ),
            child: Text(
              category,
              style: const TextStyle(
                color: AppThemeColor.darkGreenColor,
                fontSize: Dimensions.fontSizeDefault,
                fontWeight: FontWeight.w600,
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  static Widget _appBarViewWithQrButton(
      {required BuildContext context,
      required String title,
      required EventModel eventModel}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Expanded(
          child: Row(
            children: [
              InkWell(
                onTap: () => Navigator.pop(context),
                child: AppButtons.roundedButton(
                  iconData: Icons.arrow_back_ios_rounded,
                  iconColor: AppThemeColor.pureWhiteColor,
                  backgroundColor: AppThemeColor.darkGreenColor,
                ),
              ),
              const SizedBox(
                width: 15,
              ),
              Text(
                title,
                style: const TextStyle(
                  color: AppThemeColor.darkBlueColor,
                  fontSize: Dimensions.paddingSizeLarge,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
        if (eventModel.customerUid == FirebaseAuth.instance.currentUser!.uid)
          Row(
            children: [
              InkWell(
                onTap: () => showDialog(
                  context: context,
                  builder: (context) => DeleteEventDialoge(
                    singleEvent: eventModel,
                  ),
                ),
                child: AppButtons.roundedButton(
                  iconData: Icons.delete_forever_rounded,
                  iconColor: Colors.red,
                  backgroundColor: AppThemeColor.darkGreenColor,
                ),
              ),
              const SizedBox(
                width: 10,
              ),
              InkWell(
                onTap: () => showDialog(
                  context: context,
                  builder: (context) => ShareQRDialog(
                    singleEvent: eventModel,
                  ),
                ),
                child: AppButtons.roundedButton(
                  iconData: Icons.qr_code_2_rounded,
                  iconColor: AppThemeColor.pureWhiteColor,
                  backgroundColor: AppThemeColor.darkGreenColor,
                ),
              ),
            ],
          ),
      ],
    );
  }
}
