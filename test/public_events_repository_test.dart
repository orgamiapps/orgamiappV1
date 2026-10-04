import 'dart:convert';
import 'dart:io';

import 'package:firebase_core/firebase_core.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:attendus/Services/public_events_repository.dart';
import 'package:attendus/models/event_model.dart';

void main() {
  group('PublicEventsQuerySpec', () {
    test('describes the production Discover query exactly', () {
      final referenceTime = DateTime.utc(2026, 8, 4, 12);
      final spec = PublicEventsQuerySpec.forReferenceTime(referenceTime);

      expect(spec.collectionPath, 'Events');
      expect(spec.visibilityField, 'private');
      expect(spec.visibilityValue, isFalse);
      expect(spec.rangeField, 'selectedDateTime');
      expect(spec.rangeOperator, 'isGreaterThan');
      expect(spec.cutoff, DateTime.utc(2026, 8, 2, 12));
      expect(spec.requiredIndex.id, 'public-events-active');
    });

    test('required composite index is present in the checked-in manifest', () {
      final manifest =
          jsonDecode(File('firestore.indexes.json').readAsStringSync())
              as Map<String, dynamic>;
      final contract = PublicEventsRepository.requiredIndex;
      final indexes = (manifest['indexes'] as List<dynamic>)
          .cast<Map<String, dynamic>>();

      final hasRequiredIndex = indexes.any((index) {
        if (index['collectionGroup'] != contract.collectionGroup ||
            index['queryScope'] != contract.queryScope) {
          return false;
        }
        final fields = (index['fields'] as List<dynamic>)
            .cast<Map<String, dynamic>>();
        if (fields.length != contract.fields.length) return false;

        for (var index = 0; index < fields.length; index++) {
          final actual = fields[index];
          final expected = contract.fields[index];
          if (actual['fieldPath'] != expected.fieldPath ||
              actual['order'] != expected.direction.manifestValue) {
            return false;
          }
        }
        return true;
      });

      expect(
        hasRequiredIndex,
        isTrue,
        reason:
            'The ${contract.id} query requires a matching entry in '
            'firestore.indexes.json.',
      );
    });
  });

  group('PublicEventsFailure', () {
    test('classifies and redacts a missing-index failure', () {
      final failure = PublicEventsFailure.classify(
        FirebaseException(
          plugin: 'cloud_firestore',
          code: 'failed-precondition',
          message:
              'The query requires an index. Create it at '
              'https://console.firebase.google.com/project/example/indexes',
        ),
      );

      expect(failure.kind, PublicEventsFailureKind.missingIndex);
      expect(failure.code, 'failed-precondition');
      expect(failure.userMessage, 'Please try again in a moment.');
      expect(failure.userMessage, isNot(contains('firebase.google.com')));
      expect(failure.userMessage, isNot(contains('requires an index')));
    });

    test('distinguishes permission, offline, and unknown failures', () {
      PublicEventsFailure classify(String code) => PublicEventsFailure.classify(
        FirebaseException(plugin: 'cloud_firestore', code: code),
      );

      expect(
        classify('permission-denied').kind,
        PublicEventsFailureKind.permissionDenied,
      );
      expect(classify('unavailable').kind, PublicEventsFailureKind.offline);
      expect(classify('internal').kind, PublicEventsFailureKind.unknown);
    });
  });

  test('feed state retains last-known-good events after a stream failure', () {
    final state = PublicEventsFeedState();
    final event = _event();

    state.recordSuccess([event]);
    state.recordFailure(
      FirebaseException(plugin: 'cloud_firestore', code: 'unavailable'),
    );

    expect(state.hasLastSuccessfulEvents, isTrue);
    expect(state.lastSuccessfulEvents, [same(event)]);
    expect(state.failure?.kind, PublicEventsFailureKind.offline);
  });
}

EventModel _event() {
  final startsAt = DateTime.utc(2026, 8, 5, 18);
  return EventModel(
    id: 'event-1',
    groupName: 'AttendUs',
    title: 'Public event',
    description: 'Test event',
    location: 'Online',
    customerUid: 'owner',
    imageUrl: '',
    selectedDateTime: startsAt,
    eventGenerateTime: startsAt.subtract(const Duration(days: 1)),
    status: 'active',
    private: false,
    getLocation: false,
    radius: 0,
    latitude: 0,
    longitude: 0,
  );
}
