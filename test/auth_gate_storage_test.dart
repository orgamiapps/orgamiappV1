import 'dart:async';
import 'dart:convert';

import 'package:attendus/Services/guest_mode_service.dart';
import 'package:attendus/controller/customer_controller.dart';
import 'package:attendus/models/customer_model.dart';
import 'package:attendus/screens/Home/dashboard_screen.dart';
import 'package:attendus/widgets/auth_gate.dart';
import 'package:attendus/widgets/deferred_screen_loader.dart';
import 'package:firebase_auth_platform_interface/firebase_auth_platform_interface.dart';
import 'package:firebase_app_check_platform_interface/firebase_app_check_platform_interface.dart';
import 'package:cloud_firestore_platform_interface/cloud_firestore_platform_interface.dart';
import 'package:cloud_functions_platform_interface/cloud_functions_platform_interface.dart';
import 'package:connectivity_plus_platform_interface/connectivity_plus_platform_interface.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_core_platform_interface/firebase_core_platform_interface.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';

class _Core extends FirebasePlatform {
  final value = FirebaseAppPlatform(
    '[DEFAULT]',
    const FirebaseOptions(
      apiKey: 'offline-only',
      appId: 'offline-only',
      messagingSenderId: '1',
      projectId: 'demo-attendus-admin',
    ),
  );
  @override
  FirebaseAppPlatform app([String name = '[DEFAULT]']) => value;
  @override
  List<FirebaseAppPlatform> get apps => [value];
  @override
  Future<FirebaseAppPlatform> initializeApp({
    String? name,
    FirebaseOptions? options,
  }) async => value;
}

class _User extends Fake
    with MockPlatformInterfaceMixin
    implements UserPlatform {
  @override
  String get uid => 'owned-offline-user';
  @override
  bool get isAnonymous => false;
  @override
  String? get displayName => 'Offline user';
  @override
  String? get email => 'owned@example.test';
  @override
  String? get photoURL => null;
}

class _Auth extends FirebaseAuthPlatform {
  final user = _User();
  final changes = StreamController<UserPlatform?>.broadcast(sync: true);
  @override
  FirebaseAuthPlatform delegateFor({required FirebaseApp app}) => this;
  @override
  FirebaseAuthPlatform setInitialValues({
    InternalUserDetails? currentUser,
    String? languageCode,
  }) => this;
  @override
  UserPlatform? get currentUser => user;
  @override
  Stream<UserPlatform?> authStateChanges() => changes.stream;
}

class _AppCheck extends FirebaseAppCheckPlatform {
  @override
  FirebaseAppCheckPlatform delegateFor({required FirebaseApp app}) => this;
  @override
  FirebaseAppCheckPlatform setInitialValues() => this;
  @override
  Future<void> activate({
    WebProvider? webProvider,
    AndroidProvider? androidProvider,
    AppleProvider? appleProvider,
    AndroidAppCheckProvider? providerAndroid,
    AppleAppCheckProvider? providerApple,
    WindowsAppCheckProvider? providerWindows,
  }) async {}
}

// The gate's existing background profile refresh is outside this regression.
// Reject that platform I/O immediately rather than allowing a real transport.
class _Db extends FirebaseFirestorePlatform {
  @override
  FirebaseFirestorePlatform delegateFor({
    required FirebaseApp app,
    required String databaseId,
  }) => this;
  @override
  DocumentReferencePlatform doc(String path) => _Document(this, path);
  @override
  CollectionReferencePlatform collection(String path) =>
      _Collection(this, path);
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
  ) => throw StateError('background callable disabled in offline gate test');
}

class _Connectivity extends ConnectivityPlatform {
  @override
  Future<List<ConnectivityResult>> checkConnectivity() async => [
    ConnectivityResult.wifi,
  ];
}

class _Document extends DocumentReferencePlatform {
  _Document(super.firestore, super.path);
  @override
  Future<DocumentSnapshotPlatform> get([
    GetOptions options = const GetOptions(),
  ]) async => throw FirebaseException(
    plugin: 'cloud_firestore',
    code: 'permission-denied',
  );
}

class _Collection extends CollectionReferencePlatform {
  _Collection(super.firestore, super.path);
  @override
  DocumentReferencePlatform doc([String? id]) =>
      firestore.doc('$path/${id ?? 'offline-only'}');
}

class _Preferences extends SharedPreferencesStorePlatform {
  bool denyRead = false;
  bool denyRemove = false;
  int reads = 0;
  final removes = <String>[];
  final values = <String, Object>{};
  @override
  Future<Map<String, Object>> getAll() async {
    reads++;
    if (denyRead) throw StateError('synthetic browser localStorage denied');
    return Map.of(values);
  }

  @override
  Future<bool> remove(String key) async {
    removes.add(key);
    if (denyRemove) throw StateError('synthetic browser clear denied');
    values.remove(key);
    return true;
  }

  @override
  Future<bool> clear() async {
    values.clear();
    return true;
  }

  @override
  Future<bool> setValue(String valueType, String key, Object value) async {
    values[key] = value;
    return true;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final originalCore = FirebasePlatform.instance;
  final originalAuth = FirebaseAuthPlatform.instance;
  final originalAppCheck = FirebaseAppCheckPlatform.instance;
  late FirebaseFirestorePlatform originalFirestore;
  final originalFunctions = FirebaseFunctionsPlatform.instance;
  final originalConnectivity = ConnectivityPlatform.instance;
  final originalPreferences = SharedPreferencesStorePlatform.instance;
  final auth = _Auth();
  late _Preferences preferences;

  setUpAll(() {
    FirebasePlatform.instance = _Core();
    originalFirestore = FirebaseFirestorePlatform.instance;
    FirebaseAuthPlatform.instance = auth;
    FirebaseAppCheckPlatform.instance = _AppCheck();
    FirebaseFirestorePlatform.instance = _Db();
    FirebaseFunctionsPlatform.instance = _Functions();
    ConnectivityPlatform.instance = _Connectivity();
  });
  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
    SharedPreferences.resetStatic();
    preferences = _Preferences();
    SharedPreferencesStorePlatform.instance = preferences;
    CustomerController.logeInCustomer = null;
  });
  tearDownAll(() async {
    await auth.changes.close();
    FirebasePlatform.instance = originalCore;
    FirebaseAuthPlatform.instance = originalAuth;
    FirebaseAppCheckPlatform.instance = originalAppCheck;
    FirebaseFirestorePlatform.instance = originalFirestore;
    FirebaseFunctionsPlatform.instance = originalFunctions;
    ConnectivityPlatform.instance = originalConnectivity;
    SharedPreferencesStorePlatform.instance = originalPreferences;
    SharedPreferences.resetStatic();
    CustomerController.logeInCustomer = null;
  });

  Future<DashboardScreen> selectedDashboard(
    WidgetTester tester, {
    bool forceDiscover = false,
    CustomerModel? expectedProfileAtSelection,
  }) async {
    await tester.pumpWidget(
      MaterialApp(home: AuthGate(forceDiscover: forceDiscover)),
    );
    // Inspect this real, mounted gate's destination without mounting unrelated
    // dashboard services or starting DeferredScreenLoader's own load timer.
    final gate = find.byType(AuthGate);
    final selected = tester
        .state<State<AuthGate>>(gate)
        // Intentional test-only inspection of the gate's resolved widget.
        // ignore: invalid_use_of_protected_member
        .build(tester.element(gate));
    expect(selected, isA<DeferredScreenLoader>());
    if (expectedProfileAtSelection != null) {
      expect(
        CustomerController.logeInCustomer,
        same(expectedProfileAtSelection),
      );
    }
    final loader = selected as DeferredScreenLoader;
    await tester.runAsync(loader.loadLibrary);
    final dashboard = loader.builder();
    expect(dashboard, isA<DashboardScreen>());
    expect(CustomerController.logeInCustomer?.uid, auth.user.uid);
    expect(GuestModeService().isGuestMode, isFalse);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    await tester.pump();
    return dashboard as DashboardScreen;
  }

  testWidgets(
    'denied saved-navigation read enters fresh Discover with the full identity',
    (tester) async {
      preferences.denyRead = true;
      final dashboard = await selectedDashboard(tester);
      expect(preferences.reads, greaterThan(0));
      expect(dashboard.initialIndex, 0);
      expect(dashboard.restoreSavedTab, isFalse);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'denied explicit Discover clear does not demote the signed-in user',
    (tester) async {
      preferences.denyRemove = true;
      final dashboard = await selectedDashboard(tester, forceDiscover: true);
      expect(preferences.removes, contains('flutter.pending_auth_intent_v1'));
      expect(dashboard.initialIndex, 0);
      expect(dashboard.restoreSavedTab, isFalse);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'denied pending-intent removal enters fresh Discover with the full identity',
    (tester) async {
      preferences.denyRemove = true;
      final dashboard = await selectedDashboard(tester);
      expect(preferences.removes, contains('flutter.pending_auth_intent_v1'));
      expect(dashboard.restoreSavedTab, isFalse);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'ordinary successful navigation preserves the matching profile and restore policy',
    (tester) async {
      final current = CustomerModel(
        uid: auth.user.uid,
        name: 'Stored profile',
        email: 'owned@example.test',
        createdAt: DateTime.utc(2020),
      );
      CustomerController.logeInCustomer = current;
      final dashboard = await selectedDashboard(
        tester,
        expectedProfileAtSelection: current,
      );
      expect(dashboard.initialIndex, 0);
      expect(dashboard.restoreSavedTab, isTrue);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'successful explicit Discover clears saved state and keeps the identity',
    (tester) async {
      final dashboard = await selectedDashboard(tester, forceDiscover: true);
      expect(preferences.removes, contains('flutter.pending_auth_intent_v1'));
      expect(dashboard.initialIndex, 0);
      expect(dashboard.restoreSavedTab, isFalse);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'valid pending Messages destination is still honored for the signed-in user',
    (tester) async {
      preferences.values['flutter.pending_auth_intent_v1'] = jsonEncode({
        'action': 'dashboardTab',
        'dashboardTab': 2,
        'sourceFeature': 'messages',
        'expiresAt': DateTime.now()
            .add(const Duration(days: 1))
            .toIso8601String(),
      });
      final dashboard = await selectedDashboard(tester);
      expect(dashboard.initialIndex, 2);
      expect(dashboard.restoreSavedTab, isFalse);
      expect(
        preferences.values.containsKey('flutter.pending_auth_intent_v1'),
        isFalse,
      );
      expect(tester.takeException(), isNull);
    },
  );
}
