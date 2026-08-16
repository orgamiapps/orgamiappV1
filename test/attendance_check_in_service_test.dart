import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:attendus/Services/attendance_check_in_service.dart';

void main() {
  test('creates a web-safe attendance idempotency key', () {
    final key = createAttendanceIdempotencyKey(
      Random(7),
      now: DateTime.fromMicrosecondsSinceEpoch(123456),
    );

    expect(key, matches(RegExp(r'^123456-\d+$')));
    final randomPart = int.parse(key.split('-').last);
    expect(randomPart, inInclusiveRange(0, 0xffffffff));
  });
}
