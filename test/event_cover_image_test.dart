import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:attendus/Services/event_cover_image.dart';
import 'package:attendus/models/event_wizard_model.dart';
import 'package:attendus/models/check_in_policy.dart';

void main() {
  test('cover image content type follows bytes, not filenames', () {
    expect(
      eventCoverContentType(
        Uint8List.fromList([137, 80, 78, 71, 13, 10, 26, 10]),
      ),
      'image/png',
    );
    expect(
      eventCoverContentType(Uint8List.fromList([255, 216, 255, 0])),
      'image/jpeg',
    );
    expect(
      () => eventCoverContentType(Uint8List.fromList([1, 2, 3])),
      throwsFormatException,
    );
    expect(
      () => eventCoverContentType(Uint8List(10 * 1024 * 1024 + 1)),
      throwsFormatException,
    );
  });
  test('typed location may keep optional coordinates through reopening', () {
    final draft = EventWizardDraft.blank()
      ..locationInputMode = 'text'
      ..locationCoordinatesEnabled = true
      ..location = 'Upstairs lounge'
      ..latitude = 35
      ..longitude = -80;
    final reopened = EventWizardDraft.fromJson({
      'formData': draft.toFormJson(),
    });
    expect(reopened.hasMappedLocation, true);
    expect(reopened.location, 'Upstairs lounge');
    reopened.clearMappedLocation();
    expect(reopened.hasMappedLocation, false);
    expect(reopened.location, 'Upstairs lounge');
  });
  test('text location round trips and removes mapped attendance settings', () {
    final draft = EventWizardDraft.blank()
      ..locationInputMode = 'text'
      ..location = 'Community clubhouse'
      ..latitude = 35
      ..longitude = -80
      ..checkInPolicy = const CheckInPolicy(
        profile: CheckInProfile.hybrid,
        smartArrivalEnabled: true,
        proximityAssist: true,
      );
    draft.clearMappedLocation();
    final restored = EventWizardDraft.fromJson({
      'formData': draft.toFormJson(),
    });
    expect(restored.locationInputMode, 'text');
    expect(restored.location, 'Community clubhouse');
    expect(restored.latitude, 0);
    expect(restored.checkInPolicy.smartArrivalEnabled, false);
    expect(restored.checkInPolicy.proximityAssist, false);
    expect(
      EventWizardDraft.fromJson({
        'formData': {'location': 'Old venue'},
      }).locationInputMode,
      'place',
    );
  });
}
