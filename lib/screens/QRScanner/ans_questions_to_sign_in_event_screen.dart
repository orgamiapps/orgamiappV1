import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:attendus/firebase/firebase_firestore_helper.dart';
import 'package:attendus/models/attendance_model.dart';
import 'package:attendus/models/event_model.dart';
import 'package:attendus/models/event_question_model.dart';
import 'package:attendus/screens/Events/single_event_screen.dart';
import 'package:attendus/Utils/app_app_bar_view.dart';
import 'package:attendus/Utils/colors.dart';
import 'package:attendus/Utils/router.dart';
import 'package:attendus/Utils/toast.dart';
import 'package:rounded_loading_button_plus/rounded_loading_button.dart';

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
  late AttendanceModel newAttendance = widget.newAttendance;

  final _btnCtlr = RoundedLoadingButtonController();

  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final List<TextEditingController> _textControllers = [];

  List<EventQuestionModel> questionsList = [];
  bool isLoading = true;

  Future<void> _getQuestions() async {
    try {
      final questions = await FirebaseFirestoreHelper().getEventQuestions(
        eventId: widget.eventModel.id,
      );

      setState(() {
        questionsList = questions;
        isLoading = false;
        // Initialize text controllers for each question
        _textControllers.clear();
        for (int i = 0; i < questions.length; i++) {
          _textControllers.add(TextEditingController());
        }
      });
    } catch (e) {
      setState(() {
        isLoading = false;
      });
      if (!mounted) return;
      ShowToast().showSnackBar('Error loading questions: $e', context);
    }
  }

  void _makeSingIn() {
    if (_formKey.currentState!.validate()) {
      _formKey.currentState!.save();

      // Collect answers from text controllers
      for (int i = 0; i < questionsList.length; i++) {
        final answer = _textControllers[i].text.trim();
        if (answer.isNotEmpty) {
          newAttendance.answers.add(
            '${questionsList[i].questionTitle}--ans--$answer',
          );
        }
      }

      FirebaseFirestore.instance
          .collection(AttendanceModel.firebaseKey)
          .doc(newAttendance.id)
          .set(newAttendance.toJson())
          .then((value) {
            if (!mounted) return;
            ShowToast().showSnackBar('Signed In Successfully!', context);
            _btnCtlr.success();
            Future.delayed(const Duration(seconds: 1), () {
              _btnCtlr.reset();
              if (widget.nextPageRoute == 'singleEventPopup') {
                // Navigate back to SingleEventScreen and refresh it
                if (!mounted) return;
                Navigator.pop(context); // Close the questions screen
                // Navigate to SingleEventScreen to refresh the attendance status
                if (!mounted) return;
                RouterClass.nextScreenAndReplacement(
                  context,
                  SingleEventScreen(eventModel: widget.eventModel),
                );
              } else if (widget.nextPageRoute == 'dashboardQrScanner') {
                if (!mounted) return;
                RouterClass.nextScreenAndReplacement(
                  context,
                  SingleEventScreen(eventModel: widget.eventModel),
                );
              } else if (widget.nextPageRoute == 'qrScannerForLogedIn') {
                if (!mounted) return;
                RouterClass.nextScreenAndReplacement(
                  context,
                  SingleEventScreen(eventModel: widget.eventModel),
                );
              } else if (widget.nextPageRoute == 'withoutLogin') {
                if (!mounted) return;
                Navigator.pop(context);
              }
            });
          })
          .catchError((error) {
            _btnCtlr.error();
            if (!mounted) return;
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
  void dispose() {
    for (var controller in _textControllers) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppThemeColor.lightBlueColor,
      body: SafeArea(child: _bodyView()),
      bottomNavigationBar: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Colors.white,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              spreadRadius: 0,
              blurRadius: 10,
              offset: const Offset(0, -2),
            ),
          ],
        ),
        child: SafeArea(
          child: RoundedLoadingButton(
            animateOnTap: true,
            borderRadius: 12,
            width: double.infinity,
            controller: _btnCtlr,
            onPressed: _makeSingIn,
            color: AppThemeColor.darkBlueColor,
            elevation: 0,
            child: const Text(
              'Sign In',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: Colors.white,
                fontFamily: 'Roboto',
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _bodyView() {
    return Column(
      children: [
        // Modern Header
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: Colors.white,
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.05),
                spreadRadius: 0,
                blurRadius: 10,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: AppAppBarView.appBarView(
            context: context,
            title: 'Event Sign-In',
          ),
        ),

        // Content Area
        Expanded(
          child: isLoading
              ? const Center(
                  child: CircularProgressIndicator(
                    color: AppThemeColor.darkBlueColor,
                  ),
                )
              : questionsList.isEmpty
              ? _buildEmptyState()
              : _buildQuestionsForm(),
        ),
      ],
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 80,
            height: 80,
            decoration: BoxDecoration(
              color: AppThemeColor.lightGrayColor.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(40),
            ),
            child: const Icon(
              Icons.question_answer_outlined,
              size: 40,
              color: AppThemeColor.lightGrayColor,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'No questions to answer',
            style: TextStyle(
              color: AppThemeColor.dullFontColor,
              fontSize: 16,
              fontFamily: 'Roboto',
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'You can proceed with sign-in',
            style: TextStyle(
              color: AppThemeColor.dullFontColor,
              fontSize: 14,
              fontFamily: 'Roboto',
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildQuestionsForm() {
    return Container(
      margin: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            spreadRadius: 0,
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: AppThemeColor.lightBlueColor.withValues(alpha: 0.1),
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(16),
                  topRight: Radius.circular(16),
                ),
              ),
              child: Row(
                children: [
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: AppThemeColor.darkBlueColor.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(
                      Icons.question_answer,
                      color: AppThemeColor.darkBlueColor,
                      size: 24,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Event Questions',
                          style: const TextStyle(
                            color: AppThemeColor.pureBlackColor,
                            fontSize: 18,
                            fontWeight: FontWeight.w600,
                            fontFamily: 'Roboto',
                          ),
                        ),
                        Text(
                          'Please answer the following questions to complete your sign-in',
                          style: const TextStyle(
                            color: AppThemeColor.dullFontColor,
                            fontSize: 14,
                            fontFamily: 'Roboto',
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            // Questions List
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.all(20),
                itemCount: questionsList.length,
                itemBuilder: (context, index) {
                  return _buildQuestionCard(index);
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildQuestionCard(int index) {
    final question = questionsList[index];
    final isRequired = question.required;

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppThemeColor.borderColor, width: 1),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.02),
            spreadRadius: 0,
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Question Header
          Row(
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: AppThemeColor.darkBlueColor,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Center(
                  child: Text(
                    '${index + 1}',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      fontFamily: 'Roboto',
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  question.questionTitle,
                  style: const TextStyle(
                    color: AppThemeColor.pureBlackColor,
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    fontFamily: 'Roboto',
                  ),
                ),
              ),
              if (isRequired)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: AppThemeColor.orangeColor.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Text(
                    'Required',
                    style: TextStyle(
                      color: AppThemeColor.orangeColor,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      fontFamily: 'Roboto',
                    ),
                  ),
                )
              else
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: AppThemeColor.dullFontColor.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Text(
                    'Optional',
                    style: TextStyle(
                      color: AppThemeColor.dullFontColor,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      fontFamily: 'Roboto',
                    ),
                  ),
                ),
            ],
          ),

          const SizedBox(height: 16),

          // Answer Input
          TextFormField(
            controller: _textControllers[index],
            decoration: InputDecoration(
              hintText: 'Type your answer here...',
              hintStyle: TextStyle(
                color: AppThemeColor.dullFontColor.withValues(alpha: 0.6),
                fontFamily: 'Roboto',
              ),
              filled: true,
              fillColor: AppThemeColor.lightBlueColor.withValues(alpha: 0.1),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(
                  color: AppThemeColor.borderColor,
                  width: 1,
                ),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(
                  color: AppThemeColor.borderColor,
                  width: 1,
                ),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(
                  color: AppThemeColor.darkBlueColor,
                  width: 2,
                ),
              ),
              errorBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(
                  color: AppThemeColor.orangeColor,
                  width: 1,
                ),
              ),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 16,
              ),
            ),
            maxLines: 3,
            validator: (value) {
              if (isRequired && (value == null || value.trim().isEmpty)) {
                return 'This question is required';
              }
              return null;
            },
            onSaved: (value) {
              questionsList[index].answer = value?.trim() ?? '';
            },
          ),
        ],
      ),
    );
  }
}
