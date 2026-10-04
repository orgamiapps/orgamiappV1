import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:attendus/Services/public_profile_service.dart';
import 'package:attendus/models/customer_model.dart';

Map<String, dynamic> card(String uid) => {
  'uid': uid,
  'name': 'Member $uid',
  'username': uid,
  'bio': 'Public bio',
  'isDiscoverable': true,
};

void main() {
  late String? actor;
  late StreamController<String?> changes;
  late List<(String, Map<String, dynamic>)> calls;
  late Future<Map<String, dynamic>> Function(String, Map<String, dynamic>)
  respond;
  late PublicProfileService service;

  setUp(() {
    actor = 'owner';
    changes = StreamController<String?>.broadcast(sync: true);
    calls = [];
    respond = (name, data) async => {
      'profiles': [
        for (final id in data['userIds'] as List? ?? []) card(id as String),
      ],
    };
    service = PublicProfileService(
      currentUid: () => actor,
      accountChanges: () => changes.stream,
      call: (name, data) {
        calls.add((name, data));
        return respond(name, data);
      },
    );
  });
  tearDown(() async => changes.close());

  test('cross-user lookup cannot invoke the private owner loader', () async {
    var privateReads = 0;
    final profile = await service.getCustomer(
      'other',
      loadSelf: (_) async {
        privateReads++;
        return null;
      },
    );
    expect(profile?.uid, 'other');
    expect(privateReads, 0);
    expect(calls.single.$1, 'getPublicProfilesV1');
  });

  test(
    'self lookup retains private owner data without a public request',
    () async {
      final privateProfile = CustomerModel(
        uid: 'owner',
        name: 'Owner',
        email: 'owner@example.test',
        createdAt: DateTime(2026),
        eventsCreated: 5,
      );
      expect(
        await service.getCustomer(
          'owner',
          loadSelf: (_) async => privateProfile,
        ),
        same(privateProfile),
      );
      expect(calls, isEmpty);
    },
  );

  test('public projection ignores unexpected private fields', () async {
    respond = (_, _) async => {
      'profiles': [
        {
          ...card('other'),
          'email': 'secret@example.test',
          'phoneNumber': '5551234',
          'age': 30,
          'gender': 'private',
          'favorites': ['private-event'],
          'eventsCreated': 9,
          'groupsCreated': 4,
          'fcmToken': 'secret-token',
          'createdAt': DateTime(2020).toIso8601String(),
        },
      ],
    };
    final profile = (await service.getByIds(['other'])).single;
    expect(profile.email, isEmpty);
    expect(profile.phoneNumber, isNull);
    expect(profile.age, isNull);
    expect(profile.gender, isNull);
    expect(profile.favorites, isEmpty);
    expect(profile.eventsCreated, 0);
    expect(profile.groupsCreated, 0);
    expect(
      CustomerModel.getPublicMap(profile).keys,
      unorderedEquals([
        'uid',
        'name',
        'username',
        'profilePictureUrl',
        'bannerUrl',
        'bio',
        'isDiscoverable',
      ]),
    );
  });

  test(
    'known-ID reads batch, deduplicate and preserve requested order',
    () async {
      final ids = List.generate(103, (index) => 'u$index');
      respond = (_, data) async => {
        'profiles': [
          ...(data['userIds'] as List).reversed.map((id) => card(id as String)),
          card('unrequested'),
        ],
      };
      final profiles = await service.getByIds([...ids, 'u0', '']);
      expect(profiles.map((p) => p.uid), ids);
      expect(calls.map((call) => (call.$2['userIds'] as List).length), [
        50,
        50,
        3,
      ]);
    },
  );

  test(
    'search bounds server requests and removes non-discoverable results',
    () async {
      respond = (_, _) async => {
        'profiles': [
          card('shown'),
          {...card('hidden'), 'isDiscoverable': false},
        ],
      };
      expect(
        (await service.search(' @member ', limit: 1000)).map((p) => p.uid),
        ['shown'],
      );
      expect(calls.single.$1, 'searchPublicProfilesV1');
      expect(calls.single.$2, {'query': 'member', 'limit': 50});
      expect(await service.search('x' * 81), isEmpty);
      expect(calls, hasLength(1));
    },
  );

  test(
    'failed search propagates without a broad collection fallback',
    () async {
      respond = (_, _) async => throw StateError('Unavailable');
      await expectLater(service.search('member'), throwsStateError);
      expect(calls, hasLength(1));
    },
  );

  test(
    'username availability returns only a matching normalized answer',
    () async {
      respond = (_, _) async => {'username': 'member', 'available': true};
      expect(await service.isUsernameAvailable(' @Member '), isTrue);
      expect(calls.single.$1, 'checkUsernameAvailabilityV1');
      expect(calls.single.$2, {'username': 'member'});
      respond = (_, _) async => {'username': 'different', 'available': true};
      expect(await service.isUsernameAvailable('member'), isFalse);
    },
  );

  test('late public results are discarded after an account switch', () async {
    final response = Completer<Map<String, dynamic>>();
    respond = (_, _) => response.future;
    final pending = service.getByIds(['other']);
    final assertion = expectLater(pending, throwsStateError);
    actor = 'second';
    changes.add(actor);
    response.complete({
      'profiles': [card('other')],
    });
    await assertion;
  });

  test(
    'logout and same-account return still invalidates pending private reads',
    () async {
      final response = Completer<CustomerModel?>();
      final pending = service.getCustomer(
        'owner',
        loadSelf: (_) => response.future,
      );
      final assertion = expectLater(pending, throwsStateError);
      actor = null;
      changes.add(actor);
      actor = 'owner';
      changes.add(actor);
      response.complete(
        CustomerModel(
          uid: 'owner',
          name: 'Owner',
          email: 'private',
          createdAt: DateTime(2026),
        ),
      );
      await assertion;
    },
  );

  test(
    'known-ID profile is refetched for a different authenticated actor',
    () async {
      await service.getByIds(['other']);
      actor = 'second';
      changes.add(actor);
      await service.getByIds(['other']);
      expect(calls, hasLength(2));
    },
  );

  test(
    'staff email lookup is scoped to one event and handles unavailable targets',
    () async {
      respond = (_, _) async => {
        'profile': {
          'uid': 'staff',
          'name': 'Staff',
          'email': 'must-not-propagate',
        },
      };
      final staff = await service.lookupEventStaffAccount(
        eventId: 'event',
        email: ' Staff@Example.test ',
      );
      expect(calls.single.$1, 'lookupEventStaffAccountV1');
      expect(calls.single.$2, {
        'eventId': 'event',
        'email': 'staff@example.test',
      });
      expect(staff?.uid, 'staff');
      expect(staff?.email, isEmpty);
      respond = (_, _) async => {'profile': null};
      expect(
        await service.lookupEventStaffAccount(
          eventId: 'event',
          email: 'missing@example.test',
        ),
        isNull,
      );
    },
  );

  test('unauthenticated requests never access profile endpoints', () async {
    actor = null;
    await expectLater(service.getByIds(['other']), throwsStateError);
    expect(calls, isEmpty);
  });
}
