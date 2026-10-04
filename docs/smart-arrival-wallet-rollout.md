# Smart Arrival and personal passes rollout

## Current scope and authorization

The owner authorizes local validation followed by controlled production testing in Firebase project `orgami-66nxok`; a separate staging deployment is not required. Preserve existing records and paid-checkout feature gates. Initial enablement requires a dedicated test event and designated test accounts. Apple/Google issuer verification, credential provisioning, publishing approval, and actual Wallet installation/update acceptance are explicitly deferred until the owner resumes that final phase.

The repository contains existing uncommitted implementation. Historical test counts and artifact hashes are not evidence for this checkout. Current validation and deployment evidence is recorded below as it becomes available; implementation is not equivalent to live or real-device acceptance.

## Core attendance and passes

Home/Discover, event details and general check-in offer Smart Arrival without opening the camera automatically. Permission follows explanatory consent. Location is acquired only in the foreground and invalidated on route changes or backgrounding. HTTPS browsers use foreground geolocation. Acquisition is bounded to 10 seconds, then offers retry, venue QR/code or staff assistance.

Policy version 3 requires explicit Smart Arrival enablement, a confirmed physical boundary and a profile allowing self check-in. Legacy proximity settings or an address do not activate it. The default radius is 150 m, adjustable 50–500 m. Server validation requires a reading at most 30 seconds old, reported accuracy at most 50 m, and the entire accuracy circle inside the boundary. Location is a convenience signal, not protection against fabricated device location. Raw attendee coordinates must never be persisted or logged.

Registered events precede eligible public walk-ins. Private access, overlapping-event choice, individual ticket selection, guest names and required answers remain server-authoritative. Reuse registration answers and show a confirmed receipt only after server acceptance.

Event passes are available from registration confirmation, event details, My Tickets and secure `/manage/attendance`; reusable My Attendus pass is in Profile. Guest issuance requires authenticated ownership or the existing secure management session. An email or record ID alone is insufficient. Pending, waitlisted, cancelled, revoked or unpaid admissions cannot receive usable passes.

Ed25519 credentials contain opaque stable pass IDs, credential version, signing-key ID, kind and expiry. Event expiry is check-in closing plus 24 hours; admission itself remains restricted to the check-in window. Reusable expiry is 365 days with renewal inside 30 days. Stable registration/ticket and provider identifiers survive claims, session restarts, renewal and replacement. The legacy v1 verifier remains available.

Pass Lock protects in-app display and relocks on background. When device authentication is unavailable, offer venue/staff alternatives. Unavailable Add to Wallet buttons are hidden. Wallet admission remains supported when providers are activated later.

## Independent core and provider controls

`AppConfig/attendance` is server-owned. Missing configuration disables new features. Each pilot feature is scoped by event IDs and designated account UIDs:

```json
{
  "smartArrival": {"enabled": false, "allEvents": false, "eventIds": [], "userIds": []},
  "corePasses": {"enabled": false, "allEvents": false, "eventIds": [], "userIds": [], "identityEnabled": false},
  "appleDelivery": {"enabled": false, "allEvents": false, "eventIds": [], "userIds": [], "identityEnabled": false},
  "googleDelivery": {"enabled": false, "allEvents": false, "eventIds": [], "userIds": [], "identityEnabled": false}
}
```

The legacy `wallet` configuration is a compatibility fallback only when `corePasses` is absent. Explicit `corePasses.enabled=false` overrides it. Issuance and core refresh bind only `ATTENDANCE_PASS_SIGNING_KEY`. Guest management and legacy interfaces have no Apple/Google secret dependency. Core lifecycle jobs (`AttendanceWalletJobs`, retained name for compatibility) maintain eligibility, revocation, renewal and current pass state independently of delivery.

Provider deployment switches `ATTENDANCE_APPLE_DELIVERY_ENABLED` and `ATTENDANCE_GOOGLE_DELIVERY_ENABLED` default false. Leave both false/absent for this phase. Provider secrets are bound only for an explicitly deployed provider. The runtime provider flags must also permit the account/event. Separate `AttendanceWalletDeliveryJobs` and delivery workers handle external transports; disabled providers neither issue external requests nor add retry work. Core pass responses use cached delivery state. Later activation queues current records without replacing stable identities.

Preview scoped configuration with the read-only default:

```powershell
node functions/tools/set-attendance-rollout.js --project orgami-66nxok --feature smartArrival --enabled true --events TEST_EVENT_ID --accounts TEST_UID
node functions/tools/set-attendance-rollout.js --project orgami-66nxok --feature corePasses --enabled true --events TEST_EVENT_ID --accounts TEST_UID --identity
```

Use `--apply` after checking the exact event/accounts. Do not enable providers in this phase. Missing test identities or physical venue/time must be supplied by the owner, not inferred from unrelated production records.

## Attendance and native offline correctness

Scheduled opening uses server time with atomic session creation. Persistent manual pause/close overrides automatic opening. Admission transactions recheck current access, registration/ticket/payment eligibility, revocation, answers and duplicates. Stable admission identities connect location, event/reusable passes, staff entry and legacy records. Already-checked-in submissions return existing attendance; reentry requires prior checkout and policy permission. Receipt replay must not become another reentry after a later checkout. Preserve history across session restarts and reject ambiguous tickets for explicit resolution.

Native kits are encrypted, staff-authorized and event-scoped. They include eligible admissions, stable pass/ticket/roster mappings, public keys, credential versions, questions, check-in windows and schedule revision. Offline acceptance requires a kit downloaded within 24 hours, valid signatures and cached eligibility, and observation inside the allowed window. Browser staff scanning stays online. Same-device duplicates are rejected across scan methods.

Offline receipts are visibly pending until server reconciliation. Serialize the 500-entry queue, allow replay for at most 24 hours, reconcile idempotently and retain conflicts/rejections for review. Validate current revocation and schedule changes, evaluate pause/close history against observation time, and report conflicting scans from separate disconnected devices. Automated fixtures cannot establish disconnected-device acceptance.

## Validation and deployment sequence

1. Run current backend/provider-disabled unit tests, Firestore attendance integration and rules tests, Flutter tests, analysis, function-manifest and release checks. Mock provider transport and use fixture certificates only. Validate paid entitlement with local fixtures; preserve paid feature gates.
2. Verify production target and the existing attendance key metadata without printing secret values. Deploy compatible rules/indexes and backend first; avoid deleting live-only resources or resetting data. Verify function revisions and index readiness.
3. Build and publish clients with the normal environment-specific release builder (`scripts/build_web_release.ps1`), retaining immutable releases and recording source/artifact identity. Verify hosted routes and release assets after backend compatibility checks. Native iOS compilation/signing requires macOS/Xcode and native distribution credentials.
4. Apply only the designated event/account pilot controls once supplied. Exercise authenticated live core flows with both providers disabled. Preserve records and label test evidence explicitly.
5. Conduct real-device acceptance below, observe reconciliation through closing plus the replay allowance, then decide whether to expand. Issuer work remains last.

Rollback disables `smartArrival` and/or `corePasses` issuance flags without deleting signing public keys, issued credentials, sessions, receipts or attendance history. Keep verification deployed for issued credentials. Provider flags can be disabled independently.

## Current-run evidence (2026-09-12)

- Repository `.firebaserc`, Firebase client configuration and live function inventory target `orgami-66nxok`.
- Metadata-only production check: `ATTENDANCE_PASS_SIGNING_KEY` version 1 is `ENABLED`, created `2026-09-06T00:24:13.319080Z`. No payload was accessed or printed; no rotation was performed. Reproduce with `tools/attendance-production-status.cjs` using authorized Firebase CLI authentication.
- Initial live inventory reports the new Smart Arrival/pass/control endpoints absent. This is pre-deployment evidence, not a failure of a completed deployment.
- Backend unit tests: 105/105 passed after the deployment-specification regression fix. Attendance Firestore integration: 20/20 passed with both provider credentials absent. General Functions integration: 8/8 passed across admin/account/ticket, analytics and scheduled reminders. Firestore/Storage rules: 24/24 passed; the final explicit delivery-collection denial rerun passed all 20 Firestore tests.
- Targeted Flutter Smart Arrival/offline tests: 16/16 passed. The final full Flutter suite passed 145/145 tests (excluding emulator-tagged tests), and full analysis of `lib`, `test`, and `tools` reported no issues. Logs: `build/smart-arrival-full-flutter-tests.log` and `build/smart-arrival-full-dart-analysis.log`. Android release compilation passed with an isolated Attendus CI fixture certificate; signature verification and strict APK inspection confirmed exactly `arm64-v8a` and `armeabi-v7a`. The successful command uses `--target-platform android-arm,android-arm64 --android-project-arg=disable-abi-filtering=true`; CI now checks the packaged ABIs. APK SHA-256: `8f2af15dec37c80a0a9650086fabb01f270a4efd7f8fce7d08306419e0051631`. Evidence: `build/native-compile-validation-20260912/verification.json`. This compile-only APK uses a placeholder Maps key and was not installed or published; production Android signing and device acceptance remain pending. iOS compilation requires macOS/Xcode.
- Backend ESLint, source syntax, function-manifest regression tests, provider-disabled bound-secret checker tests and Firestore query contracts passed. Metadata preflight verified 10 actually bound production secrets. The secret checker now examines endpoint bindings and declared SecretParam specifications. Provider SecretParams are registered only when the corresponding deployment switch is enabled; unused declarations otherwise still require Firebase CLI secret resolution. All four provider-switch combinations and three secret-checker tests pass.
- Production web release builder passed using the existing dedicated Maps and App Check configuration. Release ID: `a3b8bb005f2a3ffd8901df669f69ca2f1cbc267e74bc146087bea8c66c64a4a8`. Current `main.dart.js` SHA-256: `5b583af48d2059fea48315bf283b1f6299479e8573e688e14d97fe42a6c759b0`. No placeholder key remains. Eight releases/525 local files and 17 current deferred chunks validated; initial bundle 1.097 MB gzip against 1.800 MB budget. Build log: `build/attendance-production-web-build.log`.
- Backend source fingerprint: `9fb10d04499e35f4f847b7d82a4d904e51131deaf579904937d2c118da090d30` across 94 source/config files, captured in `build/attendance-source-manifest.json`. Checkout HEAD is `8c40edcf77d7ae269c38294e5bbd8931da1fb3bb` plus preserved uncommitted work. The fingerprint includes failure telemetry and the conditional provider SecretParam fix. The originally approved manifest is retained as `build/attendance-source-manifest-approved.json`; only `functions/attendance/wallet.js` and its existing unit test changed within the 94-file backend snapshot. The compiled client source was not changed.
- Full hosted artifact fingerprint: `b94252d16a06ec30a30395f249c3b3e78d3ccc5b3fbb4afde5307e7f672231e5` across 545 hosted files, captured in `build/attendance-web-artifact.json`. Verify these files are unchanged before publishing the prepared artifact.
- Pre-deployment inventory: 92 active production functions, no live-only exports; 16 new exports absent. Attendance rollout configuration is absent, so new issuance/Smart Arrival are disabled. Both provider deployment switches are disabled. Metadata snapshot: `build/attendance-functions-before.json`.
- **Production deployment completed after explicit owner confirmation.** Firestore rules/indexes and all 108 backend exports deployed before Hosting. Firebase discovery required `FUNCTIONS_DISCOVERY_TIMEOUT=120`; conditional provider SecretParams fixed the unused-secret dependency. A transient function-list request recovered, and `--force` accepted the implemented retry policies after a fresh inventory proved zero live-only functions. No functions were deleted and no attendance data was reset. Final deployment log: `build/attendance-production-backend-deploy-approved.log`.
- Live backend revision verification at `2026-09-12T07:25:26Z`: 108/108 `ACTIVE`, 92 changed existing revisions, 16 new functions, no stale/missing/live-only exports. No function binds Apple/Google Wallet secrets and both provider deployment switches remain false. `AppConfig/attendance` remains absent (disabled defaults). Evidence: `build/attendance-functions-after.json` and `build/attendance-revision-verification.json`.
- Signing key version 1 remains enabled and unchanged. Deployment granted its runtime service account secret-access permission without rotating or replacing the key. Verification tools accessed metadata only and did not read or print the payload.
- Live Firestore verification at `2026-09-12T07:26:16Z`: all 33 composites and 10 field/TTL configurations ready, no missing/extra/pending/failed entries; all 10 bounded read-only query checks passed. Deployed ruleset `d0a09d46-8162-474e-a35a-1ec83c3d06bf` matches local normalized SHA-256 `f41868de9faf846c12129bd4a6ff1f8f94d19157024cd7d6247e1ab3a9c06968`. Evidence: `build/attendance-readiness-after.json`.
- Hosting published at `2026-09-12T07:26:17.195Z`, version `2e034bca653f732a`, live release `1789197977195000`. Previous Hosting version `cf9231d6bc7285c2` is recorded for rollback. All 545 uploaded artifact files are present; Hosting adds only `/__/firebase/init.js` and `/__/firebase/init.json`. Metadata: `build/attendance-hosting-releases.json` and `build/attendance-hosting-file-inventory.json`.
- Live HTTP verification passed 82/82 checks, 41 each on `https://attendus.app` and `https://orgami-66nxok.web.app`: exact release manifest identity, current main and all 17 chunks, bootstrap/index/service-worker hashes, seven retained release IDs and retained main/sample chunks, MIME/cache headers, guest-management 401 without a session, and expected Wallet-delivery 503 while disabled. Evidence: `build/attendance-hosting-verification-2026-09-12T07-27-01-335Z.json`. These are anonymous HTTP checks; no authenticated attendance was submitted and no pass was issued.
- Bounded health audit through `2026-09-12T07:30:41.124Z` identified 11 deployment quota/retry audit errors (all function operations ultimately succeeded), 102 callable invalid-request log entries during deployment, and four HTTP 503 log entries positively matched to the known probe path and release-verifier user agent. The invalid callable requests originated during `07:21:35Z`–`07:24:09Z`; their origin is unknown. No errors occurred after `07:27:16.172Z` through `07:30:41.124Z`, and no startup, signing-secret or index error class was observed. All 13 Scheduler jobs are enabled. The two new attendance jobs had not yet reached their first scheduled runs (`07:36Z`/`07:37Z`), so first-run acceptance is pending. A preexisting usage-reminder status 13 dates to `2026-08-25`; it is outside this attendance release. Evidence: `build/attendance-health-after.json` and `build/attendance-wallet-probe-log-match.json`. This brief post-deployment interval does not replace the pilot observation window.
- Browser automation initialization timed out twice, so a rendered browser smoke test was not completed. Authenticated pilot acceptance, real-device acceptance and closing-plus-24-hour reconciliation observation remain pending the designated event/account/device details. Android remains a compile-only fixture-signed artifact; no native app was installed or distributed.
- Test accounts, dedicated event/physical boundary/time and available devices: requested from owner; pending.

## Required physical acceptance (not yet conducted)

| Surface | Required current evidence |
| --- | --- |
| Native iPhone and Android attendee | Foreground consent, permission denial, timeout/retry, background/navigation cancellation, boundary behavior, event/ticket choice, Pass Lock alternatives, server-confirmed receipt |
| Safari and Chrome attendee | HTTPS grant/denial, bounded acquisition, secure guest management, required answers, duplicate prevention and server receipt |
| Two disconnected native staff devices | Fresh/stale kits, paid fixtures, tampering/expiry/wrong-event scans, same-device cross-method duplicate, cross-device conflict, pause/close and schedule history, reconnect replay exactly once |
| Organizer | Explicit boundary opt-in, scheduled/manual controls, cancellation/rescheduling, registration status changes, guest claim, historical attendance, permitted reentry |
| Observation | Reconciliation through closing plus 24 hours, visible unresolved/rejected/conflicted entries, completion times and fallback/pass-failure metrics |

No real-device acceptance should be claimed until these tests are actually conducted. Physical testing and the 24-hour observation cannot be replaced by local unit tests.

## Final phase: issuer activation (explicitly deferred)

Prepare Apple pass signing/team/type identifiers, WWDR certificate and authenticated update/APNs service; prepare Google event/generic classes, issuer credentials and publishing approval only when the owner resumes this phase. Preserve the existing attendance signing key and stable pass/provider IDs. Activation must synchronize current state, including cancellations and revocations.

At that time, configure the appropriate deployment switch and server-only provider secret, validate fixture adapters, apply scoped provider flags, then test installation and updates on actual iOS/Android devices. Wallet admission must remain allowed for Pass Lock events. No issuer, publishing or installation acceptance is implied by locally generated packages or mocked Google requests.

The deferred adapter configuration is:

| Setting | Required later |
| --- | --- |
| `ATTENDANCE_WALLET_ORIGIN` | Attendus HTTPS origin serving `/api/wallet/**` |
| `APPLE_WALLET_SIGNING` | Server secret JSON containing `certificate`, `privateKey`, and `wwdrCertificate` PEM strings |
| `APPLE_WALLET_PASS_TYPE_ID` / `APPLE_WALLET_TEAM_ID` | Identifiers matching the Apple signing certificate |
| `GOOGLE_WALLET_SERVICE_ACCOUNT_JSON` | Server secret for an account authorized by the intended issuer |
| `GOOGLE_WALLET_ISSUER_ID` | Intended Google issuer, with publishing/demo status explicitly verified |

Persist provider deployment switches in the environment configuration used by Firebase deployment, not only in an invoking shell, and verify the resulting service configuration. Runtime account/event flags remain a second independent gate. Do not provision placeholder production provider secrets to satisfy preflight. Apple certificate/team/expiry/private-key matching, APNs updates, Google issuer rights and publishing status require their own final-phase checks.

## Operations and privacy

Record method/result, server completion time, foreground duration, bounded fallback reasons, duplicate/replay counts, pass failures and unresolved offline receipts. Do not log location payloads or raw attendee coordinates. `CheckInAudit` and bounded funnel events are intended for these metrics. Monitor core lifecycle jobs separately from provider delivery jobs; provider failures must not block core renewal or guest management.

Core issuance failures now emit `CheckInAudit.action = attendance_pass_issue_failed` with only kind, event/account identifiers, a whitelisted failure code, duration and timestamp. Request bodies, credentials, answers, coordinates and error messages are excluded. Failure to store telemetry preserves the original issuance error. Provider refresh failures remain separately visible in their respective job queues.
