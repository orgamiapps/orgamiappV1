# Deletion continuation evidence — 2026-09-27

Status: implemented locally, partially tested, not deployed, not device-qualified, not observed. Step 3 remains open; this document is evidence for the integrator's acceptance ledger, not a completion declaration.

## Changes

- `functions/account/deletion-lease.js`: random worker token, ten-minute renewable lease, five-attempt bound, explicit `review_required` / `terminal_failed` states, transactional current-token/expiry checks. Stale workers cannot publish phase/final/failure state or clear another worker's lease. Persisted counts seed retries.
- `functions/account/deletion.js`: query-page deletions and payment cleanup atomically checkpoint cumulative counts; recursive tree leaves and selective guest/pass/ticket/message writes recheck leases at commit. Tree cleanup includes nonexistent ancestors with surviving descendants. Storage batches and Auth removal have pre-boundary checks. Ownership review precedes destruction. Unlinked purchased admissions enter review instead of guessing attendee ownership.
- `functions/account/dispositions.js`: shared query/root/payment/Storage disposition definitions drive cleanup and final verification. Added lowercase notifications, drafts, guest sessions, reservations, follower/following user-ID relationships, `user_banners/{uid}/` and `event-drafts/{uid}/`. Verification covers remaining roots/descendants, payment owner fields, history identities/groups, guests, shared conversations, passes and actor-owned exports. Inventory fingerprints and remaining categories persist before Auth deletion. Existing event/community ownership, event roles, shared templates and matching audit records require explicit reviewed disposition before destructive phases.
- `functions/account/attendance-history.js`: new original stamps carry a stable fingerprint; deletion validates original and each source/manager correction. Changed legacy originals without a committed fingerprint require review. Unknown timestamps remain null. Archive writes made by deletion use its lease fence. Unsupported source evidence enters review.

## Local checks

- `node --test test/account-deletion.test.js`: 6/6 passed.
- `npx eslint account test/account-deletion*.test.js`: passed.
- Added `test/account-deletion-emulator.test.js` for owner preservation/review, residual Storage blocking Auth, complete cleanup/replay. Integrator owns the combined emulator run; see main acceptance ledger for that result. Its Storage surface is a failure-injection fake, not actual Storage qualification.

## Open implementation and acceptance gates

- Disposition registry is broader, not yet exhaustive. Field-level operational contacts, provider IDs, nested audit/payment/moderation content, entitlements and follower documents lacking a userId still require full schema inventory and reviewed dispositions. Do not claim all personal data covered.
- Shared-conversation redirect, writer/read-boundary coordination and per-message checkpoints are now implemented in the continuation below. Integrated concurrency/deep-link qualification and reviewed identifying-reference retention remain open.
- Tree enumeration uses listDocuments so missing ancestors are covered, but enumeration and some related-record inventory remain unbounded. There is no durable cursor for every phase; selected query batches have persistent item/count checkpoints. Other per-item/external counters may undercount a crash after the side effect and before checkpoint. Do not claim exact final counts at every failure boundary.
- Storage and Auth cannot share the Firestore transaction. Checkpoints precede calls, but full external side-effect retry/observation evidence remains required. Real Storage cleanup fixture tests are outstanding.
- New fingerprints detect mismatches relative to a stored fingerprint; they are not a signed external ledger. Legacy archive provenance and aggregate admission/re-entry conservation require migration reconciliation. Concurrent correction races require additional testing.
- Review states deliberately stop automated retry. Audited operator resolution, Apple revocation recovery/status, verified-guest deletion proof, public deletion/status UI and reviewed retention expiry/access policies remain open.
- No staging/production changes, real-account deletion, signing/device acceptance or observation performed by this work segment.

## Guest mutation follow-up

`functions/account/mutation-guard.js`, `functions/public-web/accountless.js` and `functions/public-web/renderer.js` now transactionally re-read actual guest/registration links and deletion jobs before duplicate confirmation, resend, email-change, claim/profile, follow, manage-session exchange, manage email-change and post-Stripe personal-data writes. Tokens and messages commit together with the guarded mutation. Claims refuse another full account's already-linked guest, invalid expiry and ambiguous admission links; tickets are never selected by a shared name/email. Renderer transaction acceptance no longer depends on mutable callback state. Tests: 20 accountless/public-web/checkout units passed; ESLint passed. Added seven guest-deletion emulator cases; integrator owns their result.

Post-Stripe guard rejection does not automatically cancel/refund an already-created provider intent; existing provider reconciliation remains a gate. Rate-limit record hashes and provider/retention fields still require disposition inventory. No provider activation or real payment action occurred.

## Shared-conversation continuation

Backend protocol implemented in `functions/account/deletion.js` and `functions/messaging/service.js`:

- Original conversation becomes a sanitized authorized redirect (`redirectConversationId`, `migrationState`, surviving `participantIds` plus opaque former participant marker). It is retained for existing links. Destination remains locked with `migrationState: moving` until all pages complete. The integrator owns client/rules/index handling.
- Each 100-message page moves surviving records in place, preserving their IDs, contents, timestamps and numeric sequence/read boundaries; removed sender records are deleted. Recipient totals/unread counts are recomputed excluding removed messages using explicit recipient evidence. Unsupported ordering/group-recipient evidence requires review.
- Conversation, page and per-message checkpoints commit under the active deletion lease. A restart finds prepared aliases from the job, even though they no longer contain the deleting UID. Stale workers cannot commit pages. Sends and read updates transactionally follow bounded redirects and reject moving histories.
- Server-only `ConversationMigrationState` tracks prior ID namespaces so retries after redirect do not duplicate messages. Deleting another group participant scrubs existing aliases and migrates the current canonical record. Deleting a recorded group creator sets `ownerUnavailable`; it does not select another owner.
- Raw legacy redirect IDs, job links and idempotency namespaces remain potentially identifying. State records explicitly retain `subjectDeletionJobIds` and `retentionReviewStatus: pending`. Final disposition verification checks `retention-review:ConversationMigrationState:subjectDeletionJobIds`; a shared-conversation deletion pauses as `review_required` before Auth removal. There is no implicit retention approval or configuration bypass. Review runs after the resumable move so other participants' records can finish recovering.

Final targeted ESLint passed. Added `test/shared-conversation-deletion-emulator.test.js`: surviving message/read-boundary/old-ID retry behavior and a 205-message crash/page-resume/expired-lease takeover scenario (103 removed sender records, 102 preserved). Integrated emulator results belong in the main ledger.

Open gates: actual client/rules/index integration qualification, unsupported legacy group evidence resolution, exhaustive nested messaging/provider/audit disposition, a reviewed retention basis/expiry/access policy with audited operator resolution for redirects and retry namespace records, and real device/deep-link acceptance. Whole-conversation discovery still uses full enumeration; bounded message pages do not establish fully bounded account inventory.
