import 'package:flutter/material.dart';
import 'package:orgami/Firebase/FirebaseFirestoreHelper.dart';
import 'package:orgami/Models/EventModel.dart';
import 'package:orgami/Models/EventQuestionModel.dart';
import 'package:orgami/Screens/Events/Widget/AddQuestionPopup.dart';
import 'package:orgami/Utils/AppAppBarView.dart';
import 'package:orgami/Utils/Colors.dart';
import 'package:orgami/Utils/dimensions.dart';
import 'package:rounded_loading_button_plus/rounded_loading_button.dart';

class AddQuestionsToEventScreen extends StatefulWidget {
  final EventModel eventModel;
  const AddQuestionsToEventScreen({
    super.key,
    required this.eventModel,
  });

  @override
  State<AddQuestionsToEventScreen> createState() =>
      _AddQuestionsToEventScreenState();
}

class _AddQuestionsToEventScreenState extends State<AddQuestionsToEventScreen>
    with SingleTickerProviderStateMixin {
  late final double _screenWidth = MediaQuery.of(context).size.width;
  late final double _screenHeight = MediaQuery.of(context).size.height;

  final _btnCtlr = RoundedLoadingButtonController();

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
      floatingActionButton: FloatingActionButton(
        onPressed: () async {
          await showDialog(
            context: context,
            builder: (BuildContext context) {
              return AddQuestionPopup(
                eventModel: widget.eventModel,
              );
            },
          ).then((newQuestion) {
            if (newQuestion != null) {
              setState(() {
                questionsList.add(newQuestion);
              });
            }
          });
        },
        backgroundColor: AppThemeColor.darkGreenColor,
        child: const Icon(
          Icons.add_box_rounded,
          color: AppThemeColor.pureWhiteColor,
          size: 33,
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
              title: 'Add Sign-In Prompts',
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
    if (questionsList.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(18.0),
          child: Text(
            'To add sign-in prompts, tap the "+" icon at the bottom right of your screen',
            textAlign: TextAlign.center,
          ),
        ),
      );
    } else {
      return ListView.builder(
          itemCount: questionsList.length,
          itemBuilder: (listContext, index) {
            return _singleQuestion(index: index);
          });
    }
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
      child: Row(
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
    );
  }
}
