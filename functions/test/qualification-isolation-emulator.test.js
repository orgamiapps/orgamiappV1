"use strict";
const test = require("node:test"), assert = require("node:assert/strict"), {randomUUID} = require("node:crypto");
if (!/^127\.0\.0\.1:\d+$/.test(process.env.FIRESTORE_EMULATOR_HOST || "")) throw Error("Local emulator required");
process.env.GCLOUD_PROJECT = "demo-attendus-admin";
const admin = require("../firebase-admin-compat"), db = admin.firestore();
const {bindingId, interceptQualification} = require("../communications/qualification-isolation");
const {createLegacyNotificationSender} = require("../notifications/legacy-delivery");
const {deliverMessageNotifications} = require("../messaging/notifications");
const {processMessage} = require("../communications/delivery");
test.after(async () => db.terminate());
test("actual transactions capture overlap once and staging suppresses unscoped or expired fixtures before inbox/provider", async (t) => {
  const suffix = randomUUID(), runId = `qa-${suffix}`, actor = `actor-${suffix}`, uid = `qa-${suffix}`, eventId = `event-${suffix}`, conversationId = `conversation-${suffix}`;
  const saved = {GCLOUD_PROJECT: process.env.GCLOUD_PROJECT, GOOGLE_CLOUD_PROJECT: process.env.GOOGLE_CLOUD_PROJECT};
  process.env.GCLOUD_PROJECT = "attendus-staging"; delete process.env.GOOGLE_CLOUD_PROJECT;
  t.after(() => { for (const [key, value] of Object.entries(saved)) { if (value === undefined) delete process.env[key]; else process.env[key] = value; } });
  const scope = db.doc(`QualificationScopes/${runId}`);
  await scope.set({schemaVersion: 1, projectId: "attendus-staging", status: "active", mode: "capture", createdAt: new Date(Date.now() - 1000), expiresAt: new Date(Date.now() + 60000),
    actorUids: [actor], recipientUids: [uid], eventIds: [eventId], organizationIds: [], conversationIds: [conversationId], recipientEmailHashes: []});
  for (const [kind, id] of [["event", eventId], ["account", uid], ["conversation", conversationId]]) {
    await db.doc(`QualificationBindings/${bindingId(kind, id)}`).set({schemaVersion: 1, projectId: "attendus-staging", runId, state: "bound"});
  }
  let sends = 0; const messaging = {send: async () => { sends++; throw Error("Provider must not run"); }};
  const sender = createLegacyNotificationSender({firestore: admin.firestore, messaging: () => messaging});
  const payload = {title: "Fixture", body: "Fixture only", actorUid: actor, eventId, type: "new_event"};
  await Promise.all([sender(uid, payload, db, `source-${suffix}`), sender(uid, payload, db, `source-${suffix}`)]);
  assert.equal((await db.collection("QualificationCaptures").where("runId", "==", runId).get()).size, 1);
  await db.doc(`Conversations/${conversationId}`).set({participantIds: [actor, uid]});
  await db.doc(`users/${uid}`).set({fcmToken: "must-not-send"});
  const message = db.doc(`Messages/message-${suffix}`);
  await message.set({conversationId, senderId: actor, content: "Controlled message", notificationRecipients: [uid]});
  await deliverMessageNotifications(db, messaging, {data: await message.get()});
  assert.equal((await db.collection("QualificationCaptures").where("runId", "==", runId).get()).size, 2);
  assert.equal((await db.collection(`users/${uid}/notifications`).get()).size, 0);
  await scope.delete();
  assert.equal((await sender(uid, payload, db, `later-${suffix}`)).status, "qualification_suppress");
  assert.equal((await interceptQualification(db, {recipientUid: uid}, "expired", {body: "hidden"})).mode, "suppress");
  const outbound = db.doc(`OutboundMessages/unscoped-${suffix}`);
  // Invalid encrypted content proves suppression occurs before KMS/provider IO.
  await outbound.set({ownerUid: `unscoped-${suffix}`, status: "pending", channel: "email", encryptedEmail: "must-not-decrypt"});
  await processMessage(admin, outbound);
  assert.equal((await outbound.get()).get("status"), "suppressed");
  assert.equal(sends, 0);
  assert.equal((await db.collection(`users/${uid}/notifications`).get()).size, 0);
});
