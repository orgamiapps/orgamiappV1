import 'package:flutter_test/flutter_test.dart';
import 'package:attendus/models/check_in_policy.dart';

void main() {
  test('Attendance 2.0 defaults to Hybrid with a one-hour window', () {
    const policy = CheckInPolicy();
    expect(policy.profile, CheckInProfile.hybrid);
    expect(policy.eligibility, CheckInEligibility.open);
    expect(policy.opensBeforeMinutes, 60);
    expect(policy.closesAfterMinutes, 60);
    expect(policy.staffFallback, isTrue);
    expect(policy.attendeeSelfCheckInEnabled, isTrue);
    expect(policy.staffEntryEnabled, isTrue);
  });

  test('legacy tiers migrate without silently weakening restricted events', () {
    expect(
      CheckInPolicy.fromLegacyTier('regular').profile,
      CheckInProfile.selfCheckIn,
    );
    expect(CheckInPolicy.fromLegacyTier('all').profile, CheckInProfile.hybrid);
    for (final tier in ['most_secure', 'geofence_only']) {
      final policy = CheckInPolicy.fromLegacyTier(tier);
      expect(policy.profile, CheckInProfile.hybrid);
      expect(policy.needsOrganizerReview, isTrue);
    }
  });

  test('policy JSON round-trips organizer choices', () {
    const original = CheckInPolicy(
      profile: CheckInProfile.staffEntry,
      eligibility: CheckInEligibility.ticketRequired,
      opensBeforeMinutes: 30,
      closesAfterMinutes: 120,
      checkoutEnabled: true,
      allowReentry: true,
      passLockEnabled: true,
    );
    final decoded = CheckInPolicy.fromJson(original.toJson());
    expect(decoded.profile, original.profile);
    expect(decoded.eligibility, original.eligibility);
    expect(decoded.opensBeforeMinutes, 30);
    expect(decoded.closesAfterMinutes, 120);
    expect(decoded.checkoutEnabled, isTrue);
    expect(decoded.allowReentry, isTrue);
    expect(decoded.passLockEnabled, isTrue);
  });

  test('invalid policy input is bounded and uses safe profile defaults', () {
    final policy = CheckInPolicy.fromJson({
      'profile': 'facial_recognition',
      'eligibility': 'unknown',
      'opensBeforeMinutes': 5000,
      'closesAfterMinutes': -20,
    });
    expect(policy.profile, CheckInProfile.hybrid);
    expect(policy.eligibility, CheckInEligibility.open);
    expect(policy.opensBeforeMinutes, 1440);
    expect(policy.closesAfterMinutes, 0);
  });
}
