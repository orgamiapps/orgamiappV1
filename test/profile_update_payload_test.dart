import 'package:attendus/models/customer_model.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'name-only patch preserves current independent and untouched fields',
    () {
      final form = {'name': 'Original', 'bio': 'Original bio'};
      final baseline = ProfileEditSnapshot.profile(form);
      form['name'] = 'Edited';
      final timestamp = Timestamp(1791110400, 123456000);
      final current = <String, dynamic>{
        'name': 'Original',
        'bio': 'Newer bio',
        'isDiscoverable': false,
        'favorites': ['newer-saved-event'],
        'createdAt': timestamp,
        'eventsCreated': 8,
        'groupsCreated': 5,
        'profilePictureUrl': 'newer-photo',
        'bannerUrl': 'newer-banner',
      };
      expect(
        {...current, ...baseline.changes(form)},
        {...current, 'name': 'Edited'},
      );
    },
  );
  test(
    'legacy explicit privacy edit persists while untouched bio is omitted',
    () {
      final baseline = ProfileEditSnapshot.profile({
        'name': 'Member',
        'isDiscoverable': true,
        'bio': 'Bio',
      });
      expect(
        baseline.changes({
          'name': 'Member',
          'isDiscoverable': false,
          'bio': 'Bio',
        }),
        {'isDiscoverable': false},
      );
    },
  );
  test('normalized empty fields and rendered social JSON stay untouched', () {
    final values = {
      'name': 'Member',
      'bio': null,
      'socialMediaLinks': '{"twitter":"https://example.test/member"}',
    };
    final baseline = ProfileEditSnapshot.profile(values);
    expect(baseline.changes({...values, 'name': 'New name'}), {
      'name': 'New name',
    });
  });
  test('notification patch excludes unchanged false and defaults', () {
    final baseline = ProfileEditSnapshot.notifications({
      'eventReminders': false,
      'messagesAll': true,
      'generalNotifications': true,
    });
    expect(
      baseline.changes({
        'eventReminders': false,
        'messagesAll': false,
        'generalNotifications': true,
      }),
      {'messagesAll': false},
    );
  });
  test('unloaded or non-form fields cannot enter a patch', () {
    for (final field in [
      'uid',
      'favorites',
      'createdAt',
      'eventsCreated',
      'groupsCreated',
      'profilePictureUrl',
      'bannerUrl',
    ]) {
      expect(
        () => ProfileEditSnapshot.profile({field: 'cached'}),
        throwsArgumentError,
      );
    }
    final baseline = ProfileEditSnapshot.profile({'name': 'Member'});
    expect(
      () => baseline.changes({'name': 'Member', 'bio': 'Unloaded'}),
      throwsStateError,
    );
  });
  test(
    'auth enrichment preserves user-selected name and current phone/photo',
    () {
      final profile = CustomerModel(
        uid: 'uid',
        name: 'User-selected name',
        email: 'member@example.test',
        phoneNumber: 'new phone',
        profilePictureUrl: 'new photo',
        createdAt: DateTime(2026),
      );
      expect(
        CustomerModel.missingAuthProfileFields(
          profile,
          name: 'Old Auth name',
          phoneNumber: 'old phone',
          profilePictureUrl: 'old photo',
        ),
        isEmpty,
      );
      profile.name = '';
      expect(
        CustomerModel.missingAuthProfileFields(profile, name: ' Auth name '),
        {'name': 'Auth name'},
      );
    },
  );
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
