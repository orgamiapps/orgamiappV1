import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:attendus/Services/event_creation_entitlement_service.dart';

void main() {
  test(
    'switching accounts, revocation and logout clear the allowance',
    () async {
      final accounts = StreamController<String?>();
      final grants = <String, StreamController<bool>>{};
      String? current;
      final service = EventCreationEntitlementService.testing();
      service.bind(
        accounts.stream,
        () => current,
        (uid) => (grants[uid] = StreamController<bool>()).stream,
      );
      Future<void> flush() => Future<void>.delayed(Duration.zero);
      current = 'owner';
      accounts.add(current);
      await flush();
      grants['owner']!.add(true);
      await flush();
      expect(service.unlimited, isTrue);
      current = 'other';
      expect(service.unlimited, isFalse);
      accounts.add(current);
      await flush();
      grants['owner']!.add(true);
      await flush();
      expect(service.unlimited, isFalse);
      grants['other']!.add(true);
      await flush();
      expect(service.unlimited, isTrue);
      grants['other']!.add(false);
      await flush();
      expect(service.unlimited, isFalse);
      grants['other']!.addError(StateError('permission denied'));
      await flush();
      expect(service.unlimited, isFalse);
      current = null;
      accounts.add(null);
      await flush();
      expect(service.unlimited, isFalse);
      service.clear();
      service.dispose();
      await accounts.close();
      for (final stream in grants.values) {
        await stream.close();
      }
    },
  );
}
