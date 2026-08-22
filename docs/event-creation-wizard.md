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

Attendance settings map only to Attendance 2.0 profiles (`self_check_in`, `staff_entry`, and
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
