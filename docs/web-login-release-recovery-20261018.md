# Persistent login deployment recovery

The October 18 candidate failed before deployment. Its Chromium accessibility trace shows the native dialog `close` event was absent at 24842.913 ms and present at 24851.151 ms. Dialog visibility and focus had already changed. The test now waits for the asynchronous event and still requires exactly one close plus trusted Escape input; no application behavior or assertion was removed.

Staging's retirement manifest expected 63 records but only 61 remained. Both missing records were retired QualificationScopes. Historical evidence for the first retained an October 7 expiry after retirement, and the collection has TTL enabled; this supports an expiry hypothesis, not a proven deletion cause.

With deployment recovery authorized, a read-only inventory validated all 61 retained records against their exact pinned content/version and confirmed only the two expected scope paths were absent. A single atomic commit created two new retirement markers using `exists: false` preconditions. They contain no actors, recipients, or expiry and are explicitly labeled as recreated markers with the original document hashes. No binding, setup, user, event, or production record was changed. These are new acknowledged writes, not claimed restoration of original document versions.

The exact plan, commit acknowledgement, and readback are in `web-retired-scope-repair-20261018.json`, canonical receipt SHA256 `6ec856558b4fdc7553e5e93309497f7fa952a76364831c310bfa944a7f97f9bf`. The manifest pins the new versions and retains each original hash and receipt linkage. All 63 records and the complete empty-staging prerequisite passed after repair at `2026-10-18T20:29:32.743Z`. All 27 retirement/rehearsal tests pass; release guards remain unchanged. Original failure and trace evidence are retained in workflow 39160955560 and the release worktree's build directory.

This repair permits a fresh candidate attempt; it does not qualify or promote production. Same-candidate executable acceptance and observation requirements still apply.

## App Check and Safari diagnosis, 2026-10-18

The real provider returned a valid staging token with action `fire_app_check` and score 0.1 for a local automated Chromium session. Staging's configured minimum is 0.5; domains, key, enabled APIs and the App Check service-agent role match. No threshold or enforcement was changed. The operator then completed the normal-browser public RSVP flow; read-only server inspection found confirmed registration/flow records at 22:23:58Z and 22:25:01Z. This proves that bounded normal-browser path, not the entire release. Private diagnostic receipts are retained in the original checkout's `build/login-manual-appcheck-receipt.json` and `build/login-recaptcha-assessment-diagnostic.json`.

Temporary staging-only debug credentials isolated the application behavior. Each credential was revoked in the diagnostic's `finally` block. These runs remain diagnostic-only and cannot qualify a release. Real App Check and the release contract remain enabled.

Two independent acceptance defects were reproduced:

- Programmatic Playwright `fill()` changed Flutter's semantics mirror without updating the form controllers. No password-login request occurred; clicking submit produced both empty-field validation errors. Pointer activation followed by keyboard input produced HTTP 200 and the exact owned account UID. Browser and cache-upgrade collectors now use that interaction and the visible submit button.
- Background Discover initialized under an event route, opened a location-onboarding modal, and could replace the event URL. Discover now defers the modal until its route and dashboard tab are visible. Its history coordinator does not initialize an inactive page. Regressions cover covered routes, inactive tabs, and preservation of the foreground event URL.

Safari WebDriver returned stale computed styles within the same script task on the live public page. A synchronous layout flush did not fix it. The shared probe now waits for rendering after baseline restoration and after applying 200-percent text. Safari uses the asynchronous WebDriver endpoint to await the result. The isolated loopback test and exact owned staging page passed in branded Safari 26.6.1 on macOS 15.7.9: run 39171904745. Failed live reproduction 39171432609 and unsuccessful synchronous fix 39171577590 remain retained. This focused regression is not a passing full Safari journey.

Local validation: 75 JavaScript producer/security tests, 11 navigation/foreground Flutter tests, 9 WebKit layout tests, and 31 workflow contract tests passed. Full candidate qualification, the remaining Safari journey, real-provider browser acceptance and the required observation/replay window remain separate release requirements. Staging still serves candidate 39164341158; production has not been promoted. Do not reuse the failed pilot as a passing new candidate or reset its original schedule.
