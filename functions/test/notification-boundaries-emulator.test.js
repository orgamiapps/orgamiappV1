"use strict";
const test = require("node:test");
const assert = require("node:assert/strict");
const {randomUUID} = require("node:crypto");
if (!/^127\.0\.0\.1:\d+$/.test(process.env.FIRESTORE_EMULATOR_HOST || "")) throw Error("Local emulator required");
process.env.GCLOUD_PROJECT = "demo-attendus-admin";
process.env.FUNCTIONS_EMULATOR = "true";
const admin = require("../firebase-admin-compat");
const db = admin.firestore();
const {createAdminDispatchHandlers} = require("../notifications/admin-dispatch");
const {createPushTokenOperations} = require("../notifications/push-tokens");
const {reconcileReminder, reminderDocumentId, reminderInboxId, runScheduledWorker} = require("../notifications/scheduled-reminders");
const suffix = randomUUID();
test.after(async () => db.terminate());

test("admin push respects ownership/deletion, binds payload and carries recipient identity", async () => {
  const actor = `admin-${suffix}`, uid = `recipient-${suffix}`, deleted = `deleted-${suffix}`;
  await db.doc(`admin_roles/${actor}`).set({roles: ["support"], active: true});
  await db.doc(`users/${deleted}`).set({fcmToken: "stale-token-deleted"});
  await db.doc(`account_deletion_jobs/${deleted}`).set({status: "processing"});
  await createPushTokenOperations(admin).registerPushTokenV1.run({auth: {uid, token: {}}, data: {
    expectedUid: uid, token: `token-${suffix}`, installationId: `install-${suffix}`, generation: 1,
  }});
  const sent = [];
  const fakeAdmin = {firestore: admin.firestore, messaging: () => ({sendEach: async (messages) => {
    sent.push(...messages); return {successCount: messages.length, failureCount: 0};
  }})};
  const handler = createAdminDispatchHandlers({admin: fakeAdmin}).sendCustomNotifications;
  const req = {app: {}, auth: {uid: actor, token: {admin: true}}, data: {
    confirmation: true, reason: "Local notification regression", idempotencyKey: `dispatch-${suffix}`,
    title: "Fixture", body: "Local only", userIds: [uid, deleted, `missing-${suffix}`], data: {recipientUid: "spoof"},
  }};
  const first = await handler(req);
  assert.equal(first.recipientCount, 1);
  assert.equal(sent.length, 1);
  assert.equal(sent[0].data.recipientUid, uid);
  assert.deepEqual(await handler(req), first);
  assert.equal(sent.length, 1);
  await assert.rejects(handler({...req, data: {...req.data, body: "Different"}}), {code: "failed-precondition"});
  assert.equal((await db.collection(`users/${deleted}/notifications`).get()).size, 0);
});

test("reminder worker preserves read state and never replays an uncertain provider handoff", async () => {
  const uid = `reminder-${suffix}`, eventId = `reminder-event-${suffix}`;
  const now = new Date();
  await db.doc(`users/${uid}`).set({});
  await db.doc(`Events/${eventId}`).set({customerUid: uid, title: "Reminder", status: "active", private: false,
    selectedDateTime: admin.firestore.Timestamp.fromMillis(now.getTime() + 60 * 60 * 1000)});
  await reconcileReminder(admin, eventId, uid, now);
  const ref = db.doc(`scheduledNotifications/${reminderDocumentId(eventId, uid)}`);
  await ref.update({deliveryState: "processing", claimId: "crashed", pushDispatching: true,
    leaseUntil: admin.firestore.Timestamp.fromMillis(now.getTime() - 1)});
  let sends = 0;
  const fakeAdmin = {firestore: admin.firestore, messaging: () => ({send: async () => { sends++; }})};
  await runScheduledWorker(fakeAdmin, now);
  assert.equal((await ref.get()).get("deliveryState"), "unknown");
  await reconcileReminder(admin, eventId, uid, now);
  assert.equal((await ref.get()).get("deliveryState"), "unknown");
  assert.equal(sends, 0);
  await ref.update({deliveryState: "processing", claimId: "before-handoff", pushDispatching: false,
    leaseUntil: admin.firestore.Timestamp.fromMillis(now.getTime() - 1)});
  const inbox = db.doc(`users/${uid}/notifications/${reminderInboxId(ref.id, (await ref.get()).get("eventTime"))}`);
  await inbox.set({isRead: true, body: "Existing"});
  await runScheduledWorker(fakeAdmin, now);
  assert.equal((await ref.get()).get("deliveryState"), "in_app_only");
  assert.equal((await inbox.get()).get("isRead"), true);
  assert.equal(sends, 0);
});

test("lost reminder acknowledgement is terminal and late completion cannot overwrite a reschedule", async () => {
  const uid = `handoff-${suffix}`, eventId = `handoff-event-${suffix}`;
  const now = new Date();
  await createPushTokenOperations(admin).registerPushTokenV1.run({auth: {uid, token: {}}, data: {
    expectedUid: uid, token: `handoff-token-${suffix}`, installationId: `handoff-install-${suffix}`, generation: 1,
  }});
  const event = db.doc(`Events/${eventId}`);
  await event.set({customerUid: uid, title: "Handoff", status: "active", private: false,
    selectedDateTime: admin.firestore.Timestamp.fromMillis(now.getTime() + 60 * 60 * 1000)});
  await reconcileReminder(admin, eventId, uid, now);
  let sends = 0;
  const unknownAdmin = {firestore: admin.firestore, messaging: () => ({send: async (payload) => {
    sends++;
    assert.equal(payload.data.recipientUid, uid);
    throw Object.assign(Error("lost acknowledgement"), {code: "app/network-error"});
  }})};
  await runScheduledWorker(unknownAdmin, now);
  const queue = db.doc(`scheduledNotifications/${reminderDocumentId(eventId, uid)}`);
  assert.equal((await queue.get()).get("deliveryState"), "unknown");
  await runScheduledWorker(unknownAdmin, now);
  assert.equal(sends, 1);
  const changed = new Date(now.getTime() + 60 * 60 * 1000 + 1000);
  await event.update({selectedDateTime: admin.firestore.Timestamp.fromDate(changed)});
  await reconcileReminder(admin, eventId, uid, now);
  const laterNow = new Date(now.getTime() + 1000);
  const lateAdmin = {firestore: admin.firestore, messaging: () => ({send: async () => {
    sends++;
    await event.update({selectedDateTime: admin.firestore.Timestamp.fromMillis(now.getTime() + 3 * 60 * 60 * 1000)});
    await reconcileReminder(admin, eventId, uid, laterNow);
    return "accepted-before-reschedule";
  }})};
  await runScheduledWorker(lateAdmin, laterNow);
  assert.equal(sends, 2);
  assert.equal((await queue.get()).get("deliveryState"), "pending");
  assert.equal((await queue.get()).get("claimId"), null);
});
