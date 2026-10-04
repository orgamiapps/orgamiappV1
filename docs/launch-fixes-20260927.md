# Attendus launch implementation and acceptance ledger

Date: 2026-09-27. Status: local implementation candidate; not deployed or launch-qualified.

## Source and preservation

Repository: `C:\Users\block\Downloads\orgamiappV1-main\orgamiappV1-main`.
HEAD: `8c40edcf77d7ae269c38294e5bbd8931da1fb3bb`.
This checkout already contained extensive modified and untracked Smart Arrival, messaging, event-lineup, entitlement, and discovery work. Those changes were preserved. HEAD alone does not identify the candidate; the source manifest alongside this document records working-file hashes. No commit, reset, production deployment, real-account deletion, or attendee announcement was performed.

## Implemented locally

| Plan area | Implementation |
| --- | --- |
| Registration | V3 transactional idempotency and conflicts, shared guest/full-account form with required questions, authoritative current status, independent attendance loading, retry states, retained authentication intent, mobile primary action. Existing private and paid gates remain. |
| Schedules | Exact-minute schedule helpers in Dart and Node, IANA presentation, legacy-quality handling on the server, real ICS with stable IDs/revisions, encoded Google/Outlook links, public metadata and communication integration. |
| Organizer | Shared manager/door capabilities, event-specific announcement composer with preview, durable deterministic recipients and truthful provider-acceptance counts, cancellation preview/revisions/recurrence scope, protected permanent deletion, automatic reschedule notices, edit reason/affected-audience preview and Reschedule action. |
| Roster/export | Stable registration/ticket/attendance projection, cursor pagination, full-event search, distinct metrics, complete filtered private CSV jobs, formula protection, browser/native download adapter, individual offline conflict acknowledgment, kit and sync information. |
| Trust/history | Report/block connected to existing backend, canonical moderation fields, server-only permanent attendance stamps and encrypted separate identity records, audited identity retrieval and append-only corrections. |
| Deletion | Resumable leased phases, archival verification before destruction, pass/token/photo/cache cleanup, selective shared messaging cleanup, preservation of another attendee's purchased admission, guest email-claim cleanup, account-deletion guards on registration/messaging/announcement generation. |
| Native/polish | Native Google API integration, Apple nonce and deletion-token revocation code, Maps initialization, contextual notification permission, practical event details, discovery shortcuts and startup stabilization, improved schedule/capacity labels, deferred rating prompt. |

These entries describe implemented code, not blanket completion of each acceptance row in the approved plan.

## Validation evidence

- Backend ESLint: passed; backend unit suite: 111/111 passed.
- Full Flutter suite: 175/175 passed before the final small edits. Subsequent wizard/schedule tests: 5/5; offline suite including two-conflict preservation: 10/10. Final Flutter analyze: no issues.
- Combined local Firestore/Storage emulator integration and rules run: 63/63 passed. Includes Smart Arrival, messaging, guest idempotency, capacity/waitlist, owner-only status, 620-person pagination/search, role restrictions, retained history, deletion failure/retry and preservation of another attendee's ticket.
- Launch emulator suite repeated after deletion guards: 7/7 passed.
- Final targeted backend schedule/wizard/roster tests: 16/16 passed; earlier renderer/wizard/schedule tests: 21/21.
- Firestore query-contract check: 6 contracts / 9 call sites passed. Provider-disabled secret-manifest tests: 3/3 passed. No Wallet provider activation.
- `git diff --check`: passed after removing one trailing blank line.
- Final web release rebuild succeeded in 147.7 seconds. Output: `build/launch-polish-web`. `main.dart.js` SHA-256: `49fe77d8fc3ab8ae0e0352aadf67826f8b05b6cc165e5c6a343d31a3e26025e4`. Compilation is not authenticated browser or production acceptance.
- `launch-candidate-manifest-20260927.json` records 554 source-file hashes and 83 web-build hashes; manifest SHA-256: `c08988b117a1f634846dd73140a3d0b305f3ff5e1ab2db92dffa4e718acdc3d3`. Source includes preserved pre-existing work. No immutable release artifact has been promoted.
- Final delivery-guard change passed ESLint and 13 targeted accountless/roster tests. Actual provider/deletion concurrency remains an integration acceptance gate.
- Emulator tests used only `demo-attendus-admin`. The deliberate archive-failure fixture logs an error before the successful recovery assertion; that is expected test evidence.
- Read-only production inventory at `2026-09-27T08:50:26.148Z`: 143 events; 133 schedules legacy/incomplete; 82 attendance records; zero historical archive records. No mismatch among events with a stored confirmed counter. Missing counters and historical source completeness still require reconciliation. See `launch-inventory-20260927.json`. No production records changed.

## Outstanding implementation and verification gates

1. Complete a field-by-field personal-data inventory and review deletion retention exceptions. Audit/payment records, shared-content ownership, follower links, claimed credentials, and legacy collections require explicit disposition. A separate account-closure workflow is not exposed. Do not advertise closure as available. Privacy wording requires review before launch.
2. Reconcile the completed read-only production inventory before any migration or activation. Backfill historical attendance with provenance and verify counts; reconcile missing legacy registration capacity counters and the 133 flagged schedules. Preserve source records until verification. There is no approved production backfill result yet.
3. Verify legacy ticket-only registration recovery, account switching, all approval/promotion/cancellation permutations, stale role changes, recurring reschedule preview/application, export completeness with real browser/native downloads, and interrupted job execution. Production composite indexes and Storage download CORS require verification.
4. Finish staff name/role presentation and remaining responsive, keyboard, screen-reader, denied-permission and slow-network reviews. Verify refreshed URLs, Back/filter/scroll restoration, discovery resize behavior, and image quality visually on the final candidate.
5. Qualify all durable workers under concurrent execution, ambiguous provider responses, deletion races and repeated permanent failures; define terminal failure handling and projection-generation cleanup. Local deterministic-job tests do not qualify actual email acceptance/delivery or real export storage/downloads.
6. Account deletion is destructive: full inventory, retention review, authenticated fixture acceptance and cleanup verification remain release blockers even though the failure/retry emulator test passes. Do not test on real accounts.
7. Obtain verified Apple team/app identifiers, App Store configuration and Play signing certificate. On 2026-09-27 the live Apple association returned an empty `details` array. Android published package `com.stormdeve.orgami` with SHA-256 `59:84:23:E5:05:16:F7:81:B6:FB:CE:2E:46:49:98:92:C6:4E:2D:05:9C:A8:BA:6A:63:79:A3:2A:62:84:A8:CB`; comparison with Play signing is pending. Association files are not yet represented in the web source and must be preserved/configured before hosting publication.
8. Produce genuinely signed TestFlight and Play test builds, then test Apple/Google login, token revocation, cold/warm event/community links, Maps and native sharing. Windows web compilation does not satisfy iOS or Android release acceptance.
9. Conduct an owned-account event pilot with real iPhone/Android devices, two offline staff devices, conflict/revocation reconciliation, complete export, reschedule/cancellation and attendee updates. Observe through event closing plus the existing 24-hour offline replay allowance. No pilot or observation window has been completed for this candidate.

## Deployment order and rollback

Resolve critical implementation gaps and migration counts first. Freeze and hash one candidate; qualify it against the same backend/index configuration. Deploy compatible backend/index/rules changes before clients, verify owned fixtures, then enable narrowly scoped entry points. Preserve existing issued identifiers and wallet/provider-off boundaries. Paid activation, automatic refunds, biometrics and Wallet issuer activation remain outside this release.

Before deployment, capture the actual current client artifact and backend configuration as rollback evidence. Rollback restores that client and disables affected entry points while retaining compatible backend reads, new records, attendance evidence, identities and audit history. Do not roll back by deleting pilot records or reverting data schemas destructively.

## Immediate continuation

Use this ledger with the approved user plan. Continue remaining implementation and authenticated acceptance; do not treat passing automated tests as permission to skip the open gates. Signing identifiers and the retention reviewer were requested, with no answer recorded at the time of this ledger.

## Subsequent implementation checkpoint

See [launch-completion-checkpoint-20260927.md](launch-completion-checkpoint-20260927.md) for the current continuation, evidence and remaining gates. Earlier counts and test results above describe the preceding candidate.


## Execution continuation - 2026-09-27

Current implementation checkpoint: [launch-execution-checkpoint-20260927.md](launch-execution-checkpoint-20260927.md). Earlier entries describe prior candidates. This remains unfinished local work, not a release freeze.

| Plan area | Implemented | Local evidence | Staging / device / deployed / observed |
| --- | --- | --- | --- |
| Authorization/capacity | Protected client writes; transactional roles/deletion; shared capacity and explicit links; guarded cancellation/refunds; missing-counter compatibility without guessed counts | Direct-write attacks, mixed last-seat requests, role races, explicit-link cancellation and current/legacy recovery | No / no / no / no |
| Durable operations | Fenced renewable jobs; bounded announcement pages and queue/root scans; signed cursors; audited unknown-delivery resolution; export ambiguous-commit recovery | Lease competition, paging/dispositions, cursor attacks, provider-result fencing and export publication checks | No / no / no / no |
| Lifecycle/calendar | Transactional original-revision snapshots; eligibility before ICS attachment; prior-confirmation cancellation evidence | Delayed revision scenario and attachment eligibility units | No / no / no / no |
| Deletion/history | Expanded dispositions and evidence checks; fenced cleanup; guest mutation guards; exact Storage paths; resumable shared conversations/redirects | Archive tampering/retry, guest flows, Storage cleanup, 205-message crash/resume, surviving read boundaries; retained references block Auth deletion for review | No / no / no / no |
| UX/native | Explicit admissions/account-switch fences, truthful sharing/iPad anchors, discovery URLs/history, chat redirects; staging/production native preflight | Focused Dart/Python checks; full results in checkpoint | No / no / no / no |
| Migration | Resulting-state fingerprints, per-attendance checkpoints, export/isolated-restore proof required for apply; admission schedule-review gates | Unit and emulator source-change/archive-tamper checks | No rehearsal / N/A / no apply / no |

Combined Node 22 emulator run: 98/98 passed (`launch-continuation-integrated-4.log`). Backend units: 167/167; ESLint clean. Contract/manifest/provider-secret tests: 11/11. Attendus Admin analysis clean and 6/6 tests. Latest full Flutter analysis is clean and 189/189 tests passed. Final Functions integration passed all three suites (8/8 tests). Retained failed evidence is recorded in the checkpoint. Tests do not establish all acceptance gates.

Baseline: original 991 manifest files matched; recoverable 993-file ZIP and hash recorded in checkpoint. All pre-existing changes preserved; no commit, push, deployment or production mutation. Main pushes automatically deploy indexes/functions/Hosting.

Owner: user owns GitHub orgamiapps and has iPhone/Samsung Galaxy. Read-only inspection confirmed repo admin access and no configured environments. Guided first action: create native-release with reviewer orgamiapps and branch pattern codex/**. Actual protections/configuration are not yet verified. Apple/Play access, isolated staging configuration, signing/provider material, actual Play signing certificate, retention reviewer and iPad tester remain pending. Store credentials in protected configuration, never chat. See [native setup](launch-native-continuation-20260927.md).

Remaining implementation: unified lifecycle coordination/reminders/sessions/passes; all issued calendar UIDs; bounded coherent export/contact snapshots and download revocation; exhaustive deletion/retention inventory, guest-proof deletion and Apple recovery; reviewed resolution for retained messaging identifiers; remaining capabilities/navigation; complete migration/orphan/backup scope and rehearsal. Some export/account inventory scans remain unbounded. Steps 1-6 are partial.

Remaining acceptance: protected owner config, retention review, isolated recovery rehearsal, refreshed production inventory/dry run and ambiguous-link evidence, immutable artifacts, real browsers and signed TestFlight/Play device matrix including iPad, compatible production reconciliation/deployment, owned two-offline-device pilot and event-close plus 24-hour observation. No release, pilot or observation has started. Completion is not declared.

## Deployment status update — 2026-09-27 21:59 UTC

Supersedes earlier no-deployment statements; implementation and local test evidence above remains historical. See [deployment report](launch-deployment-report-20260927.md) and `launch-deployment-manifest-20260927.json`.

Staging web, all 113 Functions, default Firestore/Storage rules and additive indexes deployed. Both staging domains passed 63 immutable-asset checks; analytics and scheduled-reminder canaries passed; 14 explicit canary fixture paths verified absent. All 48 indexes READY in each project. Production received 13 additive indexes only; production web and 111 Functions unchanged. No production migration applied. All code areas remain partially implemented as listed above; staging deployment is not full functional acceptance. Signed/native/device qualification, authenticated browser matrix, recovery rehearsal, production reconciliation, pilot and event-close plus 24-hour observation remain open. Completion gates are not satisfied.

Owner needs Apple/Play enrollment help; see [enrollment guide](launch-store-enrollment-20260927.md). Legal account type remains pending; credentials stay in protected configuration. No store enrollment or distribution performed.

## Production website publication — 2026-09-27 22:16 UTC

Owner explicitly requested attendus.app publication while deferring launch completion. Website deployed and guest rendering checked; 525 immutable assets verified on attendus.app and orgami-66nxok.web.app. Added 24 website backend dependencies, all ACTIVE; original 111 Functions unchanged. No migration apply/rules/native release. See [production release report](production-web-release-20260927.md) for version, rollback and evidence.

Correction: prior 113-function staging completeness claims used a parser that omitted dynamic exports. Explicit exports plus a runtime-inventory regression test now cover them; staging still needs that expanded inventory reconciled. Authenticated/end-to-end, device and observation gates remain unqualified. Launch completion is deferred, not achieved.
