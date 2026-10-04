import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:attendus/Services/notification_preferences_service.dart';
import 'package:attendus/models/notification_model.dart';

void main() {
  test(
    'late old-account preferences cannot replace new account cache',
    () async {
      String? uid = 'a';
      final old = Completer<Map<String, dynamic>?>();
      final service = NotificationPreferencesService(
        currentUid: () => uid,
        load: (id) => id == 'a'
            ? old.future
            : Future.value({'generalNotifications': false}),
        save: (_, _) async {},
      );
      final pending = service.read();
      uid = 'b';
      final fresh = await service.read();
      old.complete({'generalNotifications': true});
      await expectLater(pending, throwsStateError);
      expect(service.cached, same(fresh));
      expect(service.cached!.generalNotifications, false);
      uid = null;
      expect(service.cached, isNull);
    },
  );
  test(
    'failed save is surfaced and does not change cached preferences',
    () async {
      final service = NotificationPreferencesService(
        currentUid: () => 'a',
        load: (_) async => null,
        save: (_, _) async => throw StateError('write failed'),
      );
      final original = await service.read();
      await expectLater(
        service.write(original.copyWith(generalNotifications: false)),
        throwsStateError,
      );
      expect(service.cached, same(original));
    },
  );
  test(
    'rapid saves preserve order and a queued save cannot cross accounts',
    () async {
      String? uid = 'a';
      final first = Completer<void>();
      final writes = <String>[];
      final service = NotificationPreferencesService(
        currentUid: () => uid,
        load: (_) async => null,
        save: (id, _) {
          writes.add(id);
          return first.future;
        },
      );
      final a = service.write(UserNotificationSettings());
      final b = service.write(UserNotificationSettings());
      final expectedA = expectLater(a, throwsStateError);
      final expectedB = expectLater(b, throwsStateError);
      await Future<void>.delayed(Duration.zero);
      uid = 'b';
      first.complete();
      await Future.wait([expectedA, expectedB]);
      expect(writes, ['a']);
      expect(service.cached, isNull);
    },
  );
}
