import 'package:attendus/Services/notification_preferences_service.dart';
import 'package:attendus/firebase/firebase_messaging_helper.dart';
import 'package:attendus/models/notification_model.dart';
import 'package:attendus/screens/Home/notification_settings_screen.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/auth_fakes.dart';

class _Messaging extends Fake implements FirebaseMessagingHelper {
  _Messaging(this.auth);
  late final NotificationPreferencesService preferences =
      NotificationPreferencesService(
        currentUid: () => auth.currentUser?.uid,
        load: (_) async {
          if (failLoad) throw StateError('Load failed');
          return {...saved};
        },
        save: (_, patch) async {
          writes.add({...patch});
          saved.addAll(patch);
          return {...saved};
        },
      );
  final TestFirebaseAuth auth;
  final saved = <String, dynamic>{'eventReminders': true, 'reminderTime': 60};
  final writes = <Map<String, dynamic>>[];
  bool failLoad = false;
  int permissionRequests = 0;
  int registrations = 0;
  @override
  UserNotificationSettings? get settings => preferences.cached;
  @override
  Future<UserNotificationSettings> getUserNotificationSettings() =>
      preferences.read();
  @override
  Future<void> updateNotificationSettings(
    UserNotificationSettings settings, {
    UserNotificationSettings? baseline,
  }) => preferences.write(settings, baseline: baseline);
  @override
  Future<NotificationSettings> requestPermissions() async {
    permissionRequests++;
    throw StateError('Unexpected permission request');
  }

  @override
  Future<void> initialize() async {
    registrations++;
  }
}

void main() {
  const channelKeys = [
    'eventReminders',
    'newEvents',
    'ticketUpdates',
    'eventFeedback',
    'generalNotifications',
    'eventChanges',
    'geofenceCheckIn',
    'messagesAll',
    'messageMentions',
    'organizationUpdates',
    'organizerFeedback',
  ];
  late TestFirebaseAuth auth;
  late _Messaging helper;
  setUp(() {
    auth = TestFirebaseAuth()..user = TestAuthUser('owner');
    helper = _Messaging(auth);
  });
  tearDown(() => auth.changes.close());
  Future<void> open(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(1000, 1200));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        home: NotificationSettingsScreen(
          auth: auth,
          messagingHelper: helper,
          readPermissionStatus: () async => AuthorizationStatus.denied,
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets(
    'denied device permission still allows persisted account opt-out without requesting permission',
    (tester) async {
      await open(tester);
      await tester.ensureVisible(find.text('Event Reminders'));
      await tester.tap(find.text('Event Reminders'));
      await tester.pumpAndSettle();
      expect(helper.saved['eventReminders'], false);
      expect(helper.writes, [
        {'eventReminders': false},
      ]);
      expect(helper.permissionRequests, 0);
      expect(helper.registrations, 0);
      await tester.pumpWidget(const SizedBox());
      await open(tester);
      final tile = tester.widget<SwitchListTile>(
        find.ancestor(
          of: find.text('Event Reminders'),
          matching: find.byType(SwitchListTile),
        ),
      );
      expect(tile.value, false);
    },
  );

  testWidgets(
    'denied permission leaves reminder selector editable without device registration',
    (tester) async {
      await open(tester);
      await tester.ensureVisible(find.text('1 hour'));
      await tester.tap(find.text('1 hour'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('15 minutes').last);
      await tester.pumpAndSettle();
      expect(helper.writes, [
        {'reminderTime': 15},
      ]);
      expect(helper.permissionRequests, 0);
      expect(helper.registrations, 0);
    },
  );

  testWidgets('denied permission leaves master account opt-out editable', (
    tester,
  ) async {
    await open(tester);
    await tester.ensureVisible(find.text('All Notifications'));
    await tester.tap(find.text('All Notifications'));
    await tester.pumpAndSettle();
    expect(helper.saved['eventReminders'], false);
    expect(helper.saved['messagesAll'], false);
    expect(helper.saved['organizationUpdates'], false);
    expect(channelKeys.every((key) => helper.saved[key] == false), true);
    expect(helper.permissionRequests, 0);
    expect(helper.registrations, 0);
  });

  testWidgets(
    'partially enabled messages appear in master state and can be disabled in one tap',
    (tester) async {
      for (final key in channelKeys) {
        helper.saved[key] = false;
      }
      helper.saved['messagesAll'] = true;
      await open(tester);
      final master = find.widgetWithText(SwitchListTile, 'All Notifications');
      expect(tester.widget<SwitchListTile>(master).value, true);
      expect(find.text('Some notification types are on'), findsOneWidget);
      await tester.ensureVisible(master);
      await tester.tap(find.text('All Notifications'));
      await tester.pumpAndSettle();
      expect(channelKeys.every((key) => helper.saved[key] == false), true);
      expect(helper.writes, [
        {'messagesAll': false},
      ]);
      expect(helper.permissionRequests, 0);
      expect(helper.registrations, 0);
    },
  );

  testWidgets(
    'all-off master enables its channels without changing independent delivery preferences',
    (tester) async {
      for (final key in channelKeys) {
        helper.saved[key] = false;
      }
      helper.saved['soundEnabled'] = false;
      helper.saved['vibrationEnabled'] = false;
      await open(tester);
      final master = find.widgetWithText(SwitchListTile, 'All Notifications');
      expect(tester.widget<SwitchListTile>(master).value, false);
      expect(find.text('All notification types are off'), findsOneWidget);
      await tester.ensureVisible(master);
      await tester.tap(find.text('All Notifications'));
      await tester.pumpAndSettle();
      expect(channelKeys.every((key) => helper.saved[key] == true), true);
      expect(helper.saved['soundEnabled'], false);
      expect(helper.saved['vibrationEnabled'], false);
      expect(helper.saved['reminderTime'], 60);
      expect(find.text('All notification types are on'), findsOneWidget);
      expect(helper.permissionRequests, 0);
      expect(helper.registrations, 0);
    },
  );

  testWidgets('failed preferences load keeps consent controls unavailable', (
    tester,
  ) async {
    helper.failLoad = true;
    await open(tester);
    expect(
      find.text('Unable to load notification preferences.'),
      findsOneWidget,
    );
    expect(find.byType(SwitchListTile), findsNothing);
    expect(helper.writes, isEmpty);
    expect(helper.permissionRequests, 0);
  });

  testWidgets(
    'an account switch before the auth event cannot write the old controls',
    (tester) async {
      await open(tester);
      auth.user = TestAuthUser('other');
      await tester.ensureVisible(find.text('Event Reminders'));
      await tester.tap(find.text('Event Reminders'));
      await tester.pumpAndSettle();
      expect(helper.writes, isEmpty);
      expect(helper.permissionRequests, 0);
    },
  );
}
