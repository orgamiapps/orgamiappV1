# Remaining-launch implementation checkpoint — 2026-09-27

This is a local, unqualified candidate. It has not been deployed and does not satisfy the approved completion definition. Existing working changes are preserved; source HEAD remains 8c40edcf77d7ae269c38294e5bbd8931da1fb3bb.

## Implemented in this continuation

- Transactional event/organization authorization, immutable edit-draft sources, deletion guards, bounded recurrence scopes, dedicated change previews, and idempotent publication replay.
- Shared capacity validation for public registration and organizer decisions; retry-safe approval/promotion and explicit rejection of full events without waitlisting.
- Legacy notification fan-out now queues durable jobs and avoids repeating new publication jobs. Outbound reservation no longer relies on mutable transaction callback state.
- Export publication verifies lease, actual roles and subject deletion guards in a transaction, uses lease-specific private objects, and records snapshot metadata and an atomic audit. Failed publication removes its private object.
- Ten-minute job leases, bounded retries and visible terminal failures; paginated announcement recipient snapshots and filter-bound export request identities.
- Stable roster generations and fifteen-minute page cursors, snapshot-specific aggregates, dirty-roster navigation, chronological attendance transition folding, unknown-time handling, and paid/revoked ticket eligibility.
- Upcoming registrations/tickets endpoint and Flutter destination, including RSVP-only registrations; server capability/staff endpoints and staff-name UI.
- Restricted archive admission grouping, evidence verification, unknown timestamp provenance, review queues for unproven attendance, audited identity retrieval, idempotent corrections, and additional deletion cleanup/anonymous-session support.
- Community authentication continuation, permission-gated push token acquisition, native association generation, tracked Hosting handling, protected signing workflow and Apple signing-material helper.
- Read-only migration planner and checkpointed apply tooling requiring a verified backup object. No apply operation has run.

## Current evidence

- Backend ESLint passed.
- Backend unit suite: 113/113 passed; the latest export/recipient guards are covered in part by the targeted suite below.
- Launch emulator and roster suite: 19/19 passed, including draft authorization, removed roles, approval retries, dirty-snapshot pagination, export key conflicts, lease serialization, publication replay, paid/revoked admission counts, and deletion racing with export publication.
- Flutter analysis passed with no issues after fixing five style findings. Full Flutter suite: 176/176 passed. Fresh web release compilation passed to build/remaining-launch-web (compile evidence only; production configuration and live acceptance remain open).
- Firestore rules, attendance and messaging integration: 52/52 passed. Query/public-web contracts and function manifest/provider-disabled secret checks: 11/11 passed. Storage rules and the admin client were not rerun in this continuation.
- Native workflow YAML and Apple helper syntax passed. Association validation used fixture identifiers only. No signing, store upload or native device acceptance occurred.
- Fresh read-only production migration dry run: 143 events, one ambiguous admission link, zero records classified as insufficient attendance evidence by the current classifier. Final read-only refresh is in launch-migration-dry-run-final-20260927.json and includes unpaid/revoked eligibility handling. No migration was applied.

## Remaining implementation blockers

1. Unify every legacy ticket issuance/cancellation capacity path and enforce material-change preview requirements on legacy direct writes; exercise concurrent publication/approval and stale-role races comprehensively.
2. Finish a single lifecycle pipeline and reconcile every issued calendar UID, and restrict attachments to eligible confirmed admissions.
3. Finish worker fencing/checkpoints and provider-unknown operator recovery; stress-test transactional export publication guards and short-lived download revocation; bind cursors securely and complete large-event stress checks.
4. Complete multi-admission pass selection, organizer capability usage across all screens, native share outcome handling and real browser downloads.
5. Finish the complete personal-data disposition inventory, guest proof/public account-deletion entry, shared-conversation redirects/concurrent cleanup, ownership disposition, and cleanup verification before authentication deletion. Retention wording still needs review.
6. Finish discovery URL/filter/scroll restoration and responsive/accessibility acceptance. Repeat affected checks after remaining implementation and qualify the final artifact before deployment.
7. Register isolated native staging apps, verify release identifiers/configuration, configure protected CI credentials, run signed builds, and collect real device evidence.

## Migration and launch gates

Resolve the ambiguous admission link without guessing. Regenerate the dry run after final code changes. Capture and verify a recoverable backup before migration; reconcile counters and actual attendance evidence, preserve source records, and gate schedules needing organizer correction. The previously recorded 10 exact / 45 legacy / 88 incomplete schedule split must be refreshed at that point.

No staging deployment, production migration, signed native release, owned event pilot or 24-hour replay observation has completed. Do not enable the candidate until code/security/deletion blockers and current acceptance are cleared. Owner prerequisites remain the protected GitHub release environment, verified Apple/Play identifiers/signing credentials, and a retention-policy reviewer. Secret values must remain outside chat.

## Artifact checkpoint

Fresh compile output: `build/remaining-launch-web`; `main.dart.js` SHA-256: `cab799ea9287fc45a92b1925e20e2bab01bde387063912ed6caeb5f84902d83c`. Two Dart files were subsequently formatted only; this is compile evidence, not a frozen release artifact. The owned Firestore emulator was stopped after validation. No background tests or builds remain.
