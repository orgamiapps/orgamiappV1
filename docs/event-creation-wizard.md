# Progressive event creation wizard

The wizard is an additive V2 event-authoring experience. It remains fail-closed until
`AppConfig/eventCreation.experienceVersion` is exactly `2`; missing, malformed, or unreadable
configuration keeps the existing create and edit screens active.

## Architecture

- `EventDrafts` stores server-normalized, revisioned drafts. Clients cannot read or write this
  collection directly; organizer callables enforce personal and group authorization.
- `EventTemplates` stores sanitized personal or group template content. Dates, attendee state,
  counters, payment state, access lists, staff, and online credentials are excluded.
- `EventSeries` stores the normalized recurrence rule and occurrence metadata. Every occurrence
  is still a normal event with independent registration, ticket, attendance, and analytics data.
- Draft images use `event-drafts/{uid}/{draftId}/...` and are limited to the owning full account.
- `startPublicRegistrationV3` adds versioned registration-question answers plus pending,
  confirmed, and waitlisted outcomes. V2 remains deployed for rollback.

Attendance settings map only to Attendance 2.0 profiles (`none`, `self_check_in`, `staff_entry`, and
`hybrid`) and eligibility values. The wizard never enables facial recognition, legacy geofencing,
or background attendance tracking.

## Rollout

Keep V1 selected while rules, indexes, Functions, and clients are deployed and validated:

```powershell
Set-Location functions
npm run event-wizard:rollout -- --project attendus-staging --experience-version 1
```

After staging draft, publish, recurrence, registration V3, and rollback checks pass, explicitly
enable V2:

```powershell
npm run event-wizard:rollout -- --project attendus-staging --experience-version 2
```

Production uses the same command with `orgami-66nxok`. Roll back atomically with version `1`.
The tool refuses unknown projects and versions.

## Release gates

- Run Functions lint/tests, Firestore and Storage rules tests, Flutter analysis/tests, web release
  build, Android AAB build, and the macOS iOS archive workflow.
- Verify index readiness before deploying Functions.
- Confirm autosave and publish error rates are below one percent and that no draft is publicly
  readable.
- Roll back immediately for any duplicate occurrence or ticket, private draft exposure, or
  publish/autosave error threshold breach.
- Keep V1 callables and screens for one full release cycle.


New events (blank, curated/saved templates, and duplicates) start with RSVP registration
and the explicit `none` attendance profile. Existing events and restored drafts retain
their saved policies; missing legacy policies keep their historical defaults.
`none` keeps registration, capacity, waitlists, and registration questions available,
but disables attendance methods, advanced controls, attendance passes, Smart Arrival,
manual entry, and offline replay. Ticket registration can be selected independently.
Historical attendance and saved check-in questions are retained. Backend attendance
support must be deployed before the client; no existing-event migration is needed.

### RSVP-only validation (2026-10-18)

- 18 targeted Flutter tests passed (policy, draft model, wizard widgets, check-in service).
- 44 targeted Node tests passed, including actual callable handlers with in-memory
  transactions rejecting all credential types and offline submissions for `none`,
  preserving historical attendance, and retaining RSVP approval behavior.
- Analysis of the 14 changed Dart files passed; changed backend files passed ESLint.
- The isolated `integration_test/rsvp_only_harness.dart` web build passed. An Edge
  walkthrough reached all four steps, verified RSVP registration, toggled Hybrid
  and RSVP-only with advanced settings visibility, and verified the ticket-specific
  no-attendance label. The harness uses a fake repository, not production publication.
- Screenshot: `build/rsvp-only-browser/step-3-rsvp-only.png`.
- Real Firestore attendance integration remains unverified: two emulator starts
  timed out before port 8180 became available. The added emulator regression is
  retained in `functions/test/arrival-emulator.test.js` for the next successful run.
- No deployment or production data migration was performed.

## Typed locations and durable covers (2026-10-19)

In-person events support `locationInputMode: place|text` (legacy/default: `place`).
A typed label can optionally use a map pin, recorded by
`locationCoordinatesEnabled: true`. Without that explicit flag, text locations
have their geographic metadata cleared and do not participate in maps, nearby
results, proximity assistance, or Smart Arrival. Adding/removing a pin preserves
the typed label. Online events keep their existing behavior. Templates that omit
location also omit the optional pin. Backend support must precede client release;
no bulk migration is required.

Cover selection validates the encoded image format, size, and client decoding.
Uploads and final draft saves complete before an image is marked saved or the
wizard publishes. Failed uploads retain the selection for retry within the editor;
only saved images survive reopening. Navigation and browser unload warn about
unsaved selections. Draft saves are serialized, and superseded/account-stale
upload completions cannot update the editor.

Publication prepares an immutable permanent image before the event transaction,
using the uploaded object's generation to identify the destination. A copy
failure does not publish an event or consume an event allowance. Retried
publication returns its original result. Cleanup removes only the matching source
generation after commit, preserving newer uploads.

Validation includes `test/event_cover_wizard_test.dart`,
`test/event_cover_image_test.dart`, `functions/test/event-cover-emulator.test.js`,
and the isolated `integration_test/event_location_cover_harness.dart` browser
fixture. The browser fixture uses local storage and never writes production;
Firebase image publication is independently verified against Firestore/Storage
emulators. Physical-device pickers and live Maps services remain release checks.
