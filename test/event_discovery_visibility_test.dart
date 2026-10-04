import 'package:attendus/Utils/event_discovery_visibility.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'public discovery permits only explicit published and visible events',
    () {
      for (final status in ['active', 'scheduled']) {
        expect(
          isDiscoverableEventData({'private': false, 'status': status}),
          isTrue,
        );
      }
      for (final status in [
        null,
        '',
        'draft',
        'pending_approval',
        'rejected',
        'cancelled',
        'ended',
      ]) {
        expect(
          isDiscoverableEventData({'private': false, 'status': status}),
          isFalse,
          reason: '$status',
        );
      }
    },
  );
  test(
    'discovery does not expose missing privacy, private or tombstoned events',
    () {
      for (final data in <Map<String, dynamic>>[
        {'status': 'active'},
        {'private': true, 'status': 'scheduled'},
        {'private': false, 'status': 'active', 'isHidden': true},
        {'private': false, 'status': 'scheduled', 'deleted': true},
      ]) {
        expect(isDiscoverableEventData(data), isFalse);
      }
    },
  );
}
