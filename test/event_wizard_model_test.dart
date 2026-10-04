import 'package:attendus/Services/event_wizard_service.dart';
import 'package:attendus/models/check_in_policy.dart';
import 'package:attendus/models/event_wizard_model.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('local picker instants cross the server boundary with explicit UTC', () {
    final start = DateTime(2027, 7, 14, 9, 30);
    final end = start.add(const Duration(hours: 2));
    final draft = EventWizardDraft(startAt: start, endAt: end)
      ..registrationOpensAt = start.subtract(const Duration(days: 7))
      ..registrationClosesAt = start.subtract(const Duration(minutes: 30));
    final form = draft.toFormJson();
    final registration = form['registration'] as Map<String, dynamic>;
    for (final entry in {
      'startAt': start,
      'endAt': end,
      'opensAt': draft.registrationOpensAt!,
      'closesAt': draft.registrationClosesAt!,
    }.entries) {
      final encoded = (form[entry.key] ?? registration[entry.key]) as String;
      final parsed = DateTime.parse(encoded);
      expect(parsed.isUtc, isTrue, reason: entry.key);
      expect(parsed.isAtSameMomentAs(entry.value), isTrue, reason: entry.key);
    }
    final restored = EventWizardDraft.fromJson(form);
    expect(restored.startAt, start);
    expect(restored.startAt.isUtc, isFalse);
    expect(restored.endAt, end);
    expect(restored.registrationOpensAt, draft.registrationOpensAt);
    expect(restored.registrationClosesAt, draft.registrationClosesAt);
  });

  test('explicit DST offsets retain distinct instants and recurrence dates', () {
    // The repeated New York 01:30 occurs twice when DST ends. A transport
    // round-trip must preserve the distinct instants, not reinterpret wall time.
    final restored = EventWizardDraft.fromJson({
      'startAt': '2027-11-07T01:30:00-04:00',
      'endAt': '2027-11-07T01:30:00-05:00',
      'eventTimeZone': 'America/New_York',
      'recurrence': {
        'enabled': true,
        'endMode': 'date',
        'endDate': '2027-11-14',
      },
    });
    expect(
      restored.endAt.difference(restored.startAt),
      const Duration(hours: 1),
    );
    final form = restored.toFormJson();
    expect(form['startAt'], '2027-11-07T05:30:00.000Z');
    expect(form['endAt'], '2027-11-07T06:30:00.000Z');
    expect(form['eventTimeZone'], 'America/New_York');
    expect((form['recurrence'] as Map)['endDate'], '2027-11-14');
  });

  test('event creation configuration fails closed', () {
    expect(resolveEventCreationExperienceVersion(null), 1);
    expect(resolveEventCreationExperienceVersion({}), 1);
    expect(
      resolveEventCreationExperienceVersion({'experienceVersion': '2'}),
      1,
    );
    expect(resolveEventCreationExperienceVersion({'experienceVersion': 3}), 1);
    expect(resolveEventCreationExperienceVersion({'experienceVersion': 2}), 2);
  });

  test('wizard form round-trips versioned questions and Attendance 2.0', () {
    final draft =
        EventWizardDraft.blank(selectedDateTime: DateTime.utc(2027, 3, 14, 13))
          ..title = 'Accessible workshop'
          ..registrationMode = EventRegistrationMode.freeTicket
          ..approvalMode = EventApprovalMode.manual
          ..questions = [
            EventWizardQuestion(
              id: 'access',
              prompt: 'What support would help?',
              timing: EventQuestionTiming.registration,
            ),
          ]
          ..checkInPolicy = const CheckInPolicy(
            profile: CheckInProfile.hybrid,
            eligibility: CheckInEligibility.registeredOnly,
          );
    final restored = EventWizardDraft.fromJson({
      'id': 'draft-a',
      'revision': 4,
      'formData': draft.toFormJson(),
    });
    expect(restored.title, draft.title);
    expect(restored.questions.single.timing, EventQuestionTiming.registration);
    expect(restored.checkInPolicy.profile, CheckInProfile.hybrid);
    expect(
      restored.checkInPolicy.eligibility,
      CheckInEligibility.registeredOnly,
    );
  });

  test('curated templates are stable and only alter reusable defaults', () {
    expect(EventWizardTemplate.curated, hasLength(8));
    expect(
      EventWizardTemplate.curated.map((template) => template.id).toSet(),
      hasLength(8),
    );
    final draft = EventWizardDraft.blank(
      selectedDateTime: DateTime.utc(2027, 1, 1, 15),
    );
    final start = draft.startAt;
    draft.applyTemplate(
      EventWizardTemplate.curated.firstWhere(
        (template) => template.id == 'webinar',
      ),
    );
    expect(draft.startAt, start);
    expect(draft.locationType, 'online');
    expect(draft.checkInPolicy.profile, CheckInProfile.selfCheckIn);
  });
}
