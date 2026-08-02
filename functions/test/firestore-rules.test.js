"use strict";
const test = require("node:test");
const fs = require("node:fs");
const path = require("node:path");
const {initializeTestEnvironment, assertFails, assertSucceeds} = require("@firebase/rules-unit-testing");

let env;
test.before(async () => {
  env = await initializeTestEnvironment({projectId: "demo-attendus-admin", firestore: {rules: fs.readFileSync(path.join(__dirname, "../../firestore.rules"), "utf8"), host: "127.0.0.1", port: 8080}});
});
test.beforeEach(async () => {
  await env.clearFirestore();
});
test.after(async () => {
  await env?.cleanup();
});

const token = {firebase: {sign_in_provider: "password"}};
const dbFor = (uid, extra = {}) => env.authenticatedContext(uid, {...token, ...extra}).firestore();
const seed = async (callback) => env.withSecurityRulesDisabled((context) => callback(context.firestore()));

for (const role of ["ordinary", "super_admin", "support", "billing_admin", "analyst", "moderator"]) {
  test(`${role} client cannot write server-only collections`, async () => {
    const token = role === "ordinary" ? {} : {admin: true, role};
    const db = env.authenticatedContext(`${role}-uid`, token).firestore();
    for (const collection of ["admin_roles", "admin_audit_logs", "admin_metrics_daily", "admin_metrics_current", "admin_jobs", "subscriptions"]) await assertFails(db.collection(collection).doc("target").set({roles: ["super_admin"], tier: "premium"}));
  });
}
test("ordinary user can read only their own subscription", async () => {
  await seed(async (db) => db.collection("subscriptions").doc("user-a").set({tier: "basic"}));
  const db = dbFor("user-a");
  await assertSucceeds(db.collection("subscriptions").doc("user-a").get());
  await assertFails(db.collection("subscriptions").doc("user-b").get());
});

test("members cannot promote or approve themselves", async () => {
  await seed(async (db) => {
    await db.collection("Organizations").doc("org-a").set({createdBy: "owner"});
    await db.collection("Organizations").doc("org-a").collection("Members").doc("member").set({
      userId: "member", organizationId: "org-a", role: "member", status: "pending",
    });
  });
  const member = dbFor("member").collection("Organizations").doc("org-a").collection("Members").doc("member");
  await assertFails(member.update({role: "admin"}));
  await assertFails(member.update({status: "approved"}));
  await assertSucceeds(member.update({displayName: "Member Name"}));
});

test("organization administrators can manage another member role", async () => {
  await seed(async (db) => {
    await db.collection("Organizations").doc("org-a").set({createdBy: "owner"});
    await db.collection("Organizations").doc("org-a").collection("Members").doc("owner").set({
      userId: "owner", organizationId: "org-a", role: "owner", status: "approved",
    });
    await db.collection("Organizations").doc("org-a").collection("Members").doc("member").set({
      userId: "member", organizationId: "org-a", role: "member", status: "approved",
    });
  });
  const target = dbFor("owner").collection("Organizations").doc("org-a").collection("Members").doc("member");
  await assertSucceeds(target.update({role: "admin"}));
});

test("event owners cannot grant themselves paid or featured entitlements", async () => {
  await seed(async (db) => db.collection("Events").doc("event-a").set({
    customerUid: "owner", private: false, isFeatured: false, issuedTickets: 0,
  }));
  const event = dbFor("owner").collection("Events").doc("event-a");
  await assertFails(event.update({isFeatured: true}));
  await assertFails(event.update({issuedTickets: 999}));
  await assertSucceeds(event.update({title: "Safe title update"}));
});

test("ticket purchasers cannot mark tickets paid, used, or upgraded", async () => {
  await seed(async (db) => {
    await db.collection("Events").doc("event-a").set({customerUid: "owner", private: false});
    await db.collection("Tickets").doc("ticket-a").set({
      eventId: "event-a", customerUid: "buyer", isPaid: false, isUsed: false,
      isSkipTheLine: false,
    });
  });
  const ticket = dbFor("buyer").collection("Tickets").doc("ticket-a");
  await assertFails(ticket.update({isPaid: true}));
  await assertFails(ticket.update({isUsed: true}));
  await assertFails(ticket.update({isSkipTheLine: true}));
  await assertFails(dbFor("buyer").collection("Tickets").doc("forged").set({
    eventId: "event-a", customerUid: "buyer", isPaid: false, isUsed: false,
    isSkipTheLine: false,
  }));
});

test("private events and attendance are limited to owners and participants", async () => {
  await seed(async (db) => {
    await db.collection("Events").doc("private-event").set({
      customerUid: "owner", private: true, accessList: ["invited"],
    });
    await db.collection("Attendance").doc("attendance-a").set({
      eventId: "private-event", customerUid: "invited",
    });
  });
  await assertFails(dbFor("stranger").collection("Events").doc("private-event").get());
  await assertSucceeds(dbFor("invited").collection("Events").doc("private-event").get());
  await assertFails(dbFor("stranger").collection("Attendance").doc("attendance-a").get());
  await assertSucceeds(dbFor("invited").collection("Attendance").doc("attendance-a").get());
  await assertSucceeds(dbFor("owner").collection("Attendance").doc("attendance-a").get());
});

test("messages require conversation participation and authenticated sender identity", async () => {
  await seed(async (db) => db.collection("Conversations").doc("conversation-a").set({
    participantIds: ["user-a", "user-b"], lastMessage: "",
  }));
  const validMessage = {
    senderId: "user-a", receiverId: "user-b", conversationId: "conversation-a", content: "Hello",
  };
  await assertSucceeds(dbFor("user-a").collection("Messages").doc("message-a").set(validMessage));
  await assertFails(dbFor("user-a").collection("Messages").doc("message-b").set({...validMessage, senderId: "user-b"}));
  await assertFails(dbFor("stranger").collection("Messages").doc("message-c").set({...validMessage, senderId: "stranger"}));
  await assertFails(dbFor("stranger").collection("Conversations").doc("conversation-a").get());
});

test("facial templates are inaccessible to every client", async () => {
  await seed(async (db) => db.collection("FaceEnrollments").doc("face-a").set({
    userId: "user-a", faceFeatures: [0.1, 0.2],
  }));
  await assertFails(dbFor("user-a").collection("FaceEnrollments").doc("face-a").get());
  await assertFails(dbFor("user-a").collection("FaceEnrollments").doc("face-b").set({
    userId: "user-a", faceFeatures: [0.3],
  }));
});
