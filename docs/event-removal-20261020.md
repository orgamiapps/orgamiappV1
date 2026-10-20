# Event deletion and cancellation

Removal now has one shared lifecycle contract across the backend, organizer
controls, event pages, and event listings.

## Behavior

- Opening removal controls requests manager-only eligibility. Empty events can
  be deleted; dependent registrations, tickets, payments, or attendance records
  require cancellation. Pending ticket reservations also prevent deletion,
  including the interval before a payment record exists. Cancellation retains
  its attendee preview and reason.
- Confirmed results update the shared lifecycle store before the dialog and
  affected event routes close. The previous list keeps its filters and scroll
  position. A direct event root falls back to Discover.
- One reference-counted Firestore document listener per mounted event updates
  public and private lists and details. Cancelled events leave active listings,
  while registrations, tickets, and attended history retain a cancellation label.
  Profile's Created view, also reached from Organizer workspace, includes
  Cancelled events.
- Deleted links show Event unavailable. A denied source read is resolved through
  the capabilities callable; service failures offer retry instead of requesting
  private-event access.
- Account changes invalidate listener state and pending responses. Cached
  absence cannot establish deletion, and detached persisted feeds require
  current server validation before reuse.
- Profile bulk deletion reports confirmed, failed, unconfirmed, and unattempted
  items separately. An uncertain result stops the batch and retains its request
  identity for retry. Populated events remain available for cancellation review.

## Backend compatibility

`getEventCapabilitiesV1` accepts optional `includeRemovalEligibility`. Additional
dependent-record queries only run when a manager explicitly requests it.
`deleteEmptyEventV1` accepts `requestId` and optional `expectedEventRevision`.
The transaction rechecks management, revision, and dependent records, removes
the public projection, and writes an actor-bound deletion receipt. A replay
returns the original successful result even when the event is already absent.
Legacy callers retain their existing response fields.

Both removal mutations return `status` and `affectedEventIds`. Cancellation
includes every affected recurrence occurrence and removes public projections in
the same transaction. It checks an optional expected revision while preserving
successful preview replay. Projection maintenance and backfill exclude cancelled
events without removing their direct historical pages. Notification jobs and
historical records are preserved.
Deletion receipts are included in the existing account-deletion disposition.
Firestore access rules have not been broadened.

## Local verification

The added Flutter tests cover lifecycle delivery and caching, account switches,
late responses, deletion/cancellation navigation, dialog submission, retries,
bulk partial outcomes, and retained history. The emulator suite tests actual
Firestore transactions, revision/dependency races, receipt replay, recurrence,
and projection removal. Existing access-rule tests remain required.

The browser fixture uses production Flutter widgets with synthetic Firebase
delegates. It only runs on loopback and blocks external provider writes.

```text
flutter test --exclude-tags=emulator
flutter analyze lib test tools integration_test test_driver
flutter build web --release --no-wasm-dry-run
cd functions
npm run lint
npm test
npm run test:rules
npm run test:launch
```

To reproduce the local desktop/phone journey:

```text
flutter build web --release --no-wasm-dry-run --target integration_test/event_removal_preview.dart --output build/event-removal-preview
node tests/browser/event-removal-preview.cjs
```

Fixtures and responsive Chromium screenshots do not establish live Firebase,
branded Safari, physical iPhone, or production qualification.

## Release and observation

Follow `docs/web-release-pipeline-20261004.md` for the exact committed candidate:
web quality, frozen artifacts, staging backend before client, executable
same-candidate evidence, the required observation interval, qualification, then
promotion without rebuilding. Do not deploy this client ahead of the compatible
backend response contract.

Use owned test events for successful empty deletion, populated cancellation,
two online public/private sessions, stale revision, and response-loss replay.
Check that each affected list removes its card after server delivery; verify
Back/Forward and reconnect, private-link access requests, cancelled history, and
physical iPhone Safari. Preserve the compact Discover layout.

During staging and post-promotion observation, inspect callable failures for
`getEventCapabilitiesV1`, `deleteEmptyEventV1`, and `cancelEventV1`, distinguishing
expected permission/revision/dependency conflicts from transport or internal
errors. Compare affected IDs against Events and PublicWebEvents, inspect
existing cancellation delivery jobs, and retain two-session UI evidence of
list updates. Unexpected stale cards, false access prompts, duplicate mutation
effects, or lost history block acceptance. Local tests alone cannot close these
release gates.

## Staging preparation evidence

The prior pilot `webqa-20261020-675992333e` (candidate `39353123209`) was
archived and retired with explicit owner approval on 2026-10-20. Its exact
196 source and derived documents and four approved Auth identities were
removed using version/identity guards and a one-shot journal. The verified
baseline anonymous identity, 32 captures, 150 earlier retirement pins, and all
prior evidence were preserved. The 35 newly retired isolation records were
pinned from read-back; the existing empty-staging check passed with all 185
retained pins. Private document and identity archives remain outside Git.

The current 152 staging Functions source generations were copied into the
existing private recovery bucket with create-only destination preconditions.
Every copied archive was verified by byte hash; the 152 production archive
entries remain unchanged. These updates refresh the two frozen prerequisite
manifests without weakening the empty-staging or rollback checks.

The cleanup receipt SHA-256 is
`89d0287eaf351b15d4f231204839d889194bb1793d1efba09611ec8983025d66`.
The verified source-archive manifest SHA-256 is
`382a105729b8419144d0218e7e443a2575d41a5db533d180bddc6a1426d7b00d`.
The actual receipt/manifests were independently reconciled, and 64 focused
rollback, retired-fixture, and release-contract tests passed. This is release
preparation evidence; no staging deployment or production qualification follows
from these checks alone.

## Fresh staging prerequisite after the held activation

Candidate `39477954816`, source
`7bf56a800ef295a40cba234a77c1d217d0ebc2cb`, successfully deployed staging
at `2026-10-20T19:24:09.583Z`. Both local activation attempts stopped before
seed-intent. The first failed during Windows long-path extraction; the second
passed extraction but failed during read-only preseed snapshots. Its exact
cause was not retained and remains unknown. Subsequent read-only checks passed,
but the first-write window expired. This candidate remains held, with both
journals and deployment artifacts preserved; no qualification clock is reset.

The owner approved a fresh staging attempt. At
`2026-10-20T21:56:02.424Z`, all 152 current staging source generations were
retained using new create-only private backups and verified by byte hash.
Their identities match the held candidate's immutable deployment receipt.
All 152 production manifest entries and earlier archive objects are preserved.
The new manifest SHA-256 is
`c3459b670de775509fcc44a4c7701a73ebce5cde5bf0b7e0739793b9d62277e2`.
No fixture or account cleanup was repeated.

This update changes only the predecessor archive prerequisite and evidence.
The fresh candidate still requires protected CI, a new first-attempt deployment,
timely activation and first observation, all 13 qualification gates, separate
live event-removal and physical iPhone acceptance, and production verification.
