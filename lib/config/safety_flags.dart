/// Security-sensitive capabilities that are intentionally unavailable while
/// their server-authoritative replacements complete staging verification.
abstract final class SafetyFlags {
  static const bool paidCheckoutEnabled = false;
  static const bool eventFeaturingEnabled = false;
  static const bool biometricCheckInEnabled = false;
  static const bool scheduledPlanChangesEnabled = false;

  static const String paymentMaintenanceMessage =
      'Paid checkout is temporarily unavailable while Attendus completes a security upgrade.';
  static const String biometricMaintenanceMessage =
      'Facial check-in is temporarily unavailable. Please use QR code or manual code check-in.';
}
