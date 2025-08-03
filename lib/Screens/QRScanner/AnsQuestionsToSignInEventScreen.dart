import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:orgami/Firebase/FirebaseFirestoreHelper.dart';
import 'package:orgami/Models/AttendanceModel.dart';
import 'package:orgami/Models/EventModel.dart';
import 'package:orgami/Models/EventQuestionModel.dart';
import 'package:orgami/Screens/Events/SingleEventScreen.dart';
import 'package:orgami/Utils/AppAppBarView.dart';
import 'package:orgami/Utils/Colors.dart';
import 'package:orgami/Utils/Router.dart';
import 'package:orgami/Utils/Toast.dart';
import 'package:orgami/Utils/dimensions.dart';
import 'package:rounded_loading_button_plus/rounded_loading_button.dart';
import 'package:orgami/Screens/MyEvents/MyEventsScreen.dart';

class AnsQuestionsToSignInEventScreen extends StatefulWidget {
  final EventModel eventModel;
  final AttendanceModel newAttendance;
  final String nextPageRoute;
  const AnsQuestionsToSignInEventScreen({
    super.key,
    required this.eventModel,
    required this.newAttendance,
    required this.nextPageRoute,
  });

  @override
  State<AnsQuestionsToSignInEventScreen> createState() =>
      _AnsQuestionsToSignInEventScreenState();
}

class _AnsQuestionsToSignInEventScreenState
    extends State<AnsQuestionsToSignInEventScreen>
    with SingleTickerProviderStateMixin {
  late final double _screenWidth = MediaQuery.of(context).size.width;
  late final double _screenHeight = MediaQuery.of(context).size.height;

  late AttendanceModel newAttendance = widget.newAttendance;

  final _btnCtlr = RoundedLoadingButtonController();

  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();

  List<EventQuestionModel> questionsList = [];

  Future<void> _getQuestions() async {
    await FirebaseFirestoreHelper()
        .getEventQuestions(eventId: widget.eventModel.id)
        .then((value) {
      setState(() {
        questionsList = value;
      });
    });
  }

  void _makeSingIn() {
    print('M called');

    if (_formKey.currentState!.validate()) {
      _formKey.currentState!.save();
      print('M called 1');

      for (var element in questionsList) {
        newAttendance.answers
            .add('${element.questionTitle}--ans--${element.answer}');
      }

      print(
          'Recording attendance with questions for event: ${newAttendance.eventId}');
      print('Attendance data: ${newAttendance.toJson()}');

      FirebaseFirestore.instance
          .collection(AttendanceModel.firebaseKey)
          .doc(newAttendance.id)
          .set(newAttendance.toJson())
          .then((value) {
        print('Attendance with questions recorded successfully');
        ShowToast().showSnackBar('Signed In Successful!', context);
        _btnCtlr.success();
        Future.delayed(const Duration(seconds: 1), () {
          _btnCtlr.reset();
          if (widget.nextPageRoute == 'singleEventPopup') {
            // Pop current screen and navigate to fresh SingleEventScreen to refresh data
            Navigator.pop(context);
            RouterClass.nextScreenAndReplacement(
              context,
              SingleEventScreen(eventModel: widget.eventModel),
            );
          } else if (widget.nextPageRoute == 'dashboardQrScanner') {
            RouterClass.nextScreenAndReplacement(
              context,
              SingleEventScreen(
                eventModel: widget.eventModel,
              ),
            );
          } else if (widget.nextPageRoute == 'qrScannerForLogedIn') {
            RouterClass.nextScreenAndReplacement(
              context,
              SingleEventScreen(
                eventModel: widget.eventModel,
              ),
            );
          } else if (widget.nextPageRoute == 'withoutLogin') {
            Navigator.pop(context);
            // RouterClass.nextScreenAndReplacement(
            //   context,
            //   SingleEventScreen(
            //     eventModel: widget.eventModel,
            //   ),
            // );
          }
          // Add this block to always navigate to MyEventsScreen and refresh after sign-in
          Future.delayed(const Duration(milliseconds: 500), () {
            Navigator.of(context).pushAndRemoveUntil(
              MaterialPageRoute(builder: (context) => const MyEventsScreen()),
              (Route<dynamic> route) => false,
            );
          });
        });
        // RouterClass.nextScreenAndReplacementAndRemoveUntil(
        //   context: context,
        //   page: const DashboardScreen(),
        // );
        // RouterClass.nextScreenNormal(
        //   context,
        //   SingleEventScreen(
        //     eventModel: widget.eventModel,
        //   ),
        // );
      }).catchError((error) {
        _btnCtlr.error();
        ShowToast().showSnackBar('Error signing in: $error', context);
        Future.delayed(const Duration(seconds: 2), () {
          _btnCtlr.reset();
        });
      });
    } else {
      _btnCtlr.reset();
    }
  }

  @override
  void initState() {
    _getQuestions();
    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: _bodyView(),
      ),
      bottomNavigationBar: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: 20.0,
          vertical: 10,
        ),
        child: RoundedLoadingButton(
          animateOnTap: true,
          borderRadius: 13,
          width: _screenWidth,
          controller: _btnCtlr,
          onPressed: _makeSingIn,
          color: AppThemeColor.darkGreenColor,
          elevation: 0,
          child: const Wrap(
            children: [
              Text(
                'Sign In',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: Colors.white,
                ),
              )
            ],
          ),
        ),
      ),
    );
  }

  Widget _bodyView() {
    return Container(
      width: _screenWidth,
      height: _screenHeight,
      decoration: const BoxDecoration(),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 10),
            child: AppAppBarView.appBarView(
              context: context,
              title: 'Question for Event',
            ),
          ),
          Expanded(
            child: _questionsView(),
          ),
        ],
      ),
    );
  }

  Widget _questionsView() {
    return Form(
      key: _formKey,
      child: ListView.builder(
        itemCount: questionsList.length,
        itemBuilder: (listContext, index) {
          return _singleQuestion(index: index);
        },
      ),
    );
  }

  Widget _singleQuestion({required int index}) {
    EventQuestionModel singleQuestion = questionsList[index];
    return Container(
      margin: const EdgeInsets.symmetric(
        horizontal: 15,
        vertical: 10,
      ),
      padding: const EdgeInsets.symmetric(
        horizontal: 15,
        vertical: 10,
      ),
      decoration: BoxDecoration(
        color: AppThemeColor.pureWhiteColor,
        borderRadius: BorderRadius.circular(10),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withOpacity(0.5),
            spreadRadius: 5,
            blurRadius: 7,
            offset: const Offset(0, 3), // changes position of shadow
          ),
        ],
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Container(
                    height: 40,
                    width: 40,
                    decoration: BoxDecoration(
                      color: AppThemeColor.darkGreenColor,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Center(
                      child: Text(
                        '${index + 1}',
                        style: const TextStyle(
                          color: AppThemeColor.pureWhiteColor,
                          fontSize: Dimensions.fontSizeDefault,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(
                    width: 10,
                  ),
                  Text(
                    singleQuestion.questionTitle,
                    style: const TextStyle(
                      color: AppThemeColor.darkBlueColor,
                      fontWeight: FontWeight.w500,
                      fontSize: Dimensions.fontSizeLarge,
                    ),
                  ),
                ],
              ),
              Text(
                singleQuestion.required ? '(required)' : '(not-required)',
                style: const TextStyle(
                  color: AppThemeColor.dullFontColor,
                  fontWeight: FontWeight.w500,
                  fontSize: Dimensions.fontSizeLarge,
                ),
              ),
            ],
          ),
          const SizedBox(
            height: 10,
          ),
          TextFormField(
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
              hintText: 'Type here....',
            ),
            onSaved: (val) {
              questionsList[index].answer = val;
            },
            validator: (value) {
              if (singleQuestion.required) {
                print('validate callde');
                if (value!.isEmpty) {
                  return 'Enter ${singleQuestion.questionTitle} first!';
                }
              }

              return null;
            },
          ),
        ],
      ),
    );
  }
}
