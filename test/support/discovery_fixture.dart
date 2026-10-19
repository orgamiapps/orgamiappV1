// In-memory services for production-widget layout tests and the local preview.
// No Firebase server, live account, or provider map tiles are used.
import 'dart:convert';
import 'package:attendus/Services/guest_mode_service.dart';
import 'package:attendus/Utils/attendus_theme.dart';
import 'package:attendus/Utils/theme_provider.dart';
import 'package:attendus/screens/Home/home_hub_screen.dart';
import 'package:attendus/widgets/attendus_scaffold.dart';
import 'package:cloud_firestore_platform_interface/cloud_firestore_platform_interface.dart';
import 'package:cloud_functions_platform_interface/cloud_functions_platform_interface.dart';
import 'package:firebase_auth_platform_interface/firebase_auth_platform_interface.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_core_platform_interface/firebase_core_platform_interface.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:geolocator_platform_interface/geolocator_platform_interface.dart';
import 'package:google_maps_flutter_platform_interface/google_maps_flutter_platform_interface.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

const discoveryEventFixture = <String, dynamic>{
  'id': 'compact-discovery-event',
  'title': 'Community garden evening',
  'groupName': 'Bonita Neighbors',
  'description': 'An evening of food and community.',
  'location': 'Riverside Park',
  'city': 'Bonita Springs',
  'regionCode': 'FL',
  'imageUrl': '',
  'customerUid': 'fixture-organizer',
  'status': 'active',
  'private': false,
  'selectedDateTime': '2030-10-19T21:00:00Z',
  'eventGenerateTime': '2030-10-01T12:00:00Z',
  'eventTimeZone': 'America/New_York',
  'discoveryCategoryIds': ['food-drink'],
};

Map<String, dynamic> discoveryHomeFixture({bool empty = false}) => {
  'schemaVersion': 2,
  'localResultCount': empty ? 0 : 1,
  'sections': [
    if (!empty)
      {
        'id': 'near_you',
        'title': 'Near you',
        'subtitle': 'Events in your area',
        'events': [discoveryEventFixture],
        'totalAvailable': 1,
      },
  ],
};

class DiscoveryFixture {
  // FlutterFire caches delegates by app; keep their identities stable between tests.
  static final _auth = _Auth();
  static final _firestore = _Firestore();
  static final _functions = _Functions();
  final auth = _auth;
  final firestore = _firestore;
  final functions = _functions;

  Future<void> install({
    bool guest = false,
    String city = 'Bonita Springs',
  }) async {
    functions.requests.clear();
    functions.handler = null;
    FirebasePlatform.instance = _Core();
    FirebaseAuthPlatform.instance = auth;
    FirebaseFirestorePlatform.instance = firestore;
    FirebaseFunctionsPlatform.instance = functions;
    GeolocatorPlatform.instance = _Geo();
    GoogleMapsFlutterPlatform.instance = _Maps();
    firestore.discovery = {
      'useLegacyFeed': false,
      'marketplaceExperienceVersion': 2,
    };
    auth.signedIn = !guest;
    SharedPreferences.setMockInitialValues({
      'discovery_location_v1': jsonEncode({
        'latitude': 26.34,
        'longitude': -81.78,
        'city': city,
        'regionCode': 'FL',
        'source': 'search',
        'nationwide': false,
      }),
    });
    FlutterSecureStorage.setMockInitialValues({});
    await GuestModeService().disableGuestMode();
  }

  Widget app({double textScale = 1, Widget? body}) => ChangeNotifierProvider(
    create: (_) => ThemeProvider(),
    child: MaterialApp(
      theme: AttendUsTheme.light,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(textScaler: TextScaler.linear(textScale)),
        child: child!,
      ),
      home: AttendUsScaffold(
        title: 'Discover',
        selectedIndex: 0,
        destinations: const [
          AttendUsNavDestination(
            label: 'Home',
            icon: Icons.home_outlined,
            selectedIcon: Icons.home,
          ),
          AttendUsNavDestination(
            label: 'Groups',
            icon: Icons.apartment_outlined,
            selectedIcon: Icons.apartment,
          ),
          AttendUsNavDestination(
            label: 'Messages',
            icon: Icons.forum_outlined,
            selectedIcon: Icons.forum,
          ),
          AttendUsNavDestination(
            label: 'Profile',
            icon: Icons.person_outline,
            selectedIcon: Icons.person,
          ),
        ],
        onDestinationSelected: (_) {},
        onNotificationsPressed: () {},
        onLoginPressed: auth.signedIn ? null : () {},
        body: body ?? const HomeHubScreen(),
      ),
    ),
  );
}

class _Core extends FirebasePlatform {
  final value = FirebaseAppPlatform(
    '[DEFAULT]',
    const FirebaseOptions(
      apiKey: 'local-probe-only',
      appId: 'local-probe',
      messagingSenderId: '1',
      projectId: 'demo-attendus-admin',
    ),
  );
  @override
  FirebaseAppPlatform app([String name = '[DEFAULT]']) => value;
  @override
  List<FirebaseAppPlatform> get apps => [value];
}

class _User extends UserPlatform {
  _User(FirebaseAuthPlatform auth)
    : super(
        auth,
        _MultiFactor(auth),
        InternalUserDetails(
          userInfo: InternalUserInfo(
            uid: 'map-widget-owner',
            displayName: 'Preview Member',
            isAnonymous: false,
            isEmailVerified: true,
          ),
          providerData: [],
        ),
      );
}

class _MultiFactor extends MultiFactorPlatform {
  _MultiFactor(super.auth);
}

class _Auth extends FirebaseAuthPlatform {
  bool signedIn = true;
  @override
  FirebaseAuthPlatform delegateFor({required FirebaseApp app}) => this;
  @override
  FirebaseAuthPlatform setInitialValues({
    InternalUserDetails? currentUser,
    String? languageCode,
  }) => this;
  @override
  UserPlatform? get currentUser => signedIn ? _User(this) : null;
  @override
  Stream<UserPlatform?> authStateChanges() => Stream.value(currentUser);
}

class _Firestore extends FirebaseFirestorePlatform {
  Map<String, dynamic>? discovery;
  @override
  FirebaseFirestorePlatform delegateFor({
    required FirebaseApp app,
    required String databaseId,
  }) => this;
  @override
  CollectionReferencePlatform collection(String path) =>
      _Collection(this, path);
  @override
  QueryPlatform collectionGroup(String path) => _Collection(this, path);
  @override
  DocumentReferencePlatform doc(String path) => _Document(this, path);
}

class _Document extends DocumentReferencePlatform {
  _Document(super.firestore, super.path);
  @override
  CollectionReferencePlatform collection(String path) =>
      firestore.collection('${this.path}/$path');
  @override
  Future<DocumentSnapshotPlatform> get([
    GetOptions options = const GetOptions(),
  ]) async => DocumentSnapshotPlatform(
    firestore,
    path,
    path == 'AppConfig/discovery'
        ? (firestore as _Firestore).discovery
        : path == 'Customers/map-widget-owner'
        ? {
            'uid': 'map-widget-owner',
            'name': 'Preview Member',
            'email': '',
            'createdAt': '2026-01-01T00:00:00Z',
            'favorites': <String>[],
          }
        : null,
    InternalSnapshotMetadata(hasPendingWrites: false, isFromCache: false),
  );
}

class _Collection extends CollectionReferencePlatform {
  _Collection(super.firestore, super.path) {
    parameters.addAll({
      'where': <List<dynamic>>[],
      'orderBy': <List<dynamic>>[],
    });
  }
  @override
  DocumentReferencePlatform doc([String? id]) => firestore.doc('$path/$id');
  @override
  QueryPlatform limit(int limit) => this;
  @override
  QueryPlatform orderBy(Iterable<List<dynamic>> orders) => this;
  @override
  QueryPlatform where(List<List<dynamic>> conditions) => this;
  @override
  Future<QuerySnapshotPlatform> get([
    GetOptions options = const GetOptions(),
  ]) async =>
      QuerySnapshotPlatform([], [], SnapshotMetadataPlatform(false, false));
  @override
  Stream<QuerySnapshotPlatform> snapshots({
    bool includeMetadataChanges = false,
    required ListenSource listenSource,
  }) => Stream.fromFuture(get());
}

class _Functions extends FirebaseFunctionsPlatform {
  _Functions() : super(null, 'us-central1');
  final requests = <(String, Map<String, dynamic>)>[];
  Future<dynamic> Function(String, Map<String, dynamic>)? handler;
  @override
  FirebaseFunctionsPlatform delegateFor({
    FirebaseApp? app,
    required String region,
  }) => this;
  @override
  HttpsCallablePlatform httpsCallable(
    String? origin,
    String name,
    HttpsCallableOptions options,
  ) => _Callable(this, origin, name, options, null);
}

class _Callable extends HttpsCallablePlatform {
  _Callable(
    super.functions,
    super.origin,
    super.name,
    super.options,
    super.uri,
  );
  @override
  Future<dynamic> call([dynamic parameters]) async {
    final service = functions as _Functions;
    final name = this.name!;
    final data = Map<String, dynamic>.from(parameters as Map? ?? {});
    service.requests.add((name, data));
    if (service.handler != null) return service.handler!(name, data);
    if (name.startsWith('getDiscoveryHome')) return discoveryHomeFixture();
    if (name.startsWith('searchDiscoveryEvents')) {
      return {
        'events': [discoveryEventFixture],
        'total': 1,
      };
    }
    if (name == 'listMyAdmissionsV1') return {'admissions': []};
    return <String, dynamic>{};
  }
}

class _Geo extends GeolocatorPlatform {
  @override
  Future<bool> isLocationServiceEnabled() async => false;
  @override
  Future<LocationPermission> checkPermission() async =>
      LocationPermission.denied;
}

// The map route is real. Only the external platform renderer is replaced;
// these entry tests do not claim provider tiles/markers loaded.
class _Maps extends GoogleMapsFlutterPlatform {
  @override
  Widget buildViewWithConfiguration(
    int creationId,
    PlatformViewCreatedCallback onPlatformViewCreated, {
    required MapWidgetConfiguration widgetConfiguration,
    MapConfiguration mapConfiguration = const MapConfiguration(),
    MapObjects mapObjects = const MapObjects(),
  }) => const ColoredBox(color: Colors.blueGrey);
}
