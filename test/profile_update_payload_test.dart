import 'package:attendus/models/customer_model.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('profile edits never replay cached server-owned creation quotas', () {
    final profile = CustomerModel(
      uid: 'user',
      name: 'Updated name',
      email: 'user@example.test',
      createdAt: DateTime(2026),
      eventsCreated: 4,
      groupsCreated: 2,
    );
    final update = CustomerModel.getProfileUpdateMap(profile);
    expect(update.containsKey('eventsCreated'), isFalse);
    expect(update.containsKey('groupsCreated'), isFalse);
    expect(update['name'], 'Updated name');
    expect(profile.eventsCreated, 4);
    expect(profile.groupsCreated, 2);
  });
  test('new signup serialization still initializes quotas to zero', () {
    final profile = CustomerModel(
      uid: 'user',
      name: 'Name',
      email: 'user@example.test',
      createdAt: DateTime(2026),
    );
    final creation = CustomerModel.getMap(profile);
    expect(creation['eventsCreated'], 0);
    expect(creation['groupsCreated'], 0);
  });
}
