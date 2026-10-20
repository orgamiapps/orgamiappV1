import 'dart:async';

import 'package:attendus/Services/event_lifecycle_store.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late EventLifecycleStore store;
  late StreamController<String?> auth;
  late Map<String, List<StreamController<EventLifecycleSnapshot>>> streams;
  String? uid;

  Future<void> flush() async {
    await Future<void>.delayed(Duration.zero);
  }

  void emit(
    String id, {
    bool exists = true,
    bool cached = false,
    String status = 'scheduled',
    bool private = false,
  }) => streams[id]!.last.add(
    EventLifecycleSnapshot(
      exists: exists,
      fromCache: cached,
      data: exists ? {'status': status, 'private': private} : null,
    ),
  );

  setUp(() {
    uid = 'owner';
    auth = StreamController<String?>.broadcast();
    streams = {};
    store = EventLifecycleStore(
      currentUserId: () => uid,
      userChanges: auth.stream,
      observeAppLifecycle: false,
      watch: (id) {
        final controller = StreamController<EventLifecycleSnapshot>.broadcast();
        streams.putIfAbsent(id, () => []).add(controller);
        return controller.stream;
      },
    );
  });

  tearDown(() async {
    store.dispose();
    await auth.close();
    for (final controllers in streams.values) {
      for (final controller in controllers) {
        await controller.close();
      }
    }
  });

  test('surfaces share a reference-counted event subscription', () {
    final a = store.retain(['one', 'one']);
    final b = store.retain(['one', 'two']);
    expect(streams['one'], hasLength(1));
    a.dispose();
    expect(streams['one']!.single.hasListener, isTrue);
    b.update(['two']);
    expect(streams['one']!.single.hasListener, isFalse);
    b.dispose();
    expect(streams['two']!.single.hasListener, isFalse);
  });

  test('cached absence cannot delete a callable-loaded card', () async {
    store.retain(['one']);
    emit('one', exists: false, cached: true);
    await flush();
    expect(store.allowsActive('one'), isTrue);
    expect(store.stateFor('one').isServerConfirmed, isFalse);
    emit('one');
    await flush();
    emit('one', exists: false, cached: true);
    await flush();
    expect(store.allowsActive('one'), isTrue);
    emit('one', exists: false);
    await flush();
    expect(store.stateFor('one').status, EventLifecycleStatus.deleted);
    expect(store.allowsHistory('one'), isFalse);
  });

  test('cancelled events leave active lists but retain history', () async {
    store.retain(['one']);
    emit('one', status: 'cancelled');
    await flush();
    expect(store.allowsActive('one'), isFalse);
    expect(store.allowsHistory('one'), isTrue);
  });

  test(
    'privacy change removes discovery without denying owner access',
    () async {
      store.retain(['one']);
      emit('one', private: true);
      await flush();
      expect(store.allowsDiscovery('one'), isFalse);
      expect(store.allowsActive('one'), isTrue);
      expect(store.allowsHistory('one'), isTrue);
    },
  );

  test('confirmed mutation wins over late source responses', () async {
    store.retain(['one']);
    store.applyConfirmed(
      eventIds: ['one'],
      status: EventLifecycleStatus.cancelled,
    );
    emit('one');
    await flush();
    expect(store.stateFor('one').status, EventLifecycleStatus.cancelled);
    store.applyConfirmed(
      eventIds: ['one'],
      status: EventLifecycleStatus.deleted,
    );
    store.applyConfirmed(
      eventIds: ['one'],
      status: EventLifecycleStatus.cancelled,
    );
    expect(store.stateFor('one').status, EventLifecycleStatus.deleted);
  });

  test(
    'server cancellation refreshes history after local confirmation',
    () async {
      store.retain(['one']);
      emit('one');
      await flush();
      store.applyConfirmed(
        eventIds: ['one'],
        status: EventLifecycleStatus.cancelled,
      );
      streams['one']!.last.add(
        const EventLifecycleSnapshot(
          exists: true,
          fromCache: false,
          data: {
            'status': 'cancelled',
            'private': false,
            'cancellationReason': 'Severe weather',
            'cancelledAt': '2030-10-19T15:00:00Z',
          },
        ),
      );
      await flush();
      expect(
        store.stateFor('one').data?['cancellationReason'],
        'Severe weather',
      );
      expect(
        store.stateFor('one').data?['cancelledAt'],
        '2030-10-19T15:00:00Z',
      );
      expect(store.allowsHistory('one'), isTrue);
      expect(store.allowsActive('one'), isFalse);

      emit('one');
      emit('one', cached: true, status: 'cancelled');
      await flush();
      expect(store.stateFor('one').status, EventLifecycleStatus.cancelled);
      expect(
        store.stateFor('one').data?['cancellationReason'],
        'Severe weather',
      );
    },
  );

  test('late cancellation cannot restore server-deleted history', () async {
    store.retain(['missing', 'deleted']);
    store.applyConfirmed(
      eventIds: ['missing'],
      status: EventLifecycleStatus.cancelled,
    );
    emit('missing', exists: false);
    streams['deleted']!.last.add(
      const EventLifecycleSnapshot(
        exists: true,
        fromCache: false,
        data: {'status': 'cancelled', 'deleted': true},
      ),
    );
    await flush();
    store.applyConfirmed(
      eventIds: ['missing', 'deleted'],
      status: EventLifecycleStatus.cancelled,
    );
    for (final id in ['missing', 'deleted']) {
      expect(store.stateFor(id).status, EventLifecycleStatus.deleted);
      expect(store.stateFor(id).isServerConfirmed, isTrue);
      expect(store.allowsHistory(id), isFalse);
    }
  });

  test('permission denial is unavailable, never asserted deleted', () async {
    store.retain(['one']);
    streams['one']!.last.addError(
      FirebaseException(plugin: 'cloud_firestore', code: 'permission-denied'),
    );
    await flush();
    expect(store.stateFor('one').status, EventLifecycleStatus.unavailable);
    store.reconcile();
    emit('one');
    await flush();
    expect(store.allowsActive('one'), isTrue);
  });

  test(
    'account change clears scoped suppression and rejects old streams',
    () async {
      store.retain(['one']);
      final previous = streams['one']!.last;
      store.applyConfirmed(
        eventIds: ['one'],
        status: EventLifecycleStatus.cancelled,
      );
      uid = 'next';
      auth.add(uid);
      await flush();
      expect(streams['one'], hasLength(2));
      expect(store.allowsHistory('one'), isFalse);
      emit('one', cached: true);
      await flush();
      expect(store.allowsHistory('one'), isFalse);
      previous.add(
        const EventLifecycleSnapshot(exists: false, fromCache: false),
      );
      emit('one');
      await flush();
      expect(store.stateFor('one').status, EventLifecycleStatus.available);
    },
  );

  test('releasing and reloading preserves a confirmed removal', () {
    final lease = store.retain(['one']);
    store.applyConfirmed(
      eventIds: ['one'],
      status: EventLifecycleStatus.deleted,
    );
    lease.dispose();
    store.retain(['one']);
    expect(store.allowsActive('one'), isFalse);
    expect(streams['one'], hasLength(1));
  });

  test(
    'detached private events wait for current-account server authorization',
    () async {
      final lease = store.retain(['private-event']);
      emit('private-event', private: true);
      await flush();
      expect(store.allowsHistory('private-event'), isTrue);
      lease.dispose();

      uid = 'next';
      auth.add(uid);
      await flush();
      store.retain(['private-event']);
      expect(store.allowsHistory('private-event'), isFalse);
      emit('private-event', private: true, cached: true);
      await flush();
      expect(store.allowsHistory('private-event'), isFalse);
      expect(store.stateFor('private-event').data, isNull);

      streams['private-event']!.last.addError(
        FirebaseException(plugin: 'cloud_firestore', code: 'permission-denied'),
      );
      await flush();
      expect(
        store.stateFor('private-event').status,
        EventLifecycleStatus.unavailable,
      );
      expect(store.stateFor('private-event').data, isNull);

      store.reconcile();
      emit('private-event', private: true);
      await flush();
      expect(store.allowsHistory('private-event'), isTrue);
      expect(store.allowsDiscovery('private-event'), isFalse);
    },
  );

  test(
    'late source IDs after an account change cannot trust cached data',
    () async {
      store.retain(const []);
      uid = 'next';
      auth.add(uid);
      await flush();

      store.retain(['late-event']);
      emit('late-event', private: true, cached: true);
      await flush();
      expect(store.allowsHistory('late-event'), isFalse);
      expect(store.stateFor('late-event').data, isNull);
      emit('late-event');
      await flush();
      expect(store.allowsDiscovery('late-event'), isTrue);
    },
  );

  test(
    'independent online sessions receive public and private cancellation',
    () async {
      final second = EventLifecycleStore(
        currentUserId: () => 'other-authorized-user',
        userChanges: const Stream<String?>.empty(),
        observeAppLifecycle: false,
        watch: (id) => streams[id]!.single.stream,
      );
      addTearDown(second.dispose);
      store.retain(['public-event', 'private-event']);
      second.retain(['public-event', 'private-event']);
      emit('public-event');
      emit('private-event', private: true);
      await flush();
      for (final session in [store, second]) {
        expect(session.allowsDiscovery('public-event'), isTrue);
        expect(session.allowsHistory('private-event'), isTrue);
        expect(session.allowsDiscovery('private-event'), isFalse);
      }

      store.applyConfirmed(
        eventIds: ['public-event', 'private-event'],
        status: EventLifecycleStatus.cancelled,
      );
      expect(second.allowsActive('public-event'), isTrue);
      emit('public-event', status: 'cancelled');
      emit('private-event', status: 'cancelled', private: true);
      await flush();
      for (final session in [store, second]) {
        for (final id in ['public-event', 'private-event']) {
          expect(session.allowsActive(id), isFalse);
          expect(session.allowsHistory(id), isTrue);
          expect(session.stateFor(id).isServerConfirmed, isTrue);
        }
      }
    },
  );
}
