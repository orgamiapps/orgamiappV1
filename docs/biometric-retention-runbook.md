# Biometric retention runbook

Client access to `FaceEnrollments` is denied by Firestore rules and biometric
check-in is disabled by `SafetyFlags`. The retained records must remain
quarantined until the approved deletion date, then be removed through the
audited utility in this repository.

## Inventory

Run from `functions/` with production application-default credentials:

```text
npm run biometrics:inventory
```

The command returns only aggregate counts, missing-metadata counts, and the
earliest/latest enrollment timestamps. It does not print biometric templates,
user IDs, names, event IDs, or document IDs.

## Deletion controls

Before deletion, verify a Firestore export and record its immutable storage
reference. The utility refuses deletion unless all three controls are present:

- The exact typed confirmation `DELETE_FACE_ENROLLMENTS`.
- A backup reference of at least eight characters.
- A UTC `not-before` date that has already passed.

Example for the currently approved 30-day quarantine window:

```text
node tools/biometric-retention.js --delete --confirm=DELETE_FACE_ENROLLMENTS --backup-reference=gs://BUCKET/EXPORT --not-before=2026-09-01 --requested-by=OPERATOR
```

The utility deletes in bounded batches, verifies the collection is empty, and
writes an `admin_audit_logs` completion record. Do not run deletion until the
backup has been restored successfully in staging and the retention date has
been approved by the project owner and privacy counsel.
