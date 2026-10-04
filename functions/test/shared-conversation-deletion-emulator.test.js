"use strict";
const test = require("node:test");
const assert = require("node:assert/strict");
const {randomUUID} = require("node:crypto");
if (!/^127\.0\.0\.1:\d+$/.test(process.env.FIRESTORE_EMULATOR_HOST || "")) throw Error("Local Firestore emulator required");
process.env.GCLOUD_PROJECT = "demo-attendus-admin";
process.env.FUNCTIONS_EMULATOR = "true";
const db = require("../firebase-admin-compat").firestore();
const {sendMessage, markRead} = require("../messaging/service");
const {migrateSharedConversation, removeSharedMessagingIdentity} = require("../account/deletion");
const {claimDeletion} = require("../account/deletion-lease");
const {key} = require("../events/roster");
const request = (uid, data) => ({auth: {uid, token: {firebase: {sign_in_provider: "password"}}}, data});
const send = (uid, id, requestId) => sendMessage(db, request(uid, {conversationId: id, requestId, content: requestId}));

async function fixture() {
  const suffix = randomUUID(); const ids = ["deleting", "reader", "writer"].map((name) => `${name}-${suffix}`);
  const ref = db.collection("Conversations").doc(`group-${suffix}`);
  await ref.set({participantIds: ids, participantInfo: Object.fromEntries(ids.map((uid) => [uid, {name: uid}])),
    createdBy: ids[0], isGroup: true, messagingVersion: 2, sequence: 0, receivedTotals: {}, readTotals: {}, readSequences: {}, unreadCounts: {}, lastMessage: ""});
  const job = db.collection("account_deletion_jobs").doc(ids[0]);
  return {ids, ref, job};
}

test("shared deletion preserves other messages and read boundaries, redirects old calls and deduplicates retries", async () => {
  const {ids: [gone, reader, writer], ref, job} = await fixture();
  const first = await send(gone, ref.id, "first-deleted");
  await markRead(db, request(reader, {conversationId: ref.id, lastMessageId: first.messageId}));
  const second = await send(writer, ref.id, "second-preserved");
  const third = await send(gone, ref.id, "third-deleted");
  const fourth = await send(reader, ref.id, "fourth-preserved");
  const lease = await claimDeletion(db, job, "fixture");
  await migrateSharedConversation(db, gone, ref.id, {job, lease});
  const alias = await ref.get(); const destination = db.collection("Conversations").doc(alias.get("redirectConversationId"));
  const current = await destination.get();
  assert.equal(alias.get("migrationState"), "complete");
  assert.equal(alias.get("participantIds").includes(gone), false);
  assert.equal(current.get("participantInfo")[gone], undefined);
  assert.equal(current.get("createdBy"), undefined);
  assert.equal(current.get("ownerUnavailable"), true);
  assert.equal(current.get("receivedTotals")[reader], 1);
  assert.equal(current.get("unreadCounts")[reader], 1);
  assert.equal(current.get("readSequences")[reader], 1);
  for (const id of [first.messageId, third.messageId]) assert.equal((await db.collection("Messages").doc(id).get()).exists, false);
  for (const id of [second.messageId, fourth.messageId]) assert.equal((await db.collection("Messages").doc(id).get()).get("conversationId"), destination.id);
  assert.equal((await send(writer, destination.id, "second-preserved")).messageId, second.messageId);
  const next = await send(writer, ref.id, "fifth-preserved");
  assert.equal(next.conversationId, destination.id);
  await markRead(db, request(reader, {conversationId: ref.id, lastMessageId: second.messageId}));
  assert.equal((await destination.get()).get("unreadCounts")[reader], 1);
  await assert.rejects(markRead(db, request(gone, {conversationId: ref.id, lastMessageId: second.messageId})), /unavailable/);
});

test("retained conversation aliases block Auth deletion until retention review", async () => {
  const {ids: [gone, , writer], ref, job} = await fixture();
  await send(writer, ref.id, "retention-survivor");
  let authDeleted = false;
  await assert.rejects(require("../account/deletion").runAccountDeletion({uid: gone, db,
    bucket: {getFiles: async () => [[]], file: () => ({delete: async () => {}})},
    auth: {deleteUser: async () => { authDeleted = true; }},
  }), {code: "deletion/review-required"});
  assert.equal(authDeleted, false);
  assert.equal((await job.get()).get("status"), "review_required");
  const alias = await ref.get();
  assert.equal(alias.get("migrationState"), "complete");
  assert.equal((await db.collection("Messages").where("conversationId", "==", alias.get("redirectConversationId")).get()).size, 1);
});

test("paged migration survives crash and lease takeover without losing other participants' records", async () => {
  const {ids: [gone, reader, writer], ref, job} = await fixture();
  const totals = {[gone]: 0, [reader]: 0, [writer]: 0};
  const batch = db.batch();
  for (let sequence = 1; sequence <= 205; sequence++) {
    const senderId = sequence % 2 ? gone : writer;
    const recipients = senderId === gone ? [reader, writer] : [gone, reader];
    for (const id of recipients) totals[id]++;
    batch.set(db.collection("Messages").doc(`${ref.id}-${sequence}`), {conversationId: ref.id, senderId, content: `message ${sequence}`,
      sequence, recipientTotals: {...totals}, notificationRecipients: recipients, readByUserIds: [senderId], timestamp: new Date(sequence * 1000)});
  }
  batch.update(ref, {sequence: 205, receivedTotals: totals, readSequences: {[reader]: 100}, readTotals: {[reader]: 100}});
  await batch.commit();
  const lease = await claimDeletion(db, job, "fixture"); let commits = 0;
  const crashing = {...lease, transaction: async (work) => {
    const value = await lease.transaction(work);
    if (++commits === 2) throw Error("simulated worker crash after committed page");
    return value;
  }};
  await assert.rejects(migrateSharedConversation(db, gone, ref.id, {job, lease: crashing}), /simulated worker crash/);
  assert.equal((await job.collection("conversations").doc(key(ref.id)).get()).get("processed"), 100);
  await assert.rejects(send(writer, ref.id, "during-migration"), {code: "unavailable"});
  await job.update({leaseUntil: new Date(0)});
  const replacement = await claimDeletion(db, job, "fixture");
  await assert.rejects(lease.checkpoint({phase: "stale"}), /replaced/);
  await removeSharedMessagingIdentity(db, gone, {job, lease: replacement});
  const checkpoint = await job.collection("conversations").doc(key(ref.id)).get();
  assert.equal(checkpoint.get("processed"), 205);
  assert.equal(checkpoint.get("removed"), 103);
  assert.equal(checkpoint.get("preserved"), 102);
  const destination = await db.collection("Conversations").doc(checkpoint.get("destinationConversationId")).get();
  assert.equal(destination.get("receivedTotals")[reader], 102);
  assert.equal(destination.get("readTotals")[reader], 50);
  assert.equal(destination.get("unreadCounts")[reader], 52);
  assert.equal((await db.collection("Messages").where("conversationId", "==", ref.id).get()).size, 0);
  assert.equal((await db.collection("Messages").where("conversationId", "==", destination.id).get()).size, 102);
});
