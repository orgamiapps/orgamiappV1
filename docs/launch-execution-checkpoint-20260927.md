# Attendus execution checkpoint - 2026-09-27

Status: implementation advanced; completion gates remain open. This checkpoint supplements the approved `launch-next-agent-plan-20260927.md`; it does not replace that plan or qualify a release. The single acceptance ledger is `launch-fixes-20260927.md`.

## Preserved baseline and release controls

- Workspace: `C:\Users\block\Downloads\orgamiappV1-main\orgamiappV1-main`.
- Branch `codex/comprehensive-hardening`; HEAD `8c40edcf77d7ae269c38294e5bbd8931da1fb3bb` plus preserved pre-existing and new changes. No commit/push/deploy or production record mutation.
- Read checkpoint and original source manifest first; all 991 original file hashes matched before edits.
- Recoverable source ZIP: `C:\Users\block\Downloads\orgamiappV1-main\attendus-continuation-baseline-20260927T204330Z\working-source.zip`, 993 files, CRC verified; SHA-256 `9e2e214edd5158890a2df5c2c956473704a9cfd14c5ef42f9f6ba767e4973471`. Adjacent `report.json` and `git-status.txt` preserve capture evidence.
- Main push workflow deploys indexes, Functions and Hosting. Keep unfinished work off that path. Existing compiled web artifacts are historical, not artifacts of this checkpoint.
- `launch-execution-manifest-20260927.json` records the resulting working-source/evidence hashes. It is a local checkpoint manifest, not an immutable qualified release candidate.

## Implemented in this continuation

1. **Authorization/admissions:** server-owned event creation and protected schedule/lifecycle/role/counter updates; Firestore/Storage deletion guards; transactional role rechecks; shared confirmed/reserved capacity with legacy missing-counter compatibility; explicit ticket-registration pairs; linked cancellation and idempotent refunds; event-aware recovery through current and legacy UID fields; explicit multiple-admission and pair selection in backend and Flutter; admission/check-in schedule-review gates. Existing issued identities and provider-off boundaries remain intact.
2. **Jobs/delivery:** renewable ten-minute/five-attempt lease fencing, poisoned-job validation, recipient/checkpoint/final publication transactions; bounded 100-row announcements and bounded queue/root scans; exact recipient dispositions; HMAC roster cursors bound to actor/event/filter/generation/expiry; safe snapshot retention; audited unknown-delivery resolution without automatic resend; stale-send token fencing; preserve private export objects on an ambiguous publication commit. Original cancellation/reschedule payload revisions now commit with the mutation and cannot be replaced by later edits. Calendar attachment eligibility is rechecked against current linked admission/identity/deletion state; duplicate/unconfirmed messages do not attach; cancellation requires prior-confirmation evidence. Existing registration/ticket UID forms remain preserved.
3. **Deletion/history:** disposition registry and final inventory checks, fenced cleanup/checkpoints, exact banner/draft/profile Storage paths, archival source/correction verification, guest/session mutation guards. Shared conversations migrate in 100-message pages with per-message checkpoints, sanitized aliases, preserved message IDs/sequences/read boundaries, transactional send/read redirects and idempotency across old namespaces. Client follows bounded aliases and blocks interaction while moving. Group ownership becomes explicitly unavailable rather than selecting another person. Retained alias/job/idempotency references are potentially identifying: they stop Auth deletion in `review_required`, pending an actual retention decision and audited resolution.
4. **UX/native:** account-switch/request fencing, selected admission IDs through Upcoming/event/pass, pending/waitlisted/cancelled display, truthful browser/share outcomes and iPad popover anchors; canonical discovery filter URLs and per-entry scroll coordination; separate staging/production service configuration/preflight and protected signing inputs; native FCM auto-init disabled before Dart; inactive permission/capability claims removed. This does not establish store or device qualification.
5. **Migration:** fingerprint-version-2 resulting-state verification before completed-checkpoint reuse, per-attendance archival checkpoints, source/archive/correction checks in final commit. Apply tooling requires successful live export/import metadata and matching isolated restored scope, not a backup object's size alone. No live dry-run refresh, apply or restore rehearsal ran in this continuation.

Focused detail: `launch-jobs-continuation-20260927.md`, `launch-deletion-continuation-20260927.md`, `launch-native-continuation-20260927.md`, `launch-migration-continuation-20260927.md`.

## Validation evidence

- Node 22.23.3 and Java 21.0.12 used for the latest integrated backend tests. Flutter 3.44.6 / Dart 3.12.2 verified despite the local Flutter folder's older name.
- `launch-continuation-integrated-4.log`: **98/98 passed**. Arrival, launch, fenced jobs, deletion/guest guards, migration checkpoint replay/tampering, messaging, shared-conversation crash/resume and retained-ID review stop, Firestore/Storage rules. Includes 205-recipient paging, delayed-revision preservation, forged cursor checks and ambiguous export publication.
- `launch-continuation-node22-unit-2.log`: **167/167 passed**. `launch-continuation-lint-final.log`: clean ESLint after the final shared-retention test.
- `launch-continuation-contracts-2.log`: **11/11 passed** for query/public-web/manifest/provider-secret contracts; query checker found six contracts across seven collection-group call sites.
- Attendus Admin: analysis clean and **6/6 tests passed**, `launch-continuation-admin-{analyze,tests}.log`.
- Python native preflight: **5/5** fixture tests; focused native staging/default, sharing and admission-selection tests passed. No real signing inputs or distribution installed.
- `launch-continuation-npm-audit.json`: no high or critical production dependency advisories; seven moderate remain. No dependency upgrade was performed.
- `launch-continuation-format-2.log`: 369 Dart files checked, zero changes needed after formatting eight existing candidate files; semantic content preserved.
- Final Flutter analysis: clean (`launch-continuation-flutter-analyze-2.log`); full latest Flutter suite **189/189 passed** (`launch-continuation-flutter-tests-2.log`). Chat redirect/feed **7/7** and discovery **9/9** focused tests also passed. Final Functions integration: all three suites passed, **8/8 tests** (admin/account/ticket 3, analytics 3, scheduled reminders 2), `launch-continuation-ci-integration-3.log`. This uses demo emulators and ephemeral dummy credentials, never production credentials.

Failed evidence is retained. `launch-continuation-integrated-2.log` had four failures: two old arrival fixtures lacked explicit admission links, a roster fixture lacked a UID, and guest resend wrote undefined optional fields. Fixtures were made explicit and the real optional-field bug fixed; the later 54/54 and 98/98 runs passed. `launch-continuation-ci-integration.log` had a first-invocation timeout before the free-ticket worker started; only that cold invocation now has a 60-second allowance, replay retains 15 seconds. `launch-continuation-ci-integration-2.log` passed admin/account/ticket but timed out analytics while source reloads were occurring; it is not clean integration evidence. The Edge discovery test stalled before reporting any cases and was interrupted; its isolated owned browser process was verified and stopped, unrelated Edge preserved. Real browser history behavior remains unqualified.

## Owner configuration and guidance

User owns GitHub account `orgamiapps` and has an iPhone and Samsung Galaxy. Read-only inspection confirmed repository admin access and zero configured environments at that time. First setup step: open `https://github.com/orgamiapps/orgamiappV1/settings/environments`, create `native-release`, select reviewer `orgamiapps`, restrict deployment branch pattern to `codex/**`. With one reviewer, do not enable prevention of self-review if that would make the workflow impossible to approve. Do not dispatch the unfinished candidate.

Awaiting owner answers/access: Apple Developer and Play Console enrollment/app records; actual Apple team/app/profile and Play-installed certificate; isolated staging Firebase native apps/domain/providers; protected signing/service configuration locations; named retention reviewer; iPad tester. Credentials/signing material belong in protected GitHub environment secrets or protected configuration stores, never in chat. The native continuation document provides exact configuration names and setup order. Environment names in YAML do not prove protections are configured.

## Open gates and next executable work

Unfinished code is distinct from external prerequisites. Remaining code includes a unified revision-bound lifecycle coordinator across availability/check-in/reminders/sessions/passes; reconciliation of every already-issued calendar identity; complete side-effect eligibility/preferences; bounded coherent contact/export snapshot semantics and issued-download revocation; exhaustive field-level deletion/retention/provider inventory; public verified-guest deletion and Apple revocation recovery; reviewed/audited resolution of retained identifiers; remaining capability and large-roster acceptance; complete orphan/source/Storage/Auth/config backup scope and migration rehearsal. Some account/export inventory scans remain unbounded. Unsupported legacy messaging evidence intentionally requires review.

Continue these implementations while protected owner inputs are pending. Before migration or activation, refresh production inventory/dry-run after final code, resolve the named ambiguous admission from evidence, rehearse isolated recovery and reconcile counters/history/schedules. No missing counters or uncertain dates should be fabricated.

Steps 7-8 remain unfulfilled: freeze one source/config candidate; produce and hash matching web/native artifacts; qualify authenticated browser/device matrix including iPad, TestFlight and Play-installed builds; review retention wording; verify rollback; deploy compatible gated backend and verified migration; run owned two-offline-staff-device pilot; observe through event close plus the 24-hour replay window. No deployment, device qualification, pilot or observation is claimed. Observation automation should start only when there is a qualified owned pilot to monitor.

## Deployment status update — 2026-09-27 21:59 UTC

Supersedes earlier no-deployment statements; implementation and local test evidence above remains historical. See [deployment report](launch-deployment-report-20260927.md) and `launch-deployment-manifest-20260927.json`.

Staging web, all 113 Functions, default Firestore/Storage rules and additive indexes deployed. Both staging domains passed 63 immutable-asset checks; analytics and scheduled-reminder canaries passed; 14 explicit canary fixture paths verified absent. All 48 indexes READY in each project. Production received 13 additive indexes only; production web and 111 Functions unchanged. No production migration applied. All code areas remain partially implemented as listed above; staging deployment is not full functional acceptance. Signed/native/device qualification, authenticated browser matrix, recovery rehearsal, production reconciliation, pilot and event-close plus 24-hour observation remain open. Completion gates are not satisfied.

Owner needs Apple/Play enrollment help; see [enrollment guide](launch-store-enrollment-20260927.md). Legal account type remains pending; credentials stay in protected configuration. No store enrollment or distribution performed.

## Production website publication — 2026-09-27 22:16 UTC

Owner explicitly requested attendus.app publication while deferring launch completion. Website deployed and guest rendering checked; 525 immutable assets verified on attendus.app and orgami-66nxok.web.app. Added 24 website backend dependencies, all ACTIVE; original 111 Functions unchanged. No migration apply/rules/native release. See [production release report](production-web-release-20260927.md) for version, rollback and evidence.

Correction: prior 113-function staging completeness claims used a parser that omitted dynamic exports. Explicit exports plus a runtime-inventory regression test now cover them; staging still needs that expanded inventory reconciled. Authenticated/end-to-end, device and observation gates remain unqualified. Launch completion is deferred, not achieved.
