# Supplemental live event-removal qualification

This harness runs against the frozen staging website. It does not deploy, alter
the canonical pilot, replace the existing qualification workflow, or qualify a
physical iPhone. Keep its report separate from local Flutter and emulator tests.

Freeze these tools in the candidate before using them. The harness requires a
clean checkout at the candidate source SHA, the matching immutable candidate and
staging deployment receipt, and real Enterprise App Check. It rejects emulator
and debug-token environments. Each browser navigation verifies the release ID
and the actual loaded `main.dart.js` bytes against the candidate.

Run the canonical browser pilot first and let its mutations settle. Prepare the
supplemental fixture afterward; its observer pins the seven canonical event
versions and rejects changes during the supplemental run. Canonical read-only
hourly observations can continue, but do not run another mutating browser
collector concurrently.

The separate fixture contains three controlled accounts, its own organization,
six events, and a separate capture scope. Public/private empty events exercise
deletion; public/private populated events retain synthetic registration, ticket,
and attendance records after cancellation. One private event remains as an
access-control and healthy-list sentinel. A sixth event tests registration
arriving after the creator's deletion confirmation opened.

See [the seed command reference](../tools/event_removal_seed.README.md) to prepare,
apply, or read-only reconcile the create-only fixture. Context files, credentials,
and operation journals must remain under the ignored repository `build` directory.
Do not print or upload them or replace the canonical context secret.

After successful seeding, run:

```text
node tools/event_removal_live_acceptance.js --candidate <immutable-staging-candidate.json> --receipt <deployment.json> --fixture <seeded-fixture-private.json> --output build/event-removal-live/<new-evidence-directory>
```

The creator uses the actual Organizer removal dialog. An independent signed-in
viewer keeps Saved, public Discover, and detail screens open. The checks require
the card to exist before removal and disappear without document navigation,
while the list remains healthy. Public Discover retains its search query; the
creator returns to its originating route. Cancellation history is checked in
Organizer workspace, attendance, and registrations/tickets. A separate outsider
tests restricted access, followed by a cross-tab viewer-to-outsider account
switch.

The lost-response test forwards the real deletion request, waits for a successful
server response, then drops that response once. It requires the client to retry
the identical request and reconciles the server state. A separate eligibility
read is interrupted to verify the retry UI. The registration race invokes the
real registration callable from the viewer's authenticated browser after the
creator's confirmation opens; creator deletion must then preserve the event and
offer cancellation review.

Every business mutation is explicitly armed for one owned event and actor, with
a private intent journal written before transmission. Direct document writes,
unreviewed callable mutations, production endpoints, and unreviewed Auth changes
are blocked. Unknown outcomes are retained and reconciled; the harness does not
automatically restart. A per-fixture attempt lock prevents an accidental rerun.
Do not remove that lock to resume an uncertain operation.

Fresh guest startup or the explicit sign-out may create anonymous accounts. Their
exact observed identities and request provenance are retained privately, including
unknown outcomes, for a separately reviewed retirement. No automatic cleanup runs.

The `curated` directory contains screenshots and a fixed-schema report without
tokens, passwords, raw exceptions, or DOM/log dumps. Failure reports retain a
deterministic phase and, when safe after login, a screenshot. Service workers are
blocked so every operation can be observed and journaled; optional funnel
telemetry is blocked. This is live lifecycle evidence, not a replacement for the
existing cache-upgrade, full browser, or real-device gates.

The current release collector is dispatch-only. Arrange the first observation
to finish within 20 minutes of the deployment receipt, then collect hourly with
no gap longer than 75 minutes. Preserve every immutable collector run ID.
Qualification also requires at least 24 hours after the canonical event closes,
an authenticated post-close replay, every existing release gate, unchanged
deployment state, and a recent final observation. The canonical seed closes
about 105 minutes after seeding, so plan more than 24 hours of collection.
Do not resume an older paused production-health automation for this candidate.

Run the branded macOS Safari producer through the existing workflow. Separately
verify the removal journey on a physical iPhone Safari using dedicated untouched
test events bound to the same candidate. A desktop 390-pixel viewport does not
close that gate. Cancellation recurrence, all removal entry points, and
service-worker cache behavior still require their existing focused tests and
acceptance checks; this six-event supplement does not silently claim them.
