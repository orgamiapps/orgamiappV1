# Attendus: next-agent execution plan

Prepared 2026-09-27 from the current checkout and read-only backend, privacy, native and UX reviews. This is one continuation plan for the approved launch work. Implement it; do not restart the review or replace it with another planning-only response.

## 1. Objective and fixed decisions

Finish the existing candidate, reconcile source data, qualify web/iOS/Android, and complete an owned production pilot plus the 24-hour offline replay observation window before expanding availability.

- Workspace: `C:\Users\block\Downloads\orgamiappV1-main\orgamiappV1-main`.
- Preserve all existing working changes, records, attendance evidence, calendar UIDs and issued credentials. Do not reset, clean, broadly stage or overwrite unrelated work.
- Implement actual account deletion. The optional Close account feature remains deferred; remove copy implying it is available.
- Extend the existing protected GitHub native release workflow. Signed TestFlight and Play-installed acceptance is required.
- Paid-feature activation, automatic refunds, biometrics and Apple/Google Wallet issuer activation remain out of scope. Preserve existing paid records and compatibility without activating those features.
- Use owned accounts and dedicated events. Do not announce to unrelated attendees or delete real accounts for testing.
- Continue independent implementation while signing, device or policy-review inputs are outstanding. Report genuine external blockers separately from unfinished code.

## 2. Starting point and evidence

Read these files first, relative to the workspace:

1. `docs/launch-completion-checkpoint-20260927.md` — latest implementation and limitations.
2. `docs/launch-completion-manifest-20260927.json` — 991 source-file hashes at HEAD `8c40edcf77d7ae269c38294e5bbd8931da1fb3bb` plus uncommitted work.
3. `docs/launch-migration-dry-run-final-20260927.json` — final saved read-only migration report.
4. `docs/launch-inventory-20260927.json` and `docs/launch-fixes-20260927.md` — earlier inventory and implementation history.
5. Applicable `AGENTS.md` instructions and `.github/workflows/ci.yml`.

All 991 manifest-listed files matched at handoff review. This plan is an additional documentation file, outside that earlier manifest. Refresh the comparison when starting; do not assume HEAD alone represents the candidate.

The saved final inventory, generated at `2026-09-27T19:58:12.827Z`, contains 143 events: 10 exact, 45 legacy and 88 incomplete schedules; 82 attendance records; and one ambiguous admission link. Review event `WISE-234NT`, ticket `AQcvxavSlVWo2KGYyyMM`. Do not infer a linkage from shared name, email or purchaser. The earlier full inventory found all 143 confirmed-registration counters missing and no history archives; refresh both figures before migration. Zero records classified as insufficient evidence by the current classifier is not proof of complete archival correctness.

Recorded local results: clean Flutter analysis; 176 Flutter tests; 113 backend tests; 19 launch/roster checks; 52 Firestore/attendance/messaging checks; and 11 contract/manifest/secret checks passed. Storage rules and the admin client were not rerun in that continuation. Native workflow/helper syntax passed using fixture association inputs. These results do not cover all cases below and must not substitute for final-candidate acceptance.

Web compilation output is `build/remaining-launch-web`; `main.dart.js` SHA-256 is `cab799ea9287fc45a92b1925e20e2bab01bde387063912ed6caeb5f84902d83c`. Two Dart files were formatted afterward. This is compile evidence, not a frozen deployment artifact. No staging deployment, production migration, signed native release, pilot or observation window completed. The owned emulator and validation processes were stopped.

## 3. Execution order

### Step 0 — Preserve the candidate and establish release controls

Capture status, source/configuration hashes and a recoverable working-state snapshot. Keep the dirty checkout intact. Use a `codex/` implementation branch when appropriate; a new worktree must receive the intended existing work explicitly because worktree creation does not copy uncommitted changes.

Inspect deployment triggers before committing/pushing: `.github/workflows/firebase-hosting-merge.yml` deploys on `main` and chains backend deployment. Keep unfinished work off that automatic release path. The new `capacityState()` rejects missing counters, so deploying it directly into active registration paths before migration could interrupt registration across the saved inventory. Design an explicit compatibility/activation gate and test it before production deployment.

Ask once, early, for configuration locations/access and ownership of:

- Protected GitHub environment `native-release`, reviewers and distribution permissions.
- Apple/Play app access, verified app/team identifiers, protected signing material, provider configuration and actual Play App Signing certificate.
- Isolated staging Firebase apps and platform configuration, or access to register them.
- A retention-policy reviewer and owned iPhone/iPad/Play-installed Android testers.

Never request secret values in chat. Verify actual environment protections and identifiers; their names in YAML do not establish configuration.

**Exit:** recoverable baseline, known deployment triggers, tracked owner prerequisites, and an acceptance ledger. Continue code work if external inputs are pending.

### Step 1 — Close authorization, deletion and capacity bypasses

Primary files: `firestore.rules`, `storage.rules`, `functions/events/{access,capacity,registration-v3,wizard}.js`, `functions/tickets/issuance.js`, `functions/public-web/{accountless,checkout,renderer}.js`, `functions/index.js`.

1. Prevent direct event writes from bypassing protected schedule/lifecycle/organization/counter operations. Route these changes through authoritative callables, preserving safe legacy reads and returning clear update-required behavior where necessary.
2. Recheck the actual affected event roles and account-deletion state within every mutation transaction, including announcement submission and empty-event deletion. Require both source-management and destination-publication authority for transfers. Missing/unapproved membership grants no authority.
3. Unify capacity across V3 registration, legacy free-ticket issuance, approval, promotion, cancellation and existing checkout reservations. Define confirmed/reserved/issued semantics once; write explicit ticket-registration links. Do not count unpaid/refunded/revoked admissions as confirmed or double-count linked admissions.
4. Apply deletion guards to client Firestore/Storage rules and every relevant server writer, while preserving deletion-status access. Prevent new data from being recreated during cleanup.
5. Complete current-admission recovery for both `customerUid` and legacy `userId`; pass the actual event into eligibility evaluation. Return separate stable admissions, not a guessed owner derived from purchaser or contact information.

**Exit tests:** direct-write attacks; cross-organization edits/transfers; role removal during operations; mixed legacy/V3 last-place requests; issuance versus approval/promotion/cancellation; full-without-waitlist; duplicate/conflicting keys; account switching; legacy and multiple-admission recovery; and mutation-versus-deletion races.

### Step 2 — Finish durable operations and lifecycle propagation

Primary files: `functions/events/{jobs,launch-operations,wizard}.js`, `functions/communications/delivery.js`, `functions/notifications/scheduled-reminders.js`, `functions/attendance/{arrival,wallet}.js`, `functions/index.js`, schedule/calendar modules.

1. Keep ten-minute renewable leases and five-attempt bounded retries. Reject expired leases and fence every recipient commit, checkpoint, final state and cleanup with the current token/expiry. A stale worker must not publish results or overwrite a later completion.
2. Process recipients and exports in bounded pages with durable cursors/checkpoints. Replace full queue/root scans with indexed bounded selection and resumable cleanup. Count every selected recipient exactly once, including removed, opted-out, unreachable or ineligible recipients.
3. Add audited operator resolution for `delivery_unknown`. Preserve the distinction between queued, provider-accepted, failed and unknown; never automatically resend an ambiguous provider outcome.
4. Implement one revision-bound lifecycle job coordinating cancellation/rescheduling, availability, check-in windows, reminders, sessions, passes and calendar updates. Bind preview/application to actor, draft/form, scope, target occurrences and revisions. Preserve explicit pre-mutation rejection of unsupported recurrence sizes.
5. Bind updates to the intended change, even when later edits or reordered triggers occur. Preserve the recently implemented legacy fan-out deduplication, but prove a single lifecycle outcome across old/new entry points.
6. Reconcile every already-issued calendar UID. Flutter event calendars use event-based UIDs; confirmations/guest pages use registration-based UIDs. One recipient can have several issued identities. Increment revisions and update/cancel each appropriate entry without replacing its UID. Ordinary announcements and unconfirmed admissions must not gain confirmation attachments; previously confirmed cancellations still need their cancellation updates.
7. Recheck actor/recipient eligibility and deletion state at side-effect boundaries. Include RSVP-only guests, respect applicable preferences, and exclude revoked admissions from reminders and ordinary audiences.

**Exit tests:** worker crashes at each boundary; competing expired workers; poisoned jobs; transient/permanent/unknown delivery; duplicate/reordered triggers; exact-minute and timezone-only changes; DST/midnight; every recurrence scope; RSVP-only audiences; multiple calendar identities per recipient; and accurate final disposition counts.

### Step 3 — Complete attendance evidence and personal-data deletion

Primary files: `functions/account/{deletion,attendance-history}.js`, `functions/messaging/service.js`, `functions/public-web/{accountless,renderer}.js`, rules, `firebase.json`, deletion/history/privacy screens and Apple auth helper.

1. Build one field-level disposition registry that drives inventory, cleanup and verification. Cover operational contacts, guest claims, tokens/passes, followers/following, messages, lowercase notifications, exports/roster generations, moderation/audit/payment fields, drafts/templates, provider identifiers, entitlements, storage and shared ownership. Verify exact paths including `user_banners/{uid}/` and `event-drafts/{uid}/` as well as profile photos.
2. Convert deletion phase labels into persistent phase/item checkpoints, cumulative counts, evidence fingerprints, renewable fenced leases, bounded retries and visible terminal/review states. Verify every disposition category before deleting authentication; do not rely only on current `DELETE_QUERIES` or archive existence.
3. Verify the original attendance stamp and complete correction chain before destruction. Preserve proven attendance with explicit unknown timestamps; unsupported evidence enters review and blocks its destructive cleanup. Reconcile admission groups/re-entry totals before and after identity removal. Resolve relationships from record identities, not current profile details or name/email matches.
4. Make shared-conversation migration resumable with stable redirects, transactional writer/reader coordination and per-item checkpoints. Preserve other participants' messages, unread/read boundaries and deep links. Define explicit event/community owner transfer or unavailable-owner handling; never silently select an unrelated replacement owner.
5. Add public `/account-deletion` and resumable status, independent of discovery rollout state. Support authenticated accounts, owned anonymous sessions and narrowly scoped verified-guest requests with expiry, rate limits, replay protection and generic acknowledgments. Guest proof must never authorize deletion of a linked full account or unrelated guest.
6. Integrate Apple revocation failure/retry/status into deletion recovery. Preserve straightforward in-app deletion after restart or authentication loss. Make progress and errors truthful.
7. Finish history authorization, audit and correction consistency. Display unknown timestamps clearly and distinguish source-evidence corrections, manager notes and voids.
8. Implement reviewed retention exceptions by field, basis, purpose, expiry and access policy. Treat hashes, account/job IDs and audit references as potentially identifying. Update privacy and deletion copy only after it matches actual behavior; remove deferred closure claims. Obtain the named review before launch.

**Exit tests:** failure/restart at every destructive boundary; concurrent writes cannot recreate data; archive/correction tampering stops cleanup; unchanged permanent totals; unauthorized and removed-role access; guest-proof attacks/account switching; actual Storage fixture cleanup; concurrent conversation migration; ownership preservation; Apple cancellation/partial failure; and final inventory verification preventing premature Auth deletion.

Rerun admin deletion tests intentionally: an existing admin fixture containing only `userId` may now be unproven attendance. Correct the fixture or expected review outcome; do not weaken archival safeguards to make the test pass.

### Step 4 — Finish rosters, attendee retrieval, exports and navigation

Primary files: `functions/events/{roster,launch-operations}.js`, `lib/screens/MyProfile/my_registrations_screen.dart`, `lib/widgets/public_registration_card.dart`, attendance screens, `lib/Services/artifact_download_*`, `event_export_service.dart`, discovery and router files.

1. Authenticate cursor contents and bind event, actor, generation, filters and expiry. Retain fifteen-minute stable navigation during check-in; users must not extend retention by editing a base64 cursor. Make deletion/authorization invalidation override stale snapshot access safely.
2. Define contact revision semantics for exports: roster rows currently come from a snapshot while contact values are read live. Produce a coherent identified snapshot with count, filters, generation time and timezone. Preserve transactional publication/deletion guards, lease-specific private objects and atomic audit evidence.
3. Complete download authorization/revocation behavior, including after a URL is issued. A five-minute bearer URL cannot be revoked merely by checking a later callable. Test and document the chosen bounded behavior.
4. Preserve selected registration/ticket identity through Upcoming → event → pass. Render recovered multiple admissions, RSVP-only, pending, waitlisted, confirmed and cancelled states. Sort Upcoming by schedule with stable tie-breaking/cursors. Clear previous-user data and reject stale responses on account switches.
5. Extend server capabilities to remaining attendance-sheet, private-event and export controls. Preserve already-working capability checks in the event screen and console. Distinguish permission loading, removed staff and unavailable accounts.
6. Return explicit platform download/share outcomes. Distinguish download initiation, share completion where reported, dismissal and failure; support iPad popover anchoring. Never label opening a sheet as a saved file.
7. Serialize discovery filters in canonical URLs and restore refresh/bookmark/Back state and per-history-entry scroll. Retain existing event/community routing, explicit registration submission after authentication, empty-inventory alternatives and a usable persistent action area.

**Exit tests:** several-thousand-person rosters during live check-in, repeated names/multiple admissions, deterministic arrival/inside/no-show counts, complete exports matching filtered totals, forged/expired cursors, revoked downloads, CSV formula/quoting cases, account-switch races, real browser/native saving and ICS import, and responsive/keyboard/screen-reader/large-text navigation.

### Step 5 — Complete native staging and protected release configuration

Primary files: `.github/workflows/native-release.yml`, `lib/firebase_options.dart`, native Firebase/auth/configuration files, `tools/prepare_ios_release.py`, `tools/prepare_mobile_associations.js`, release scripts and permission/token initialization.

The signed workflow, tests on both platforms, signing helper, association generator, community auth continuation and Dart permission-gated token acquisition already exist. Extend and qualify them.

1. Register isolated Android/iOS staging apps with deliberate application IDs/flavors. Current Dart options explicitly reject native staging. Align Firebase, OAuth, App Check, Maps, APNs/FCM and associated domains for each environment.
2. Add one shared local/CI release preflight. Fail on absent, placeholder or mismatched app/environment/signing/provider configuration. Verify service configuration beyond identifier syntax.
3. Configure the actual protected release environment and verify Apple app/team/profile and the actual Play App Signing SHA-256. Validate deployed `.well-known` content and Hosting behavior; fixture identifiers are insufficient.
4. Complete Apple/Google first/returning/cancelled auth and token-revocation recovery using signed builds; retain mobile-web auth behavior. Preserve event/community destinations through cold/warm starts, restart, auth and account switching without submitting registration automatically.
5. Audit native FCM auto-init before Dart runs. Remove inactive biometric permission and unsupported disclosures; align camera/location/background/NFC permissions with enabled features. Verify denied-permission behavior and Maps initialization.
6. Produce distribution-signed TestFlight IPA and upload-signed Play AAB through CI. Staging and production application IDs require separate artifacts and configuration manifests; a staging binary is not the production release. Qualify the final production-configured internal artifact on owned fixtures before broad promotion. Record source/config/artifact hashes, CI runs, store processing/build identifiers and actual installed signing identities. Upload success alone is not device acceptance.

**Exit:** signed staging/internal candidates pass the browser/device matrix against the matching backend/configuration; owner configuration and policy-review prerequisites are recorded as resolved or explicit blockers.

### Step 6 — Finish migration tooling and rehearse the apply procedure

Primary files: `functions/events/migration.js`, `functions/tools/{launch-inventory,complete-launch-migration}.js`, history/capacity/schedule gates and organizer correction UI.

1. Extend inventory/reporting to every relevant admission and archive relationship, correction chain and orphaned record. Use the same event-aware eligibility everywhere. Resolve the named ambiguous ticket with evidence or retain a review block.
2. Strengthen backup verification: an existing metadata object with size/generation alone does not establish a completed recoverable export of the intended project/scope. Capture source, backend/configuration and applicable Storage/Auth recovery evidence; rehearse recovery in isolation.
3. Make completed migration checkpoint reuse revision-aware. The current script returns `already_complete` before verifying current source state. Persist per-record archival progress and verify complete stamps/corrections and aggregate fingerprints before declaring an event reconciled.
4. Wire `launchScheduleNeedsReview` into actual availability/check-in gates and organizer correction. It is currently only written by migration. Preserve start instants; recover precise timezone/duration only from reliable evidence. Keep historical ambiguity explicit and affected upcoming flows gated until corrected.
5. Rehearse fail/resume/concurrent-source-change behavior in staging with source-preserving fixtures. Refresh both full inventory and dry-run reports after final code changes. Reconcile all eligible confirmed admissions, archived attendance and permanent totals; retain source records.
6. Prepare the production apply runbook; execute it only in Step 8 after integrated qualification. Apply only a verified dry-run scope after backup and rehearsal. Block or report every ambiguous/changed item explicitly. Verify results before event activation; do not treat a partially successful migration as readiness for all events.

**Exit:** staging before/after counts and fingerprints reconcile, the production dry run is reviewed, backup recovery is evidenced, no history/schedules are guessed, and the activation procedure protects events with missing counters or uncertain schedules. Production reconciliation remains a Step 8 gate.

### Step 7 — Freeze and qualify one integrated candidate

Run targeted regressions during implementation. Once contracts and migration behavior stabilize, freeze a source/configuration candidate and run all relevant checks from the workflow: formatting, Flutter analysis/tests, Attendus Admin analysis/tests, backend lint/tests, Firestore and Storage rules, Functions integration, launch/attendance/messaging suites, query/index/public-web contracts, manifest/provider-secret checks and release configuration checks. CI uses Flutter 3.44.6, Node 22 and Java 21 for Firebase tests; verify installed tool versions rather than trusting directory names.

Collect real acceptance on Chrome/Edge, Firefox, Safari, mobile Safari/Chrome, iPhone/iPad and Play-installed Android. Cover guest discovery → questions/registration → admission retrieval → check-in; account switching; denied permissions/slow networks; downloads/calendars; cold/warm links; sign-in; Maps; keyboard, large text and screen readers. Use the same qualified backend and intended client configuration.

Create a new immutable manifest with source/config hashes, web/native artifact hashes, store build IDs, migration evidence, CI/test results, failed evidence and device records. The existing compile artifact is not the final release candidate. Do not rebuild between qualification and promotion; if source/configuration changes, regenerate affected artifacts and repeat affected acceptance.

**Exit:** no unresolved critical authorization, deletion, integrity, guest-conversion, attendance or native-release defect; retention wording reviewed; required configuration/device evidence complete.

### Step 8 — Deploy, pilot, observe and expand

1. Capture current production rollback artifacts/configuration and verify release gates.
2. Deploy compatible backend/index/rules additions with new behavior safely gated. Preserve older installed clients and issued credentials. Run verified migrations and enable only reconciled owned fixtures; avoid activating counter-dependent code prematurely.
3. Release the same qualified client artifacts and run the pilot: discover → register → retrieve admission → check in → two disconnected staff devices → duplicate/revoked credential conflict → reconnect/reconcile → export → reschedule/cancel → attendee update.
4. Observe through event closing plus the existing 24-hour replay allowance. Record registration/check-in/message/export/deletion failures, lease/backlog health, conflicts and final reconciliation. Set up durable monitoring for this explicitly requested observation; unchanged status should not produce repeated notifications.
5. Expand only after the window closes and all completion evidence is present.

Rollback restores the previous web client and disables affected entry points while preserving compatible backend reads, new pilot records, calendar/pass identities and audit/history evidence. Native recovery uses feature gates and a replacement build where necessary. Never erase pilot records as rollback.

## 4. Coordination and deliverables

After Step 1 contracts are agreed, parallelize backend/lifecycle, privacy/deletion and native/UX work with clear file ownership. One integrator owns shared rules/exports/contracts, migration, combined validation and release gates. Avoid simultaneous edits to shared files such as `functions/index.js`, `launch-operations.js` and authentication helpers without coordination.

Keep a single updated acceptance ledger with implemented, locally verified, staging verified, device verified, deployed, observed and blocked states. End every work segment with exact source/artifact pointers, tests, failures, outstanding prerequisites and the next executable action. Passing tests must not turn an unfinished workflow into a completed item.

Completion requires all remaining code, reconciled migration, reviewed privacy wording, signed device acceptance, the owned pilot and the closed observation window. If external access blocks one phase, continue independent work; do not declare completion or repeat the whole plan in place of implementation.
