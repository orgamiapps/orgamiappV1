import 'dart:async';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:attendus/Services/live_quiz_service.dart';

void main() {
  test(
    'host transition retries exact request id and observed server revision',
    () async {
      final mutations = <Map<String, dynamic>>[];
      final service = LiveQuizService.forTesting(
        currentUid: () => 'host',
        caller: (name, data) async {
          if (name == 'quizReadV1') {
            return {
              'data': {'id': 'quiz', 'revision': 7},
            };
          }
          mutations.add(data);
          if (mutations.length == 1) {
            throw FirebaseFunctionsException(
              code: 'unavailable',
              message: 'Temporary outage',
            );
          }
          return {'ok': true, 'quizId': 'quiz', 'revision': 8};
        },
      );
      expect(await service.nextQuestion('quiz'), true);
      expect(mutations, hasLength(2));
      expect(mutations[0], mutations[1]);
      expect(mutations[0]['expectedRevision'], 7);
      expect(mutations[0]['requestId'], isNotEmpty);
      service.dispose();
    },
  );
  test(
    'answer sends displayed run identity without client score or timing authority',
    () async {
      final mutations = <Map<String, dynamic>>[];
      final service = LiveQuizService.forTesting(
        currentUid: () => 'member',
        caller: (name, data) async {
          if (name == 'quizReadV1') {
            return {
              'data': {
                'id': 'question',
                'quizId': 'quiz',
                'session': 2,
                'question': 'Question',
                'options': ['A', 'B'],
              },
            };
          }
          mutations.add(data);
          return {'ok': true};
        },
      );
      final question = await service.getCurrentQuestion('quiz');
      expect(question!.correctOptionIndex, isNull);
      expect(
        await service.submitAnswer(
          quizId: 'quiz',
          questionId: question.id,
          participantId: 'self',
          questionIndex: 999,
          answer: 1,
          timeToAnswer: -999,
          session: question.session,
        ),
        true,
      );
      expect(mutations.single['payload'], {'answer': 1, 'session': 2});
      service.dispose();
    },
  );
  test('delayed old-account quiz data is discarded', () async {
    String? uid = 'a';
    final response = Completer<Map<String, dynamic>>();
    final service = LiveQuizService.forTesting(
      currentUid: () => uid,
      caller: (_, _) => response.future,
    );
    final pending = service.getQuiz('quiz');
    uid = 'b';
    response.complete({
      'data': {'id': 'quiz', 'revision': 1},
    });
    await expectLater(pending, throwsStateError);
    service.dispose();
  });
  test('redacted pending grade does not become an incorrect answer', () async {
    final service = LiveQuizService.forTesting(
      currentUid: () => 'member',
      caller: (_, _) async => {
        'data': {'id': 'answer', 'gradingPending': true, 'answer': 1},
      },
    );
    final response = await service.getParticipantResponse('self', 'question');
    expect(response!.scoringAvailable, false);
    service.dispose();
  });
}
