import 'package:attendus/Services/guest_mode_service.dart';
import 'package:attendus/Utils/theme_provider.dart';
import 'package:attendus/screens/Events/global_events_map_screen.dart';
import 'package:attendus/screens/Home/home_hub_screen.dart';
import 'package:attendus/screens/Home/home_screen.dart';
import 'package:attendus/screens/Home/discovery_marketplace_view.dart';
import 'package:attendus/widgets/attendus_scaffold.dart';
import 'package:cloud_firestore_platform_interface/cloud_firestore_platform_interface.dart';
import 'package:cloud_functions_platform_interface/cloud_functions_platform_interface.dart';
import 'package:firebase_auth_platform_interface/firebase_auth_platform_interface.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_core_platform_interface/firebase_core_platform_interface.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator_platform_interface/geolocator_platform_interface.dart';
import 'package:google_maps_flutter_platform_interface/google_maps_flutter_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

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

class _User extends Fake
    with MockPlatformInterfaceMixin
    implements UserPlatform {
  @override
  String get uid => 'map-widget-owner';
  @override
  bool get isAnonymous => false;
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
  UserPlatform? get currentUser => signedIn ? _User() : null;
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
  Future<DocumentSnapshotPlatform> get([
    GetOptions options = const GetOptions(),
  ]) async => DocumentSnapshotPlatform(
    firestore,
    path,
    path == 'AppConfig/discovery' ? (firestore as _Firestore).discovery : null,
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
  Future<dynamic> call([dynamic parameters]) async => <String, dynamic>{
    'sections': [],
    'schemaVersion': name == 'getDiscoveryHomeV2' ? 2 : 1,
  };
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

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final core = _Core();
  FirebasePlatform.instance = core;
  final firestore = _Firestore();
  FirebaseFirestorePlatform.instance = firestore;
  final auth = _Auth();
  FirebaseAuthPlatform.instance = auth;
  FirebaseFunctionsPlatform.instance = _Functions();
  GeolocatorPlatform.instance = _Geo();
  GoogleMapsFlutterPlatform.instance = _Maps();
  setUp(() async {
    SharedPreferences.setMockInitialValues({
      'discovery_location_v1':
          '{"latitude":39.8,"longitude":-98.5,"city":"United States","regionCode":"US","source":"nationwide","nationwide":true}',
    });
    FlutterSecureStorage.setMockInitialValues({});
    auth.signedIn = true;
    await GuestModeService().disableGuestMode();
  });

  Widget app(Widget home) => ChangeNotifierProvider(
    create: (_) => ThemeProvider(),
    child: MaterialApp(home: home),
  );
  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  Future<void> dispose(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 30));
  }

  testWidgets('standalone legacy header control really exposes Maps', (
    tester,
  ) async {
    await tester.pumpWidget(app(const HomeScreen()));
    await settle(tester);
    expect(find.bySemanticsLabel('View events map'), findsOneWidget);
    await dispose(tester);
  });

  for (final config in [
    null,
    <String, dynamic>{'useLegacyFeed': true},
    <String, dynamic>{'useLegacyFeed': false},
    <String, dynamic>{
      'useLegacyFeed': false,
      'marketplaceExperienceVersion': 2,
    },
  ]) {
    testWidgets('production HomeHub exposes Maps for config $config', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      firestore.discovery = config;
      await tester.pumpWidget(app(const HomeHubScreen()));
      await settle(tester);
      expect(
        find.byType(
          config?['useLegacyFeed'] == false
              ? DiscoveryMarketplaceView
              : HomeScreen,
          skipOffstage: false,
        ),
        findsOneWidget,
      );
      // This is the actual production constructor and actual selected child.
      expect(find.bySemanticsLabel('View events map'), findsOneWidget);
      await tester.tap(find.byTooltip('View events map'));
      await settle(tester);
      expect(find.byType(GlobalEventsMapScreen), findsOneWidget);
      expect(find.text('No events with map locations yet'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await dispose(tester);
      handle.dispose();
    });
  }

  for (final guest in [false, true]) {
    for (final legacy in [true, false]) {
      testWidgets(
        '390px 200% guest=$guest legacy=$legacy keeps map and shared account actions',
        (tester) async {
          final semantics = tester.ensureSemantics();
          tester.view.physicalSize = const Size(390, 844);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          auth.signedIn = !guest;
          await GuestModeService().disableGuestMode();
          firestore.discovery = {'useLegacyFeed': legacy};
          var loginTaps = 0;
          var bellTaps = 0;
          await tester.pumpWidget(
            ChangeNotifierProvider(
              create: (_) => ThemeProvider(),
              child: MaterialApp(
                builder: (context, child) => MediaQuery(
                  data: MediaQuery.of(
                    context,
                  ).copyWith(textScaler: TextScaler.linear(2)),
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
                      icon: Icons.group_outlined,
                      selectedIcon: Icons.group,
                    ),
                  ],
                  onDestinationSelected: (_) {},
                  onLoginPressed: guest ? () => loginTaps++ : null,
                  onNotificationsPressed: () => bellTaps++,
                  body: const HomeHubScreen(),
                ),
              ),
            ),
          );
          await settle(tester);
          final target = find.byTooltip('View events map');
          expect(target, findsOneWidget);
          expect(find.bySemanticsLabel('View events map'), findsOneWidget);
          expect(find.byTooltip('Notifications'), findsOneWidget);
          expect(find.text('Log in'), guest ? findsOneWidget : findsNothing);
          final bounds = tester.getRect(target);
          expect(bounds.left, greaterThanOrEqualTo(0));
          expect(bounds.right, lessThanOrEqualTo(390));
          expect(bounds.top, greaterThanOrEqualTo(0));
          expect(bounds.bottom, lessThanOrEqualTo(844));
          expect(tester.takeException(), isNull);
          await tester.tap(find.byTooltip('Notifications'));
          expect(bellTaps, 1);
          if (guest) {
            await tester.tap(find.text('Log in'));
            expect(loginTaps, 1);
          }
          // Use the actual keyboard activation path as well as pointer tests above.
          final button = tester.widget<IconButton>(
            find.widgetWithIcon(IconButton, Icons.map_outlined),
          );
          expect(button.onPressed, isNotNull);
          Focus.of(
            tester.element(find.byIcon(Icons.map_outlined)),
          ).requestFocus();
          await tester.pump();
          await tester.sendKeyEvent(LogicalKeyboardKey.enter);
          await settle(tester);
          expect(find.byType(GlobalEventsMapScreen), findsOneWidget);
          await dispose(tester);
          semantics.dispose();
        },
      );
    }
  }
}
