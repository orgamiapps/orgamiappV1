import 'package:attendus/screens/Events/Attendance/check_in_console_screen.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'approval that reaches capacity reports the returned waitlist outcome',
    () {
      expect(
        registrationDecisionMessage('approve', {'status': 'waitlisted'}),
        'Registration waitlisted.',
      );
    },
  );

  test('confirmed approval and promotion retain their successful copy', () {
    expect(
      registrationDecisionMessage('approve', {
        'status': 'confirmed',
        'ticketId': 'ticket',
      }),
      'Registration approved.',
    );
    expect(
      registrationDecisionMessage('promote', {'status': 'confirmed'}),
      'Registration promoted.',
    );
  });

  test('decline is based on the returned status', () {
    expect(
      registrationDecisionMessage('decline', {'status': 'declined'}),
      'Registration declined.',
    );
  });

  for (final status in [
    null,
    '',
    'pending',
    'CONFIRMED',
    true,
    1,
    <String>[],
  ]) {
    test('unsupported result $status cannot produce a success message', () {
      expect(
        () => registrationDecisionMessage('approve', {'status': status}),
        throwsA(isA<FormatException>()),
      );
    });
  }

  test('absent status cannot produce a success message', () {
    expect(
      () => registrationDecisionMessage('approve', {}),
      throwsA(isA<FormatException>()),
    );
  });

  for (final pair in [
    ('approve', 'declined'),
    ('decline', 'confirmed'),
    ('decline', 'waitlisted'),
    ('promote', 'waitlisted'),
    ('promote', 'declined'),
    ('unknown', 'confirmed'),
  ]) {
    test(
      'incompatible decision/status ${pair.$1}/${pair.$2} is not success',
      () {
        expect(
          () => registrationDecisionMessage(pair.$1, {'status': pair.$2}),
          throwsA(isA<FormatException>()),
        );
      },
    );
  }
}
