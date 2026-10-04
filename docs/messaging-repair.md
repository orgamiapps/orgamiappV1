# Messaging repair — 2026-09-26

## Contract

The inbox uses `Conversations.participantIds array-contains currentUid`, ordered by `lastMessageTime DESC`. History uses `Messages.conversationId == id`, ordered by `timestamp ASC`. Both collection-scoped composites are declared and checked by `tools/check_firestore_query_contracts.js`. Legacy participant1/participant2 queries are removed: they cannot satisfy participantIds-based authorization.

Authenticated, non-anonymous callable operations in `functions/messaging/service.js`:

- `getOrCreateDirectConversationV2({otherUserId})` returns `{conversationId}`. A transaction creates only missing conversations, validates existing membership/identity, and preserves existing metadata.
- `sendConversationMessageV2({conversationId, requestId, content})` returns `{messageId}`. Content is trimmed and limited to 4000 characters. A stable request ID deduplicates uncertain retries; reusing it with different content fails. Sender identity comes exclusively from Auth. A transaction writes the message, preview, sequence, recipient totals, and per-user unread counts. Per-sender limit: 60 new messages/minute. Direct blocks prevent sends; group blocks exclude recipients from unread increments and notifications.
- `markConversationReadV2({conversationId, lastMessageId})` advances that user's read watermark to the displayed snapshot boundary. Later messages remain unread; stale calls cannot move the watermark backward.

New fields are additive: conversations have `messagingVersion: 2`, `sequence`, `receivedTotals`, `readTotals`, `readSequences`, and `unreadCounts`; messages have `sequence` and `recipientTotals`. The client reads its own unread count. Existing document IDs and top-level collections remain unchanged. Group creation initializes empty counters; all message writes and conversation counters/previews are server-owned. Clients may update group name/avatar only.

`MessagingFeed` owns listener cancellation, async setup generations, timeout, retries, and account clearing. Recoverable errors retain loaded content. Authorization errors clear it. Empty cache-only snapshots do not masquerade as confirmed empty inboxes. Parse errors propagate to an explicit error state. Draft text/request IDs survive failed sends within the open chat.

## Notifications

The existing `sendMessageNotifications` export handles direct and group delivery, preferences, mentions, blocks, and the stored conversation ID. The old mention trigger is retained as a no-op during rollout. Clients no longer read other users' push tokens or enqueue duplicate push requests. Each recipient has a deterministic notification record and a durable dispatch claim. FCM delivery interrupted after dispatch remains `dispatching`/`unknown`; it is not automatically repeated, because FCM does not provide exactly-once delivery. In-app notifications remain available without a push token.

Mobile taps and in-app notifications open the chat; web pushes link to `?conversationId=...`, consumed after authentication. The placeholder VAPID key is removed. A deployment can supply `ATTENDUS_WEB_PUSH_VAPID_KEY`; otherwise the Firebase SDK default is used. Real-device push permission/provider acceptance is a separate check from message storage and delivery.

## Migration and release

Run `node functions/tools/migrate-messaging-v2.js --project orgami-66nxok` for inventory only. The production inventory before this release contained 3 conversations and 29 messages. Nine historical messages had no parent conversation and a missing recipient profile. They must be retained unchanged, never assigned guessed membership or deleted.

Apply requires server-owned write rules to be deployed first, plus `--apply --writes-frozen --backup <absolute-new-file> --preserve-orphans`. The backup contains private message data and must stay outside version control. The script upgrades identifiable conversations, uses original message timestamps or document creation timestamps, preserves content/IDs, and reports orphan records. It is resumable per conversation; messages can be patched in bounded batches while the conversation remains version 1. Version 2 sends cannot race incomplete upgrades. Rerun inventory to verify no identifiable conversations remain pending.

Release order: create composites and verify READY; deploy the three callable functions and the two notification exports; deploy messaging rules; migrate known conversations; run authenticated canary; publish the tested immutable web build; verify desktop/mobile-width UI and live hashes. Only named functions are deployed. The workspace already contained unrelated local changes; they were preserved.

`functions/tools/messaging-canary.js` uses three dedicated QA accounts and requires explicit project, mode, and an absolute private fixture file. Setup saves credentials locally; exercise uses Firebase client authentication and rules plus the deployed callables (not Admin writes for messages); cleanup verifies QA-only conversation membership, removes the test conversations/messages/profiles/auth accounts, and deletes the credential fixture. Never use real users for this test.

Rollback evidence is stored in ignored `dist/messaging-release-20260926/`: prior Hosting version metadata, exact live rules, and the prior notification-function source ZIP. Hosting rollback must be paired with compatible rules/backend; keep new message data and additive migration fields. Do not restore the data backup over newer messages. The old release has the original messaging defects, so rollback restores the previous baseline rather than certifying messaging functionality.

## Validation

- Firestore transaction/security suite: 30 passing tests, including creation races, retry deduplication, read/send races, blocks, notification claims/preferences, migration, and participant-only rules.
- Backend unit suite: 105 passing tests.
- Full Flutter suite: 171 passing tests, including feed/model and pending conversation-link coverage.
- Query/index/function-manifest unit checks: 8 passing tests.
- ESLint and full Flutter analysis passed for the core repair. Final link changes passed scoped Dart analysis with no issues. Two redundant whole-workspace analysis runs were stopped after producing no output; the complete final Flutter test suite and production build passed.

Initial harness errors from the modular Firebase Admin SDK and fake-async stream cleanup were corrected before the passing runs. The first Functions deployment required explicit retry-policy acknowledgement (`--force`); this is scoped to the idempotent notification trigger, not function deletion.

## Production acceptance

Production release `5ee4993e2032b14ed7d01ec8dd4df8e03b76ca33d9f477e75550d6e8739d1c4a` was built once, uploaded to the named preview channel, then cloned to live. Its main JavaScript SHA-256 is `ebe338a051b31de59e6b82be69f08181113e7f1d245040609f0ad236ab4d7032`. Both attendus.app and orgami-66nxok.web.app served that hash; all 330 retained/current immutable assets passed verification. Initial bundle: 1.096 MB gzip, below the 1.800 MB limit. Source hashes and prior rollback artifacts are in the ignored evidence directory.

Authenticated QA confirmed: empty inbox; direct first send; idempotent retry; participant-only history; outsider denial; read watermark; incoming live reply; three-person group creation/send. Production browser checks on desktop and 390px mobile width confirmed inbox, existing chat send, live incoming reply without reload, unread clearing, new conversation's first message, and group history. The notification-style web URL initially returned Home; startup now captures it before routing and stores a validated pending-auth intent, opening the deferred conversation after auth restoration. Signed-in live deep-link acceptance passed. A signed-out link also resumed the intended chat after real UI login; initial automated fill attempts failed, and native keyboard entry succeeded.

Preview-domain sign-in was rejected by reCAPTCHA domain restrictions; these protections were left intact. Authenticated acceptance used the approved production domain with dedicated disposable QA accounts. Real iPhone Safari and actual device push delivery remain unverified; responsive Chromium and server notification tests do not substitute for those checks. Nine original orphan messages remain preserved and quarantined from guessed membership.

Final cleanup removed three QA accounts, three QA-only conversations and their messages/subcollections, and the private credential fixture. Post-cleanup inventory is exactly 3 original conversations and 29 original messages, with zero pending upgrades. A direct comparison against the private pre-migration backup verified all 29 original IDs/content/timestamps/sender/receiver fields and all 9 orphan documents unchanged. `final-data-preservation.json` records the assertions; screenshots record desktop/mobile chat, groups, and the linked chat after sign-in.
