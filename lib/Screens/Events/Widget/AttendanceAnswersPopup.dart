import 'package:flutter/material.dart';
import 'package:orgami/Models/AttendanceModel.dart';
import 'package:orgami/Models/EventModel.dart';
import 'package:orgami/Utils/Colors.dart';

class AttendanceAnswersPopup extends StatelessWidget {
  final EventModel eventModel;
  final AttendanceModel attendance;

  const AttendanceAnswersPopup({
    super.key,
    required this.attendance,
    required this.eventModel,
  });

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: AppThemeColor.pureWhiteColor,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: EdgeInsets.all(8.0),
            child: Text(
              '${attendance.userName}\'s Answers',
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
          ),
          const Divider(),
          ListView.builder(
            shrinkWrap: true,
            itemCount: attendance.answers.length,
            itemBuilder: (context, index) {
              String title = attendance.answers[index].split('--ans--').first;
              String answer = attendance.answers[index].split('--ans--').last;
              return ListTile(
                title: Text(title),
                subtitle: Text(answer),
              );
            },
          ),
          const Divider(),
          ElevatedButton(
            onPressed: () {
              Navigator.of(context).pop(); // Close the dialog
            },
            child: Text('Close'),
          ),
        ],
      ),
    );
  }
}
