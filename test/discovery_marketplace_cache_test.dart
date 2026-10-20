import 'dart:async';
import 'dart:convert';

import 'package:attendus/Services/discovery_marketplace_service.dart';
import 'package:attendus/Services/event_lifecycle_store.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _home = <String, dynamic>{
  'sections': [
    {
      'id': 'near_you',
      'events': [
        {
          'id': 'one',
          'title': 'Cached event',
          'groupName': 'Community',
          'description': 'Fixture event',
          'location': 'Park',
          'imageUrl': '',
          'customerUid': 'owner',
          'private': false,
          'status': 'scheduled',
          'selectedDateTime': '2030-10-19T21:00:00Z',
          'eventGenerateTime': '2030-10-01T12:00:00Z',
        },
      ],
    },
  ],
};

class _Result<T> extends Fake implements HttpsCallableResult<T> {
  _Result(this.data);
  @override
  final T data;
}

class _Callable extends Fake implements HttpsCallable {
  _Callable(this.functions);
  final _Functions functions;

  @override
  Future<HttpsCallableResult<T>> call<T>([dynamic parameters]) async =>
      _Result<T>(await functions.handler() as T);
}

class _Functions extends Fake implements FirebaseFunctions {
  Future<Map<String, dynamic>> Function() handler = () async => {..._home};

  @override
  HttpsCallable httpsCallable(String name, {HttpsCallableOptions? options}) =>
      _Callable(this);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late EventLifecycleStore previousStore;
  late EventLifecycleStore store;
  late DiscoveryMarketplaceService service;
  late _Functions functions;
  late StreamController<String?> auth;
  late StreamController<EventLifecycleSnapshot> events;
  String? uid;

  Future<void> flush() => Future<void>.delayed(Duration.zero);
  Future<void> cacheHome() async {
    await service.home(latitude: 0, longitude: 0);
  }

  Future<void> expireCache() async {
    final prefs = await SharedPreferences.getInstance();
    final key = prefs.getKeys().single;
    final cached = jsonDecode(prefs.getString(key)!) as Map<String, dynamic>;
    cached['_cachedAt'] = DateTime.now()
        .subtract(const Duration(hours: 1))
        .toIso8601String();
    await prefs.setString(key, jsonEncode(cached));
  }

  Future<void> authorizeEvent() async {
    store.retain(['one']);
    events.add(
      const EventLifecycleSnapshot(
        exists: true,
        fromCache: false,
        data: {'status': 'scheduled', 'private': false},
      ),
    );
    await flush();
  }

  void offline() {
    functions.handler = () async => throw FirebaseFunctionsException(
      code: 'unavailable',
      message: 'Offline',
    );
  }

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    uid = 'owner';
    auth = StreamController<String?>.broadcast();
    events = StreamController<EventLifecycleSnapshot>.broadcast();
    previousStore = EventLifecycleStore.instance;
    store = EventLifecycleStore(
      currentUserId: () => uid,
      userChanges: auth.stream,
      observeAppLifecycle: false,
      watch: (_) => events.stream,
    );
    EventLifecycleStore.instance = store;
    functions = _Functions();
    service = DiscoveryMarketplaceService(functions: functions);
  });

  tearDown(() async {
    EventLifecycleStore.instance = previousStore;
    store.dispose();
    await auth.close();
    await events.close();
  });

  test('offline fallback cannot reuse an unvalidated cached event', () async {
    await cacheHome();
    offline();
    await expectLater(
      service.home(latitude: 0, longitude: 0),
      throwsA(isA<FirebaseFunctionsException>()),
    );
  });

  test(
    'offline fallback keeps validated events and filters removals',
    () async {
      await cacheHome();
      await authorizeEvent();
      await expireCache();
      offline();
      final result = await service.home(latitude: 0, longitude: 0);
      expect(result.cacheState, 'stale');
      expect(result.sections.single.events.single.event.id, 'one');

      store.applyConfirmed(
        eventIds: ['one'],
        status: EventLifecycleStatus.deleted,
      );
      final removed = await service.home(latitude: 0, longitude: 0);
      expect(removed.sections.single.events, isEmpty);
    },
  );

  test('fallback rechecks the account after an in-flight failure', () async {
    await cacheHome();
    await authorizeEvent();
    await expireCache();
    final pending = Completer<Map<String, dynamic>>();
    functions.handler = () => pending.future;
    final request = service.home(latitude: 0, longitude: 0);
    final expectation = expectLater(
      request,
      throwsA(isA<FirebaseFunctionsException>()),
    );
    await flush();
    uid = 'next';
    auth.add(uid);
    await flush();
    pending.completeError(
      FirebaseFunctionsException(code: 'unavailable', message: 'Offline'),
    );
    await expectation;
  });
}
