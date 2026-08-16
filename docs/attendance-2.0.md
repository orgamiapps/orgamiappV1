# Attendus Attendance 2.0

Attendance 2.0 uses a single server-authoritative contract for self, staff,
guest, pass, roster, and checkout operations. Client writes to `Attendance`
are denied by Firestore Rules.

## Deployment order

1. Deploy `firestore.rules` and `firestore.indexes.json`.
2. Deploy Cloud Functions.
3. Release the Flutter clients.
4. Run the migration in dry-run mode and review the counts:

   ```powershell
   cd functions
   npm run attendance:migrate
   ```

5. Apply only after the review:

   ```powershell
   npm run attendance:migrate -- --apply
   ```

`regular` events migrate to Self Check-in. `all` events migrate to Hybrid.
`most_secure` and `geofence_only` events migrate to Hybrid with
`needsOrganizerReview: true`, so they cannot silently operate at lower
assurance. Legacy radii are converted from feet to meters.

## Callable contract

All callables run in `us-central1`, enforce App Check outside the emulator,
derive the actor from Firebase Authentication, and use shared server-side rate
limits.

- `startCheckInSession`
- `endCheckInSession`
- `mintVenueCredential`
- `resolveCheckInCredential`
- `submitCheckIn`
- `voidAttendance`
- `getPersonalAttendancePass`

Attendance, session secrets, idempotency records, event session locks, rate
limits, and audit entries are server-owned collections. The event owner,
co-hosts, and user IDs in `checkInStaff` can read the operational console.

Authenticated attendees retain a conservative per-minute request ceiling.
Authorized event managers use a separate event-day ceiling sized for at least
ten arrivals per second across eight staff devices and for replaying a full
500-entry offline queue. Authorization, App Check, idempotency, credential
verification, and auditing still apply to every request.

## Offline behavior

Opening the console downloads the eligible roster, ticket verification data,
and the session Ed25519 public key into encrypted local storage. Personal passes
are public-key signed, so staff devices verify them before accepting an offline
scan. Pending scans retain the client observation time and idempotency key and
reconcile exactly once when connectivity returns. Venue codes are never
accepted offline because they are intentionally short-lived.

## Wallet configuration

Google Wallet links are issued when these server environment values exist:

- `GOOGLE_WALLET_ISSUER_ID`
- `GOOGLE_WALLET_CLASS_ID`
- `GOOGLE_WALLET_SERVICE_ACCOUNT_JSON`

Store the service-account JSON with Firebase Secret Manager (for example,
`firebase functions:secrets:set GOOGLE_WALLET_SERVICE_ACCOUNT_JSON`). The
issuer and class IDs are non-secret environment configuration.

The class must be an approved, pre-created Google Wallet event-ticket class.

Apple Wallet delivery is enabled by setting `APPLE_WALLET_PASS_URL` to the
organization's HTTPS `.pkpass` issuer endpoint. Attendus sends that endpoint a
signed, attendee-specific credential. Keep signing certificates and private
keys in the issuer service; never put them in the Flutter application.

When issuer configuration is absent, Wallet buttons remain visibly disabled;
the in-app signed personal pass continues to work.

## Biometrics and location

Event-wide facial search remains disabled. Pass Lock uses the operating
system's device authentication and does not store face templates. Venue
coordinates are stored in meters and are not interpreted as a geofence unless
the separately feature-gated proximity-assist policy is enabled. Background
dwell tracking is not part of Attendance 2.0; checkout is explicit.
