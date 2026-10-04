import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter_test/flutter_test.dart';
import '../integration_test/roster_readiness.dart';

void main() {
  Future<void> noDelay() async {}
  FirebaseFunctionsException unavailable() => FirebaseFunctionsException(
    code: 'unavailable',
    message: 'Roster rebuilding',
  );

  test('roster rebuild reads retry and return the ready result', () async {
    var calls = 0;
    final result = await waitForRoster(() async {
      if (++calls < 3) throw unavailable();
      return ['attendee'];
    }, retryDelay: noDelay);
    expect(calls, 3);
    expect(result, ['attendee']);
  });

  test('access denial is not retried', () async {
    var calls = 0;
    await expectLater(
      waitForRoster(() async {
        calls++;
        throw FirebaseFunctionsException(
          code: 'permission-denied',
          message: 'No access',
        );
      }, retryDelay: noDelay),
      throwsA(isA<FirebaseFunctionsException>()),
    );
    expect(calls, 1);
  });

  test(
    'later lifecycle failure cannot replay the successful read or admission',
    () async {
      var reads = 0;
      var admissions = 0;
      Future<void> journey() async {
        await waitForRoster(() async => ++reads, retryDelay: noDelay);
        admissions++;
        await Future<void>.error(unavailable());
      }

      await expectLater(journey(), throwsA(isA<FirebaseFunctionsException>()));
      expect(reads, 1);
      expect(admissions, 1);
    },
  );

  test('roster rebuild retries stop at their configured limit', () async {
    var calls = 0;
    await expectLater(
      waitForRoster(
        () async {
          calls++;
          throw unavailable();
        },
        maxAttempts: 2,
        retryDelay: noDelay,
      ),
      throwsA(isA<FirebaseFunctionsException>()),
    );
    expect(calls, 2);
  });
}
