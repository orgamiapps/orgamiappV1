# Compact Discover implementation — 2026-10-18

## Result

Implemented locally; not deployed or production-qualified.

- The mode chips and 48×48 map action share one toolbar. The chips wrap within
  their own space when text or viewport constraints require it.
- V2 location is a constrained text button, followed by search and one horizontal
  category/date/price/online filter row. Category selection and clearing reuse
  the existing handlers and sheet.
- Discover's account shortcuts have moved directly below the signed-in Profile
  header. Registrations opens the unified admissions screen; Saved and Organizer
  select and scroll to the existing Saved/Created tabs. Existing wallet/pass
  entries and the guest Profile sign-in gate are preserved.
- The first section has 12px top spacing. Standard card dimensions are unchanged;
  enlarged text receives extra vertical space to prevent card overflow.
- No backend, schema, deployment configuration, or authorization changes were
  made for this task. Unrelated concurrent authentication/attendance edits remain.

## Validation

The final combined suite passed **59 tests**:

```text
test/discover_compact_layout_test.dart
test/profile_discovery_activity_test.dart
test/discover_mobile_scroll_test.dart
test/discover_map_entry_test.dart
test/discovery_route_state_test.dart
test/discovery_rollback_test.dart
test/guest_header_auth_test.dart
test/guest_access_experience_test.dart
test/profile_tickets_settings_smoke_test.dart
```

Evidence: `build/compact-discover-qualification.log`.

The populated production-widget fixture verifies the full first image, title,
and date are above bottom navigation at 390×740 for signed-in and guest users.
It loads Flutter's bundled Roboto fonts rather than relying on Ahem geometry.
Widths 320/360/390/430/768/1280 passed at text scales 1 and 2 with long location
names. Tests also cover category selection/clear, combined category/date/free
search requests, location-dialog entry, loading/empty/stale states, refresh
failure, Profile destinations and scrolling, map entry/keyboard activation,
and the existing history/scroll and rollback contracts.

Analysis of the three changed production files, new test/support files, and
preview entry point passed with no issues. Evidence:
`build/compact-discover-analysis-final.log`. Scoped `git diff --check` passed.

## Reviewable local preview

Build succeeded: `build/discovery-preview`.
Evidence: `build/compact-discover-preview-build-2.log`.

```powershell
flutter build web --no-pub --no-wasm-dry-run --target integration_test/discovery_preview.dart --output build/discovery-preview
python tools/serve_discovery_preview.py
```

Open `http://127.0.0.1:8769/`. Optional query parameters: `guest=1`, `long=1`,
`scale=2`, or `profile=1`. The harness runs only on localhost/127.0.0.1 and uses
in-memory Firebase/provider fixtures. It is separate from the production entry
point and must not be published. Browser reloads should start at the root URL
with the desired preview parameters; Discover history canonicalizes its URL.

## Remaining acceptance

Browser/device visual acceptance is **unverified**. The first browser attempt
exposed a release-incompatible mock user, which was replaced with a proper
platform subclass and rebuilt successfully. Before the rebuilt artifact could
be reviewed, Computer Use stopped because it could not reliably determine the
active Windows browser URL. No further browser input was attempted.

Review the rebuilt preview at mobile widths, then verify the real candidate on
iPhone Safari with browser controls visible. Confirm live location selection,
provider maps, authenticated Profile data, and browser Back/Forward in the
candidate environment. Widget/history fixtures are not live backend or device
acceptance. Production publication remains a separate request and must use the
repository's current immutable-artifact qualification/promotion process.
