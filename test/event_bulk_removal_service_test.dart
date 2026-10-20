import 'dart:async';
import 'package:attendus/Services/event_bulk_removal_service.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'bulk continues after known populated-event failure and reports each success',
    () async {
      final called = <String>[];
      final removed = <String>[];
      final service = EventBulkRemovalService(
        deleteEvent: (id) async {
          called.add(id);
          if (id == 'populated') {
            throw FirebaseFunctionsException(
              code: 'failed-precondition',
              message: 'Cancel to keep records.',
            );
          }
        },
      );
      final result = await service.remove(
        eventIds: ['a', 'populated', 'b'],
        isCurrentAccount: () => true,
        onDeleted: removed.add,
      );
      expect(called, ['a', 'populated', 'b']);
      expect(removed, ['a', 'b']);
      expect(result.deletedIds, ['a', 'b']);
      expect(result.keptErrors.keys, ['populated']);
      expect(result.unconfirmedIds, isEmpty);
      expect(result.summary, contains('2 events deleted.'));
    },
  );

  test(
    'bulk stops on uncertain commit and distinguishes events never attempted',
    () async {
      final called = <String>[];
      final service = EventBulkRemovalService(
        deleteEvent: (id) async {
          called.add(id);
          if (id == 'uncertain') throw TimeoutException('response lost');
        },
      );
      final result = await service.remove(
        eventIds: ['a', 'uncertain', 'waiting'],
        isCurrentAccount: () => true,
      );
      expect(called, ['a', 'uncertain']);
      expect(result.deletedIds, ['a']);
      expect(result.unconfirmedIds, ['uncertain']);
      expect(result.unattemptedIds, ['waiting']);
      expect(result.keptErrors, isEmpty);
      expect(result.summary, contains('deletion is unconfirmed'));
      expect(result.summary, contains('1 event was not attempted'));
      expect(result.summary, isNot(contains('were kept')));
    },
  );

  test(
    'account changes stop the batch and suppress stale local updates',
    () async {
      var current = true;
      final service = EventBulkRemovalService(
        deleteEvent: (_) async {
          current = false;
        },
      );
      final result = await service.remove(
        eventIds: ['a', 'b'],
        isCurrentAccount: () => current,
        onDeleted: (_) => fail('Must not alter another account selection'),
      );
      expect(result.accountChanged, true);
      expect(result.deletedIds, isEmpty);
      expect(result.unattemptedIds, ['b']);
    },
  );
}
