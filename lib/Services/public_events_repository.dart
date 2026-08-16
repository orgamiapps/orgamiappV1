import 'package:cloud_firestore/cloud_firestore.dart';

import 'package:attendus/Utils/logger.dart';
import 'package:attendus/models/event_model.dart';

enum FirestoreIndexDirection {
  ascending('ASCENDING'),
  descending('DESCENDING');

  const FirestoreIndexDirection(this.manifestValue);

  final String manifestValue;
}

class FirestoreIndexFieldContract {
  const FirestoreIndexFieldContract(this.fieldPath, this.direction);

  final String fieldPath;
  final FirestoreIndexDirection direction;
}

class FirestoreIndexContract {
  const FirestoreIndexContract({
    required this.id,
    required this.collectionGroup,
    required this.queryScope,
    required this.fields,
  });

  final String id;
  final String collectionGroup;
  final String queryScope;
  final List<FirestoreIndexFieldContract> fields;
}

class PublicEventsQuerySpec {
  const PublicEventsQuerySpec({
    required this.collectionPath,
    required this.visibilityField,
    required this.visibilityValue,
    required this.rangeField,
    required this.rangeOperator,
    required this.cutoff,
    required this.requiredIndex,
  });

  factory PublicEventsQuerySpec.forReferenceTime(DateTime referenceTime) {
    return PublicEventsQuerySpec(
      collectionPath: PublicEventsRepository.collectionPath,
      visibilityField: PublicEventsRepository.visibilityField,
      visibilityValue: false,
      rangeField: PublicEventsRepository.rangeField,
      rangeOperator: 'isGreaterThan',
      cutoff: referenceTime.subtract(PublicEventsRepository.queryLookback),
      requiredIndex: PublicEventsRepository.requiredIndex,
    );
  }

  final String collectionPath;
  final String visibilityField;
  final bool visibilityValue;
  final String rangeField;
  final String rangeOperator;
  final DateTime cutoff;
  final FirestoreIndexContract requiredIndex;
}

abstract interface class PublicEventsDataSource {
  Stream<List<EventModel>> watchActiveEvents({DateTime? referenceTime});
}

class PublicEventsRepository implements PublicEventsDataSource {
  PublicEventsRepository({FirebaseFirestore? firestore})
    : _firestore = firestore ?? FirebaseFirestore.instance;

  static const String collectionPath = 'Events';
  static const String visibilityField = 'private';
  static const String rangeField = 'selectedDateTime';
  static const Duration queryLookback = Duration(hours: 48);
  static const int maximumDocuments = 50;

  static const FirestoreIndexContract requiredIndex = FirestoreIndexContract(
    id: 'public-events-active',
    collectionGroup: collectionPath,
    queryScope: 'COLLECTION',
    fields: [
      FirestoreIndexFieldContract(
        visibilityField,
        FirestoreIndexDirection.ascending,
      ),
      FirestoreIndexFieldContract(
        rangeField,
        FirestoreIndexDirection.ascending,
      ),
    ],
  );

  final FirebaseFirestore _firestore;

  @override
  Stream<List<EventModel>> watchActiveEvents({DateTime? referenceTime}) {
    final spec = PublicEventsQuerySpec.forReferenceTime(
      referenceTime ?? DateTime.now(),
    );

    return _firestore
        .collection(spec.collectionPath)
        .where(spec.visibilityField, isEqualTo: spec.visibilityValue)
        .where(spec.rangeField, isGreaterThan: Timestamp.fromDate(spec.cutoff))
        .snapshots()
        .map(_mapSnapshot);
  }

  List<EventModel> _mapSnapshot(QuerySnapshot<Map<String, dynamic>> snapshot) {
    final events = <EventModel>[];
    for (final document in snapshot.docs.take(maximumDocuments)) {
      try {
        final data = Map<String, dynamic>.from(document.data());
        data['id'] = document.id;
        events.add(EventModel.fromJson(data));
      } catch (error, stackTrace) {
        Logger.error(
          'Skipping an invalid public event document',
          error,
          stackTrace,
        );
      }
    }
    return events;
  }
}

enum PublicEventsFailureKind {
  missingIndex,
  permissionDenied,
  offline,
  unknown,
}

class PublicEventsFailure {
  const PublicEventsFailure({
    required this.kind,
    required this.code,
    required this.userMessage,
  });

  final PublicEventsFailureKind kind;
  final String code;
  final String userMessage;

  static PublicEventsFailure classify(Object error) {
    final firebaseError = error is FirebaseException ? error : null;
    final code = firebaseError?.code.toLowerCase() ?? 'unknown';
    final message =
        firebaseError?.message?.toLowerCase() ?? error.toString().toLowerCase();

    if (code == 'failed-precondition' &&
        (message.contains('requires an index') ||
            message.contains('create_composite'))) {
      return const PublicEventsFailure(
        kind: PublicEventsFailureKind.missingIndex,
        code: 'failed-precondition',
        userMessage: 'Please try again in a moment.',
      );
    }

    if (code == 'permission-denied') {
      return const PublicEventsFailure(
        kind: PublicEventsFailureKind.permissionDenied,
        code: 'permission-denied',
        userMessage: 'Your account cannot load these events right now.',
      );
    }

    if (code == 'unavailable' ||
        code == 'network-request-failed' ||
        code == 'deadline-exceeded') {
      return PublicEventsFailure(
        kind: PublicEventsFailureKind.offline,
        code: code,
        userMessage:
            'You appear to be offline. Check your connection and retry.',
      );
    }

    return PublicEventsFailure(
      kind: PublicEventsFailureKind.unknown,
      code: code,
      userMessage: 'Please try again in a moment.',
    );
  }
}

class PublicEventsFeedState {
  List<EventModel> _lastSuccessfulEvents = const [];
  PublicEventsFailure? _failure;
  String? _lastReportedFailure;

  List<EventModel> get lastSuccessfulEvents => _lastSuccessfulEvents;
  PublicEventsFailure? get failure => _failure;
  bool get hasLastSuccessfulEvents => _lastSuccessfulEvents.isNotEmpty;

  void recordSuccess(List<EventModel> events) {
    _lastSuccessfulEvents = List<EventModel>.unmodifiable(events);
    _failure = null;
    _lastReportedFailure = null;
  }

  PublicEventsFailure recordFailure(Object error) {
    final failure = PublicEventsFailure.classify(error);
    _failure = failure;
    final signature = '${failure.kind.name}:${failure.code}';
    if (_lastReportedFailure != signature) {
      _lastReportedFailure = signature;
      Logger.error(
        'Public events query failed '
        '[kind=${failure.kind.name}, code=${failure.code}, '
        'contract=${PublicEventsRepository.requiredIndex.id}]',
        error,
      );
    }
    return failure;
  }
}
