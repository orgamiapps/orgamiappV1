"use strict";
// Actual delivery handler with in-memory Firestore and an injected provider.
// No Admin app, network client, emulator process or external send is created.
const test = require("node:test");
const assert = require("node:assert/strict");
const {memoryAdmin} = require("./helpers/community-memory");
const {deliverMessageNotifications} = require("../messaging/notifications");
const {tokenHash} = require("../notifications/push-tokens");

const environment = {GCLOUD_PROJECT: "demo-attendus-admin", GOOGLE_CLOUD_PROJECT: "demo-attendus-admin",
  FUNCTIONS_EMULATOR: "true", FIRESTORE_EMULATOR_HOST: "127.0.0.1:1"};
const previous = Object.fromEntries(Object.keys(environment).map((key) => [key, process.env[key]]));
test.before(() => Object.assign(process.env, environment));
test.after(() => {
  for (const [key, value] of Object.entries(previous)) {
    if (value === undefined) delete process.env[key]; else process.env[key] = value;
  }
});

function fixture({canonical, legacy, customer} = {}) {
  const token = "injected-recipient-token";
  const installationHash = tokenHash("injected-installation");
  const initial = {
    "Conversations/sender_recipient": {participantIds: ["sender", "recipient"], isGroup: false},
    "Customers/sender": {name: "Controlled sender"},
    "Customers/recipient": {name: "Controlled recipient", username: "recipient"},
    "users/recipient": {fcmToken: token},
    [`PushTokenBindings/${tokenHash(token)}`]: {ownerUid: "recipient", installationHash, generation: 1, status: "active"},
    [`PushInstallations/${installationHash}`]: {ownerUid: "recipient", tokenHash: tokenHash(token), generation: 1, operation: "register", invalidated: false},
  };
  if (customer !== undefined) initial["Customers/recipient"].notificationPreferences = customer;
  if (canonical !== undefined) initial["users/recipient/settings/notifications"] = canonical;
  if (legacy !== undefined) initial["users/recipient/notificationSettings/settings"] = legacy;
  const {db} = memoryAdmin(initial);
  const document = db.doc;
  const collection = db.collection;
  // Supply the same small reference APIs the real handler uses. Writes remain
  // buffered in memory; this adapter has no connection or credentials.
  const ref = (name) => ({...document(name), collection: (child) => col(`${name}/${child}`),
    update: (data) => db.runTransaction(async (tx) => { tx.update(document(name), data); })});
  const col = (name) => ({...collection(name), doc: (id) => ref(`${name}/${id}`)});
  db.doc = ref;
  db.collection = col;
  db.getAll = (...refs) => Promise.all(refs.map((item) => item.get()));
  const sent = [];
  const messaging = {send: async (payload) => { sent.push(payload); return "injected-message-id"; }};
  const deliver = async (id, content = "Controlled ordinary message") => {
    db.values.set(`Messages/${id}`, {conversationId: "sender_recipient", senderId: "sender", receiverId: "recipient",
      notificationRecipients: ["recipient"], content});
    await deliverMessageNotifications(db, messaging, {data: await db.doc(`Messages/${id}`).get()});
  };
  const inbox = () => [...db.values.entries()].filter(([key]) => key.startsWith("users/recipient/notifications/")).map(([, value]) => value);
  return {db, sent, deliver, inbox};
}

test("canonical message opt-out overrides an older enabled document before inbox or provider delivery", async () => {
  const f = fixture({canonical: {messagesAll: false, messageMentions: false}, legacy: {messagesAll: true}});
  await f.deliver("conflicting-normal");
  assert.equal(f.inbox().length, 0);
  assert.equal(f.sent.length, 0);
  await f.deliver("conflicting-mention", "Controlled @recipient mention");
  assert.equal(f.inbox().length, 0);
  assert.equal(f.sent.length, 0);
});

test("canonical opt-in overrides older opt-out and existing trigger replay stays idempotent", async () => {
  const f = fixture({canonical: {messagesAll: true}, legacy: {messagesAll: false, messageMentions: false}});
  await f.deliver("canonical-enabled");
  await f.deliver("canonical-enabled");
  assert.equal(f.inbox().length, 1);
  assert.equal(f.sent.length, 1);
  assert.equal(f.sent[0].data.recipientUid, "recipient");
  assert.equal(f.sent[0].data.type, "new_message");
});

test("canonical mentions-only preference wins and preserves mention delivery", async () => {
  const f = fixture({canonical: {messagesAll: false, messageMentions: true}, legacy: {messagesAll: true}});
  await f.deliver("ordinary");
  assert.equal(f.sent.length, 0);
  await f.deliver("mention", "Controlled @recipient mention");
  assert.equal(f.sent.length, 1);
  assert.equal(f.sent[0].data.type, "message_mention");
  assert.equal(f.inbox().length, 1);
});

test("canonical compatibility opt-out alias is respected despite older enabled settings", async () => {
  const f = fixture({canonical: {messageNotifications: false, messageMentions: false}, legacy: {messagesAll: true}});
  await f.deliver("compatibility-opt-out");
  assert.equal(f.inbox().length, 0);
  assert.equal(f.sent.length, 0);
});

test("an existing canonical document uses its own defaults without merging stale legacy opt-outs", async () => {
  const f = fixture({canonical: {}, legacy: {messagesAll: false, messageMentions: false}});
  await f.deliver("canonical-default");
  assert.equal(f.inbox().length, 1);
  assert.equal(f.sent.length, 1);
});

test("legacy settings remain the fallback only when the canonical document is absent", async () => {
  const disabled = fixture({legacy: {messagesAll: false, messageMentions: false}});
  await disabled.deliver("legacy-disabled");
  assert.equal(disabled.inbox().length, 0);
  assert.equal(disabled.sent.length, 0);
  const enabled = fixture({legacy: {messagesAll: true}});
  await enabled.deliver("legacy-enabled");
  assert.equal(enabled.inbox().length, 1);
  assert.equal(enabled.sent.length, 1);
});

test("missing settings preserve the existing default without modifying preference documents", async () => {
  const f = fixture();
  await f.deliver("no-settings");
  assert.equal(f.inbox().length, 1);
  assert.equal(f.sent.length, 1);
  assert.equal(f.db.values.has("users/recipient/settings/notifications"), false);
  assert.equal(f.db.values.has("users/recipient/notificationSettings/settings"), false);
});


test("Customer-only legacy opt-out suppresses ordinary and mention delivery", async () => {
  const f = fixture({customer: {messages: false, messageMentions: false}});
  await f.deliver("customer-normal");
  await f.deliver("customer-mention", "Controlled @recipient mention");
  assert.equal(f.inbox().length, 0);
  assert.equal(f.sent.length, 0);
});

test("Customer fallback preserves mentions-only and maps messages ahead of messagesAll", async () => {
  const f = fixture({customer: {messages: false, messagesAll: true, messageMentions: true}});
  await f.deliver("customer-ordinary");
  assert.equal(f.sent.length, 0);
  await f.deliver("customer-mentioned", "Controlled @recipient mention");
  assert.equal(f.sent.length, 1);
  assert.equal(f.sent[0].data.type, "message_mention");
});

test("Customer compatibility opt-out alias remains effective when both settings docs are absent", async () => {
  const f = fixture({customer: {messages: true, messageNotifications: false, messageMentions: false}});
  await f.deliver("customer-alias");
  assert.equal(f.inbox().length, 0);
  assert.equal(f.sent.length, 0);
});

test("an existing canonical or legacy document never merges Customer opt-outs into its defaults", async () => {
  for (const selected of [{canonical: {}}, {legacy: {}}]) {
    const f = fixture({...selected, customer: {messages: false, messageNotifications: false, messageMentions: false}});
    await f.deliver("selected-document-defaults");
    assert.equal(f.inbox().length, 1);
    assert.equal(f.sent.length, 1);
  }
});

test("non-map Customer preferences do not become settings or create migration writes", async () => {
  for (const customer of [null, false, ["messages", false]]) {
    const f = fixture({customer});
    await f.deliver("malformed-customer");
    assert.equal(f.sent.length, 1);
    assert.equal(f.db.values.has("users/recipient/settings/notifications"), false);
    assert.equal(f.db.values.has("users/recipient/notificationSettings/settings"), false);
  }
});
