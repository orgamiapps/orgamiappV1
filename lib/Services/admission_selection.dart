/// Invalidates all earlier reads after refresh, account change, or disposal.
class AdmissionRequestGuard {
  int _revision = 0;
  String? _uid;

  int begin(String? uid) {
    _uid = uid;
    return ++_revision;
  }

  void invalidate() {
    _uid = null;
    _revision++;
  }

  bool accepts(int revision, String? currentUid) =>
      revision == _revision && _uid != null && _uid == currentUid;
}

/// Both selected identifiers must describe the same admission. Multiple rows
/// require an explicit choice, even when their names or statuses are identical.
Map<String, dynamic>? selectAdmission(
  List<Map<String, dynamic>> admissions, {
  String? registrationId,
  String? ticketId,
}) {
  if (registrationId == null && ticketId == null) {
    return admissions.length == 1 ? admissions.single : null;
  }
  final matches = admissions.where(
    (row) =>
        (registrationId == null || row['registrationId'] == registrationId) &&
        (ticketId == null || row['ticketId'] == ticketId),
  );
  return matches.length == 1 ? matches.single : null;
}
