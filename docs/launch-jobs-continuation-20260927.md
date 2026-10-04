# Durable job lease continuation — 2026-09-27

Status: implemented locally; targeted unit verification passed. Firestore integration, staging, deployment, device qualification and observation are not established by this segment.

## Scope and preservation

Read the continuation plan, completion checkpoint, source manifest header, existing worker and CI configuration before changing the worker. Existing checkout changes were retained. This segment owns `functions/events/jobs.js` and dedicated tests only; the integrator owns worker call sites and the main acceptance ledger. No production writes, deployment or provider calls were made.

## Implemented

- Ten-minute leases renew only while the same token remains unexpired. Expiry is inclusive: a lease at its expiry instant has already expired.
- The existing `work(ref, heartbeat)` interface remains compatible. `heartbeat.token` identifies the claim; `heartbeat.assert(tx)` reads and checks the current job before other transaction reads/writes; `heartbeat.transaction(callback)` wraps a Firestore transaction with token/expiry/terminal-state validation and a second local expiry check after the callback.
- Recipient, checkpoint and final-state writes must use the transaction helper in the caller. Its job read participates in Firestore transaction conflict detection, so a replacement claim invalidates the older transaction. Transactions must contain only Firestore work, not irreversible external effects.
- Post-work release and error handling check token and expiry. A late worker cannot clear a replacement lease or overwrite its completion. An exception after committed terminal state does not turn completion into a retry.
- Transient errors retain bounded backoff and stop at five attempts. Permanent errors fail immediately. Malformed or exhausted attempt counters fail closed. Completed, failed, cancelled, delivery-unknown and review jobs do not restart automatically.

## Evidence

- `node --test test/launch-jobs.test.js`: 9/9 passed on Node v24.13.0. This host runtime differs from CI Node 22; final qualification must use the intended CI runtime.
- Scoped ESLint over the worker and both dedicated test files: passed.
- Scoped `git diff --check`: passed.
- Unit cases cover renewal, expiry before writes, expiry during a callback, competing reclaimed worker, exception after committed completion, transient backoff/five attempts, terminal and ambiguous states, poisoned counters, and future retry/live lease exclusions.
- `functions/test/launch-jobs-emulator.test.js` contains three dedicated Firestore tests for discarded recipient/checkpoint writes after expiry, stale-worker fencing after reclaim, and completion surviving cleanup failure. The integrator will run these with the combined owned emulator suites; they have not been run in this segment.

## Remaining gates

The helper cannot fence call sites that continue to write directly. Integrator adoption in announcement/export recipient commits, checkpoints, final states and cleanup is required. This work does not implement provider-unknown operator resolution, lifecycle coordination, paginated recipient/export scans, resumable external-object cleanup, or a production backlog observation. Those Step 2 requirements remain open until separately implemented and qualified. Emulator tests are targeted boundary evidence, not actual provider-delivery or storage acceptance.

## Follow-up: refund capacity correctness

The integrator assigned `handleRefund` in `functions/public-web/checkout.js` after review found that full refunds bypassed the reconciled confirmed counter. This handler now reads ticket, event, linked registration and any necessary original reservation before writes. It resolves explicit forward/reverse admission links or the original reservation identity; conflicting links and unresolved guest-only legacy relationships require review. It preserves paid fields, revokes the admission and cancels its linked registration, and releases only the pre-refund eligible contribution. Already revoked admissions and repeated or reordered webhook events cannot release the place twice. Events without migrated confirmed counters retain that missing state.

`node --test test/refund-capacity.test.js`: 10/10 passed. The deterministic transaction fixture rejects reads after writes and tests full/partial/refunded replay, revoked and pending admissions, missing counters, conflicting links, original reservation recovery and reordered notifications. Scoped ESLint and diff checks passed. Actual signed Stripe webhook/emulator integration remains a separate gate; no external refund was initiated and no paid feature was activated. The integrator was notified that the shared checkout file was released for further edits.

## Follow-up: authenticated roster cursors

Added `functions/events/roster-cursor.js`: versioned, domain-separated HMAC-SHA256 tokens bind event, actor, roster generation, canonical filter hash, row identity, issue time and expiry. Missing signing configuration fails closed. Constant-time MAC comparison, strict size/type checks and a maximum fifteen-minute validity prevent cursor editing from extending generation retention. Pagination must preserve original issue/expiry values; the integrator owns callable adoption and deletion/authorization checks. The existing contact HMAC secret is reused with a distinct domain; no new secret is required.

`node --test test/roster-cursor.test.js`: 7/7 passed; scoped ESLint passed after correcting an initial control-character-regex lint error. Tests include actor/event/filter replay, tampering, exact expiry, oversized/malformed payloads, missing keys and domain separation. These unit results do not qualify large-roster live navigation or deletion invalidation.

## Follow-up: audited delivery-unknown resolution

Added `createResolveOutboundDeliveryUnknownV1(admin)` in `functions/communications/delivery.js`. The integrator must export the callable. It requires an admin claim plus a currently active role with `communications.mutate`, transactionally rechecks role and actor/recipient deletion state, and accepts only `accepted` or `failed` with a reason and evidence reference. It atomically writes an immutable resolution record and audit record, rejects conflicting idempotency keys, and never queues a resend. Resolution indicates a reviewed provider outcome, not recipient delivery/read confirmation.

Abandoned-send cleanup now checks the current sending state and timestamp in a transaction. Each send has an attempt token; final message and guest updates check that token and sending state transactionally, preventing late workers from overwriting an operator resolution or later outcome. Guest-owner deletion is checked even where the message carries only a guest ID.

`node --test test/delivery-resolution.test.js`: 9/9 passed; scoped ESLint passed. Cases cover authorization, revoked role, deletion, replay/conflict, forbidden retries, sweep races and late-worker writes. Deliberate unsupported-channel failures exercise final-write fencing without contacting a provider; their warning logs are expected. No provider calls or attendee messages were sent. Actual provider acceptance, operator UI, emulator authorization/race validation and production observation remain separate gates. `OutboundDeliveryResolutions` contains potentially identifying actor/message IDs, reasons and evidence references and requires disposition/retention coverage before launch.

## Follow-up: current calendar attachment eligibility

`calendarAttachmentEligible` in `functions/communications/delivery.js` now transactionally verifies current event, admission, explicit ticket links, recipient identity, guest contact and deletion state immediately before the provider send. Confirmations/reschedules attach only for an eligible current admission. Duplicate proof messages, ordinary announcements, pending/waitlisted/declined admissions, missing identities and revoked/unpaid tickets cannot gain a confirmation attachment.

Cancellation attachments require explicit `calendarPreviouslyConfirmed: true` evidence captured by the trusted producer before cancellation, plus the matching current cancelled registration/event. This retains cancellation updates after normal credential revocation and suppresses stale cancellations after reinstatement. Accountless cancellation emits that field from `cancellationAdmissions.previouslyConfirmed`; the integrator owns the matching renderer/lifecycle producer changes. Missing evidence fails closed and must not be backfilled by guessing.

Calendar generation keeps the existing registration-based UID, or the existing ticket-based UID for a ticket-only lifecycle message. It never emits `undefined@attendus.app`. No UID is replaced. This does not reconcile every previously issued event-based/calendar identity, prove all sequence/revision transitions, make the provider call transactional with concurrent deletion, or qualify calendar import on devices; those broader lifecycle/acceptance gates remain open.

`node --test test/calendar-eligibility.test.js test/accountless-registration.test.js test/delivery-resolution.test.js`: 27/27 passed (8 new calendar eligibility tests). Scoped ESLint passed. Tests cover active RSVP and ticket confirmation, revoked/unpaid/missing/foreign identities, changed guest contact/deletion, duplicate proof, explicit former-confirmation evidence, reinstatement and stable registration/ticket cancellation UIDs. No message or provider call was performed.
