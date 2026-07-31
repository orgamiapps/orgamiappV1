# Attendus Admin production rollout and rollback

## Pre-production

- Review all findings in `attendus-admin-architecture.md`, especially the remaining legacy ticket-payment amount trust issue.
- Create restricted Firebase API-key policy; store only the build-time public key in CI secrets.
- Store `STRIPE_SECRET_KEY` as a Cloud Functions secret and configure every plan alias to an approved Stripe Price ID. Never configure price amounts in the client.
- Run Node unit tests, Firestore Rules emulator tests, Functions emulator integration tests, Flutter tests/analyze, Windows release build, installer smoke test, malware scan, and Authenticode verification.
- Test with one non-admin account and each role in a staging Firebase project.
- Confirm retention/alerting for `admin_audit_logs`, function errors, Stripe failures, denied calls, rate limits, and stuck `admin_jobs`.

## Controlled rollout

1. Deploy only the new/changed Functions to staging, then production after approval.
2. Verify non-admin API requests return 403 and create no mutation.
3. Obtain explicit approval for the first administrator email and run the local ADC bootstrap CLI.
4. Re-authenticate the administrator and verify every permission boundary.
5. Deploy the reviewed Firestore rules after confirming public-app critical flows in the emulator/staging project.
6. Sign and publish the installer/checksum to the approved internal channel.
7. Roll out to a small operator group and monitor before broad access.

## Rollback

1. Set affected `admin_roles/{uid}.active` to false with an approved server-side incident procedure and revoke refresh tokens.
2. Roll back the `adminApi` and aggregation function to the prior known-good revision.
3. Roll back Firestore rules only to the last reviewed least-privilege version—never the development catch-all.
4. Withdraw the installer and uninstall through Windows Apps or its Inno uninstaller.
5. Preserve audit logs and Stripe records; do not delete evidence. Reconcile any in-progress idempotency records/jobs before re-enabling access.
