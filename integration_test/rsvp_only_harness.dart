// Isolated browser UI harness: no Firebase initialization or production writes.
import 'package:flutter/material.dart';
import 'package:attendus/Utils/attendus_theme.dart';
import 'package:attendus/models/event_wizard_model.dart';
import 'package:attendus/screens/Events/event_creation_wizard_screen.dart';
import '../test/support/wizard_fake.dart';

void main() {
  final draft =
      EventWizardDraft.blank(selectedDateTime: DateTime(2027, 6, 1, 12))
        ..title = 'RSVP-only browser verification'
        ..description = 'Local verification of optional attendance tracking.'
        ..locationType = 'online'
        ..location = 'https://example.test/meet'
        ..primaryDiscoveryCategoryId = 'community-causes'
        ..discoveryCategoryIds = ['community-causes'];
  runApp(
    MaterialApp(
      theme: AttendUsTheme.light,
      home: EventCreationWizardScreen(
        initialDraft: draft,
        service: TestWizardRepository(),
      ),
    ),
  );
}
