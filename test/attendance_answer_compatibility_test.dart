import 'package:attendus/Utils/check_in_questions.dart';
import 'package:attendus/models/attendance_model.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('history renders mixed server V3 and legacy door answers', () {
    final attendance = AttendanceModel.fromJson({
      'id': 'receipt',
      'answers': [
        {'questionId': 'access', 'prompt': 'Accessibility', 'answer': 'Ramp'},
        {
          'prompt': 'Options',
          'answer': ['A', 'B'],
        },
        {'prompt': 'Agreed', 'answer': true},
        'Door code--ans--LOCAL',
        null,
        {'unexpected': 'ignored'},
      ],
    });
    expect(attendance.answers, [
      'Accessibility--ans--Ramp',
      'Options--ans--A, B',
      'Agreed--ans--Yes',
      'Door code--ans--LOCAL',
    ]);
  });

  test('door validation preserves legacy timing and uses current prompt', () {
    final questions = [
      {
        'prompt': 'Registration only',
        'timing': 'registration',
        'required': true,
      },
      {'questionTitle': 'Legacy door', 'required': true},
      {
        'prompt': 'Current door',
        'questionTitle': 'Old title',
        'timing': 'check_in',
        'required': true,
      },
    ].where(isRequiredCheckInQuestion).toList();
    expect(questions, hasLength(2));
    expect(checkInQuestionTitle(questions.last), 'Current door');
    expect(hasCheckInAnswer(questions.first, ['Legacy door--ans--OK']), isTrue);
    expect(
      hasCheckInAnswer(questions.last, ['Current door--ans--  ']),
      isFalse,
    );
    expect(
      hasCheckInAnswer(questions.last, [
        {'prompt': 'Current door', 'answer': 'Registration answer'},
      ]),
      isFalse,
    );
    expect(hasCheckInAnswer(questions.last, ['Current door--ans--OK']), isTrue);
  });
}
