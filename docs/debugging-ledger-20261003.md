# Attendus debugging ledger — October 3, 2026

Historical checkpoint. The subsequent user-approved web-only qualification and conditional production-promotion scope is recorded in `web-release-qualification-20261004.md`; its current evidence and boundaries supersede the authorization/status statements below. Native distribution remains excluded from the current effort.

Status: local repair candidate verified to the boundaries below; complete-project acceptance remains open. No production deployment,
production migration, store release, or production data mutation is authorized.
Disabled payment/featuring/biometric/scheduled-plan features remain disabled.

## Recoverable baseline

- Branch: `codex/project-debugging-20261003`.
- Starting HEAD: `8c40edcf77d7ae269c38294e5bbd8931da1fb3bb`, with existing changes preserved.
- Snapshot: `C:\Users\block\Downloads\orgamiappV1-main\attendus-debug-baseline-20261003T043908Z\working-source.zip`.
- Snapshot includes 1,037 nonignored working-source files, SHA-256 file manifest,
  binary Git diff and status. ZIP CRC verification passed. Ignored local secrets
  remain in place and are not copied into shared artifacts.
- Toolchain verified: Flutter 3.44.6, Dart 3.12.2, Node 22.23.2, Java 21.0.12.
- Original deployment and test reports are historical; they do not qualify this candidate.

## Evidence and coverage

The machine-readable surface inventory is `debugging-inventory-20261003.json`.
Its existence proves enumeration, not completed review. Per-workstream reports
record inspected behavior, reproduced defects, fixes, tests, and remaining gaps.

| Workstream | Status | Evidence |
| --- | --- | --- |
| Client/auth/discovery | Active subsystem source review and privacy/share-link corrections; analyzer clean and 305 tests passing | `debugging-client-20261003.md`; final privacy logs |
| Backend/admissions/deletion/jobs | Active subsystem source review and local repairs; external/legacy boundaries recorded | `debugging-backend-20261003.md` |
| Admin/platform/release gates | Source review, Admin tests and Windows integration passed; Android compile-only APK/AAB passed; iOS/device acceptance open | `debugging-platform-20261003.md` |
| Browser and application integration | Both final real Flutter journeys passed; final public-browser rerun recorded below | `build/debugging-20261003/` |
| Rules and integrated emulator suites | Fresh rules45, messaging50, integration6 suites, launch44, attendance21 passed | `privacy-final-*.log` |
| Cloud inventory and migration rehearsal | Read-only inventories refreshed; synthetic export/restore and interrupted migration passed | `integration-frozen.log`; isolated recovery export |
| Physical browsers/devices and signed distribution | Not verified | Physical-device and signing evidence required |

The tables below retain chronological checkpoints, including failures. The final
candidate section at the end supersedes earlier test counts; a passing local
check never implies staging, device or distribution acceptance.

## Initial validation

- Contract tests: 16 passed, 0 failed, 0 skipped; Node 22.
  Local log: `build/debugging-20261003/contracts-baseline.log`.
- A green contract baseline does not establish authenticated browser journeys,
  full backend correctness, migration readiness, or native qualification.

## Completion rule

Every confirmed defect must be repaired and verified. Unavailable configuration,
provider access, devices, or unresolved data ambiguity is a blocked check, not a
passing result. The final candidate must retain exact source/configuration/test
and artifact provenance. Production promotion is outside this effort.

## Fresh validation checkpoint

These are run-specific results, not a claim that a later edited candidate passed.
Logs are retained under `build/debugging-20261003/` unless noted otherwise.

| Check | Fresh evidence | Remaining work |
| --- | --- | --- |
| Backend unit | 217 passed, `backend-unit-final.log` | Rerun after final notification/access repairs |
| Contracts | 16 passed, `contracts-final.log` | Refresh after final exports/indexes |
| Main Flutter | 223 passed, `flutter-test-client-full.log`; analyzer clean in `flutter-analyze-client-followup.log` | Management/draft repairs require another final run |
| Admin | 19 passed; Windows desktop integration 1 passed | Live authentication and installed/signed acceptance unverified |
| Community/quiz concurrency and rules | 10 passed, `community-final.log` | Final source parity check |
| Attendance | 21 passed, `attendance-final.log` | Physical scans/offline two-device acceptance unverified |
| Launch/deletion/lifecycle/migration | 42 passed, `launch-final.log` | Includes new interruption/resume test; cloud recovery remains separate |
| Rules | Initial 30 passed; expanded run 36 passed/1 failed | Private-event query denial repaired; rerun required |
| Public browsers | Initial Chromium 4 passed; expanded run 13 passed/3 failed | All three failures were capture deadlines; real captures subsequently arrived. Frozen-source rerun required, with retained failures |
| Flutter browser | Compile failed on missing imports during active client edits | Imports repaired; full real journey rerun required |
| Release guard tests | 12 passed, `release-guards-final.log` | No GitHub workflow dispatched |
| Production dependency audit | 0 high/critical; 2 moderate | Development-only advisory findings remain tracked separately |
| Secret scan | Current nonignored source passed after narrow public-identifier/fixture review | Final source refresh required; 12 history matches classified as public identifiers/checksums, no private credential identified |

Admin evidence is under `build/debugging-platform-20261003/`:
`admin-tests-final.log` and `admin-desktop-final.log`. The debug executable is
not a signed installer or evidence of live Firebase desktop authentication.

## Root integration defect register

Workstream reports above contain the detailed additional auth, community,
quiz, deletion, Admin and discovery defects. Status below means corrected in
source unless an explicit passing journey is cited; it never means deployed.

| ID / severity | Reproduction and expected versus actual | Root cause and correction | Evidence |
| --- | --- | --- | --- |
| WEB-01 / P1 | Render a staging public event: registration must use staging identity and links; old configuration used production identifiers/origins. | Project-aware browser configuration and business origin resolver reject unknown/conflicting projects; only a strict demo/loopback configuration connects emulators. | `browser-environment.test.js`, public page browser configuration assertion |
| WEB-02 / P1 | Drop a successful registration response and retry: one admission expected; a fresh request key could create another attempt. | Canonical actor/payload hash retains the retry key in session storage with an in-memory fallback; initialization is shared and waits for restored Auth state. | All four engines completed registration/retry with one admission; delivery deadline failures remain separate |
| WEB-03 / P2 | Existing-account login during guest upgrade must preserve its profile; old display-name update could overwrite it. | Only a newly linked credential receives the supplied display name. | Source review; authenticated provider acceptance still required |
| WEB-04 / P2 | Open disabled paid checkout: show unavailable state without Auth/provider/registration requests. | Fail before Firebase initialization, prevent overlapping dialogs, retain explicit error text. | Passing disabled-checkout case in all four browser projects |
| WEB-05 / P2 | Real callable/App Check requests must satisfy page CSP. | Added exact project Functions origin and required reCAPTCHA paths; demo-only local sources do not weaken production CSP. | CSP regression and real emulator browser calls |
| DEP-01 / P1 | Production dependency audit identified high-severity runtime advisories, including an unpatched signing dependency. | Updated compatible lockfile dependencies; replaced Wallet CMS generation with PKIjs/Node WebCrypto, retaining independent signature/manifest verification. Vulnerable legacy library is development/test-only. | `attendance-wallet.test.js` includes signature verification and mismatched-key rejection; remediated production audit |
| MIG-01 / verification gap | Interrupt after one attendance archive checkpoint, then resume and replay. | Added a real-Firestore interruption test asserting source preservation, exactly two archives/checkpoints and idempotent completion. | Passed in `launch-final.log` |

## Cloud inventory and data constraints

Read-only cloud checks used explicit projects. The default alias is production;
it is not safe evidence of staging isolation. No cloud data/configuration writes
or releases were performed.

- `attendus-staging`: current event inventory is empty. Initial Functions
  comparison found 28 source-only endpoints before this effort's new community
  and quiz endpoints. Staging is not running this candidate.
- `orgami-66nxok`: initial source comparison found 6 source-only endpoints before
  the new community/quiz exports. Inventory found 143 events, all lacking the
  stored confirmed counter; schedules were 10 exact, 45 legacy and 88 incomplete.
- The refreshed version-2 migration dry run contains one ambiguous admission
  relationship and no verified backup. No counters, dates or admission links
  were guessed or changed. Preserve this as a separate future migration gate.
- GitHub environment inventory returned an empty list. Workflow references to a
  `production` environment do not prove environment protection is configured.
- Dedicated staging Maps and reCAPTCHA public resource identifiers were found
  read-only. This does not establish isolated native registration, provider
  enrollment, protected signing credentials, or device acceptance.

## Required external acceptance

| Gate | Exact missing evidence / next action |
| --- | --- |
| Native signing and installed apps | Provide the location/owner of protected Apple/Play signing configuration, verified application identities, and enrolled test devices; do not place credentials in chat. Compile-only fixture signatures are insufficient. |
| Physical iPhone/iPad/Android | Run camera, push, Maps, associated links, cold/warm navigation, 200% text, screen reader and two disconnected staff-device replay journeys on actual devices. |
| Browser distribution | Playwright WebKit is engine coverage, not physical Safari acceptance. Qualify installed Safari/Edge and real downloads/calendar imports separately. |
| Isolated staging candidate | Deploy only after source/configuration freeze and passing local gates, then run authenticated multi-account journeys with fixture-only cleanup and provider sandboxes. Existing preview URLs are not proof of isolation. |
| Data migration/recovery | Resolve the one ambiguous admission with authoritative owner evidence and provide matching completed isolated export/restore proof; refresh the dry run before any separately authorized production migration. |
| Provider acceptance | Verify owned sandbox delivery/revocation and real App Check/Google/Apple authentication behavior. Local captured mail proves application handling only. |

## Repeatable local commands

Use Flutter 3.44.6, Node 22 and Java 21. Android compilation uses Java 17.
Run emulator commands one at a time; they share ports and temporary local
secret fixtures. The integration runner replaces ambient ADC with an ephemeral
nonexistent demo identity and restores the prior `.secret.local` on exit.

```text
flutter analyze lib test tools integration_test test_driver
flutter test --concurrency=1 --exclude-tags=emulator
npm --prefix functions run lint
npm --prefix functions test
npm --prefix functions run test:rules
npm --prefix functions run test:messaging
npm --prefix functions run test:integration
npm --prefix functions run test:launch
npm --prefix functions run test:attendance
node functions/tools/run-integration-tests.js --project demo-attendus-admin --suite public-browser
node functions/tools/run-integration-tests.js --project demo-attendus-admin --suite flutter-browser
node functions/tools/run-integration-tests.js --project demo-attendus-admin --suite migration-recovery
python -m unittest discover -s tools -p "test_*release*.py"
```

Install browser dependencies from `tests/browser` with `npm ci` and
`npx playwright install chromium firefox webkit`. For Flutter browser tests,
set `ATTENDUS_WEBDRIVER` and `CHROME_EXECUTABLE` to matching ChromeDriver/Chrome
versions. The runner enforces demo/loopback services and owns only its test
server, driver and Flutter processes. Synthetic recovery exports remain local
under `build/migration-recovery-*`; they do not satisfy cloud recovery gates.


## Notification and recovery audit follow-up

The FCM account-binding repair spans the backend registry, every active sender,
client sign-out/account-switch lifecycle and notification routing. Unregistered
legacy tokens deliberately fail closed until the updated client registers them.
An accepted provider handoff can still arrive after account switching; the OS may
render a notification payload before Dart or a browser page can apply an identity
check. This remains an explicit physical-device/provider acceptance boundary.

| ID / severity | Reproduction; expected versus actual | Root cause / correction | Regression evidence |
| --- | --- | --- | --- |
| PUSH-01 / P1 | Switch accounts on one installation, then send to the previous user; old token must not remain deliverable. Previously independent user token fields could point at the same installation. | Server-owned token/install registry with monotonically fenced registration/revocation, deletion guards and send-time ownership verification. Client uses persistent intent generation and bounded revocation. | Registry unit tests and real-Firestore transfer regression; sender regression in messaging suite. |
| PUSH-02 / P1 | Delete a recipient or remove them from a conversation between enqueue and worker execution; no private inbox/push should be recreated. | Transactional conversation/message/deletion checks; all senders use current token owner; per-recipient push data includes recipientUid. | Messaging suppression regression; admin deletion/identity emulator regression. |
| PUSH-03 / P1 | Reuse an admin notification operation key with changed recipients or message; it must not return a success for an unrelated prior payload. | Canonical payload fingerprint bound to reservation. Deterministic per-operation inbox records and recipient-specific sendEach payloads. | Callable idempotency unit test and real-Firestore admin dispatch regression. |
| REM-01 / P2 | Lose a provider acknowledgement or crash after handoff; automatic lease recovery used to resend the same reminder. | Durable handoff marker, terminal unknown result, safe pre-handoff retry, bounded claims, no blind provider replay. | Reminder unknown-handoff and lost-ack emulator cases. |
| REM-02 / P2 | Reschedule while an old worker is awaiting provider response; old completion must not replace the newly pending schedule. | Unique claim identity fences completion; reconciliation is transactional and reads the current event rather than an old trigger snapshot. | Late-completion/reschedule emulator case. |
| REM-03 / P2 | Rerun reminder delivery after a user reads the inbox record, or during deletion; preserve read state and avoid recreating personal data. | Create-only inbox transaction checks current claim/event/settings/eligibility and deletion guard. | Real-Firestore read-state recovery regression. |

Fresh follow-up results: rules **40/40**, messaging/rules **45/45**, release/native
Python guards **14/14**, source/function/query contract tests **10/10**. Evidence:
`rules-notification-final.log`, `messaging-notification-rerun2.log`,
`release-guards-current.log`, `contracts-rerun.log` under the main evidence folder.
The earlier messaging failures were missing explicit demo Functions context in the
standalone test process; a first rerun loaded before the fixture correction and
also failed. Both failures remain retained. The query contract failure exposed an
undeclared Comments query; the contract registry now includes the new deletion
queries and checks array collection-group indexes using CONTAINS semantics.

These results precede remaining discovery/onboarding/service-worker repairs;
they are not the final frozen-candidate verdict.

## Integrated verification checkpoint and journey matrix

Fresh October 3 results supersede earlier checkpoints only for their tested
snapshot. Earlier failures remain in the evidence directory. No test run proves
every file or every UI branch was exercised.

| Subsystem / journey | Reviewed and locally exercised | Remaining acceptance |
| --- | --- | --- |
| Identity and authorization | Auth epochs, role checks, account switching, token ownership, Firestore/Storage rules, cross-account denial | Real Google/Apple cancellation/recovery, App Check provider enforcement and revoked sessions in staging |
| Discovery/public pages | Explicit public eligibility, bounded search/DTOs, pagination contracts, event/community links, SEO and failure pages | Final five-browser run, real Maps and all rendered Flutter branches |
| Events/communities | Secure draft/publish/update paths, cohost/membership/post/comment/poll/quiz permissions and concurrency | Full UI navigation, timezone/DST recurrence corpus and historical schedule ambiguity |
| Registration/admissions | Capacity transactions, idempotency, disabled checkout, guest proof and legacy compatibility emulator cases | Real Flutter journey result, large historical corpus, provider refund reconciliation |
| Attendance | Staff permissions, credentials, duplicate/replayed operations and pass behavior; 21 emulator cases | Physical cameras, two disconnected staff devices, Smart Arrival and issuer/provider acceptance |
| Communications/lifecycle | Messaging46, reminder claim fencing, lost acknowledgement, late reschedule, discovery delivery recovery and recipient binding | OS notification display around account switching, external calendars and provider out-of-order callbacks |
| Privacy/rosters/exports | Deletion guards/resume, shared-content boundaries, roster access, export identity fencing and CSV behavior | Full provider retention/revocation, historical orphan disposition, real signed download expiry/revocation and large-event bounds |
| Admin/operations | Admin19 tests, Windows integration1, idempotency/errors/deadlines and audit authorization | Installed distribution authentication, real operator roles and external analytics validation |
| Platforms/release | Native/release guard16, contracts/service worker19, source/deployed drift inventories | Native artifacts, Safari/physical devices, signed distribution, actual upgrade/cache and download behavior |
| Migration/recovery | Six-suite integration includes isolated source drift refusal, export/import and reapply | Authoritative ambiguous admission resolution and cloud backup/restore rehearsal |

Current combined logs: `backend-unit-frozen.log` (258 passed),
`rules-frozen.log` (41), `messaging-frozen.log` (46),
`integration-frozen.log` (all 6 suites), `launch-frozen.log` (42),
`attendance-frozen.log` (21), `flutter-test-client-candidate-final.log` (282),
`flutter-analyze-client-final.log` (clean), `contracts-workers-final.log` (19),
and `python-guards-final.log` (16). The subsequent funnel serializer correction
has focused regression evidence in the platform report and requires a refreshed
unit result. Staging-link work likewise requires its own final validation.

Read-only cloud inventories were refreshed after the final backend exports:
staging has 34 source-only Functions and production has 12; both have 10 missing
source indexes. Neither deployment is this candidate. The production inventory
still has 143 events without the stored confirmed counter, with 10 exact,
45 legacy and 88 incomplete schedules. Ten public events contain hidden-contact
`name` fields; no contact email field was found in this subset. No historical
record was modified. The staging event inventory is empty. Function name parity
does not qualify the `triggerAIInsights` event-type transition from update to
write; that transition needs an explicit future rollout procedure.

## Future promotion and rollback checklist (not executed)

1. Close applicable device/provider/data gates above; select and verify isolated
   staging identities and provider sandbox routing before deploying fixtures.
2. Freeze source/configuration and exact artifact hashes. Rerun affected gates
   after any correction; retain failed and superseded evidence with timestamps.
3. Reconcile effective Functions exports AND trigger types, rules, query indexes,
   TTLs, secrets metadata and disabled flags. Coordinate token registry/client
   rollout because legacy unregistered push tokens deliberately fail closed.
4. Validate that protected GitHub environments and required checks actually
   exist; workflow references alone are insufficient. Do not dispatch production
   workflows during this task.
5. For a separately authorized production release, record the expected prior
   Hosting version and rollback artifact, preserve rules/Functions configuration
   and compatible client contracts, and inventory migration rollback needs.
6. Promote the already-qualified artifact without rebuilding. Verify both
   production domains and authenticated journeys, then observe errors and job
   progress. Roll back code/artifacts with recorded versions if acceptance fails;
   never attempt data rollback by guessing counters, dates or admission links.

Completion remains open while any required journey is unverified or a confirmed
defect is unresolved. Source review, emulator evidence, compilation, staging
acceptance and physical-device acceptance are distinct statuses.

## Browser startup and final privacy follow-up

| ID / severity | Reproduction / root cause | Correction and verification |
| --- | --- | --- |
| WEB-06 / P1 | Run the real Flutter Chrome driver from raw web sources. The unquoted `__ATTENDUS_WORKER_BRIDGE_ENABLED__` identifier threw before loading Flutter, leaving the loading screen indefinitely. Release-only asset placeholders also reached local bootstrap configuration. | Quote and explicitly compare the bridge switch; use Flutter's default resolution for unpackaged development. Raw messaging workers do not import or initialize provider SDKs with placeholder identities. Browser bootstrap regressions and clean-start real Flutter rerun required. |
| ENV-01 / P2 | Share a staging event/community, or open its same-environment canonical URL. Client generated production links and its parser rejected staging links. | Derive canonical origin and accepted origins from the selected Firebase environment; reject cross-environment lookup and unsafe URLs. Production and staging focused suites each passed12/12. |
| PRIV-01 / P1 | Put at least200 claimed/already-anonymized contacts before an expired guest in retention ordering, or claim a selected guest concurrently. Old worker repeatedly skipped the first page or wrote from stale selection. | Paginate bounded pages, retire terminal scheduling fields and transactionally reread claim/expiry/deletion state. Unit regressions passed; new >200-row real-Firestore case requires refreshed launch run. |

Final backend unit refresh after funnel serialization and retention changes:
**261/261 passed**, lint clean (`backend-unit-candidate.log`,
`backend-lint-candidate.log`). Source secret scan:1,127 nonignored files,
10.46MB, zero findings (`secret-source-final.log`). Dependency audit still
reports two moderate transitive findings and zero high/critical production
findings; it is not a zero-vulnerability claim.

The first real Flutter driver failed before test startup because WebDriver does
not consume `CHROME_EXECUTABLE`; the runner now passes `--chrome-binary`.
The next attempt revealed WEB-06; after its correction the guest form,
retrieval, idempotent retry, cancellation and cross-guest denial passed.
The organizer fixture then failed rules because its Customers creation omitted
the required `uid`, which has been corrected. The harness also now prints
Unicode diagnostics safely on Windows. Those failed runs are preserved and do
not qualify a clean-start candidate; the subsequent rerun is authoritative.

The clean-start rerun passed both real Flutter browser journeys
(`flutter-browser-startup-rerun.log` and
`build/debugging-flutter-integration/flutter-drive.log`). These exercise the
actual guest form and Flutter services against demo Auth/Firestore/Storage/
Functions. Organizer service coverage includes publication/replay, attendee
registration, unauthorized roster denial, check-in/replay, generated export,
rescheduling and cancellation. It does not claim every organizer screen was
driven, or that signed export downloads were fetched.

The expanded public-page run passed **20/20** across Chromium, Firefox, WebKit,
mobile Chromium and installed Edge (`browser-five-projects-final.log`). Visual
inspection found a 200%-text skip-link positioning defect after the initial
Chromium capture: a fixed negative top offset did not hide taller wrapped text.
It now translates by its own full height, with keyboard-focus visibility checks
added. This presentation change needs a final targeted browser verification.

## Final authorization follow-up

- **AUTH-01 / P1:** client-created negative `Customers.eventsCreated` and direct
  resets bypassed the publication allowance. Protect counters and privileged
  fields in rules, validate stored values, and read the live counter inside the
  publication transaction. Missing historical usage is not evidence of zero
  usage and requires explicit reconciliation. New accounts initialize zero.
- **PRIV-02 / P1:** `Customers` allowed any full account to read/list complete
  other-user records, including undiscoverable users, email, phone, saved events
  and historical extra fields. Migrating active public-profile consumers to
  bounded server DTOs and restricting raw documents to self is required before
  candidate freeze. A role-safe staff email resolver must use Firebase Auth's
  identity, not a client-editable profile email.

The coordinated source corrections are complete. Fresh backend lint and 284 unit
tests passed, along with 45 rules, 50 messaging/rules, all six integration suites,
44 launch and 21 attendance cases (`privacy-final-*.log`). These counts overlap:
messaging intentionally includes the rules suite. The default integration run
includes all four real-Firestore staff identity/rate/role regressions. Main Flutter
analysis is clean, format checked 428 files with zero changes, and all 305 tests
passed (`flutter-analyze-privacy-rerun.log`, `flutter-test-privacy-final.log`).
The final real Flutter browser run also passed both journeys, including actual
public-card DTO assertions and denied cross-user raw document reads
(`flutter-browser-privacy-final.log`). Guest registration/retrieval/retry and
organizer publication/admission/export/reschedule/cancel use the actual Flutter
services against isolated emulators; screen-by-screen organizer navigation,
signed download retrieval and external providers remain separate gates.

Read-only usage inventory at 07:50 UTC found 41 of 47 production Customers
missing `eventsCreated` (four zero, two positive, none malformed), and one of four
subscriptions missing its monthly counter. Staging contains neither collection's
records. The inventory selected counter fields only and does not establish the
accuracy of valid stored values. Missing historical counters require authoritative
reconciliation before promotion; no production counter was changed or invented.
Evidence: `orgami-66nxok-quota-inventory.json`.

Final source/deployed inventories show 38 staging and 16 production source-only
Function names. Both deployed index inventories lack 13 candidate declarations,
including two Customers search composites and ProfileReadLimits expiry metadata;
staging additionally lacks the required AttendanceWalletDownloads expiry TTL.
These are deployment differences, not passing parity checks. Nothing was deployed.
Older clients relying on raw cross-account Customers reads must update in the
coordinated rollout; the candidate deliberately does not preserve that disclosure.

Final contract regressions passed 29/29, query checks verified 15 contracts across
12 collection-group call sites, category/public-web checks passed, and native/CI
guard tests passed 18/18. Evidence: `contracts-candidate-final.log` and
`native-workflow-final.log`. Native compilation and installed/device acceptance
remain independently recorded in the platform report.

## Final candidate artifacts and acceptance boundary

The staging-configured web build is retained at
`build/debugging-candidate-531f45f2043e414cab7243bba7a7f7f9/`.
Its `source-manifest.json`, `source-after-build.json` and `artifact-manifest.json`
record exact inputs and file hashes. The source fingerprint remained
`d356d12b3c26382eb60db6d0c18106b3d3c1e44781db56b410bb2c25b2e0cea4`
through compilation/packaging. All 16 current deferred chunks passed, 65 release
files were packaged, and the initial bundle measured 1.209 MB gzip against a
1.800 MB budget. This artifact was not deployed.

The subsequent browser test-harness focus correction is the only source delta
from the web build (`web-build-source-delta.json`); no application, dependency,
asset or packaging input changed. Exact-artifact Chromium startup reached the
Flutter view and removed the loader with zero missing local assets or uncaught
page errors while allowing only SDK/font resources and blocking cloud application
traffic. The screenshot captures session checking, not an authenticated journey.
Evidence: `candidate-web-offline-startup.json` and its PNG. An earlier completely
network-blocked probe produced expected Firebase SDK import failures; those
failed diagnostics remain in `candidate-web-offline-blocked-sdk.json`. Neither
probe qualifies a fresh offline installation or staging authentication.

Final source scanning covered 1,140 nonignored files / 10.79 MB with zero findings
under the reviewed gitleaks configuration (`secret-candidate.log`). This is
separate from the previously completed history scan. Function secret metadata
checks verified ten required staging secret names; names/existence do not prove
sandbox routing, issuer readiness or permission to send test delivery externally.

The public-browser keyboard follow-up retained two failed WebKit focus runs.
An isolated Windows WebKit reproduction showed that the page initially lacked
focus and Tab/Alt+Tab skipped ordinary links even after bringing it forward.
The harness now explicitly brings pages forward. Chromium/Firefox/mobile/Edge
exercise Tab traversal; WebKit exercises focused-link presentation with explicit
focus and an `acceptance-gap` annotation. It does not claim Safari keyboard
traversal, which remains in physical Safari acceptance. This honors the browser
preference boundary described in Apple's WebKit `tabFocusesLinks` documentation:
https://developer.apple.com/documentation/webkit/wkpreferences/tabfocuseslinks

Candidate test/configuration manifests live in `build/debugging-20261003/`.
The delivery source archive preserves this working checkout and prior user work;
its manifest distinguishes the unchanged Git HEAD from the actual uncommitted
candidate contents. No commit, push, PR, cloud deployment or migration was made.

Android compile-only APK and AAB both passed after removing the obsolete Stripe
Maven repository and correcting the local harness's stale --no-pub registry.
All five temporary native configuration paths were restored byte-for-byte, and
all 362 native/Dart/assets/lock inputs retained fingerprint
`4514774f92f2f82221cc299b9d023ee9176cbabf63a7101f7dbdaf4b45caae28`.
APK SHA256:`98bf344a24b764e4954a90aa339668789572ecb7d806020ad232f2695be6e4be`;
AAB SHA256:`6bbed42294692bee7fd0ad814a6fa44ae6ae1cb65b0a99095dec67e8b574a9db`.
Evidence: `build/debugging-platform-20261003/android-compile-only/verification.json`.
Both use fixture identity/certificate and were never installed or distributed.

Final isolated public-browser run: **20/20 passed in 2.6 minutes** across Chromium,
Firefox, WebKit, mobile Chromium and installed Edge (`browser-final-isolated.log`).
The WebKit keyboard limitation above remains explicit. The preceding combined
native/browser attempt failed Functions emulator metadata discovery and was
stopped by terminating only its owned Playwright child tree; emulator shutdown
and fixture restoration completed. Its failed evidence remains in
`browser-candidate-qualified.log` and is not counted as a pass.

Final local status: repaired source, clean main analysis/format, 305 Flutter tests,
284 backend unit tests, required serialized emulator suites, 29 contract tests,
19 native/workflow guards, 19 Admin tests, 1 Windows Admin integration, 2 real Flutter
browser journeys, 20 public-browser cases, web artifact checks and Android
compile-only APK/AAB checks passed. Counts overlap; these are not unique-case
coverage totals. Inventory enumerates 759 surfaces, 152 exports and 130 literal
collections; report linkage is not individual-line or exhaustive branch coverage.

**The complete-project acceptance goal remains open.** Exact remaining actions:

- Supply verified isolated staging identities/provider routing and run this
  candidate there after coordinated Functions/rules/index/TTL configuration.
- Perform physical iPhone/iPad/Android and real Safari/Windows installation
  acceptance, including keyboard/screen-reader use, cameras, push, Maps, calendar
  imports, signed downloads, cache upgrades and two disconnected staff devices.
  iOS compilation/signing requires a macOS/Xcode environment; compile-only Android
  fixtures and Windows debug integration do not qualify distribution.
- Resolve historical missing usage/admission counters, incomplete schedules,
  ambiguous admission linkage and legacy hidden contact fields from authoritative
  records; refresh migration dry run and prove isolated backup/restore recovery.
- Verify GitHub environment protections and plan the explicit trigger-type,
  public-profile and push-token-registry older-client rollout before any future
  promotion. Keep disabled paid/featuring/biometric/scheduled-plan features off.

No production deployment, migration, data correction, public release or real-user
communication occurred. See the future promotion/rollback checklist above.
