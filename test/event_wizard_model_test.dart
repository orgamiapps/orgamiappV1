import 'package:attendus/Services/event_wizard_service.dart';
import 'package:attendus/models/check_in_policy.dart';
import 'package:attendus/models/event_wizard_model.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
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
