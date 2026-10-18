# Persistent web login

Updated 2026-10-18. This replaces the older implementation notes, which incorrectly described a functional auto-login toggle and universal encrypted token storage.

## Behavior

Desktop and mobile web use Firebase durable persistence automatically (IndexedDB, matching FlutterFire's startup default, with localStorage fallback). Web sessions have no application-imposed age limit. Firebase owns credentials and refresh tokens; secure-storage profile metadata is not proof of authentication. Logout, cleared browser storage, private browsing/storage restrictions, and Firebase account security invalidation can require another sign-in.

`WebAuthSession.ready()` is the shared barrier for Firebase initialization, durable persistence, pending OAuth redirect completion, and the first authoritative auth event. Anonymous guest creation and web sign-in/registration wait for that barrier. Failed restoration is retryable; slow restoration remains pending and never becomes a guest just because a timer expired. The auth gate displays recovery controls after ten seconds and still accepts eventual success.

Mobile Google continues to use redirects on the same configured `attendus.app` auth origin. Redirect profile completion is consumed once. Web login settings explain always-on persistence instead of exposing the old no-op toggle. Recognized unsupported-storage errors surface a temporary-session notice. Cross-tab sign-out/account changes dismiss open account routes and clear the previous in-memory profile. Notification cleanup errors/timeouts cannot prevent explicit Firebase logout.

Native session-age policy and disabled sign-in providers remain unchanged. No database schema, server session cookies, custom credential storage, or backend authorization rules were added.

## Repeatable local checks

```powershell
flutter test --no-pub test/web_auth_session_test.dart test/auth_session_test.dart test/guest_session_test.dart test/auth_gate_navigation_test.dart test/firebase_initializer_native_test.dart test/auth_profile_integrity_test.dart test/login_submission_test.dart --reporter expanded
flutter build web --no-pub --target integration_test/web_session_harness.dart --output build/web-auth-session --no-wasm-dry-run
firebase emulators:exec --only auth --config firebase.test.json --project demo-attendus-admin "node tests/browser/session-restart.cjs"
```

The browser harness imports the production restoration service and uses the local Auth emulator. It creates disposable email/password accounts, launches a browser with a fresh temporary profile, signs in, fully closes the browser context/process, and reopens the same profile without injecting storage or tokens. It checks identity after restart/reload/new-tab and cross-tab logout followed by another restart. Its small DOM controls deliberately replace the application's visual shell; it is service integration evidence, not full-product UI or real Google OAuth acceptance. The test server configures the emulator before FlutterFire hydrates Auth; its bootstrap options mirror the pinned Firebase SDK. Production API requests and optional external Google prefetches are blocked by the harness network policy. Temporary browser profiles are removed after each run, and the emulator owns all fixture accounts.

The emulator service harness exposed a cross-tab logout failure with the old forced localStorage backend. Matching FlutterFire's IndexedDB default passed the same Chromium restart/new-tab/logout sequence; fallback remains available where IndexedDB is unsupported. Historical failing runs remain in `build/session-browser-*.log`.

## Qualification status

- 38 targeted Flutter regression tests passed: `build/session-regression-final.log`.
- Changed production/test/harness files pass static analysis: `build/session-analysis-final.log`.
- Full web compilation succeeded: `build/session-web-build-final.log`, output `build/web-session-candidate`. `main.dart.js` SHA-256: `525b89b74e46ec0cbee44a1548084db674af0c06c04c9ed52a8c806e7c668865`.
- Chromium, Firefox, WebKit, and mobile Chromium passed browser-process restart, reload, new-tab, cross-tab logout, and restart-after-logout checks: `build/session-browser-indexeddb-result.log`.
- Legacy localStorage-to-IndexedDB session migration passed the same Chromium restart/logout sequence: `build/session-browser-legacy-result.log`.
- The local compilation is not a production-qualified release artifact; it was not built/promoted through the repository's immutable release pipeline.
- Not deployed. The reported live Google/mobile failure has not been reproduced with an authenticated production account in this work.

Before promotion, qualify the exact release artifact through the existing release pipeline, then verify real Google sign-in and full browser closure/reopening on iPhone Safari and Android Chrome, plus desktop browsers. Include token refresh, temporary offline recovery, storage restrictions, and sensitive account actions after restoration. Capture the previous Hosting version for rollback and repeat the mobile Google check after promotion. Emulator/WebKit automation cannot substitute for physical Safari or live Google OAuth acceptance.

## Deployment preparation

The release branch `codex/web-persistent-login-20261018` applies the fix to main revision `88a1b10b6cc9682ab974c563b15fce64207510c6`, preserving its newer navigation/storage recovery fixes. On this combined source, 44 targeted Flutter tests passed (`build/login-candidate-tests.log`), changed Dart files passed analysis (`build/login-candidate-analysis.log`), and formatting passed. The earlier compilation and browser evidence above belong to the original checkout; the pipeline must build and qualify this combined source separately.

Release browser and Safari probes now inspect the already-initialized, identity-bound Firebase SDK account regardless of persistence backend. They never initialize Auth or recover a stale stored account when the SDK is signed out. Legacy LOCAL inspection remains only for retained artifacts without the SDK namespace. Browser restart and migration regressions are included in the web quality workflow.

Before this candidate, read-only Hosting inspection found production version `sites/orgami-66nxok/versions/945968711b33e5e1` (released 2026-09-27) and staging version `sites/attendus-staging/versions/1486737616d0e934` (released 2026-10-04). These are observations, not substitutes for the pipeline's fresh predecessor capture. Production promotion requires immutable candidate artifacts and successful qualification including the required observed pilot; staging success alone does not qualify production.
