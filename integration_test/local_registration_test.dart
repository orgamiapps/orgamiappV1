import 'fixture_harness.dart';
import 'dart:convert';

import 'package:attendus/Services/firebase_initializer.dart';
import 'package:attendus/Services/guest_mode_service.dart';
import 'package:attendus/Services/public_registration_service.dart';
import 'package:attendus/Services/public_profile_service.dart';
import 'package:attendus/Services/event_wizard_service.dart';
import 'package:attendus/Utils/firebase_emulator_config.dart';
import 'package:attendus/firebase_options.dart';
import 'package:attendus/models/event_model.dart';
import 'package:attendus/models/event_wizard_model.dart';
import 'package:attendus/widgets/public_registration_card.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:integration_test/integration_test.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'guest submits the real form, retrieves admission, retries and cancels',
    (tester) async {
      expect(
        DefaultFirebaseOptions.environment,
        'emulator',
        reason: 'This test must never initialize a cloud project.',
      );
      await FirebaseInitializer.initializeOnce();
      await FirebaseAuth.instance.signOut();
      final id =
          '${BrowserFixtures.runId}-flutter-${DateTime.now().microsecondsSinceEpoch}';
      final origin = Uri.parse('http://${FirebaseEmulatorConfig.host}:4173');
      final response = await http.post(
        origin.resolve('/__fixtures/$id'),
        headers: BrowserFixtures.headers,
        body: '{}',
      );
      expect(response.statusCode, 200);
      await GuestModeService().ensureGuestSession();
      await BrowserFixtures.track();
      final snapshot = await FirebaseFirestore.instance
          .collection('Events')
          .doc(id)
          .get();
      final event = EventModel.fromJson({...snapshot.data()!, 'id': id});
      Map<String, dynamic>? registered;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) {
                return FilledButton(
                  onPressed: () async {
                    registered = await PublicRegistrationCard.showForm(
                      context,
                      event,
                    );
                  },
                  child: const Text('Register for fixture'),
                );
              },
            ),
          ),
        ),
      );
      await tester.tap(find.text('Register for fixture'));
      for (
        var attempt = 0;
        attempt < 100 && find.byType(TextFormField).evaluate().length < 3;
        attempt++
      ) {
        await tester.pump(const Duration(milliseconds: 200));
      }
      expect(find.byType(TextFormField), findsNWidgets(3));
      await tester.enterText(find.byType(TextFormField).at(0), 'Flutter Guest');
      await tester.enterText(
        find.byType(TextFormField).at(1),
        '$id@example.test',
      );
      await tester.enterText(
        find.byType(TextFormField).at(2),
        'Step-free access',
      );
      await tester.ensureVisible(find.text('Confirm registration'));
      await tester.tap(find.text('Confirm registration'));
      for (var attempt = 0; attempt < 300 && registered == null; attempt++) {
        await tester.pump(const Duration(milliseconds: 200));
      }
      expect(registered?['status'], 'confirmed');
      final service = PublicRegistrationService();
      final retry = await service.register(
        id,
        'Flutter Guest',
        '$id@example.test',
        {'access': 'Step-free access'},
      );
      expect(retry['registrationId'], registered!['registrationId']);
      final admission = await service.status(
        id,
        registrationId: retry['registrationId'] as String,
      );
      expect(admission['status'], 'confirmed');
      final counts =
          jsonDecode(
                (await http.get(
                  origin.resolve('/__fixtures/$id'),
                  headers: BrowserFixtures.headers,
                )).body,
              )
              as Map;
      expect(counts['confirmed'], 1);
      expect(counts['registrations'], 1);
      await FirebaseFunctions.instanceFor(region: 'us-central1')
          .httpsCallable('cancelPublicRegistrationV1')
          .call({'registrationId': retry['registrationId']});
      expect(
        (await service.status(
          id,
          registrationId: retry['registrationId'] as String,
        ))['status'],
        'cancelled',
      );
      await FirebaseAuth.instance.signOut();
      await GuestModeService().ensureGuestSession();
      await BrowserFixtures.track();
      await expectLater(
        FirebaseFunctions.instanceFor(region: 'us-central1')
            .httpsCallable('getPublicRegistrationStatusV2')
            .call({'flowId': retry['flowId']}),
        throwsA(
          isA<FirebaseFunctionsException>().having(
            (error) => error.code,
            'code',
            'not-found',
          ),
        ),
      );
      await tester.pumpWidget(const SizedBox.shrink());
      await FirebaseAuth.instance.signOut();
    },
    timeout: const Timeout(Duration(minutes: 4)),
  );

  testWidgets(
    'organizer publishes, admits an attendee, exports, reschedules and cancels',
    (tester) async {
      expect(DefaultFirebaseOptions.environment, 'emulator');
      await FirebaseInitializer.initializeOnce();
      final auth = FirebaseAuth.instance;
      await auth.signOut();
      final suffix =
          '${BrowserFixtures.runId}-organizer-${DateTime.now().microsecondsSinceEpoch}';
      final ownerEmail = '$suffix@example.test';
      const password = 'LocalFixturePassword123!';
      final origin = Uri.parse('http://${FirebaseEmulatorConfig.host}:4173');
      expect(
        (await http.post(
          origin.resolve('/__fixtures/$suffix'),
          headers: BrowserFixtures.headers,
          body: '{}',
        )).statusCode,
        200,
      );
      await auth.createUserWithEmailAndPassword(
        email: ownerEmail,
        password: password,
      );
      final ownerUid = auth.currentUser!.uid;
      await BrowserFixtures.track();
      await FirebaseFirestore.instance
          .collection('Customers')
          .doc(auth.currentUser!.uid)
          .set({
            'uid': auth.currentUser!.uid,
            'name': 'Fixture Organizer',
            'eventsCreated': 0,
            'email': ownerEmail,
          });
      Future<Map<String, dynamic>> call(
        String name,
        Map<String, dynamic> data,
      ) async {
        final result =
            await FirebaseFunctions.instanceFor(region: 'us-central1')
                .httpsCallable(
                  name,
                  options: HttpsCallableOptions(
                    timeout: const Duration(seconds: 120),
                  ),
                )
                .call(data);
        return Map<String, dynamic>.from(result.data as Map);
      }

      var wizard = EventWizardService();
      final start = DateTime.now().toUtc().add(const Duration(minutes: 30));
      final draft = EventWizardDraft(
        startAt: start,
        endAt: start.add(const Duration(hours: 2)),
        title: 'Flutter organizer fixture',
        description: 'Local multi-account verification.',
        locationType: 'online',
        location: 'https://example.test/fixture',
        primaryDiscoveryCategoryId: 'community-causes',
        discoveryCategoryIds: ['community-causes'],
        registrationMode: EventRegistrationMode.freeTicket,
        capacity: 5,
      );
      await wizard.saveDraft(draft);
      final publication = await wizard.publish(draft);
      final eventId = publication.eventId;
      await BrowserFixtures.track(eventId: eventId);
      expect(eventId, isNotEmpty);
      expect((await wizard.publish(draft)).eventId, eventId);
      await auth.signOut();
      final attendeeEmail = '$suffix-attendee@example.test';
      await auth.createUserWithEmailAndPassword(
        email: attendeeEmail,
        password: password,
      );
      final attendeeUid = auth.currentUser!.uid;
      await BrowserFixtures.track();
      await FirebaseFirestore.instance
          .collection('Customers')
          .doc(attendeeUid)
          .set({
            'uid': attendeeUid,
            'name': 'Fixture Attendee',
            'eventsCreated': 0,
            'email': attendeeEmail,
          });
      final registration = await PublicRegistrationService().register(
        eventId,
        'Fixture Attendee',
        attendeeEmail,
        {},
      );
      expect(registration['status'], 'confirmed');
      final publicProfiles = await PublicProfileService().getByIds([ownerUid]);
      expect(publicProfiles.single.name, 'Fixture Organizer');
      expect(publicProfiles.single.email, isEmpty);
      expect(publicProfiles.single.phoneNumber, isNull);
      expect(publicProfiles.single.favorites, isEmpty);
      await expectLater(
        FirebaseFirestore.instance
            .collection('Customers')
            .doc(ownerUid)
            .get(const GetOptions(source: Source.server)),
        throwsA(
          isA<FirebaseException>().having(
            (error) => error.code,
            'code',
            'permission-denied',
          ),
        ),
      );
      await expectLater(
        call('listEventRosterV2', {'eventId': eventId}),
        throwsA(
          isA<FirebaseFunctionsException>().having(
            (error) => error.code,
            'code',
            'permission-denied',
          ),
        ),
      );
      await auth.signOut();
      await auth.signInWithEmailAndPassword(
        email: ownerEmail,
        password: password,
      );
      final roster = await call('listEventRosterV2', {'eventId': eventId});
      expect(roster['rows'], hasLength(1));
      final session = await call('startCheckInSession', {'eventId': eventId});
      final checkInInput = <String, dynamic>{
        'eventId': eventId,
        'sessionId': session['sessionId'],
        'credential': {'type': 'staff_roster', 'attendeeId': attendeeUid},
        'answers': [],
        'idempotencyKey': '$suffix-admit',
      };
      final admitted = await call('submitCheckIn', checkInInput);
      expect(
        (await call('submitCheckIn', checkInInput))['attendanceId'],
        admitted['attendanceId'],
      );
      final exportInput = <String, dynamic>{
        'eventId': eventId,
        'idempotencyKey': '$suffix-export',
      };
      final export = await call('createEventExportV2', exportInput);
      expect(
        (await call('createEventExportV2', exportInput))['jobId'],
        export['jobId'],
      );
      Map<String, dynamic>? exported;
      for (var attempt = 0; attempt < 90; attempt++) {
        exported = await call('getEventExportV2', {
          'eventId': eventId,
          'jobId': export['jobId'],
        });
        if (exported['status'] == 'complete' ||
            exported['status'] == 'failed') {
          break;
        }
        await Future<void>.delayed(const Duration(seconds: 2));
      }
      expect(exported?['status'], 'complete');
      expect(exported?['rowCount'], 1);
      // Signed cloud delivery is deliberately not fetched by this local fixture.
      // Real download/expiry/revocation remains a staging/device acceptance gate.
      wizard = EventWizardService();
      final edit = await wizard.createEditDraft(eventId);
      edit.startAt = edit.startAt.add(const Duration(days: 1));
      edit.endAt = edit.endAt.add(const Duration(days: 1));
      await wizard.saveDraft(edit);
      final preview = await call('previewEventChangeV1', {
        'draftId': edit.draftId,
        'expectedDraftRevision': edit.revision,
        'recurrenceScope': 'this_occurrence',
      });
      await wizard.publish(
        edit,
        changeReason: 'Local rescheduling rehearsal',
        changePreviewToken: preview['previewToken'] as String,
      );
      final cancellation = await call('previewEventCancellationV1', {
        'eventId': eventId,
      });
      await call('cancelEventV1', {
        'eventId': eventId,
        'previewToken': cancellation['previewToken'],
        'reason': 'Local cancellation rehearsal',
      });
      expect(
        (await FirebaseFirestore.instance
                .collection('Events')
                .doc(eventId)
                .get())
            .get('status'),
        'cancelled',
      );
      await auth.signOut();
      await tester.pumpWidget(const SizedBox.shrink());
    },
    timeout: const Timeout(Duration(minutes: 8)),
  );
}
