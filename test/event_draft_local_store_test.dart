import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:attendus/Services/event_draft_local_store.dart';
import 'package:attendus/models/event_wizard_model.dart';
import 'support/auth_fakes.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
  });
  test(
    'local draft and last pointer are isolated by account, including clear',
    () async {
      String? uid = 'a';
      final store = EventDraftLocalStore(currentUid: () => uid);
      final draft = EventWizardDraft.blank()..title = 'Private organizer draft';
      await store.write(draft);
      uid = 'b';
      expect(await store.read(), isNull);
      expect(await store.read('local'), isNull);
      await store.clear(draft);
      uid = 'a';
      expect((await store.read())!.title, 'Private organizer draft');
      uid = null;
      expect(await store.read(), isNull);
    },
  );
  test(
    'unscoped legacy drafts are never attributed to the current account',
    () async {
      SharedPreferences.setMockInitialValues({
        'event_wizard_last_draft_v2': 'local',
      });
      FlutterSecureStorage.setMockInitialValues({
        'event_wizard_draft_v2_local':
            '{"formData":{"title":"Previous owner"}}',
      });
      expect(await EventDraftLocalStore(currentUid: () => 'b').read(), isNull);
    },
  );
  test(
    'account switch during storage write cannot set the new account pointer',
    () async {
      String? uid = 'a';
      final barrier = Completer<void>();
      final storage = TestSecureStorage()
        ..beforeWrite = (_, _) => barrier.future;
      final store = EventDraftLocalStore(
        currentUid: () => uid,
        storage: storage,
      );
      final pending = store.write(EventWizardDraft.blank()..title = 'A');
      await Future<void>.delayed(Duration.zero);
      uid = 'b';
      barrier.complete();
      await expectLater(pending, throwsStateError);
      expect(await store.read(), isNull);
    },
  );
}
