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


## Web qualification follow-up: profile and consent integrity (October 4)

Candidate 9 source `489f4c4` deployed successfully to isolated staging but is held
from acceptance and promotion. The following newly confirmed defects require a
new source candidate. Reproduction evidence is retained under
`build/web-qualification-20261004/`; the scope is the web application and its
shared services. Native execution is not implied.

| ID / severity | Reproduction; expected / actual | Root cause; correction in progress | Verification and current disposition |
| --- | --- | --- | --- |
| PROFILE-01 / P1 | Load profile, change its saved events/discoverability/bio elsewhere, then save only the name. Untouched current fields and exact creation time should survive; stale fields and a rounded timestamp replace them. | Editors serialize the cached whole Customer model. Capture immutable normalized control values and submit only explicitly changed editable fields, then refresh from the server after acknowledgment. | Actual model and installed codec: four failing preservation cases and two passing controls in `profile-save-regression-before.log`. Add focused and rendered editor regressions; not closed until they pass. |
| PROFILE-02 / P2 | Save a custom profile name that differs from Firebase Auth, then reopen the current editor. Stored name should remain; provider enrichment restores the provider name. | Load-time enrichment updates differing nonempty fields. Enrich only missing fields from a fresh transaction and preserve current user input. | Source-confirmed; actual rendered reopening regression added. Verification pending. |
| CONSENT-01 / P1 | Store canonical message opt-out and older enabled settings, then deliver a message. Current opt-out should suppress delivery; legacy settings create an inbox entry and invoke the provider stub. | Messaging reads the two preference document paths in reversed precedence. Canonical document now wins, legacy is used only when canonical is absent. | Actual delivery-handler regression: five failing cases before correction; seven passing cases after. Stub delivery only, no provider contact. Full integrated verification pending. |
| CONSENT-02 / P1 | Load settings, update another channel elsewhere, then change one visible control. The unrelated update should survive; a full cached document save replaces it. With no canonical document, legacy opt-outs are also lost. | Whole-map writes and canonical-only loading. Submit dirty controls and read effective current preferences transactionally; preserve legacy opt-outs when first creating canonical settings. Ordinary profile save must write no preferences. | Focused service/store regressions and concurrent rendered profile test being validated. No live acceptance yet. |
| CONSENT-03 / P1 | Load legacy `messageNotifications: false`. The all-messages control should show off; it shows on. | Client model ignores the backend-supported opt-out alias. Normalize the effective flag and synchronize the alias only for an explicit all-messages choice. | Actual Dart before proof fails in `notification-alias-before.log`. Corrected tests pending integrated validation. |

Unknown historical counters and ambiguous admissions remain separate unresolved
data questions. These application repairs do not infer or migrate those records.
The detailed candidate, artifact, rollback and acceptance history continues in
`web-release-qualification-20261004.md`.


| Follow-up ID / severity | Reproduction; expected / actual | Correction and evidence |
| --- | --- | --- |
| CONSENT-04 / P1 | Deny this browser push permission, then try to turn off account notification preferences. Global account preferences should remain editable; every toggle and selector is disabled. | Device permission remains a separate banner/action; loaded account controls now persist normally without permission requests or FCM initialization. Actual before widget case failed; five corrected widget cases pass, including reopen, master/selector, load failure and account change. A browser scenario is included in the next integrated run. |
| PROFILE-03 / P2 | Edit one social control after another session updates an untouched social link. Existing and unknown JSON keys should survive; replacing the whole social JSON loses them. | Merge only changed controls into the fresh profile inside the same transaction. Malformed social storage blocks only social edits; unrelated name edits preserve it. Actual editor regressions pass; browser acceptance remains separate. |
| PROFILE-04 / P2 | Save mixed-case username `Alice_Example` with an unrelated display name, then search that handle. The account should be found; the lowercase backend query returns no match. | V2 normalizes and validates only edited usernames against the existing 3–50 letter/number/underscore contract. Unchanged historical values and explicit optional blank remain compatible. Actual backend before proof is retained, and the 30-case editor widget suite passes. Duplicate handles remain an explicitly advisory limitation; no unique identity routing or atomic reservation is claimed. |

Final integrated validation is still in progress. The full 425-test Flutter run
and earlier focused results precede the final permission and username additions;
they do not qualify those additions by themselves.

The later complete client validation passes 443 tests with clean analysis and
formatting. Actual rendered run `browser-b1e4edf00d9d282e` then passes all five
journeys with no driver failures. Both profile editors and denied-permission
settings persist the expected fresh server state; exact timestamp precision and
unrelated concurrent changes survive. All seven fixture-owned user settings
subtrees were removed and cleanup reports complete. The backend repair passes
355 unit and 51 real messaging/rules emulator cases. These close local regression
verification for PROFILE-01 through PROFILE-04 and CONSENT-01 through CONSENT-04;
packaged staging acceptance and full release qualification remain open.

Final review also identified CONSENT-05: the All Notifications control derives its
displayed state from four fields but its action changes eleven. Reproduction and
the focused display correction are in progress; the preceding successful browser
run must not be described as validation of that final correction.

CONSENT-05 / P2 is now reproduced and locally repaired: messages enabled with
the original four channels disabled previously displayed the master as off.
Aggregate all eleven controlled types, label partial selections explicitly, and
keep the master on whenever any type remains enabled so one tap can opt out.
The actual before case failed; seven focused widget cases and analysis pass
afterward. The next immutable candidate must pass fresh complete CI and staged
acceptance; those gates remain unverified at this source freeze.

## Candidate 10 failure and subsequent web repairs (October 4)

Candidate `37210826673` is held after browser collector `37213445908` failed
all five gates. The original artifacts and failed diagnostics remain preserved.
The following rows distinguish confirmed defects from later blocked journeys.

| ID / severity / surface | Reproduction and expected versus actual behavior | Root cause and correction | Verification and remaining acceptance |
| --- | --- | --- | --- |
| WEBQA-01 / P1 / browser tooling | Required staging App Check, Maps telemetry and legacy Auth configuration requests should reach their exact endpoints; the policy denied 92 requests. | The App Check app-ID matcher stopped at a colon and two exact SDK paths were missing. Bind the allowed method, endpoint, app, project, key and query shape. | Actual failed request evidence and focused fail-before/pass-after cases retained. Included in 290 passing combined Node assertions. Fresh staged journeys required. |
| WEBQA-02 / P2 / evidence privacy | A scheme-less URL in a browser error should lose its query; seven actual errors retained query strings. | Redactor covered only scheme-prefixed URLs. Scrub both forms and retain structured coordinates only for sealed candidate assets. | Actual seven examples and regressions pass. Original private failed evidence retained. |
| WEBQA-03 / P2 / Discover | Open the actual shared Discover shell and navigate to Maps. The only entry was hidden with the child header. | Add a reachable, keyboard-accessible Maps action to the shared shell for default and marketplace branches. | Nine new cases cover route entry, narrow 200% text and shared header behavior. Actual provider markers remain unverified. |
| WEBQA-04 / P2 / public event and community pages | At 320px and 200% text, long headings should fit the viewport; the actual event title overflowed. | Allow heading wrapping and publish new immutable CSS while preserving prior assets. | Twelve rendered cases across four browser projects pass with visual review. |
| WEBQA-05 / P1 / backend roster integrity | Replay an invalidator after event deletion. No derived record should reappear; the old handler recreated the roster marker. | Read current event state and write invalidation in one transaction across all eight handlers. | Actual-handler before failure, focused cases and 48-case real Firestore launch suite pass. Current/cancelled/recreated events still invalidate correctly. |
| WEBQA-06 / P1 / backend roster integrity | Delete or replace an event during roster construction. The obsolete generation should not publish; the old finalization could publish it. | Compare exact current event updateTime at publication, use the committed transaction result and remove abandoned generations. | Focused concurrency and real Firestore regressions pass; backend total362 unit tests plus lint pass. |
| WEBQA-07 / P2 / web login and reset | Press Enter once. Exactly one password/reset request is expected; both actual widgets sent two. | Manual controller start plus automatic animation callback duplicated submission. Disable automatic callback animation and fence in-flight/successful submissions, retaining explicit failure retry. | Both before reproductions fail, then11 new and4 related focused tests pass. Complete main Flutter suite465 passes with clean analysis. No real reset email sent; staged acceptance remains open. |
| WEBQA-08 / P1 / browser acceptance identity | Sign in under packaged LOCAL persistence. The observer should identify the exact actor; old readers missed LOCAL or selected a foreign IndexedDB actor. | Read the exact packaged LOCAL record and validate app/project/actor claims. Safari keeps the public HTML namespace separate. Cache predecessor observes its already-initialized exact SDK actor and candidate additionally checks LOCAL. | Shared14-case and Safari/cache55-case focused selections pass, included in290 combined Node assertions. Unknown predecessor SDK shape fails closed. Live Safari/cache remains unverified. |
| WEBQA-09 / P2 / failure attribution | A failed App Check exchange should preserve safe provider error classification; only403 was retained. | Add bounded status/code/allowlisted-reason projection for exact staging exchanges; omit raw body, token, message and metadata. | Three cases fail before implementation;27 producer tests pass afterward. Missing/oversize/timed-out bodies remain unavailable. The original403 cause is still unknown. |

The null-check exception recorded by the failed browser run remains an
unclassified hypothesis. Downstream export/privacy/cache timeouts from that run
are blocked checks, not independent confirmed product defects. The narrow
packaged screenshot shows a session spinner and cannot close layout acceptance.

| ID / severity / surface | Reproduction and expected versus actual behavior | Root cause and correction | Verification and remaining acceptance |
| --- | --- | --- | --- |
| WEBQA-10 / P1 / public event and community privacy | Deliver an old public update after the current source becomes private or is deleted; then deliver an old deletion after a public source is recreated. The mirror must follow the current source, but both old handlers could republish private/deleted labels or delete the replacement projection. | Both handlers trusted the delivered snapshot and wrote unconditionally. Read the current source and set/delete its allowlisted projection in one Firestore transaction, so concurrent source changes cause a retry. | Eight new actual-handler unit cases fail before and pass after. All370 Functions tests and lint pass; all52 Firestore launch cases pass, including four real-SDK lifecycle/retry cases. Independent review clear. New cases are registered in the recurring launch suite. The correction has not yet been deployed. |

Maps qualification now seeds two existing owned events with distinct synthetic
locations and requires actual named marker controls, marker selection, the exact
venue sheet and navigation to the matching event details. Thirteen producer
regressions and three fixture tests pass. This adds a positive acceptance check;
actual provider marker accessibility remains unverified and must fail the run if
the Maps SDK does not expose usable controls.

Local repairs are preserved through source checkpoint
`805c161eaac1459b23ec2b28e26d8505d3ae82f5`; the isolated branch incorporates the
protected main history afterward. The combined Node suite passes290 assertions
without skips. Local counts overlap and are not an exhaustive coverage percentage.

Staging retirement of the failed fixture's32 isolation records was acknowledged
at `2026-10-04T17:23:14.601013Z` and all effects verified. The fresh inventory at
17:29:05Z contains1,458 documents,22 Auth identities and zero Storage objects.
Fixture data/Auth cleanup and configuration restoration are still open at this
checkpoint. All production data is unchanged. See the release qualification
record for immutable evidence hashes and the remaining provider, data and timed
acceptance gates.

### October 4 inventory correction

The refreshed inventory omitted the Flutter `images/` directory and three root
logos declared in `pubspec.yaml`. The scanner now recognizes image and font
assets outside `web/` and hashes their bytes without parsing them as source.
An actual declaration-to-file comparison verifies all 26 declared image files;
the total inventory increases from 862 to 927 surfaces, including 65 previously
omitted image/font files. Independent review confirms that no previous surface
was removed. Corrected inventory SHA256:
`f604825be41d4b5b45b43a45b902d4b22b9c9cfff45693d75ed6ad665dd821e4`.
This local inventory includes the pending scanner correction on source
`7b92211dd04b596c569f675bb938f577306342cf`; it is not runtime acceptance.
Its 153 lexical export matches include the commented `helloWorld` example;
effective runtime exports remain subject to the separate deployment inventory.

### October 4 deployment-entrypoint correction

| ID / severity / surface | Reproduction and expected versus actual behavior | Root cause and correction | Verification and remaining acceptance |
| --- | --- | --- | --- |
| WEBQA-11 / P1 / release controls | Run any of the five historical deployment/provider shell scripts. They could invoke Firebase without the qualified release workflow or an explicit project; the default project is production. | Old standalone scripts bypassed source, artifact and acceptance gates. All five now print the supported workflow paths and exit with failure before invoking any command. Historical implementations remain in Git. | The isolated copied-script regression failed ten behavioral cases before correction and passes all eleven cases afterward, including force-argument/environment attempts and recurring CI registration. Independent review clear. No cloud or provider operation was executed. Fresh CI is required for this source delta. |

The affected entrypoints are `deploy_web.sh`, `deploy_firestore_rules.sh`,
`deploy_guest_mode_fix.sh`, `DEPLOY_JOIN_APPROVAL_NOTIFICATIONS.sh` and
`setup_google_wallet.sh`. Their shared corrected SHA256 is
`ef7bf72e9be959278814860c01fe4f6de7efaa9a6eda750313ad55f9e83c7426`.
The new regression file is `tests/browser/legacy-deploy-entrypoints.test.cjs`;
its SHA256 is `bd696966760849a0101f3121a6c861cfb4235f6dfd5328407855d2adbec06b63`.

The inventory also now includes the three `config/` manifests, root Firebase,
Git, Flutter and analyzer configuration, root tooling and `router_fixed.dart`.
Independent reconciliation also restored localization inputs, the Admin
integration test, Firebase Storage CORS, legacy public HTML and native/installer
source formats. The working inventory contains 992 file surfaces, with all 992
file hashes verified. Inventory SHA256:
`de71a94c9bc01c81fb72044a3c0513f8f1bc9b29f26ea241096ab2969f5b7099`.
The 259 excluded tracked/nonignored paths are 243 Markdown documents, ten retained
JSON evidence files, four backups, one generated Firebase cache and one unapplied
patch. Linked subsystem reports do not assert individual-file review or execution.
The current 18-family web coverage matrix separately records hosted tests,
unexecuted preparation and remaining staging/provider journeys. Native source
inventory does not extend the current web-only acceptance scope.

### October 4 waitlist and community follow-up

These confirmed defects were corrected in candidate source; matching hosted
CI and live acceptance remain open. They were found during the active-web review;
they are not failed production mutations.

| ID / severity / surface | Reproduction and expected versus actual behavior | Root cause | Status |
| --- | --- | --- | --- |
| WEBQA-12 / P2 / waitlist decisions | The roster offers Decline for a waitlisted attendee. The actual callable declines a pending row but rejects the waitlisted row with failed-precondition; the row remains waitlisted. | Every non-promote decision requires pending, despite the supported UI decline action for both states. | Fixed in candidate: decline accepts pending or waitlisted; approve/promote keep their prior restrictions. All 17 focused handler cases and 55 Firestore launch cases pass, including authorization, replay and one-winner transitions. Live staging remains open. |
| WEBQA-13 / P2 / organizer feedback | Approve a pending registration at full capacity with waitlisting enabled. The server correctly returns and stores waitlisted, but the console says Registration approved. | The UI ignores the callable result and derives success text only from the requested action. | Fixed in candidate: feedback uses a supported acknowledged action/status pair. Full-capacity approval says waitlisted; inconsistent/malformed replies cannot show success. Included in 50 focused client cases and 515 full Flutter passes with clean analysis. The directly-used response helper is tested; packaged console acceptance remains open. |
| WEBQA-14 / P2 / community member filter | Approve a community join request, then select the Members filter. The approved row uses role Member and disappears from the filtered list. | Display filtering compares only the lowercase member value, while the established approval path writes Member. | Fixed in candidate: role casing is normalized for filters, cards and menu presentation, retaining actor authorization and write payloads. Seven actual ManageMembers widget cases pass, included in the 515-test suite. Packaged community acceptance remains open. |
| WEBQA-15 / P1 / admission integrity under contention | A tentative free-ticket approval is discarded when capacity changes; the retry correctly waitlists the registration but returns and stores the first attempt's ticket ID while no ticket exists. | Mutable ticket/result state survives outside the Firestore transaction callback across retries. | Fixed in candidate: return only the committed callback result with attempt-local state. Actual SDK retry verifies waitlisted with null ticket ID and zero committed tickets; replay and concurrent decisions preserve counts. All 17 focused and 55 launch cases pass. Production records are unchanged. |
| WEBQA-16 / P2 / community join acknowledgement | Deny the JoinRequests write. The helper logs the failure and returns normally, so the screen reports Join request sent and switches to Requested. | The asynchronous helper swallows the write failure; the caller treats completion as acknowledgement. | Fixed in candidate: unauthenticated/failed writes propagate; success waits for acknowledgement, duplicate submissions are fenced and read failures disable joining. Actual SDK-double/widget regressions cover failure, delayed acknowledgement and disposal. Included in 50 focused and 515 full client passes. |
| WEBQA-17 / P2 / community request status | Decline a join request and reopen the community. The retained declined document is displayed as Requested and Request pending. | The screen tests document existence instead of its status. | Fixed in candidate: pending, declined and unavailable requests have distinct truthful states. Declined or unknown requests remain disabled, preserving rules without an unsupported overwrite/reapply flow. Actual screen regressions pass in the full client suite. |
| WEBQA-18 / P2 / community access display | Open a community with a pending member document or an approved legacy Admin role. The former is labelled Member; the latter loses the administrative presentation. | The profile and its administrative button infer approved membership from document existence and interpret only one role casing. | Fixed in candidate: non-creator membership must be approved; administrative controls accept only the four role spellings supported by rules. Profile, administrative button and active feed have malformed-role controls. The existing creator presentation shortcut is unchanged and does not establish server authorization without the required membership record. Independent review and 515 client tests pass. |
| WEBQA-19 / P2 / public guest management | Open a valid management session for a pending, waitlisted or declined registration. Each page says Confirmed and each calendar endpoint returns a publishing invite. | Management rendering treats every non-cancelled record as confirmed and offers admission/calendar actions without checking registration eligibility. | Fixed in candidate: rendering and direct calendar/QR routes share current admission eligibility. Pending, waitlisted and declined states have no admission invite; unsupported calendar/QR requests return 409/404. Confirmed, supported legacy and cancellation controls are covered. All 31 public-web handler and 392 Functions cases pass. All 24 new rendered status cases pass across four browser projects, using a synthetic server session; browser cookie transport/token exchange remains a separate acceptance check. |
| WEBQA-20 / P2 / public event capacity display | With capacity one, a ticketed event with confirmed count one and issued count zero, or an RSVP event with one reserved seat, still advertises acquisition while the authoritative capacity helper reports full. | Public rendering uses a different subset of counters from the registration handler. | Fixed in candidate: free-ticket/RSVP display uses V3 capacity and paid legacy display uses its V2 projection. Full states respect waitlisting; unresolved counters display Availability unavailable without an acquisition action or invented zero. Actual HTTP regressions and 392 Functions cases pass; production counter reconciliation remains a separate gate. |

The registration transaction repairs pass all 17 focused unit cases and the
complete 55-case Firestore launch suite under Node 22.23.2 and Java 21 against
`demo-attendus-admin`. The successful launch log SHA256 is
`b9a2c5d51b8d81626b72cc59bbd3d0027eda26f6e12f8ced02bed2ee5b062c9b`.
Its new cases cover concurrent decline replay, the actual SDK discarding a
tentative confirmed ticket before retrying into the waitlist, and a concurrent
decline/promotion with exactly one valid winner.

The first launch run is retained as 52 passes and three failures (SHA256
`16a8701af30250d6775a8f6eedabc9fe09773b0f7a997a1504936b35bb6af714`).
All three new cases reused a guest whose deletion tombstone had been created
earlier in the suite. Only their fixture identities were isolated; the product
deletion guard was not relaxed. The unchanged registration implementation then
passed the complete rerun. Later capacity-display changes require matching
final source CI; this emulator receipt does not claim staging acceptance.

| ID / severity / surface | Reproduction and expected versus actual behavior | Root cause and correction | Verification and remaining acceptance |
| --- | --- | --- | --- |
| WEBQA-21 / P2 / enlarged guest ticket layout | At 320px and 200% text, a valid eight-character ticket code and its QR image extend past their inner panel even though the page stays within the viewport. | The grid's intrinsic minimum width and fixed QR dimensions exceed the panel's available width. Use a shrinkable grid column, wrapping code text and an aspect-preserving responsive QR image. | The pinned old stylesheet fails all four ticket-panel bound checks with a valid eight-character code. All four pass after correction; the full local rendered selection passes 36/36 across four projects, with visual review. All 23 asset/versioning contract cases pass. A new immutable stylesheet is published in the candidate source; prior assets remain intact. |

The new `registration-email-v2.css` immutable asset SHA256 is
`5b3c898270ee766874a8e7d4db561b791cccb5b0f26fbb4fd6e0bb3e6ed1f311`.
The source manifest references this new path and retains the previous
`49fc8739d038b38eb58ecd506d04369b32c872cef4cc66fbda6308f9fa569dee`
file for existing cached pages. This stylesheet change does not alter the
reviewed registration or roster transaction logic.
