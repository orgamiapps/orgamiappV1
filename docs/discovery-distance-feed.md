# Discover distance and upcoming feed

Implemented locally on 2026-10-19. Not deployed to staging or production.

## Behavior

- Auto starts at 25 miles and resolves to 50, 100, 250, 500, 1000, or United States nationwide until six matching in-person events exist. Online events do not contribute to the threshold.
- Fixed choices are 5, 10, 25, 50, and 100 miles. Online events remain eligible independently of distance. A fixed choice requires a location.
- The responsive Event distance picker has Apply/Cancel, device-local persistence, and URL precedence. Feed coordinates use the existing URL's two-decimal precision, including cursor identities restored by Back/Forward.
- One horizontal carousel uses the initial feed page, prioritizing locally saved interests. Upcoming events uses chronological cards in the main page scroll with 20-event pages and Load more. Both receive the same eligibility filters and resolved scope.
- Failed later pages retain existing cards and the retry cursor. Request generations discard superseded responses. Browser-history snapshots retain loaded pages and resolved scope in a bounded in-memory cache.
- The Create event action reuses the existing signed-in creation route and guest account-required flow.

## Backend contract and release order

`searchDiscoveryEventsV2` accepts `feedVersion: 1`. Existing callers without this flag retain their existing behavior. App Check, authentication, and rate limits are unchanged. The client requires the new response contract rather than falling back to an API that would silently ignore a fixed distance.

Requests include location, distanceMode, radiusMiles, query, categoryId, datePreset, onlineOnly, freeOnly, and optional cursor/limit. Results report feedVersion, events, nextCursor, resolving, geographicScope, radiusMiles, and distanceMode.

The feed uses Firestore keyset ordering on selectedDateTime and document ID, preserving timestamp nanoseconds in cursors. The existing private + selectedDateTime composite index supplies the ordering (implicit ascending document ID). Cursor identity binds location, distance settings, and all eligibility filters. The resolved scope and reference time stay fixed during continuation.

Each callable scans at most five batches of 200 documents. Sparse matches and automatic radius resolution continue via cursors instead of truncating the candidate set. Client continuation requests are paced to respect the existing anonymous rate limit. This avoids the old result caps but sparse nationwide searches can require additional reads and latency; production-scale query-cost qualification remains part of staging acceptance. No event-data migration is needed.

Release backend support before the client through the existing qualified release workflow. The owner authorized staging validation and production deployment on 2026-10-19; live App Check acceptance remains required.

## Validation evidence

- Flutter analysis: build/discovery-feed-analysis.log.
- Flutter Discover tests: build/discovery-feed-flutter-tests.log (31 tests), plus build/discovery-feed-carousel-test.log (one populated-carousel scroll test).
- Backend discovery and callable-security tests: build/discovery-feed-backend-tests.log (21 tests).
- ESLint passed for the changed backend code and new backend test.
- Backend fixtures cover every Auto band, nationwide fallback, online threshold exclusion, fixed boundaries, text-only/pinned locations, online/free filtering, cursor/filter mismatch, 1105-event pagination, sparse matches beyond 1200 candidates, stable ordering, and sub-millisecond timestamps.
- Flutter fixtures cover mobile/desktop picker layout, Apply/Cancel, saved settings and reopening, missing location, stale responses, pagination failure/retry, deduplication, guest creation entry, filter composition, URL/history normalization, compact layouts from 320 to 1280 pixels and doubled text.
- Local Edge preview verified the desktop layout, fixed 10-mile Apply, Back to Auto, Forward to fixed, and refresh retaining the URL distance. Signed-in Create event reaches the editor route; the fixture does not supply the real editor backend.
- Browser capture: build/discovery-feed-desktop.png. This is fixture UI evidence, not live-data or staging acceptance.

## Live acceptance blocker

On 2026-10-19 the current staging page at https://attendus-staging.web.app/app/discover reported:

- Unable to establish anonymous guest session.
- Firebase AppCheck: ReCAPTCHA error (appCheck/recaptcha-error).
- Firestore permission-denied errors during discovery.

The observed staging release was 015598203160be072f7e85e7c4172a57c54ebe6682c7c84195f91d0c62852ddd. This new change has not been deployed there. Full staging browser acceptance remains blocked until the existing App Check/session issue is resolved. No App Check, reCAPTCHA, authentication, or permissions protections were weakened. Mobile-device browser acceptance and live Firestore query qualification remain outstanding.

Prior RSVP-only defaults, event images, optional location pins, authentication changes, compact mode/map controls, and unrelated dirty checkout files were preserved.

## Release candidate verification

The isolated candidate preserves deployed location-foreground prompting and history guards. Backend suite: 415 passed. Targeted Discover/history/foreground suite: 35 passed. Flutter analysis and backend ESLint passed. All 304 current staging and production function-source rollback archives were copied to the authorized private recovery bucket and SHA-256 verified. Staging and production reCAPTCHA Enterprise key/domain bindings were verified; a minimal real-provider diagnostic reproduces the connection failure outside Flutter. No security configuration was weakened.
