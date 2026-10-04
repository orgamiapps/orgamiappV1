"use strict";

const fs = require("node:fs");
const path = require("node:path");
const {randomBytes} = require("node:crypto");
const assert = require("node:assert/strict");
const {initializeApp: initializeAdmin} = require("firebase-admin/app");
const {getAuth: getAdminAuth} = require("firebase-admin/auth");
const {getFirestore: getAdminFirestore, Timestamp} = require("firebase-admin/firestore");
const {initializeApp, deleteApp} = require("firebase/app");
const {getAuth, signInWithEmailAndPassword} = require("firebase/auth");
const {getFirestore, collection, doc, setDoc, getDoc, getDocs, query, where, orderBy, terminate} = require("firebase/firestore");
const {getFunctions, httpsCallable} = require("firebase/functions");
const {digest} = require("../messaging/service");
const value = (flag) => process.argv.includes(flag) ? process.argv[process.argv.indexOf(flag) + 1] : null;

async function main() {
  const projectId = value("--project");
  const mode = value("--mode");
  const fixturePath = value("--fixture");
  assert.ok(["orgami-66nxok", "attendus-staging"].includes(projectId));
  assert.ok(["setup", "exercise", "cleanup"].includes(mode));
  assert.ok(fixturePath && path.isAbsolute(fixturePath), "An absolute private fixture path is required");
  initializeAdmin({projectId});
  const db = getAdminFirestore();
  const adminAuth = getAdminAuth();
  if (mode === "setup") {
    const prefix = `messaging-qa-${Date.now()}`;
    const fixture = {projectId, prefix, password: randomBytes(24).toString("base64url"),
      users: ["a", "b", "c"].map((suffix) => ({uid: `${prefix}-${suffix}`, email: `${prefix}-${suffix}@example.invalid`,
        name: `Messaging QA ${suffix.toUpperCase()}`}))};
    fs.writeFileSync(fixturePath, JSON.stringify(fixture), {flag: "wx", mode: 0o600});
    for (const user of fixture.users) {
      await adminAuth.createUser({uid: user.uid, email: user.email, password: fixture.password, displayName: user.name, emailVerified: true});
      await db.doc(`Customers/${user.uid}`).set({...user, username: user.uid, isDiscoverable: true, createdAt: Timestamp.now()});
      await db.doc(`users/${user.uid}/settings/notifications`).set({messagesAll: false, messageMentions: false});
    }
    console.log(JSON.stringify({created: fixture.users.map(({email, name}) => ({email, name})), fixturePath}));
    return;
  }
  const fixture = JSON.parse(fs.readFileSync(fixturePath, "utf8"));
  assert.equal(fixture.projectId, projectId);
  assert.match(fixture.prefix, /^messaging-qa-\d+$/);
  assert.ok(fixture.users.every((user) => user.uid.startsWith(`${fixture.prefix}-`) && user.email === `${user.uid}@example.invalid`));
  if (mode === "cleanup") {
    const ids = new Set(fixture.users.map((user) => user.uid));
    const conversationIds = new Set();
    for (const uid of ids) {
      const conversations = await db.collection("Conversations").where("participantIds", "array-contains", uid).get();
      for (const conversation of conversations.docs) {
        assert.ok(conversation.data().participantIds.every((id) => ids.has(id)), "Refusing to remove a conversation with a real account");
        conversationIds.add(conversation.id);
      }
    }
    for (const id of conversationIds) {
      const messages = await db.collection("Messages").where("conversationId", "==", id).get();
      for (const message of messages.docs) await message.ref.delete();
      await db.recursiveDelete(db.collection("Conversations").doc(id));
    }
    for (const user of fixture.users) {
      const account = await adminAuth.getUser(user.uid).catch((error) => { if (error.code !== "auth/user-not-found") throw error; });
      if (account) { assert.equal(account.email, user.email); await adminAuth.deleteUser(user.uid); }
      await db.recursiveDelete(db.doc(`Customers/${user.uid}`));
      await db.recursiveDelete(db.doc(`users/${user.uid}`));
      await db.doc(`service_rate_limits/messages_${digest(user.uid)}`).delete();
      assert.equal((await db.doc(`Customers/${user.uid}`).get()).exists, false);
      assert.equal((await db.collection("Conversations").where("participantIds", "array-contains", user.uid).get()).empty, true);
    }
    fs.unlinkSync(fixturePath);
    console.log(JSON.stringify({cleanedUsers: ids.size, cleanedConversations: conversationIds.size, verified: true}));
    return;
  }
  const options = fs.readFileSync(path.join(__dirname, "../../lib/firebase_options.dart"), "utf8");
  const web = options.slice(options.indexOf("static const FirebaseOptions web"));
  const apiKey = web.match(/apiKey:\s*'([^']+)'/)[1];
  const clients = [];
  try {
    for (const user of fixture.users) {
      const app = initializeApp({projectId, apiKey}, user.uid);
      await signInWithEmailAndPassword(getAuth(app), user.email, fixture.password);
      clients.push({app, db: getFirestore(app), functions: getFunctions(app, "us-central1")});
    }
    const [a, b, c] = clients;
    const call = async (client, name, data) => (await httpsCallable(client.functions, name)(data)).data;
    assert.equal((await getDocs(query(collection(a.db, "Conversations"), where("participantIds", "array-contains", fixture.users[0].uid), orderBy("lastMessageTime", "desc")))).size, 0);
    const {conversationId} = await call(a, "getOrCreateDirectConversationV2", {otherUserId: fixture.users[1].uid});
    const payload = {conversationId, requestId: "canary-first", content: "Messaging verification: first direct message"};
    const sent = await call(a, "sendConversationMessageV2", payload);
    assert.equal((await call(a, "sendConversationMessageV2", payload)).messageId, sent.messageId);
    assert.equal((await getDocs(query(collection(b.db, "Messages"), where("conversationId", "==", conversationId), orderBy("timestamp")))).size, 1);
    await assert.rejects(getDoc(doc(c.db, "Conversations", conversationId)));
    await call(b, "markConversationReadV2", {conversationId, lastMessageId: sent.messageId});
    assert.equal((await getDoc(doc(b.db, "Conversations", conversationId))).data().unreadCounts[fixture.users[1].uid], 0);
    await call(b, "sendConversationMessageV2", {conversationId, requestId: "canary-reply", content: "Messaging verification: live reply"});
    const groupId = `${fixture.prefix}-group`;
    await setDoc(doc(a.db, "Conversations", groupId), {isGroup: true, groupName: "Messaging QA Group", participantIds: fixture.users.map((user) => user.uid),
      participantInfo: Object.fromEntries(fixture.users.map((user) => [user.uid, {name: user.name}])),
      lastMessage: "", lastMessageTime: new Date(), messagingVersion: 2, sequence: 0,
      receivedTotals: {}, readTotals: {}, readSequences: {}, unreadCounts: {}});
    await call(c, "sendConversationMessageV2", {conversationId: groupId, requestId: "group-first", content: "Messaging verification: three-person group"});
    assert.equal((await getDocs(query(collection(a.db, "Messages"), where("conversationId", "==", groupId), orderBy("timestamp")))).size, 1);
    console.log(JSON.stringify({authenticatedCanary: "PASS", checks: ["empty inbox", "first direct message", "retry deduplication", "history index", "outsider denied", "mark read", "reply", "group creation and send"], conversationId, groupId}));
  } finally {
    for (const client of clients) { await terminate(client.db); await deleteApp(client.app); }
  }
}

main().catch((error) => { console.error(error.code || error.message); process.exitCode = 1; });
