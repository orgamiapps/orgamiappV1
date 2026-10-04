"use strict";

const {createHash} = require("node:crypto");
const {FieldValue} = require("firebase-admin/firestore");
const {HttpsError} = require("firebase-functions/v2/https");

function caller(request) {
  if (!request.auth?.uid || request.auth.token?.firebase?.sign_in_provider === "anonymous") {
    throw new HttpsError("unauthenticated", "Sign in to use messages.");
  }
  return request.auth.uid;
}
function identifier(value) {
  if (typeof value !== "string" || !value || value.length > 300 || value.includes("/")) {
    throw new HttpsError("invalid-argument", "Invalid identifier.");
  }
  return value;
}
function member(data, uid) {
  if (!data || !Array.isArray(data.participantIds) || !data.participantIds.includes(uid) ||
      data.participantIds.length < 2 || data.participantIds.length > 100 ||
      new Set(data.participantIds).size !== data.participantIds.length ||
      data.participantIds.some((id) => typeof id !== "string" || !id || id.length > 300 || id.includes("/"))) {
    throw new HttpsError("permission-denied", "This conversation is unavailable.");
  }
}
const digest = (value) => createHash("sha256").update(value).digest("hex");
const profile = (doc) => ({name: doc.data()?.name || "User", username: doc.data()?.username || "",
  profilePictureUrl: doc.data()?.profilePictureUrl || null});

async function blocked(tx, db, a, b) {
  const refs = [db.doc(`Customers/${a}/blocks/${b}`), db.doc(`Customers/${b}/blocks/${a}`)];
  return (await tx.getAll(...refs)).some((doc) => doc.exists);
}

async function resolveConversation(tx, db, id, uid) {
  const seen = new Set();
  for (let depth = 0; depth < 8; depth++) {
    if (seen.has(id)) throw new HttpsError("failed-precondition", "Conversation redirect requires review.");
    seen.add(id);
    const conversation = await tx.get(db.collection("Conversations").doc(id));
    const data = conversation.data();
    member(data, uid);
    if (data.migrationState === "moving") throw new HttpsError("unavailable", "Conversation history is being updated. Please retry shortly.");
    if (!data.redirectConversationId) return conversation;
    id = identifier(data.redirectConversationId);
  }
  throw new HttpsError("failed-precondition", "Conversation redirect requires review.");
}

async function getOrCreateDirect(db, request) {
  const uid = caller(request);
  const other = identifier(request.data?.otherUserId);
  if (other === uid) throw new HttpsError("invalid-argument", "Choose another person.");
  const ids = [uid, other].sort();
  const ref = db.collection("Conversations").doc(ids.join("_"));
  await db.runTransaction(async (tx) => {
    await require("../account/mutation-guard").requireActiveAccounts(db, tx, ...ids);
    const doc = await tx.get(ref);
    if (doc.exists) {
      member(doc.data(), uid);
      if (doc.data().isGroup || doc.data().participantIds.length !== 2 || !doc.data().participantIds.includes(other)) {
        throw new HttpsError("failed-precondition", "Conversation identity conflict.");
      }
      return;
    }
    const people = await tx.getAll(...ids.map((id) => db.collection("Customers").doc(id)));
    if (people.some((person) => !person.exists) || await blocked(tx, db, uid, other)) {
      throw new HttpsError("permission-denied", "This person is unavailable.");
    }
    tx.create(ref, {participantIds: ids, participant1Id: ids[0], participant2Id: ids[1],
      participantInfo: Object.fromEntries(people.map((person) => [person.id, profile(person)])),
      isGroup: false, lastMessage: "", lastMessageTime: FieldValue.serverTimestamp(),
      messagingVersion: 2, sequence: 0, receivedTotals: {}, readTotals: {}, readSequences: {}, unreadCounts: {}});
  });
  return {conversationId: ref.id};
}

async function sendMessage(db, request) {
  const uid = caller(request);
  const conversationId = identifier(request.data?.conversationId);
  const requestId = identifier(request.data?.requestId);
  const content = request.data?.content;
  if (typeof content !== "string" || !content.trim() || content.length > 4000) {
    throw new HttpsError("invalid-argument", "Messages must contain 1–4000 characters.");
  }
  const text = content.trim();
  const rateRef = db.collection("service_rate_limits").doc(`messages_${digest(uid)}`);
  const result = await db.runTransaction(async (tx) => {
    const conversation = await resolveConversation(tx, db, conversationId, uid);
    const ref = conversation.ref;
    const lineage = await tx.get(db.collection("ConversationMigrationState").doc(ref.id));
    const ids = [...new Set([conversationId, ref.id, ...(lineage.get("legacyIds") || [])])];
    if (ids.length > 32) throw new HttpsError("failed-precondition", "Conversation history requires review.");
    const refs = ids.map((id) => db.collection("Messages").doc(digest(`${uid}\n${id}\n${requestId}`)));
    const [rate, deleting, ...previous] = await tx.getAll(rateRef, db.collection("account_deletion_jobs").doc(uid), ...refs);
    const existing = previous.find((doc) => doc.exists);
    const messageRef = db.collection("Messages").doc(digest(`${uid}\n${ref.id}\n${requestId}`));
    if (deleting.exists) throw new HttpsError("failed-precondition", "This account is being deleted.");
    const data = conversation.data();
    member(data, uid);
    if (data.formerParticipant && !data.isGroup) throw new HttpsError("failed-precondition", "This account is no longer available.");
    if (existing?.exists) {
      if (existing.data().content !== text) throw new HttpsError("already-exists", "Retry must use the same message.");
      if (existing.get("conversationId") !== ref.id || existing.get("senderId") !== uid || previous.filter((doc) => doc.exists).length !== 1) {
        throw new HttpsError("failed-precondition", "Message retry identity requires review.");
      }
      return {messageId: existing.id, conversationId: ref.id};
    }
    if (data.messagingVersion !== 2) throw new HttpsError("failed-precondition", "This conversation needs an upgrade. Please try again later.");
    const now = Date.now();
    const window = rate.data() || {};
    const count = now - (window.startedAt || 0) < 60000 ? (window.count || 0) : 0;
    if (count >= 60) throw new HttpsError("resource-exhausted", "Please wait before sending more messages.");
    const recipients = [];
    for (const id of data.participantIds.filter((id) => id !== uid)) {
      const former = data.formerParticipantIds ? data.formerParticipantIds.includes(id) : /^former_[a-f0-9]{20,24}$/.test(id);
      const unavailable = former || (await tx.get(db.collection("account_deletion_jobs").doc(id))).exists;
      if (unavailable) {
        if (!data.isGroup) throw new HttpsError("failed-precondition", "This account is no longer available.");
        continue;
      }
      const isBlocked = await blocked(tx, db, uid, id);
      if (isBlocked && !data.isGroup) throw new HttpsError("permission-denied", "This conversation is unavailable.");
      if (!isBlocked) recipients.push(id);
    }
    const totals = {...data.receivedTotals};
    const unread = {...data.unreadCounts};
    for (const id of recipients) {
      totals[id] = (totals[id] || 0) + 1;
      unread[id] = totals[id] - (data.readTotals?.[id] || 0);
    }
    const sequence = (data.sequence || 0) + 1;
    tx.create(messageRef, {conversationId: ref.id, senderId: uid,
      receiverId: data.isGroup ? null : data.participantIds.find((id) => id !== uid),
      content: text, messageType: "text", timestamp: FieldValue.serverTimestamp(),
      sequence, recipientTotals: totals, notificationRecipients: recipients, isRead: false,
      readByUserIds: [uid], messagingVersion: 2});
    tx.update(ref, {sequence, receivedTotals: totals, unreadCounts: unread,
      lastMessage: text, lastMessageTime: FieldValue.serverTimestamp(), lastMessageSenderId: uid});
    tx.set(rateRef, {startedAt: count ? window.startedAt : now, count: count + 1});
    return {messageId: messageRef.id, conversationId: ref.id};
  });
  return result;
}

async function markRead(db, request) {
  const uid = caller(request);
  const conversationId = identifier(request.data?.conversationId);
  const boundaryId = identifier(request.data?.lastMessageId);
  await db.runTransaction(async (tx) => {
    const conversation = await resolveConversation(tx, db, conversationId, uid);
    const ref = conversation.ref;
    const [boundary, deleting] = await tx.getAll(db.collection("Messages").doc(boundaryId), db.collection("account_deletion_jobs").doc(uid));
    if (deleting.exists) throw new HttpsError("failed-precondition", "This account is being deleted.");
    const data = conversation.data();
    member(data, uid);
    const message = boundary.data();
    if (!message || message.conversationId !== ref.id || !Number.isInteger(message.sequence)) {
      throw new HttpsError("invalid-argument", "Invalid read boundary.");
    }
    if (message.sequence <= (data.readSequences?.[uid] || 0)) return;
    const total = Math.max(data.readTotals?.[uid] || 0, message.recipientTotals?.[uid] || 0);
    tx.update(ref, {readTotals: {...data.readTotals, [uid]: total},
      readSequences: {...data.readSequences, [uid]: message.sequence},
      unreadCounts: {...data.unreadCounts, [uid]: Math.max(0, (data.receivedTotals?.[uid] || 0) - total)}});
  });
  return {ok: true};
}

module.exports = {caller, identifier, member, getOrCreateDirect, sendMessage, markRead, digest, resolveConversation};
