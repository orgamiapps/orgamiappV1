# Deployment request — 2026-09-27

Owner authorized deployment. This is a partial rollout, not launch completion. Existing work is preserved on `codex/comprehensive-hardening`, HEAD `8c40edcf77d7ae269c38294e5bbd8931da1fb3bb`. No commit/push/main-branch release was made.

| Component | Staging | Production |
| --- | --- | --- |
| Web | Published; exact assets verified on both domains | Previous release preserved |
| Functions | All 113 expected Functions ACTIVE and updated | Existing 111 unchanged by revision/update time |
| Rules | Default Firestore database and configured Storage bucket match source | Not deployed |
| Composite indexes | 20 additions; all 48 READY | 13 additions; all 48 READY |
| Data | Synthetic private canaries; explicit fixture cleanup verified | Read-only inventory/dry run; no migration apply |
| Native/device/pilot/observation | Not qualified | Not qualified |

Staging: https://attendus-staging.web.app/ and https://attendus-staging.firebaseapp.com/.

Release artifact: `2118df97923d086480ede14fd8f1ae79724524e0c73a9976739128222d9805bf`.
Hosting release: `projects/925344893088/sites/attendus-staging/releases/1790546061479000`.
Hosting version: `projects/925344893088/sites/attendus-staging/versions/1273c217a14dfaad`, published `2026-09-27T21:54:21.479Z`.

Built once for staging; 84 uploaded files, 63 packaged immutable assets, 14 deferred chunks. Source/artifact hashes and expected previous release checked before publication. Both domains passed all 63 immutable asset checks. This is HTTP/artifact evidence, not authenticated-browser or device acceptance. **`build/web` contains staging configuration; never promote it to production.**

Production inventory: 143 events, all missing confirmed counters; 88 incomplete schedules, 45 legacy, 10 exact. Accountless/public registration is enabled. Production application/backend/rules promotion remains held for reviewed migration, recovery rehearsal, unfinished implementation and acceptance gates. Do not fabricate counters or dates. Refreshed migration dry run is read-only and has no backup proof.

## Evidence and retained failures

All paths below are in `build/deployment-request-20260927/`.

- `staging-functions-after.json`: 113 active, no missing/unexpected/stale entries; Wallet provider delivery disabled.
- `staging-live-assets.log`: both domains passed; `staging-query-canary.log`: six query contracts passed.
- `staging-analytics-canary.log`: live aggregate create/update/delete passed. `staging-reminder-canary.log`: live scheduler produced deterministic in-app notification, `in_app_only` / `push_token_unavailable`; no physical push qualification.
- `final-verification.json`: 14 explicit canary paths absent; not an exhaustive orphan inventory. Default Firestore and Storage rules equal source. Additional named database `attendus-staging-database` retains a separate older ruleset outside the configured deployment. Initial all-database comparison retained in `final-verification-all-databases.json`.
- `postflight.json`: production Hosting and 111 Functions unchanged at 21:58 UTC. Bounded Cloud Run ERROR query found one deployment IAM quota audit event and no application ERROR entries. Affected `guestattendanceweb` public invoker permission subsequently verified present. This is not 24-hour observation.
- Initial index deploy rejected five redundant `rows` composites with only one non-name field. Removed those definitions; six index/query tests and query contracts passed; corrected deployments succeeded. Existing composite/field indexes and TTL policies preserved.
- Initial backend deploy stopped for retry-policy confirmation before publication. Retried explicit 113-function targets plus rules/Storage; CLI recovered regional quota error and completed. Both logs retained.
- Independent staging Ed25519 signing key generated directly into protected Secret Manager `ATTENDANCE_PASS_SIGNING_KEY`, version 1. No secret material stored in chat/source or copied from production. This does not configure native signing or Wallet issuers.

Prior local evidence remains Flutter 189 tests/clean analysis, backend 167 tests/clean lint, combined emulator/rules 98 tests, Functions integration 8 tests. These do not establish full live acceptance.

## Recovery and provenance

Previous staging Hosting version: `projects/925344893088/sites/attendus-staging/versions/dad906350f3774c8`, release `1787523383016000`.
Retained production Hosting version: `projects/951311475019/sites/orgami-66nxok/versions/e0b3b60897962a19`, release `1790476984806000`.

Function source/revision metadata: `staging-functions-before.json` and `../attendance-functions-before.json`. Backend restore not rehearsed. Rules capture occurred after release: `staging-rules-captured-during-deploy.json` is not pre-deployment evidence. `staging-rules-prior-candidates.json` contains historical sources only, not verified previous active pointers. Retain additive indexes and user history during rollback.

Frozen source/artifact hashes: `staging-candidate-manifest.json` (1,028 source files, 84 artifacts). `staging-working-source.zip` SHA-256 `7f63d00627e30e359fb2652afca1fb1bc834c300723102b50fea9bdeac9563df`. Later ledger/report/enrollment edits are documentation-only. Original execution manifest remains historical and unchanged. `docs/launch-deployment-manifest-20260927.json` records deployment evidence hashes.

## Owner setup and open gates

Owner has iPhone/Galaxy and needs Apple Developer/Play Console setup help. [Enrollment guide](launch-store-enrollment-20260927.md); personal versus registered-company ownership pending. Identity/payment/credentials belong only in official provider interfaces and protected stores. No enrollment, purchase, signing upload or submission performed.

Continue unfinished implementation in [execution checkpoint](launch-execution-checkpoint-20260927.md), native configuration, retention review, complete isolated recovery rehearsal and production reconciliation; then authenticated browser/signed-device acceptance including iPad, compatible production promotion, owned two-offline-device pilot and event-close plus 24-hour observation. Completion is not declared.

## Production website publication — 2026-09-27 22:16 UTC

Owner explicitly requested attendus.app publication while deferring launch completion. Website deployed and guest rendering checked; 525 immutable assets verified on attendus.app and orgami-66nxok.web.app. Added 24 website backend dependencies, all ACTIVE; original 111 Functions unchanged. No migration apply/rules/native release. See [production release report](production-web-release-20260927.md) for version, rollback and evidence.

Correction: prior 113-function staging completeness claims used a parser that omitted dynamic exports. Explicit exports plus a runtime-inventory regression test now cover them; staging still needs that expanded inventory reconciled. Authenticated/end-to-end, device and observation gates remain unqualified. Launch completion is deferred, not achieved.
