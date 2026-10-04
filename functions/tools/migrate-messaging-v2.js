"use strict";

const fs = require("node:fs");
const path = require("node:path");
const {initializeApp} = require("firebase-admin/app");
const {getFirestore} = require("firebase-admin/firestore");
const {planConversation} = require("../messaging/migration");

function archive(value) {
  if (value && typeof value.toMillis === "function") return {__timestamp: [value.seconds, value.nanoseconds]};
  if (Array.isArray(value)) return value.map(archive);
  if (value && typeof value === "object") return Object.fromEntries(Object.entries(value).map(([k, v]) => [k, archive(v)]));
  return value;
}

async function main() {
  const args = process.argv.slice(2);
  const project = args[args.indexOf("--project") + 1];
  if (!args.includes("--project") || !project) throw new Error("An explicit --project is required.");
  const apply = args.includes("--apply");
  const backup = args.includes("--backup") ? path.resolve(args[args.indexOf("--backup") + 1]) : null;
  if (apply && (!backup || !args.includes("--writes-frozen"))) {
    throw new Error("Apply requires --backup <new-file> and --writes-frozen (server-only messaging rules deployed).");
  }
  initializeApp({projectId: project});
  const db = getFirestore();
  const [conversations, messages] = await Promise.all([db.collection("Conversations").get(), db.collection("Messages").get()]);
  const docs = new Map(conversations.docs.map((doc) => [doc.id, doc]));
  const grouped = new Map();
  const issues = [];
  for (const doc of messages.docs) {
    const data = doc.data();
    const inferred = typeof data.senderId === "string" && typeof data.receiverId === "string" ?
      [data.senderId, data.receiverId].sort().join("_") : null;
    const id = data.conversationId || inferred;
    if (!id || !docs.has(id)) { issues.push({id: doc.id, issue: "orphan-message"}); continue; }
    if (!grouped.has(id)) grouped.set(id, []);
    grouped.get(id).push({id: doc.id, data, createdAt: doc.createTime});
  }
  const plans = [];
  for (const doc of conversations.docs) {
    try {
      const plan = planConversation(doc.id, doc.data(), grouped.get(doc.id) || [], doc.createTime);
      if (plan) plans.push({doc, plan});
    } catch (error) { issues.push({id: doc.id, issue: error.message}); }
  }
  console.log(JSON.stringify({project, apply, conversations: conversations.size, messages: messages.size,
    conversationsToUpgrade: plans.length, issues}, null, 2));
  if (!apply) return;
  const unresolved = issues.filter((issue) => issue.issue !== "orphan-message" || !args.includes("--preserve-orphans"));
  if (unresolved.length) throw new Error("Resolve reported records before applying; orphan records may be retained unchanged with --preserve-orphans. Nothing was written.");
  fs.writeFileSync(backup, JSON.stringify({project, createdAt: new Date().toISOString(),
    documents: [...conversations.docs, ...messages.docs].map((doc) => ({path: doc.ref.path, data: archive(doc.data())}))}),
  {flag: "wx", mode: 0o600});
  for (const {doc, plan} of plans) {
    // Version 1 threads cannot receive V2 sends. Each completed conversation is
    // independently resumable. A failed partial run keeps version 1 until done.
    for (let offset = 0; offset < plan.messages.length; offset += 400) {
      const batch = db.batch();
      for (const message of plan.messages.slice(offset, offset + 400)) {
        batch.update(db.collection("Messages").doc(message.id), message.patch);
      }
      await batch.commit();
    }
    await doc.ref.update(plan.conversation, {lastUpdateTime: doc.updateTime});
  }
  console.log(`Upgraded ${plans.length} conversations. Backup: ${backup}`);
}

if (require.main === module) main().catch((error) => {console.error(error.message); process.exitCode = 1;});
module.exports = {archive};
