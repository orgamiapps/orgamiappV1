"use strict";

const test = require("node:test");
const assert = require("node:assert/strict");
const {initializeApp, deleteApp, getApp} = require("firebase-admin/app");
const {getFirestore, Timestamp} = require("firebase-admin/firestore");
const {getOrCreateDirect, sendMessage, markRead} = require("../messaging/service");
const {deliverMessageNotifications} = require("../messaging/notifications");
const {planConversation} = require("../messaging/migration");

let db;
const request = (uid, data) => ({auth: {uid, token: {firebase: {sign_in_provider: "password"}}}, data});
test.before(() => {
  assert.match(process.env.FIRESTORE_EMULATOR_HOST || "", /^(localhost|127\.0\.0\.1):\d+$/);
  process.env.GCLOUD_PROJECT = "demo-attendus-admin";
  process.env.FUNCTIONS_EMULATOR = "true";
  db = getFirestore(initializeApp({projectId: "demo-attendus-admin"}, "messaging-tests"));
});
test.beforeEach(async () => {
  await fetch(`http://${process.env.FIRESTORE_EMULATOR_HOST}/emulator/v1/projects/demo-attendus-admin/databases/(default)/documents`, {method: "DELETE"});
  for (const uid of ["a", "b", "c"]) await db.doc(`Customers/${uid}`).set({name: uid, username: uid, isDiscoverable: true});
});
test.after(async () => { await db.terminate(); await deleteApp(getApp("messaging-tests")); });
async function bindToken(uid) {
  const {tokenHash} = require("../notifications/push-tokens");
  const token = `token-${uid}`;
  const installationHash = tokenHash(`installation-${uid}`);
  await db.doc(`users/${uid}`).set({fcmToken: token});
  await db.doc(`PushTokenBindings/${tokenHash(token)}`).set({ownerUid: uid, installationHash, generation: 1, status: "active"});
  await db.doc(`PushInstallations/${installationHash}`).set({ownerUid: uid, tokenHash: tokenHash(token), generation: 1, operation: "register", invalidated: false});
}
const direct = async () => (await getOrCreateDirect(db, request("a", {otherUserId: "b"}))).conversationId;
const send = (uid, conversationId, requestId, content = "hello") => sendMessage(db, request(uid, {conversationId, requestId, content}));

test("authentication, missing users and self conversations fail", async () => {
  await assert.rejects(getOrCreateDirect(db, {data: {otherUserId: "b"}}), {code: "unauthenticated"});
  const anonymous = request("a", {otherUserId: "b"});
  anonymous.auth.token.firebase.sign_in_provider = "anonymous";
  await assert.rejects(getOrCreateDirect(db, anonymous), {code: "unauthenticated"});
  await assert.rejects(getOrCreateDirect(db, request("a", {otherUserId: "a"})), {code: "invalid-argument"});
  await assert.rejects(getOrCreateDirect(db, request("a", {otherUserId: "missing"})), {code: "permission-denied"});
});

test("concurrent creation preserves one conversation and its existing preview", async () => {
  const results = await Promise.all([direct(), direct(), getOrCreateDirect(db, request("b", {otherUserId: "a"}))]);
  assert.equal(results[0], results[1]);
  assert.equal(results[0], results[2].conversationId);
  await send("a", results[0], "first");
  await direct();
  assert.equal((await db.doc(`Conversations/${results[0]}`).get()).data().lastMessage, "hello");
});

test("first send is atomic and uncertain retries cannot duplicate or change content", async () => {
  const id = await direct();
  const results = await Promise.all([send("a", id, "retry"), send("a", id, "retry")]);
  assert.equal(results[0].messageId, results[1].messageId);
  assert.equal((await db.collection("Messages").get()).size, 1);
  const conversation = (await db.doc(`Conversations/${id}`).get()).data();
  assert.equal(conversation.sequence, 1);
  assert.equal(conversation.unreadCounts.b, 1);
  assert.equal(conversation.unreadCounts.a || 0, 0);
  await assert.rejects(send("a", id, "retry", "different"), {code: "already-exists"});
  await assert.rejects(send("c", id, "intruder"), {code: "permission-denied"});
  await assert.rejects(send("a", id, "oversize", "x".repeat(4001)), {code: "invalid-argument"});
});

test("reading an earlier boundary preserves concurrent later arrivals", async () => {
  const id = await direct();
  const first = await send("a", id, "first");
  await Promise.all([send("a", id, "second"), markRead(db, request("b", {conversationId: id, lastMessageId: first.messageId}))]);
  let conversation = (await db.doc(`Conversations/${id}`).get()).data();
  assert.equal(conversation.unreadCounts.b, 1);
  const last = await send("a", id, "second");
  await markRead(db, request("b", {conversationId: id, lastMessageId: last.messageId}));
  await markRead(db, request("b", {conversationId: id, lastMessageId: first.messageId}));
  conversation = (await db.doc(`Conversations/${id}`).get()).data();
  assert.equal(conversation.unreadCounts.b, 0);
  assert.equal(conversation.readSequences.b, 2);
  await assert.rejects(markRead(db, request("c", {conversationId: id, lastMessageId: first.messageId})), {code: "permission-denied"});
});

test("blocks prevent direct sends and group recipients do not gain unread counts", async () => {
  const id = await direct();
  await db.doc("Customers/b/blocks/a").set({});
  await assert.rejects(send("a", id, "blocked"), {code: "permission-denied"});
  const data = (await db.doc(`Conversations/${id}`).get()).data();
  await db.doc("Conversations/group").set({...data, participantIds: ["a", "b", "c"], isGroup: true});
  const message = await send("a", "group", "group-first");
  const conversation = (await db.doc("Conversations/group").get()).data();
  assert.equal(conversation.unreadCounts.c, 1);
  assert.equal(conversation.unreadCounts.b || 0, 0);
  assert.deepEqual((await db.doc(`Messages/${message.messageId}`).get()).data().notificationRecipients, ["c"]);
});

test("rate limit rejects new sends but still permits idempotent retries", async () => {
  const id = await direct();
  await send("a", id, "existing");
  const ref = (await db.collection("service_rate_limits").get()).docs[0].ref;
  await ref.update({count: 60});
  await assert.rejects(send("a", id, "new"), {code: "resource-exhausted"});
  await send("a", id, "existing");
});

test("notification fanout uses stored group ID and claims each recipient once", async () => {
  const id = await direct();
  const data = (await db.doc(`Conversations/${id}`).get()).data();
  await db.doc("Conversations/group-alpha").set({...data, participantIds: ["a", "b", "c"], isGroup: true});
  for (const uid of ["b", "c"]) await bindToken(uid);
  const result = await send("a", "group-alpha", "notify");
  const event = {data: await db.doc(`Messages/${result.messageId}`).get()};
  const sent = [];
  const messaging = {send: async (payload) => sent.push(payload)};
  await Promise.all([deliverMessageNotifications(db, messaging, event), deliverMessageNotifications(db, messaging, event)]);
  assert.equal(sent.length, 2);
  assert.ok(sent.every((payload) => payload.data.conversationId === "group-alpha"));
  assert.equal((await db.collection("users/b/notifications").get()).size, 1);
});

test("notifications honor missing modern settings, mentions and later blocks", async () => {
  const id = await direct();
  await bindToken("b");
  await db.doc("users/b/settings/notifications").set({messagesAll: false, messageMentions: true});
  const sent = [];
  const messaging = {send: async (payload) => sent.push(payload)};
  for (const [key, content] of [["normal", "hello"], ["mention", "hello @b"]]) {
    const result = await send("a", id, key, content);
    await deliverMessageNotifications(db, messaging, {data: await db.doc(`Messages/${result.messageId}`).get()});
  }
  assert.equal(sent.length, 1);
  assert.equal(sent[0].data.type, "message_mention");
  const result = await send("a", id, "late", "@b");
  await db.doc("Customers/b/blocks/a").set({});
  await deliverMessageNotifications(db, messaging, {data: await db.doc(`Messages/${result.messageId}`).get()});
  assert.equal(sent.length, 1);
});

test("migration preserves IDs, timestamps and unread boundaries; rejects ambiguous membership", () => {
  const timestamp = Timestamp.fromMillis(1000);
  const messages = [
    {id: "old", data: {senderId: "a", receiverId: "b", content: "read", isRead: true}, createdAt: timestamp},
    {id: "new", data: {senderId: "a", receiverId: "b", content: "unread", timestamp: Timestamp.fromMillis(2000)}, createdAt: timestamp},
  ];
  const plan = planConversation("a_b", {participant1Id: "a", participant2Id: "b"}, messages, timestamp);
  assert.equal(plan.conversation.unreadCounts.b, 1);
  assert.equal(plan.conversation.readSequences.b, 1);
  assert.equal(plan.messages[0].id, "old");
  assert.equal(plan.messages[1].patch.recipientTotals.b, 2);
  assert.equal(planConversation("a_b", plan.conversation, messages, timestamp), null);
  assert.throws(() => planConversation("x", {participantIds: ["a", "c"], participant2Id: "b"}, [], timestamp), /ambiguous/);
});


test("notification delivery suppresses rebound tokens and deleted recipients", async () => {
  const id = await direct();
  await bindToken("b");
  const {tokenHash} = require("../notifications/push-tokens");
  await db.doc(`PushTokenBindings/${tokenHash("token-b")}`).update({ownerUid: "c"});
  const sent = [];
  const messaging = {send: async (payload) => sent.push(payload)};
  const first = await send("a", id, "rebound");
  await deliverMessageNotifications(db, messaging, {data: await db.doc(`Messages/${first.messageId}`).get()});
  assert.equal(sent.length, 0);
  assert.equal((await db.collection("users/b/notifications").get()).size, 1);
  const second = await send("a", id, "deleted");
  await db.doc("account_deletion_jobs/b").set({status: "processing"});
  await deliverMessageNotifications(db, messaging, {data: await db.doc(`Messages/${second.messageId}`).get()});
  assert.equal(sent.length, 0);
  assert.equal((await db.collection("users/b/notifications").get()).size, 1);
});
