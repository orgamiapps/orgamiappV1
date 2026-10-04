import 'package:attendus/models/notification_model.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

// This snapshot double exercises parsing without initializing a Firestore client.
// ignore: subtype_of_sealed_class
class _Snapshot extends Fake implements DocumentSnapshot<Map<String, dynamic>> {
  _Snapshot(this.fields);

  final Map<String, dynamic> fields;

  @override
  String get id => 'owned-notification';

  @override
  Map<String, dynamic> data() => fields;
}

NotificationModel notification(Map<String, dynamic> fields) =>
    NotificationModel.fromFirestore(
      _Snapshot({
        'title': 'Controlled notification',
        'body': 'Controlled message',
        'type': 'event_update',
        'createdAt': Timestamp.fromDate(DateTime.utc(2026, 10, 4)),
        ...fields,
      }),
    );

void main() {
  test('admin inbox payload resolves its nested event ID', () {
    final model = notification({
      'data': {'eventId': 'owned-event', 'announcementId': 'announcement'},
    });
    expect(model.eventId, 'owned-event');
    expect(model.data?['announcementId'], 'announcement');
  });

  test('a root event ID keeps precedence over a conflicting nested value', () {
    expect(
      notification({
        'eventId': 'root-event',
        'data': {'eventId': 'nested-event'},
      }).eventId,
      'root-event',
    );
  });

  test('a legacy null root event ID falls back to the nested value', () {
    expect(
      notification({
        'eventId': null,
        'data': {'eventId': 'nested-event'},
      }).eventId,
      'nested-event',
    );
  });

  test(
    'malformed nested data never breaks the inbox or overrides the root',
    () {
      for (final data in [
        null,
        42,
        'invalid',
        ['invalid'],
        {1: 'invalid'},
      ]) {
        final model = notification({'eventId': 'root-event', 'data': data});
        expect(model.eventId, 'root-event');
        expect(model.data, isNull);
      }
    },
  );

  test(
    'invalid root IDs fail closed without choosing a nested destination',
    () {
      for (final id in [
        '',
        42,
        {},
        [],
        ' padded ',
        'a/b',
        'a\n',
        '.',
        '..',
        'a' * 301,
      ]) {
        expect(
          notification({
            'eventId': id,
            'data': {'eventId': 'nested-event'},
          }).eventId,
          isNull,
        );
      }
    },
  );

  test('invalid nested IDs fail closed without breaking inbox parsing', () {
    for (final id in [null, '', 42, {}, [], 'a/b', ' padded ', 'a\n']) {
      expect(
        notification({
          'data': {'eventId': id},
        }).eventId,
        isNull,
      );
    }
  });

  test('root conversation compatibility survives malformed nested data', () {
    final model = notification({'conversationId': 'chat-1', 'data': []});
    expect(model.data?['conversationId'], 'chat-1');
    expect(model.eventId, isNull);
  });

  test('malformed discovery IDs remain distinct from intentional batches', () {
    for (final eventId in [42, {}, 'a/b', ' padded ']) {
      final model = notification({
        'type': 'discovery_new_events',
        'eventId': eventId,
      });
      expect(model.eventId, isNull);
      expect(model.hasInvalidEventId, isTrue);
      expect(model.copyWith(isRead: true).hasInvalidEventId, isTrue);
    }
    for (final eventId in [null, '']) {
      expect(
        notification({
          'type': 'discovery_new_events',
          'eventId': eventId,
        }).hasInvalidEventId,
        isFalse,
      );
    }
  });
}
