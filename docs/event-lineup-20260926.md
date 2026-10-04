# Port City event lineup — September/October 2026

Owner: the verified event organizer. Private account identifiers remain in the retained local operational evidence.
Production project: `orgami-66nxok`. Batch: `portcity-lineup-20260926`.

## Published events

All dates are 2026, with times in America/Chicago. Every event is public, free, standalone, has a unique generated cover, a 179–196-word description, three agenda items, preparation instructions, automatic registration approval, a capacity-based waitlist, and Smart Arrival disabled. The event reminder policy is `24h_1h`; delivery uses the existing application notification services and recipient preferences. Online access details remain to be supplied by the organizer.

| Event | Date/time | Location | Capacity | Registration |
| --- | --- | --- | --- | --- |
| [Port City Coffee & Connections](https://attendus.app/event/PORTCITY26-COFFEE) | Sept 30, 8–9:30 a.m. | Bienville Square | 30 | RSVP |
| [Sunset Acoustic Circle](https://attendus.app/event/PORTCITY26-ACOUSTIC) | Oct 2, 5–7 p.m. | Cooper Riverside Park | 40 | RSVP |
| [Saturday Strides: Waterfront Run Club](https://attendus.app/event/PORTCITY26-RUN) | Oct 3, 8–9 a.m. | Cooper Riverside Park | 35 | RSVP |
| [Practical AI for Everyday Projects](https://attendus.app/event/PORTCITY26-AI) | Oct 6, 6–7:30 p.m. | Online | 60 | Free ticket |
| [Sketch the Square](https://attendus.app/event/PORTCITY26-SKETCH) | Oct 10, 10 a.m.–noon | Bienville Square | 25 | RSVP |
| [Gulf Coast Picnic & Recipe Exchange](https://attendus.app/event/PORTCITY26-PICNIC) | Oct 11, noon–2 p.m. | Langan Park | 30 | RSVP |
| [Better Photos With Your Phone](https://attendus.app/event/PORTCITY26-PHOTO) | Oct 14, 6–7:30 p.m. | Online | 40 | Free ticket |
| [Small Steps, Cleaner Parks](https://attendus.app/event/PORTCITY26-CLEANUP) | Oct 17, 9–11 a.m. | Langan Park | 35 | RSVP |
| [The Midweek Mindfulness Reset](https://attendus.app/event/PORTCITY26-MINDFULNESS) | Oct 21, 6–7 p.m. | Online | 30 | Free ticket |
| [Autumn Nature Walk & Photo Hunt](https://attendus.app/event/PORTCITY26-NATURE) | Oct 24, 9–11 a.m. | Langan Park | 25 | RSVP |

## Event creation entitlement

`account_entitlements/{uid}.unlimitedEventCreation = true` is server-managed and readable only by that account. Client writes are denied. The publishing function reads the entitlement transactionally before consuming a free/basic allowance. The Flutter entitlement listener clears on account switching, logout, revocation, and read errors; the effective value is also bound to the currently authenticated UID. Creation buttons, remaining counts, upgrade indicators, and subscription-based event checks honor the override. Billing, subscription tier, group permissions, recurrence batch limits, and historical counters are unchanged.

## Production release and verification

- Hosting release `1790476984806000`, version `e0b3b60897962a19`; immutable application release `0d87bf4f16f69f1d0b1d821604e643040d701ece4e98743735effbff6e012d2b`.
- Previous Hosting version `a0346c9288aa79d8`, immutable application release `5ee4993e2032b14ed7d01ec8dd4df8e03b76ca33d9f477e75550d6e8739d1c4a`, retained for rollback.
- Only `publishEventDraftV1` was redeployed, revision `publisheventdraftv1-00003-hik`. Its source was recovered from the deployed September 12 archive and patched only for the entitlement lookup. Other functions were not deployed.
- Production rules were fetched live, patched only with the entitlement rule, and deployed independently of unrelated local rules changes.
- 13 backend entitlement/wizard tests passed; 22 Firestore rules tests passed; the Flutter entitlement account-switch/revocation/logout test passed. Targeted analyzer and ESLint checks passed.
- Production build passed deferred-chunk checks and bundle budget (1.097 MB gzip against 1.800 MB). `git diff --check` passed.
- All ten public pages and cover URLs returned HTTP 200. Twenty desktop/mobile page checks at 1440px and 390px passed title/status/horizontal-overflow checks; screenshots are saved with the batch evidence.
- Production Firestore geographic and online queries, using the application's category/free-event filters, returned all seven local events and all three online events in their intended categories. This is a database/query verification, not a completed authenticated Discover UI test.
- All 133 pre-existing events were compared with their before snapshot and were unchanged. There are 143 total events, 25 owned by this account, and zero groups.
- Creation script was run twice: stable IDs prevented duplicates. Account billing and historical creation counter remained unchanged.
- Signed-in organizer UI, RSVP, and free-ticket end-to-end checks are pending an owner sign-in. The administrative credential cannot mint an owner session (`iam.serviceAccounts.signBlob` denied); no IAM permissions were changed. This is distinct from successful production deployment and public-page validation.
- Headless client discovery verification was not accepted as passing: the app returned authentication errors and the direct browser SDK attempt could not complete its Firestore read. The interactive owner verifier was stopped without creating test registrations. Resume these checks with an owner browser session; no unattended registration script is running.

## Source, assets, and recovery

- Event copy and configuration: `tools/event-lineup-20260926.cjs`.
- Creation tool: set `ATTENDUS_LINEUP_OWNER_UID` and `ATTENDUS_LINEUP_OWNER_EMAIL` from the private verified owner record, then run `node tools/seed-owner-event-lineup.cjs` (validation only); `--apply` creates absent batch events and sets the owner entitlement. Frozen event forms and stable IDs preserve retry behavior.
- Original covers: `images/event-lineup-20260926/*.png`; generated using the built-in imagegen tool. Scene prompts and source asset paths: `tools/event-lineup-covers.json`.
- Each generation prompt used this exact wrapper around its saved scene prompt: `Create ONE original landscape 16:9 event cover image, photorealistic-natural style. {scene} Premium polished editorial photography, natural realistic textures, clean composition readable at card size. No text, logos, watermarks, identifiable celebrities, or claimed actual venue likeness. This is illustrative event artwork.`
- Evidence is kept locally in ignored `.firebase/event-lineup-20260926/`: creation manifest and media hashes, frozen event forms, before snapshots, publication result, post-retry verification, screenshots, deployed function archive, live rules backup, and Hosting release metadata. Before snapshots contain private account data and should remain local.
- `node tools/rollback-owner-event-lineup.cjs` produces a read-only rollback inventory. Use `--apply` only when removal is requested. It removes the batch's event documents and descendants, event-linked records, public projections, pending notification references, and batch media. It preserves unrelated events and the unlimited-creation grant. Re-run the inventory after deletion triggers settle. Delivered notifications cannot be recalled.
- To revoke unlimited creation separately, an administrator can set the entitlement flag to false; no subscription change is needed.

No groups were recreated and no attendee counts, reviews, or engagement were fabricated.
