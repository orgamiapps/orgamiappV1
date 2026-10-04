# Web backend qualification — 2026-10-04

This work continues the dirty `codex/project-debugging-20261003` workspace from the 1,140-file sibling backup `attendus-web-qualification-baseline-20261004T025604Z`. The earlier `375d7e…` identity is a source-content manifest, not Git HEAD. Historical October 3 results remain historical; the new candidate requires fresh validation and deployed evidence.

## Source changes

### Compatible analytics trigger transition

`functions/analytics/insights.js` preserves `triggerAIInsights` as `google.cloud.firestore.document.v1.updated` on `event_analytics/{docId}`. The new `triggerAIInsightsV2` uses `.written` on the same path. Both run the same transaction, fingerprint current source inputs, and remove stale output when the source/event disappears. Concurrent old/new deliveries commit one change; unchanged input does not rewrite the output. Completion logs contain only event ID, Eventarc delivery ID, trigger name, source update time and outcome.

The candidate adds one function export. It does not delete the existing function or force a trigger-type replacement. `backend-trigger-canaries` verifies the deployed types, creates/updates/deletes analytics only for the explicitly owned, bound canary event, and waits for both deployed versions' replay-completion logs for the exact source version. Unit and actual-Firestore overlap tests are registered separately.

Retirement is a later explicit operation: preserve both names through the full staging overlap/observation window and production rollout; retain completion/error evidence; obtain authority for the exact project/name/region retirement; prepare a new source/deployment manifest without the legacy export; then delete only `triggerAIInsights` in that approved retirement operation and verify the remaining V2 inventory. The current qualification/promotion workflow has no automatic function deletion. A successful deploy alone is not retirement evidence.

### Fixture delivery isolation

`functions/communications/qualification-isolation.js` governs inbox and provider boundaries for email, legacy notifications, messaging, reminders, admin dispatch, discovery, pending push, announcement inbox fanout and monthly usage inbox records.

- Unmarked ordinary production delivery retains its existing eligibility and token-ownership checks.
- Deployed staging suppresses unscoped delivery. Unsupported/conflicting project identities suppress delivery.
- A verified QA association captures before creating an inbox notification or handing off to Graph/FCM. Guest email addresses must match an explicitly controlled email hash before capture. Suppression occurs before decryption for unscoped staging jobs and before Graph token acquisition for qualified mail.
- Missing, expired, malformed, mixed-run or tombstoned bindings suppress. They never fall through to ordinary production delivery. Recipient/actor deletion also suppresses capture.
- Local demo behavior still requires the exact demo project, Functions emulator marker and loopback Firestore routing. Existing emulator capture/injected-provider tests remain separate from live QA evidence.

Private schema:

```text
QualificationScopes/{runId}
  schemaVersion: 1, projectId, status: active, mode: capture
  createdAt, expiresAt (at most 72 hours after createdAt)
  actorUids[<=20], recipientUids[<=20], eventIds[<=50]
  organizationIds[<=10], conversationIds[<=10], recipientEmailHashes[<=20]

QualificationBindings/{kind}_{sha256(id)}
  schemaVersion: 1, projectId, runId, state: bound | tombstone
  kind: account | event | organization | conversation

QualificationCaptures/{sha256([runId, recipientUid-or-emailHash, sourceKey])}
  sourceKey, fingerprint, payload, actorUid, recipientUid, recipientEmailHash
  eventIds, capturedAt, expiresAt, provider: qualification_capture
```

Bindings must exist **before** fixture writes and remain permanently bound or tombstoned while any fixture-derived work can exist. Bindings have no TTL. Scope/capture TTL is bounded to 72 hours; renew a scope before expiry if necessary and export/hash evidence before capture expiry. Captures reject different content reusing a source key. Firestore client reads/writes are denied, including administrator-claim clients; no public capture API exists. Captures participate in account-deletion queries, while active scope associations require an explicit retention disposition. Bindings contain hashed association IDs and are retained to prevent unsafe delivery fallback.

Staging provider credentials were reported by root to overlap production credentials. These guards must be deployed and verified before live QA fixture mutations; credentials are not assumed to be a sandbox.

### Admission question compatibility

The server previously required registration-only questions again at check-in and used only the legacy `questionTitle`. `functions/attendance/questions.js` now shares the authoritative arrival and guest-form rule: absent timing means legacy `check_in`; registration timing is excluded; current `prompt` is used with legacy title fallback. Required answers remain enforced for check-in questions.

## Executable recovery evidence

`functions/tools/complete-launch-migration.js` now rejects staging, production and demo as cloud restore targets. `attendus-recovery-20261004` is the only permitted target. Application still requires a current version-2 dry run, successful complete export/import operation metadata, available export metadata object, exact restored event scope and matching restored source/archive fingerprints. `--recovery-target-proof` binds the fresh isolation proof into the result.

`tools/capture_recovery_target.js` collects project metadata, complete enabled-service inventory, IAM/custom-role definitions, actual rules sources, and empty listener inventories for any enabled listener services. Disabled services remain disabled; their absence is checked together with protected creation IAM. No API is enabled. The collector validates the actual `cloud.firestore` release and exact deny-all rules. Missing permissions, inherited IAM not examined by the validator, unexpected mutation principals, listeners, permissive rules or stale proof block verification.

The backend producer downloads a **private**, generation- and SHA-256-pinned GCS bundle into memory. It does not publish source documents in Actions artifacts. Configuration:

```text
fixture.recovery.bundle = {bucket, object, generation, sha256}
bundle = {
  schemaVersion: 1,
  restoreProject: attendus-recovery-20261004,
  reference: gs://.../....overall_export_metadata,
  exportOperation, importOperation,
  plan: <version-2 read-only migration report>,
  sourceContent: <source REST content-hash inventory>,
  sourceHeartbeatFields: <three checkpoint field-hash inventories>
}
```

`tools/recovery_content.js` inventories the restored hierarchy, including children of missing ancestors, at a consistent Firestore read time. It uses the same canonical REST field hashing as root's retained comparison. Actual changed/missing/extra path hashes remain in the report. Only `updatedAt` changes on these exact records can be separately explained, with every other field hash equal:

- `EventOperationScans/EventAnnouncements`
- `EventOperationScans/EventExportJobs`
- `EventOperationScans/rosterCleanup`

There is no blanket timestamp exclusion. Root's historical comparison reported 1,161 records, 1,158 exact matches and these three heartbeat-only changes. That observation is not substituted for a fresh producer run.

Restoration alone cannot qualify production data readiness. The recovery gate also rejects any ambiguity remaining in the pinned migration plan and rechecks the **live source**, read-only, for ambiguous ticket/registration links or unproven attendance. `tools/authoritative_data_readiness.js` projects only the fields needed for those checks and quota evaluation. It inventories the actual `Customers.eventsCreated` and `subscriptions.eventsCreatedThisMonth` fields; missing, negative, noninteger or malformed required counters block. The exact publication policy is reused: current active premium or server-owned boolean `unlimitedEventCreation: true` bypasses counters; free and basic require their authoritative counters. No zero is fabricated. Raw missing/invalid counts remain visible even where an explicit exemption applies. Historical unresolved admission/quota issues remain promotion blockers until separately authorized remediation and a fresh backup/plan verify them.

## Live producer contract and boundaries

`tools/web_release_producers/backend.js` exports `produce({candidate, context, outputDir})`. The wrapper supplies the verified candidate/deployment identity and validates returned assertion comparisons, raw hashes and provenance. Required fixture fields are `runId`, `owner.uid`, `event.id`, `eventClosesAt` (equal to the actual event schedule end), `ownedFixtureIds`, and a separate `canaryEventId`. Event IDs may appear directly or as `Events/{id}` in the owned inventory. The current scope and permanent binding are checked before every canary mutation. Source user passwords/tokens and captured message bodies are never included in producer artifacts.

The producer emits:

| Gate | Actual evidence |
|---|---|
| `notification-delivery-isolation` | Captures from email, legacy, message, reminder, announcement, discovery, pending and admin families; empty fixture inboxes; no real provider or unknown outcomes; verified capture identities and content hashes. Missing families fail. |
| `backend-trigger-canaries` | Deployed function configurations plus completed old/V2 replay logs and creation/update/deletion output checks on the separate owned canary. |
| `data-migration-recovery` | Fresh live isolation proof, completed operation metadata, export object identity, actual restored event/archive fingerprints and full restored document-content comparison. |
| `event-close-replay-observation` | Actual job states/attempts/leases, capture identities/fingerprints, event/roster revisions and registration/ticket/attendance/archive counts; failed, dead-letter, unknown or expired active work blocks qualification. |

Hourly `context.requestedGates: ["observation"]` is read-only and skips canary mutations and recovery scans. It records the same health sample; it does not claim that 24 hours have elapsed. Historical samples come only from wrapper-verified prior workflow artifacts and are rechecked against their raw hashes and candidate/fixture identities. The final qualification enforces the window through at least event close plus 24 hours, cadence and freshness. Post-close stable-state comparisons begin after a 15-minute worker drain interval. No single CI process sleeps for 24 hours.

The root-owned operations producer additionally verifies actual journey receipts (registration, attendance, announcement/export jobs), signed-download expiry and rollback. Backend unit tests do not replace those live gates.

## Local validation ledger

- Targeted trigger/isolation/recovery/legacy/discovery/migration tests: 36 passed before the final completion-log addition.
- Final targeted completion-log and producer/recovery-tools tests: 9 passed.
- Full Functions lint passed before the final logging edit; final rerun is in progress.
- A first full unit run passed 297/298. The lone failure was a mock delivery test lacking an explicit runtime project; the fail-closed policy correctly suppressed it. The mock now explicitly models ordinary production with fake storage and unsupported channels; its 14 tests passed. Fresh full results will be appended below.
- No cloud writes, provider sends or production data changes were performed by this backend agent. Root owns cloud operations and their evidence.

Fresh static run: Functions lint passed and 306/306 unit tests passed (`build/web-qualification-20261004/backend-lint.log`, `backend-unit.log`). The later tools-only live-readiness addition passed its six-test focused tools suite. The first isolated static harness attempt incorrectly imposed emulator-only environment variables on unit tests, producing two configuration-test failures; correcting the harness to leave unit runtime flags unset resolved both without product changes. Serial rules/messaging/integration/launch/attendance runs are in progress.

Pending qualification is explicit: fresh final backend suites, rendered browser acceptance, actual staging producer execution, the 24-hour post-close window, and approved promotion. Source implementation alone does not satisfy these gates.

### Final local backend rerun (04:04 UTC)

All backend sources were frozen during the serialized emulator runs. Test processes received an explicit environment allowlist and a deliberately nonexistent demo ADC identity with a loopback token endpoint. No production credentials were inherited by test SDKs. Relevant evidence is in `build/web-qualification-20261004/` (ignored operational evidence, not a release artifact by itself):

| Check | Result | Evidence |
|---|---|---|
| Functions lint | passed | `backend-lint.log` |
| Unit and backend producer tools | 308/308 passed | `backend-unit.log` |
| Firestore/Storage rules | 46/46 passed | `backend-rules.log` |
| Messaging and rules | 51/51 passed | `backend-messaging.log` |
| Default serialized integration | all six suites passed | `backend-integration.log` |
| Launch/deletion/migration/shared-conversation | 44/44 passed | `backend-launch.log` |
| Attendance | 21/21 passed | `backend-attendance.log` |

The six integration suites comprise 3 admin/account/ticket cases, 3 analytics cases, 2 reminder cases, 25 community/quiz/profile/notification/QA/trigger-transition cases, and separate synthetic export-seed/restore scripts. Actual Functions emulator logs also show the original and replacement analytics triggers completing against the same source update time, with one update and replay handling. All emulators stopped successfully; ports were handed back for the frontend rendered rerun. `backend-static-results.json` and `backend-emulators-results.json` retain exact start/end times and exit codes.

The earlier failed static harness attempt's two failures came from imposing demo/emulator flags on unit tests and were resolved by correcting the harness environment. Its original working log was replaced by the final rerun; the tool transcript and `backend-initial-harness-failure-summary.json` retain the observed failures and correction. The separate first 297/298 run remains at `build/debugging-20261003/web-backend-unit.log`. The final static run above includes the live-readiness regressions. `git diff --check` passed (Git reported line-ending conversion warnings only).

Remaining promotion gates are live staging execution and browser acceptance, the authenticated observation window through event close plus 24 hours, historical admission/quota remediation decisions and fresh resulting evidence, rollback proof, and approved promotion. The backend changes have not been deployed by this agent.

### Authenticated staging pilot and communication sources

`tools/web_release_producers/browser-pilot.js` now executes registration, staff session/manual admission, same-key retries, a separate duplicate admission attempt, unauthorized admission/export denial, roster export, and an attendee announcement through the browser producer's real UI-authenticated App Check callable adapter. Its observer performs only private Firestore reads: current scope/bindings/setup candidate identity, unchanged pilot schedule/revision, persisted receipt links, export generation, and exact announcement/email capture fingerprints. `pilot-receipts.json` contains server-issued IDs and redacted assertions; it excludes manage tokens, signed URLs, captured message bodies and authentication credentials. The operations producer consumes only wrapper-verified same-candidate browser receipt evidence rather than arbitrary fixture-provided IDs.

`browser-communications.js` adds actual direct-conversation/message calls, attendee feedback, scoped administrator notification and future-event registration. It verifies source documents and exact `message`, `legacy`, `admin` and `pending` capture identities. The root-owned seeder supplies the tokenless legacy pending-push source only; it never creates delivery-success evidence. Future event registration drives the ordinary reminder reconciler. A fixture follower created before eligible future-event publication drives discovery. The helper records real pending jobs and verifies the configured reminder offset and the 45-minute discovery delay. It does not shorten either timer or claim their delivery before the later backend producer observes actual `reminder` and `discovery` captures. Together with the pilot's email/announcement records, these sources cover the eight required capture families.

The communication helper runs last after the other browser journeys pass. Its dedicated disposable account first creates personal app feedback via callable, then invokes the real authenticated `deleteUserAccount`. The observer requires absence of Auth, Customers, users and that feedback document plus a completed deletion job with recorded empty disposition inventory. This account is included in the owned fixture list and permanent binding, but excluded from shared scope actor/recipient lists, group ownership, staff and administrator roles: retaining those associations intentionally requires a separate retention review. Pilot actors remain available for observation. An unknown deletion response is reconciled by observing the original request, without an automatic second mutation. A previously deleted account can only be reused as evidence with a successful, immutable, wrapper-validated browser receipt from the same candidate and fresh live absence checks; it is never recreated.

During pilot contract review, a confirmed admission bug was found: V3 registration stores structured answer objects, while the admission merge called `.split()` on every saved answer. The narrow fix retains structured registration answers and merges only legacy string answers. A pure regression passes, and a new actual-Firestore manual-admission/replay test is registered in the existing attendance suite. The frontend's next rendered run includes this fix; the older 308-unit/21-attendance result above predates it.

Focused validation after these changes: 4 pilot-tool tests, 5 communication-tool tests and 3 attendance-question tests passed; targeted Functions ESLint and diff whitespace checks passed. The communication tests include prior-receipt raw-hash/deployment tampering and unknown deletion-response reconciliation. Reminder fixture events start four hours after seed, so the default one-hour reminder is due around seed plus three hours; the eight-family delivery gate must wait for the real timer evidence independently of the earlier pilot close. No cloud fixture execution or provider communication was performed by this backend agent. Fresh full backend/emulator qualification and actual staging execution remain required before these new paths can be called qualified.

Backend-only hourly/final observations now reread the public-web and attendance AppConfig documents and share the operations producer's strict runtime flag validator. Paid checkout and Apple/Google delivery must remain disabled, public guest paths and the expected App Check key must remain enabled, and attendance scope must remain restricted to owned events/users. Safe flags, their digest and the actual flag-read timestamp are retained separately from deployment metadata identity. The combined backend/operations/pilot/communications tool suite passed 21/21 after this wiring.

### Narrow-change qualification completed at 04:53 UTC

After the rendered-browser runner released the shared emulator ports, both new helper test files were registered in `functions/package.json`. Fresh Functions lint passed, the complete registered unit suite passed **318/318**, and the isolated actual-Firestore attendance suite passed **22/22**, including the structured-registration-answer/manual-door-answer/replay case. The earlier rules, messaging, integration and launch results remain historical evidence for unchanged backend paths; they were not rerun unnecessarily for this narrow admission merge. No test failed in this follow-up.

Evidence is retained separately, without replacing the earlier 308/21 baseline: `build/web-qualification-20261004/backend-pilot-lint.log`, `backend-pilot-unit.log`, `backend-pilot-attendance.log`, `backend-pilot-static-results.json`, and `backend-pilot-attendance-results.json`. The static run completed at 04:52:40 UTC and attendance at 04:53:10 UTC. The same explicit environment allowlist, nonexistent demo ADC and loopback token endpoint isolated the test processes. Firestore/CLI shutdown completed and ports were returned to the frontend for its next rendered acceptance run. Source is frozen pending any newly reproduced defect; live staging gates remain unexecuted by this agent.

The later read-only qualification review identified missing runtime `iam.serviceAccounts.signBlob` for roster URL signing, the seeder's missing Auth-emulator rejection, and Safari checks that accepted an incorrect calendar schedule/origin or an empty page after forward/reload. Root owns the scoped IAM and seeder corrections; the release agent owns the stronger Safari assertions. No IAM or runtime source was changed by this agent during that review.

The tools-only guest proof observer now supports a repeat controlled-email registration. It reads only a newly captured email after the actual browser submission, verifies candidate/scope/event ownership, recipient email hash, capture fingerprint, accepted source receipt, active proof-token linkage and current guest admission, and returns the staging manage URL only in memory for real browser navigation. Stale, wrong-recipient, tampered, production-origin, revoked, deleting or mismatched-event proof is rejected. Pilot tests now pass 7/7 and communications tests 5/5 (12/12 combined); Node syntax and whitespace checks pass. This adds three unit cases after the 318-test baseline above and does not imply live guest acceptance.
