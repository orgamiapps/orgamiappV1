import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:orgami/Models/EventModel.dart';
import 'package:orgami/Models/EventQuestionModel.dart';
import 'package:orgami/Utils/Colors.dart';
import 'package:orgami/Utils/dimensions.dart';

class AddQuestionPopup extends StatefulWidget {
  final EventModel eventModel;

  const AddQuestionPopup({super.key, required this.eventModel});
  @override
  _AddQuestionPopupState createState() => _AddQuestionPopupState();
}

class _AddQuestionPopupState extends State<AddQuestionPopup> {
  final TextEditingController _textController = TextEditingController();
  bool _isRequired = false;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: AppThemeColor.pureWhiteColor,
      title: const Text(
        'Add Question to event',
        style: TextStyle(
          color: AppThemeColor.darkBlueColor,
          fontSize: Dimensions.fontSizeLarge,
        ),
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _textController,
            decoration: const InputDecoration(
              labelText: 'Question Title',
              hintText: 'Type here',
              border: OutlineInputBorder(),
            ),
          ),
          Row(
            children: [
              const Text('Is Required: '),
              Checkbox(
                value: _isRequired,
                onChanged: (value) {
                  setState(() {
                    _isRequired = value ?? false;
                  });
                },
              ),
            ],
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () {
            Navigator.of(context).pop(); // Close the dialog
          },
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: () {
            String title = _textController.text;
            bool required = _isRequired;
            String newId = FirebaseFirestore.instance
                .collection(EventQuestionModel.firebaseKey)
                .doc()
                .id;

            EventQuestionModel newQuestion = EventQuestionModel(
                id: newId, questionTitle: title, required: required);

            FirebaseFirestore.instance
                .collection(EventModel.firebaseKey)
                .doc(widget.eventModel.id)
                .collection(EventQuestionModel.firebaseKey)
                .doc(newQuestion.id)
                .set(newQuestion.toJson())
                .then((value) {
              Navigator.of(context).pop(newQuestion); // Close the dialog
            });
          },
          child: const Text('Add'),
        ),
      ],
    );
  }

  @override
  void dispose() {
    _textController.dispose();
    super.dispose();
  }
}
