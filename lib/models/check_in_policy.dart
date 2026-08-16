enum CheckInProfile {
  selfCheckIn('self_check_in'),
  staffEntry('staff_entry'),
  hybrid('hybrid');

  const CheckInProfile(this.value);
  final String value;

  static CheckInProfile fromValue(String? value) => switch (value) {
    'self_check_in' => CheckInProfile.selfCheckIn,
    'staff_entry' => CheckInProfile.staffEntry,
    _ => CheckInProfile.hybrid,
  };
}

enum CheckInEligibility {
  open('open'),
  registeredOnly('registered_only'),
  ticketRequired('ticket_required');

  const CheckInEligibility(this.value);
  final String value;

  static CheckInEligibility fromValue(String? value) => switch (value) {
    'registered_only' => CheckInEligibility.registeredOnly,
    'ticket_required' => CheckInEligibility.ticketRequired,
    _ => CheckInEligibility.open,
  };
}

/// Versioned, organizer-facing attendance policy.
///
/// Venue location is intentionally not part of this object. A physical address
/// describes the event; [proximityAssist] is the explicit opt-in for using a
/// one-time location signal during check-in.
class CheckInPolicy {
  static const int currentVersion = 2;

  final int version;
  final CheckInProfile profile;
  final CheckInEligibility eligibility;
  final int opensBeforeMinutes;
  final int closesAfterMinutes;
  final bool allowReentry;
  final bool checkoutEnabled;
  final bool proximityAssist;
  final bool staffFallback;
  final bool passLockEnabled;
  final bool needsOrganizerReview;

  const CheckInPolicy({
    this.version = currentVersion,
    this.profile = CheckInProfile.hybrid,
    this.eligibility = CheckInEligibility.open,
    this.opensBeforeMinutes = 60,
    this.closesAfterMinutes = 60,
    this.allowReentry = false,
    this.checkoutEnabled = false,
    this.proximityAssist = false,
    this.staffFallback = true,
    this.passLockEnabled = false,
    this.needsOrganizerReview = false,
  });

  factory CheckInPolicy.fromJson(
    Map<String, dynamic>? data, {
    String? legacyTier,
  }) {
    if (data == null || data.isEmpty) {
      return CheckInPolicy.fromLegacyTier(legacyTier);
    }
    int boundedMinutes(dynamic value, int fallback) {
      final parsed = value is num ? value.toInt() : fallback;
      return parsed.clamp(0, 1440);
    }

    return CheckInPolicy(
      version: data['version'] is num
          ? (data['version'] as num).toInt()
          : currentVersion,
      profile: CheckInProfile.fromValue(data['profile']?.toString()),
      eligibility: CheckInEligibility.fromValue(
        data['eligibility']?.toString(),
      ),
      opensBeforeMinutes: boundedMinutes(data['opensBeforeMinutes'], 60),
      closesAfterMinutes: boundedMinutes(data['closesAfterMinutes'], 60),
      allowReentry: data['allowReentry'] == true,
      checkoutEnabled: data['checkoutEnabled'] == true,
      proximityAssist: data['proximityAssist'] == true,
      staffFallback: data['staffFallback'] != false,
      passLockEnabled: data['passLockEnabled'] == true,
      needsOrganizerReview: data['needsOrganizerReview'] == true,
    );
  }

  factory CheckInPolicy.fromLegacyTier(String? tier) => switch (tier) {
    'regular' => const CheckInPolicy(profile: CheckInProfile.selfCheckIn),
    'all' => const CheckInPolicy(profile: CheckInProfile.hybrid),
    'most_secure' || 'geofence_only' => const CheckInPolicy(
      profile: CheckInProfile.hybrid,
      needsOrganizerReview: true,
    ),
    _ => const CheckInPolicy(),
  };

  bool get attendeeSelfCheckInEnabled =>
      profile == CheckInProfile.selfCheckIn || profile == CheckInProfile.hybrid;

  bool get staffEntryEnabled =>
      profile == CheckInProfile.staffEntry || profile == CheckInProfile.hybrid;

  CheckInPolicy copyWith({
    CheckInProfile? profile,
    CheckInEligibility? eligibility,
    int? opensBeforeMinutes,
    int? closesAfterMinutes,
    bool? allowReentry,
    bool? checkoutEnabled,
    bool? proximityAssist,
    bool? staffFallback,
    bool? passLockEnabled,
    bool? needsOrganizerReview,
  }) => CheckInPolicy(
    version: currentVersion,
    profile: profile ?? this.profile,
    eligibility: eligibility ?? this.eligibility,
    opensBeforeMinutes: opensBeforeMinutes ?? this.opensBeforeMinutes,
    closesAfterMinutes: closesAfterMinutes ?? this.closesAfterMinutes,
    allowReentry: allowReentry ?? this.allowReentry,
    checkoutEnabled: checkoutEnabled ?? this.checkoutEnabled,
    proximityAssist: proximityAssist ?? this.proximityAssist,
    staffFallback: staffFallback ?? this.staffFallback,
    passLockEnabled: passLockEnabled ?? this.passLockEnabled,
    needsOrganizerReview: needsOrganizerReview ?? this.needsOrganizerReview,
  );

  Map<String, dynamic> toJson() => {
    'version': currentVersion,
    'profile': profile.value,
    'eligibility': eligibility.value,
    'opensBeforeMinutes': opensBeforeMinutes,
    'closesAfterMinutes': closesAfterMinutes,
    'allowReentry': allowReentry,
    'checkoutEnabled': checkoutEnabled,
    'proximityAssist': proximityAssist,
    'staffFallback': staffFallback,
    'passLockEnabled': passLockEnabled,
    'needsOrganizerReview': needsOrganizerReview,
  };
}
