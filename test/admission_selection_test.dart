import 'package:attendus/Services/admission_selection.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('account switches and refreshes reject stale reads', () {
    final guard = AdmissionRequestGuard();
    final old = guard.begin('alice');
    expect(guard.accepts(old, 'alice'), isTrue);
    expect(guard.accepts(old, 'bob'), isFalse);
    guard.invalidate();
    final current = guard.begin('bob');
    expect(guard.accepts(old, 'alice'), isFalse);
    expect(guard.accepts(current, 'bob'), isTrue);
    final refreshed = guard.begin('bob');
    expect(guard.accepts(current, 'bob'), isFalse);
    expect(guard.accepts(refreshed, 'bob'), isTrue);
    guard.invalidate();
    expect(guard.accepts(refreshed, 'bob'), isFalse);
  });
  test('multiple admissions never select a guessed registration or QR', () {
    final rows = <Map<String, dynamic>>[
      {'registrationId': 'r1', 'ticketId': 't1', 'status': 'confirmed'},
      {'registrationId': 'r2', 'ticketId': 't2', 'status': 'confirmed'},
      {'registrationId': 'r3', 'ticketId': null, 'status': 'pending'},
    ];
    expect(selectAdmission(rows), isNull);
    expect(selectAdmission(rows, registrationId: 'r1', ticketId: 't2'), isNull);
    expect(selectAdmission(rows, ticketId: 't2'), same(rows[1]));
    expect(selectAdmission(rows, registrationId: 'r3'), same(rows[2]));
    expect(selectAdmission(rows, registrationId: 'removed'), isNull);
    expect(selectAdmission([rows[2]]), same(rows[2]));
  });
  test('duplicate linkage is ambiguous even with an explicit registration', () {
    final rows = <Map<String, dynamic>>[
      {'registrationId': 'r1', 'ticketId': 't1'},
      {'registrationId': 'r1', 'ticketId': 't2'},
    ];
    expect(selectAdmission(rows, registrationId: 'r1'), isNull);
    expect(
      selectAdmission(rows, registrationId: 'r1', ticketId: 't2'),
      same(rows[1]),
    );
  });
}
