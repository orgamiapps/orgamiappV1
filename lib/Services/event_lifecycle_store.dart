import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/widgets.dart';

enum EventLifecycleStatus {
  unknown,
  available,
  cancelled,
  deleted,
  unavailable,
}

class EventLifecycleState {
  const EventLifecycleState({
    this.status = EventLifecycleStatus.unknown,
    this.isServerConfirmed = false,
    this.data,
  });

  final EventLifecycleStatus status;
  final bool isServerConfirmed;
  final Map<String, dynamic>? data;
}

/// Small source boundary so lifecycle races can be tested without Firebase.
class EventLifecycleSnapshot {
  const EventLifecycleSnapshot({
    required this.exists,
    required this.fromCache,
    this.data,
  });

  final bool exists;
  final bool fromCache;
  final Map<String, dynamic>? data;
}

typedef EventLifecycleWatch =
    Stream<EventLifecycleSnapshot> Function(String eventId);

/// One authorized source listener per event, shared by every mounted surface.
///
/// This stores presentation state, never cached permissions. A denied read
/// means unavailable to the current session; it is not evidence of deletion.
class EventLifecycleStore extends ChangeNotifier with WidgetsBindingObserver {
  EventLifecycleStore({
    EventLifecycleWatch? watch,
    String? Function()? currentUserId,
    Stream<String?>? userChanges,
    bool observeAppLifecycle = true,
  }) : _watch = watch ?? _watchFirestore,
       _currentUserId =
           currentUserId ?? (() => FirebaseAuth.instance.currentUser?.uid),
       _userChanges = userChanges,
       _observeAppLifecycle = observeAppLifecycle;

  /// Replace with an injected store in full-screen tests; restore in tearDown.
  static EventLifecycleStore instance = EventLifecycleStore();

  final EventLifecycleWatch _watch;
  final String? Function() _currentUserId;
  final Stream<String?>? _userChanges;
  final bool _observeAppLifecycle;
  final Map<String, _EventWatch> _entries = {};
  final Map<String, EventLifecycleState> _states = {};
  final Map<String, EventLifecycleStatus> _confirmedMutations = {};
  final Set<String> _awaitingAuthorization = {};
  StreamSubscription<String?>? _auth;
  String? _uid;
  bool _started = false;
  bool _disposed = false;
  int _sessionGeneration = 0;
  int get sessionGeneration => _sessionGeneration;

  static Stream<EventLifecycleSnapshot> _watchFirestore(String id) =>
      FirebaseFirestore.instance
          .collection('Events')
          .doc(id)
          .snapshots(includeMetadataChanges: true)
          .map(
            (snapshot) => EventLifecycleSnapshot(
              exists: snapshot.exists,
              fromCache: snapshot.metadata.isFromCache,
              data: snapshot.data(),
            ),
          );

  EventLifecycleState stateFor(String id) =>
      _states[id] ?? const EventLifecycleState();

  bool allowsActive(String id) => switch (stateFor(id).status) {
    EventLifecycleStatus.cancelled ||
    EventLifecycleStatus.deleted ||
    EventLifecycleStatus.unavailable => false,
    _ => true,
  };

  bool allowsHistory(String id) => switch (stateFor(id).status) {
    EventLifecycleStatus.deleted || EventLifecycleStatus.unavailable => false,
    _ => true,
  };

  /// Public callers also need to reject a source that became private/hidden.
  bool allowsDiscovery(String id) {
    if (!allowsActive(id)) return false;
    final data = stateFor(id).data;
    return data == null ||
        (data['private'] == false &&
            data['isHidden'] != true &&
            data['deleted'] != true &&
            const ['active', 'scheduled'].contains(data['status']));
  }

  EventLifecycleLease retain(Iterable<String> ids) {
    _start();
    final lease = EventLifecycleLease._(this);
    lease.update(ids);
    return lease;
  }

  void _start() {
    if (_started || _disposed) return;
    // Widgets may be built during bootstrap before Firebase is initialized.
    // The next retain/reconcile retries; no event is declared removed.
    try {
      _uid = _currentUserId();
      final changes =
          _userChanges ??
          FirebaseAuth.instance.authStateChanges().map((user) => user?.uid);
      _auth = changes.distinct().listen(_onUserChanged);
      if (_observeAppLifecycle) WidgetsBinding.instance.addObserver(this);
      _started = true;
    } catch (_) {
      return;
    }
  }

  void _onUserChanged(String? uid) {
    if (_disposed || uid == _uid) return;
    _uid = uid;
    ++_sessionGeneration;
    _states.clear();
    _confirmedMutations.clear();
    _awaitingAuthorization
      ..clear()
      ..addAll(_entries.keys);
    for (final id in _awaitingAuthorization) {
      // Source lists can survive an account change in an IndexedStack. Hide
      // their previous account's data until this session proves read access.
      _states[id] = const EventLifecycleState(
        status: EventLifecycleStatus.unavailable,
      );
    }
    for (final entry in _entries.values) {
      _stop(entry);
    }
    for (final entry in _entries.values) {
      _listen(entry);
    }
    notifyListeners();
  }

  void _acquire(String id) {
    final entry = _entries.putIfAbsent(id, () => _EventWatch(id));
    entry.references++;
    if (_sessionGeneration > 0 && !stateFor(id).isServerConfirmed) {
      // A detached list may return after the account changes. Firestore's
      // persistent cache is shared across accounts, so newly retained IDs
      // also need this session's server authorization before showing data.
      _awaitingAuthorization.add(id);
      _states[id] = const EventLifecycleState(
        status: EventLifecycleStatus.unavailable,
      );
    }
    if (entry.references == 1 ||
        (entry.subscription == null && entry.retry == null)) {
      _listen(entry);
    }
  }

  void _release(String id) {
    final entry = _entries[id];
    if (entry == null) return;
    if (--entry.references > 0) return;
    _stop(entry);
    _entries.remove(id);
    // Retain terminal results to prevent delayed requests and route caches
    // from resurrecting a removed card for the rest of this auth session.
    if (stateFor(id).status == EventLifecycleStatus.available &&
        allowsDiscovery(id)) {
      _states.remove(id);
    }
  }

  void _stop(_EventWatch entry) {
    ++entry.generation;
    entry.retry?.cancel();
    entry.retry = null;
    unawaited(entry.subscription?.cancel());
    entry.subscription = null;
  }

  void _listen(_EventWatch entry) {
    if (_disposed ||
        !_started ||
        _uid == null ||
        entry.references == 0 ||
        _confirmedMutations[entry.id] == EventLifecycleStatus.deleted) {
      return;
    }
    final generation = ++entry.generation;
    final session = _sessionGeneration;
    bool current() =>
        !_disposed &&
        entry.references > 0 &&
        entry.generation == generation &&
        session == _sessionGeneration;
    try {
      entry.subscription = _watch(entry.id).listen(
        (snapshot) {
          if (!current()) return;
          entry.failures = 0;
          _accept(entry.id, snapshot);
        },
        onError: (Object error) {
          if (!current()) return;
          unawaited(entry.subscription?.cancel());
          entry.subscription = null;
          final denied =
              error is FirebaseException && error.code == 'permission-denied';
          if (denied &&
              _confirmedMutations[entry.id] != EventLifecycleStatus.deleted) {
            _confirmedMutations.remove(entry.id);
            _states[entry.id] = const EventLifecycleState(
              status: EventLifecycleStatus.unavailable,
              isServerConfirmed: true,
            );
            notifyListeners();
          }
          // Firestore listeners stop after terminal errors. Retry transient
          // failures; denied subscriptions are retried on resume/reconcile.
          if (!denied) _scheduleRetry(entry, generation, session);
        },
      );
    } catch (_) {
      _scheduleRetry(entry, generation, session);
    }
  }

  void _scheduleRetry(_EventWatch entry, int generation, int session) {
    entry.retry?.cancel();
    final seconds = 1 << entry.failures.clamp(0, 5);
    entry.failures++;
    entry.retry = Timer(Duration(seconds: seconds), () {
      if (_disposed ||
          entry.references == 0 ||
          entry.generation != generation ||
          _sessionGeneration != session) {
        return;
      }
      _stop(entry);
      _listen(entry);
    });
  }

  void _accept(String id, EventLifecycleSnapshot snapshot) {
    if (_confirmedMutations[id] == EventLifecycleStatus.deleted) return;
    final data = snapshot.data;
    final sourceCancelled = const [
      'cancelled',
      'canceled',
    ].contains(data?['status']);
    if (_confirmedMutations[id] == EventLifecycleStatus.cancelled &&
        (snapshot.fromCache ||
            (snapshot.exists &&
                data?['deleted'] != true &&
                !sourceCancelled))) {
      return;
    }
    if (snapshot.fromCache && _awaitingAuthorization.contains(id)) return;
    if (!snapshot.fromCache) _awaitingAuthorization.remove(id);
    final previous = stateFor(id);
    // Local cache absence is not authoritative, especially when the initial
    // card was fetched through a callable instead of the Firestore client.
    if (snapshot.fromCache &&
        (!snapshot.exists || previous.isServerConfirmed)) {
      return;
    }
    final status = !snapshot.exists || data?['deleted'] == true
        ? EventLifecycleStatus.deleted
        : sourceCancelled
        ? EventLifecycleStatus.cancelled
        : EventLifecycleStatus.available;
    _states[id] = EventLifecycleState(
      status: status,
      isServerConfirmed: !snapshot.fromCache,
      data: data == null
          ? null
          : Map<String, dynamic>.unmodifiable({...data, 'id': id}),
    );
    notifyListeners();
  }

  /// Called only after an authoritative callable success/reconciliation.
  /// This overlay intentionally outranks late listener and HTTP responses.
  void applyConfirmed({
    required Iterable<String> eventIds,
    required EventLifecycleStatus status,
  }) {
    assert(
      status == EventLifecycleStatus.deleted ||
          status == EventLifecycleStatus.cancelled,
    );
    _start();
    for (final id in eventIds.where((id) => id.isNotEmpty).toSet()) {
      if (_confirmedMutations[id] == EventLifecycleStatus.deleted) continue;
      final previous = stateFor(id);
      if (status == EventLifecycleStatus.cancelled &&
          previous.isServerConfirmed &&
          previous.status == EventLifecycleStatus.deleted) {
        continue;
      }
      final priorData = previous.data;
      _confirmedMutations[id] = status;
      _states[id] = EventLifecycleState(
        status: status,
        isServerConfirmed: true,
        data: priorData == null
            ? null
            : {
                ...priorData,
                'id': id,
                'status': status.name,
                if (status == EventLifecycleStatus.deleted) 'deleted': true,
              },
      );
      final entry = _entries[id];
      if (entry != null && status == EventLifecycleStatus.deleted) _stop(entry);
    }
    notifyListeners();
  }

  /// Reattach sources on foreground/retry while preserving confirmed removals.
  void reconcile() {
    if (_disposed) return;
    _start();
    for (final entry in _entries.values) {
      _stop(entry);
      _listen(entry);
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) reconcile();
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    ++_sessionGeneration;
    if (_started && _observeAppLifecycle) {
      WidgetsBinding.instance.removeObserver(this);
    }
    unawaited(_auth?.cancel());
    for (final entry in _entries.values) {
      _stop(entry);
    }
    _entries.clear();
    super.dispose();
  }
}

class _EventWatch {
  _EventWatch(this.id);
  final String id;
  int references = 0;
  int generation = 0;
  int failures = 0;
  StreamSubscription<EventLifecycleSnapshot>? subscription;
  Timer? retry;
}

class EventLifecycleLease {
  EventLifecycleLease._(this._store);
  final EventLifecycleStore _store;
  Set<String> _ids = {};
  bool _disposed = false;

  void update(Iterable<String> eventIds) {
    if (_disposed) return;
    final next = eventIds.where((id) => id.isNotEmpty).toSet();
    for (final id in _ids.difference(next)) {
      _store._release(id);
    }
    for (final id in next.difference(_ids)) {
      _store._acquire(id);
    }
    _ids = next;
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    for (final id in _ids) {
      _store._release(id);
    }
    _ids = {};
  }
}
