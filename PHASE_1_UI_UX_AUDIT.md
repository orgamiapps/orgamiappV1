# AttendUs UI/UX Rewrite Phase 1 Audit

## Rollback Point

- Local git repository initialized in this workspace.
- Rollback checkpoint commit: `a0d026d` (`Checkpoint before UI UX audit`).
- No remote push was performed.

## Audit Scope

Inspected `lib/screens` plus the new shared UI foundation files:

- `lib/Utils/attendus_theme.dart`
- `lib/widgets/attendus_design_system.dart`
- `lib/widgets/attendus_scaffold.dart`
- `lib/screens/Home/dashboard_screen.dart`
- `lib/screens/Home/home_hub_screen.dart`
- `lib/screens/Home/account_screen.dart`
- `lib/screens/Groups/groups_screen.dart`

`lib/screens` currently contains 133 Dart files across 13 product areas.

## Screen Inventory By Product Area

| Area | Files | Major screens and flows |
| --- | ---: | --- |
| Events | 35 | Event create/edit/detail, event list cards, attendance sheet, attendee lists, event analytics, feedback, tickets, ticket scanner/revenue/management, map/geofence/location, sign-in methods, event questions, co-host/access management. |
| Groups | 24 | Groups directory, group profile, group creation/editing, feed, comments, photos, polls, announcements, members, roles, join requests, admin settings, analytics, pending events. |
| Home | 18 | Dashboard shell, home hub, legacy home feed, search, calendar, notifications/settings, account/settings/help/about/delete/blocked users, analytics dashboard. |
| MyProfile | 14 | Own profile, public user profile, followers/following, tickets, ticket card widgets, QR modal, badge/ticket painters. |
| Authentication | 11 | Login, forgot password, create-account wizard, create-account steps, suggested contacts, account data/view model. |
| QRScanner | 8 | Logged-in scanner, guest scanner, QR flow, code generator, modern scanner, modern sign-in flow, event sign-in questions. |
| LiveQuiz | 5 | Quiz builder, host, participant, leaderboard, waiting lobby. |
| FaceRecognition | 5 | Face enrollment, picture enrollment/scanner, live scanner, simple enrollment. |
| Premium | 4 | Upgrade screens, subscription management, premium feature details. |
| Splash | 3 | Splash, second splash/onboarding, social icons. |
| Messaging | 3 | Messages list, chat, new message. |
| Legal | 2 | Privacy policy, terms and conditions. |
| Feedback | 1 | Feedback form. |

## Current Design-System Adoption

Adopted or partially adopted:

- `lib/main.dart` uses `AttendUsTheme.light` and `AttendUsTheme.dark`.
- `lib/screens/Home/dashboard_screen.dart` uses `AttendUsScaffold` and adaptive navigation destinations.
- `lib/widgets/attendus_scaffold.dart` provides the adaptive desktop/tablet/mobile app shell.
- `lib/widgets/attendus_design_system.dart` defines shared cards, buttons, fields, top bar, empty/loading states, status badges, metric tiles, event summary cards, and ticket pass cards.
- `lib/screens/Groups/groups_screen.dart` uses `AttendUsLoadingState`, `AttendUsButton`, and `AttendUsTextField`.
- `lib/screens/Home/account_screen.dart` uses `AttendUsCard` and `AttendUsButton` in selected sections.

Not yet meaningfully migrated:

- `lib/screens/Home/home_hub_screen.dart` remains mostly legacy despite being inside the new dashboard shell.
- Most Events, Groups subflows, MyProfile, Authentication, QRScanner, Messaging, Premium, LiveQuiz, FaceRecognition, Legal, Feedback, and Splash screens still use local visual styling.
- The reusable `AttendUsEventSummaryCard` and `AttendUsTicketPassCard` exist but are not yet broadly connected to event/ticket surfaces.

## Duplicated Legacy UI Patterns

The scan found these high-volume legacy patterns:

- 117 screen files use direct `Color(0x...)` or `Colors.*` values.
- 115 screen files define local `BorderRadius.circular`, `BoxShadow`, or `LinearGradient` styling.
- 40 screen files define local `AppBar` or `SliverAppBar` patterns.
- 47 screen files define local dialogs or bottom sheets with `showDialog`, `AlertDialog`, `Dialog`, or `showModalBottomSheet`.

Key duplication groups:

- Hardcoded gradients: frequent purple/blue gradients such as `Color(0xFF667EEA)` and `Color(0xFF764BA2)` remain in Events, Groups, Splash, QRScanner, Premium, LiveQuiz, and profile screens.
- Card styles: many screens hand-roll white containers with radius, border, and shadow rather than using `AttendUsCard`.
- App bars and headers: many screens use local `AppBar`, custom stack headers, or `SliverAppBar`, creating inconsistent spacing, elevation, title treatment, and action placement.
- Bottom sheets and dialogs: confirmation dialogs, edit sheets, comment sheets, report/block dialogs, ticket dialogs, sign-in dialogs, and selection sheets are implemented independently.
- Buttons: legacy `RoundedLoadingButton`, `ElevatedButton.styleFrom`, `FilledButton.styleFrom`, `TextButton`, and gradient `Container` buttons coexist with `AttendUsButton`.
- Empty/loading states: most screens use local `CircularProgressIndicator`, centered text, or bespoke empty containers rather than `AttendUsLoadingState` and `AttendUsEmptyState`.
- List rows: account menu rows, settings rows, attendees, followers, members, comments, notifications, messages, and search results repeat local row layouts.
- Event cards: event list items appear in `single_event_list_view_item.dart`, Home hub, group feed cards, map sheets, analytics/revenue surfaces, and pending events with separate styling.
- Ticket cards: ticket management, profile tickets, QR modals, realistic/compact ticket widgets, ticket revenue, and scanner validation dialogs have multiple independent ticket/pass presentations.
- Group cards: group directory, groups list, management, join requests, group profile, and pending event surfaces define separate group/event cards.

## Migration Map For Later Phases

| Later phase | Recommended scope | Primary targets |
| --- | --- | --- |
| Phase 2 | Harden shared design system before wider migration. | Add shared list rows, section headers, modal/dialog shell, bottom sheet shell, form section, stat cards, event/group/ticket card variants, and responsive helpers in `attendus_design_system.dart`. |
| Phase 3 | Complete dashboard and Home surfaces. | `home_hub_screen.dart`, `home_screen.dart`, `search_screen.dart`, `calendar_screen.dart`, `notifications_screen.dart`, `notification_settings_screen.dart`, `analytics_dashboard_screen.dart`. |
| Phase 4 | Modernize Events core workflows. | `create_event_screen.dart`, `edit_event_screen.dart`, `single_event_screen.dart`, event list widgets, location/geofence/map screens, sign-in method screens, event questions. |
| Phase 5 | Modernize Groups product area. | Group profile, groups list/tab, feed, comments, create/edit screens, admin settings, members, join requests, roles, analytics. |
| Phase 6 | Modernize Account/Profile/Tickets. | `account_screen.dart` remaining sections, account details, profile screens, followers/following, ticket widgets, QR modal, ticket pass components. |
| Phase 7 | Modernize Auth and onboarding. | Login, forgot password, create-account wizard/steps, suggested contacts, splash/onboarding. |
| Phase 8 | Modernize Messaging and notification detail flows. | Messaging list, chat, new message, chat action sheets, attachment/contact pickers. |
| Phase 9 | Modernize Premium/payment surfaces without contract changes. | Upgrade screens, subscription management, feature screens, upgrade/migration prompt dialogs. |
| Phase 10 | Modernize scanner, attendance, and face-recognition operational flows. | QR scanner flow, modern sign-in flow, ticket scanner, attendance sheet, face enrollment/scanner screens. |
| Phase 11 | Modernize LiveQuiz and utility/legal/feedback screens. | Quiz builder/host/participant, leaderboard/lobby, legal pages, feedback form, connectivity/debug screens. |
| Phase 12 | Final consistency pass and QA. | Remove obsolete local styling where possible, verify responsive layouts, run analyzer/tests/build, and check primary workflows manually. |

## Recommended Next Phase

Proceed with Phase 2: Design System Hardening.

Before migrating more screens, add the missing shared primitives that are currently being recreated throughout the app: section headers, list rows, settings rows, modal and bottom-sheet shells, form sections, search/filter bars, empty/loading/error states, event cards, group cards, ticket cards, and compact stat tiles. This will make later phases faster and reduce the risk of rewriting the same UI patterns differently in each product area.
