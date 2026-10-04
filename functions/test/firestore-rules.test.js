"use strict";
const test = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const {initializeTestEnvironment, assertFails, assertSucceeds} = require("@firebase/rules-unit-testing");

let env;
test.before(async () => {
  const [host = "127.0.0.1", port = "8080"] =
    String(process.env.FIRESTORE_EMULATOR_HOST || "127.0.0.1:8080").split(":");
  env = await initializeTestEnvironment({projectId: "demo-attendus-admin", firestore: {rules: fs.readFileSync(path.join(__dirname, "../../firestore.rules"), "utf8"), host, port: Number(port)}});
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

test("profile creation accepts signup defaults but cannot inject privileges or publication allowances", async () => {
  const privileged = {
    role: "super_admin", roles: ["super_admin"], isAdmin: true,
    approved: true, approvalStatus: "approved", tier: "premium", planId: "premium",
    subscriptionStatus: "active", paid: true, isPaid: true, usage: {},
  };
  for (const [field, value] of Object.entries(privileged)) {
    for (const collection of ["Customers", "users"]) {
      await assertFails(dbFor("new-user").doc(`${collection}/new-user`).set({uid: "new-user", [field]: value}));
    }
  }
  await assertFails(dbFor("new-user").doc("Customers/new-user").set({uid: "new-user", eventsCreatedThisMonth: 0}));
  for (const field of ["eventsCreated", "groupsCreated"]) {
    for (const value of [-100, 1, "0", null, false, 0.5]) {
      await assertFails(dbFor("new-user").doc("Customers/new-user").set({uid: "new-user", [field]: value}));
    }
  }
  await assertSucceeds(dbFor("new-user").doc("Customers/new-user").set({
    uid: "new-user", name: "New User", email: "fixture@example.test", username: "newuser",
    profilePictureUrl: null, bannerUrl: null, bio: null, phoneNumber: null, age: null,
    gender: null, location: null, occupation: null, company: null, website: null,
    socialMediaLinks: null, isDiscoverable: true, favorites: [], createdAt: new Date(),
    eventsCreated: 0, groupsCreated: 0,
  }));
  await assertSucceeds(dbFor("minimal").doc("Customers/minimal").set({uid: "minimal"}));
  await assertSucceeds(dbFor("new-user").doc("users/new-user").set({name: "New User"}));
});

test("private customer documents are self-only while cross-account profile access uses the redacted callable", async () => {
  await seed(async (db) => {
    await db.doc("Customers/viewer").set({uid: "viewer", email: "own@example.test"});
    await db.doc("Customers/other").set({uid: "other", name: "Public Name", username: "other", isDiscoverable: true,
      email: "private@example.test", phoneNumber: "private-phone", favorites: ["private-save"]});
    await db.doc("ProfileReadLimits/viewer").set({buckets: {read: {count: 1}}});
  });
  const db = dbFor("viewer");
  assert.equal((await assertSucceeds(db.doc("Customers/viewer").get())).data().email, "own@example.test");
  await assertFails(db.doc("Customers/other").get());
  await assertFails(db.collection("Customers").get());
  await assertFails(db.collection("Customers").where("isDiscoverable", "==", true).get());
  await assertFails(db.collection("Customers").where("email", "==", "private@example.test").get());
  await assertFails(db.collection("Customers").where("username", "==", "other").get());
  await assertFails(db.doc("ProfileReadLimits/viewer").get());
  await assertFails(db.doc("ProfileReadLimits/viewer").set({buckets: {}}));
});

test("existing profiles can edit personal fields but cannot reset, remove or replace server quota counters", async () => {
  await seed((db) => db.doc("Customers/owner").set({uid: "owner", name: "Before", eventsCreated: 5, groupsCreated: 1}));
  const ref = dbFor("owner").doc("Customers/owner");
  await assertSucceeds(ref.update({name: "After", bio: "Editable profile"}));
  for (const field of ["eventsCreated", "groupsCreated"]) {
    await assertFails(ref.update({[field]: 0}));
    await assertFails(ref.update({[field]: -100}));
  }
  await assertFails(ref.set({uid: "owner", name: "Replaced"}));
  assert.equal((await ref.get()).data().eventsCreated, 5);
});

test("event managers can query ticket codes only within their authorized event", async () => {
  await seed(async (db) => {
    await db.doc("Events/managed").set({customerUid: "manager", private: true});
    await db.doc("Events/other").set({customerUid: "other-owner", private: true});
    await db.doc("Tickets/managed-ticket").set({eventId: "managed", ticketCode: "fixture-code", customerUid: "attendee"});
    await db.doc("Tickets/other-ticket").set({eventId: "other", ticketCode: "other-code", customerUid: "attendee"});
  });
  const managed = await assertSucceeds(dbFor("manager").collection("Tickets").where("eventId", "==", "managed").where("ticketCode", "==", "fixture-code").limit(1).get());
  assert.equal(managed.size, 1);
  await assertFails(dbFor("manager").collection("Tickets").where("ticketCode", "==", "fixture-code").get());
  await assertFails(dbFor("manager").collection("Tickets").where("eventId", "==", "other").where("ticketCode", "==", "other-code").get());
});

test("clients cannot register, replace or read another push binding outside the callable", async () => {
  await seed((db) => db.doc("users/member").set({name: "Member", fcmToken: "server-token"}));
  await assertFails(dbFor("member").doc("users/member").update({fcmToken: "forged-token"}));
  await assertFails(dbFor("new-user").doc("users/new-user").set({fcmToken: "forged-token"}));
  await assertSucceeds(dbFor("member").doc("users/member").update({name: "New name"}));
  for (const collection of ["PushTokenBindings", "PushInstallations"]) {
    await assertFails(dbFor("member").collection(collection).doc("token").set({ownerUid: "member"}));
    await assertFails(dbFor("member").collection(collection).doc("token").get());
  }
});

test("organization names are reserved atomically and can be renamed by an approved admin without legacy createdBy", async () => {
  const owner = dbFor("creator");
  const batch = owner.batch();
  batch.set(owner.doc("Organizations/new-group"), {createdBy: "creator", name: "Original", name_lowercase: "original"});
  batch.set(owner.doc("OrganizationNames/original"), {organizationId: "new-group"});
  await assertSucceeds(batch.commit());
  await assertSucceeds(owner.doc("Organizations/new-group/Members/creator").set({userId: "creator", role: "Admin", status: "approved"}));
  await assertSucceeds(owner.runTransaction(async (tx) => {
    await tx.get(owner.doc("OrganizationNames/renamed"));
    tx.set(owner.doc("OrganizationNames/renamed"), {organizationId: "new-group"});
    tx.delete(owner.doc("OrganizationNames/original"));
    tx.update(owner.doc("Organizations/new-group"), {name: "Renamed", name_lowercase: "renamed"});
  }));
  await assertFails(dbFor("outsider").doc("OrganizationNames/squatted").set({organizationId: "new-group"}));
  await assertFails(dbFor("outsider").doc("OrganizationNames/renamed").delete());
  await assertFails(owner.doc("Organizations/new-group").update({name_lowercase: "unreserved"}));
  await assertFails(dbFor("outsider").doc("Organizations/duplicate").set({createdBy: "outsider", name_lowercase: "renamed"}));
});

test("creator can commit organization, reserved name and own approved membership atomically", async () => {
  const owner = dbFor("atomic-creator");
  await assertSucceeds(owner.runTransaction(async (tx) => {
    const name = owner.doc("OrganizationNames/atomic-group");
    assert.equal((await tx.get(name)).exists, false);
    tx.set(owner.doc("Organizations/atomic-group"), {createdBy: "atomic-creator", name: "Atomic group", name_lowercase: "atomic-group"});
    tx.set(name, {organizationId: "atomic-group"});
    tx.set(owner.doc("Organizations/atomic-group/Members/atomic-creator"), {
      organizationId: "atomic-group", userId: "atomic-creator", role: "Admin", status: "approved",
      permissions: ["CreateEditEvents", "ApproveJoinRequests", "ManageMembersRoles", "ViewAnalytics"],
    });
  }));
  assert.equal((await owner.doc("Organizations/atomic-group/Members/atomic-creator").get()).data().role, "Admin");
  await assertSucceeds(owner.doc("Organizations/atomic-group").update({description: "Immediately manageable"}));
});

test("invalid atomic creator membership rolls back the organization and reserved name", async () => {
  const owner = dbFor("atomic-creator");
  const batch = owner.batch();
  batch.set(owner.doc("Organizations/invalid-creator"), {createdBy: "atomic-creator", name_lowercase: "invalid-creator"});
  batch.set(owner.doc("OrganizationNames/invalid-creator"), {organizationId: "invalid-creator"});
  batch.set(owner.doc("Organizations/invalid-creator/Members/atomic-creator"), {userId: "another-user", role: "Admin", status: "approved"});
  await assertFails(batch.commit());
  await seed(async (db) => {
    for (const key of ["Organizations/invalid-creator", "OrganizationNames/invalid-creator", "Organizations/invalid-creator/Members/atomic-creator"]) {
      assert.equal((await db.doc(key).get()).exists, false, key);
    }
  });
});

test("anonymous or unrelated users cannot bootstrap an approved creator membership", async () => {
  const anonymous = env.authenticatedContext("anonymous", {firebase: {sign_in_provider: "anonymous"}}).firestore();
  const batch = anonymous.batch();
  batch.set(anonymous.doc("Organizations/anonymous-group"), {createdBy: "anonymous", name_lowercase: "anonymous-group"});
  batch.set(anonymous.doc("OrganizationNames/anonymous-group"), {organizationId: "anonymous-group"});
  batch.set(anonymous.doc("Organizations/anonymous-group/Members/anonymous"), {userId: "anonymous", role: "Admin", status: "approved"});
  await assertFails(batch.commit());
  await seed((db) => db.doc("Organizations/existing-group").set({createdBy: "original-owner", name_lowercase: "existing-group"}));
  const outsider = dbFor("outsider");
  const takeover = outsider.batch();
  takeover.update(outsider.doc("Organizations/existing-group"), {createdBy: "outsider"});
  takeover.set(outsider.doc("Organizations/existing-group/Members/outsider"), {userId: "outsider", role: "Admin", status: "approved"});
  await assertFails(takeover.commit());
  await assertFails(outsider.doc("Organizations/absent/Members/outsider").set({userId: "outsider", role: "Admin", status: "approved"}));
  await seed(async (db) => {
    assert.equal((await db.doc("Organizations/existing-group").get()).data().createdBy, "original-owner");
    for (const key of ["Organizations/anonymous-group", "OrganizationNames/anonymous-group", "Organizations/anonymous-group/Members/anonymous", "Organizations/existing-group/Members/outsider", "Organizations/absent/Members/outsider"]) {
      assert.equal((await db.doc(key).get()).exists, false, key);
    }
  });
});

test("legacy event comments do not disclose private events to another signed-in account", async () => {
  await seed(async (db) => {
    await db.doc("Events/private-comment-event").set({customerUid: "owner", private: true, accessList: ["invited"]});
    await db.doc("Comments/comment").set({eventId: "private-comment-event", userId: "invited", comment: "Private"});
  });
  await assertSucceeds(dbFor("invited").collection("Comments").where("eventId", "==", "private-comment-event").get());
  await assertFails(dbFor("outsider").doc("Comments/comment").get());
  await assertFails(dbFor("outsider").collection("Comments").where("eventId", "==", "private-comment-event").get());
});

test("event child reads do not treat a missing private flag as public", async () => {
  await seed(async (db) => {
    await db.doc("Events/missing-privacy").set({customerUid: "owner", accessList: ["invited"]});
    await db.doc("Events/missing-privacy/Comments/comment").set({comment: "Private"});
    await db.doc("Comments/legacy-missing-privacy").set({eventId: "missing-privacy", comment: "Private"});
  });
  for (const path of ["Events/missing-privacy", "Events/missing-privacy/Comments/comment", "Comments/legacy-missing-privacy"]) {
    await assertFails(dbFor("outsider").doc(path).get());
    await assertSucceeds(dbFor("owner").doc(path).get());
    await assertSucceeds(dbFor("invited").doc(path).get());
  }
});

test("new memberships cannot self-approve, manufacture an absent group, or pregrant permissions", async () => {
  await seed((db) => db.collection("Organizations").doc("group").set({createdBy: "creator"}));
  const ref = dbFor("member").doc("Organizations/group/Members/member");
  const membership = {userId: "member", organizationId: "group", role: "Member", status: "approved", permissions: []};
  await assertFails(ref.set(membership));
  await assertFails(ref.set({...membership, status: "pending", permissions: ["manageEvents"]}));
  await assertFails(dbFor("member").doc("Organizations/missing/Members/member").set({...membership, status: "pending"}));
  await assertSucceeds(ref.set({...membership, status: "pending"}));
  await assertSucceeds(dbFor("creator").doc("Organizations/group/Members/creator").set({userId: "creator", role: "Admin", status: "approved"}));
});

test("approved members can query their group's private events but outsiders and pending members cannot", async () => {
  await seed(async (db) => {
    await db.doc("Organizations/group").set({createdBy: "owner"});
    await db.doc("Organizations/group/Members/member").set({userId: "member", role: "Member", status: "approved"});
    await db.doc("Organizations/group/Members/pending").set({userId: "pending", role: "Member", status: "pending"});
    await db.doc("Events/private-group").set({organizationId: "group", customerUid: "owner", private: true});
    await db.doc("Events/public-group").set({organizationId: "group", customerUid: "owner", private: false});
  });
  const members = await assertSucceeds(dbFor("member").collection("Events").where("organizationId", "==", "group").get());
  assert.equal(members.size, 2);
  for (const uid of ["outsider", "pending"]) {
    await assertFails(dbFor(uid).doc("Events/private-group").get());
    await assertFails(dbFor(uid).collection("Events").where("organizationId", "==", "group").get());
  }
});

test("registration and attendee access grants are server-owned even for an event owner", async () => {
  await seed((db) => db.collection("Events").doc("event").set({customerUid: "owner", private: false}));
  for (const uid of ["member", "owner"]) {
    await assertFails(dbFor(uid).collection("RegisterAttendance").doc(uid).set({eventId: "event", customerUid: uid, status: "confirmed"}));
    await assertFails(dbFor(uid).doc(`Events/event/Attendees/${uid}`).set({customerUid: uid}));
  }
});

test("feed writes, nested comments and poll counters cannot bypass the callable through generic organization rules", async () => {
  await seed(async (db) => {
    await db.doc("Organizations/group").set({createdBy: "owner"});
    for (const uid of ["owner", "member"]) await db.doc(`Organizations/group/Members/${uid}`).set({userId: uid, role: uid === "owner" ? "Admin" : "Member", status: "approved"});
    await db.doc("Organizations/group/Feed/post").set({authorId: "member", createdBy: "member", type: "poll", totalVotes: 0});
    await db.doc("Organizations/group/Feed/post/Comments/comment").set({userId: "member", comment: "Real comment"});
  });
  for (const uid of ["owner", "member"]) {
    const db = dbFor(uid);
    await assertSucceeds(db.doc("Organizations/group/Feed/post").get());
    await assertSucceeds(db.doc("Organizations/group/Feed/post/Comments/comment").get());
    await assertFails(db.doc("Organizations/group/Feed/post").update({totalVotes: 999}));
    await assertFails(db.doc("Organizations/group/Feed/post").delete());
    await assertFails(db.doc("Organizations/group/Feed/post/Comments/comment").update({comment: "Rewritten"}));
    await assertFails(db.doc("Organizations/group/Feed/new").set({authorId: uid, createdBy: uid, type: "photo"}));
  }
  await assertFails(dbFor("outsider").doc("Organizations/group/Feed/post/Comments/comment").get());
});

test("event comments are readable to the audience but only the server can change them", async () => {
  await seed(async (db) => {
    await db.doc("Events/event").set({customerUid: "owner", private: false});
    await db.doc("Events/event/Comments/comment").set({userId: "member", comment: "Comment"});
  });
  await assertSucceeds(dbFor("member").doc("Events/event/Comments/comment").get());
  for (const uid of ["owner", "member"]) await assertFails(dbFor(uid).doc("Events/event/Comments/comment").update({likes: [uid]}));
});

test("direct reports and feedback cannot bypass validation, attendance checks or deduplication", async () => {
  for (const collection of ["reports", "event_feedback", "app_feedback", "feedback_submissions"]) {
    await assertFails(dbFor("member").collection(collection).doc("forged").set({reporterUid: "member", userId: "member", eventId: "event", rating: 999, status: "resolved"}));
  }
});

test("notification owners can mark read but cannot forge content or redirect to another recipient", async () => {
  await seed((db) => db.doc("notifications/notice").set({userId: "member", type: "general", title: "Real", isRead: false}));
  const ref = dbFor("member").doc("notifications/notice");
  await assertSucceeds(ref.update({isRead: true}));
  await assertFails(ref.update({userId: "target", type: "ticket_update", title: "Forged"}));
});

test("event entitlement is readable only by its owner and never client writable", async () => {
  await seed((db) => db.collection("account_entitlements").doc("user-a")
      .set({unlimitedEventCreation: true}));
  const own = dbFor("user-a").collection("account_entitlements").doc("user-a");
  await assertSucceeds(own.get());
  await assertFails(own.update({unlimitedEventCreation: false}));
  await assertFails(own.delete());
  await assertFails(dbFor("user-b").collection("account_entitlements").doc("user-a").get());
  await assertFails(dbFor("user-b").collection("account_entitlements").doc("user-b")
      .set({unlimitedEventCreation: true}));
});

for (const role of ["ordinary", "super_admin", "support", "billing_admin", "analyst", "moderator"]) {
  test(`${role} client cannot write server-only collections`, async () => {
    const token = role === "ordinary" ? {} : {admin: true, role};
    const db = env.authenticatedContext(`${role}-uid`, token).firestore();
    for (const collection of [
      "admin_roles", "admin_audit_logs", "admin_metrics_daily",
      "admin_metrics_current", "admin_jobs", "subscriptions",
      "AttendancePasses", "AttendanceSubjects", "AttendanceSigningKeys", "AttendanceWalletDownloads", "AttendanceWalletDevices", "AttendanceWalletJobs",
      "AttendanceWalletDeliveryJobs", "AttendanceWalletDelivery",
      "CheckInSessions", "CheckInAudit", "check_in_session_secrets",
      "check_in_idempotency", "check_in_event_state", "service_rate_limits",
      "scheduledNotifications", "_user_analytics_recompute",
      "TicketReservations", "payment_review_queue", "PublicWebEvents",
      "PublicWebCommunities", "stripe_webhook_events",
      "GuestAttendees", "GuestEventEmailClaims", "GuestManageTokens",
      "GuestManageSessions", "PublicRegistrationFlows", "OutboundMessages",
      "CommunicationTemplates",
      "HistoricalAttendance", "AttendanceHistoryIdentities", "EventRosters", "EventExportJobs",
      "EventAnnouncements", "EventAnnouncementPreviews", "EventCancellationPreviews",
    ]) await assertFails(db.collection(collection).doc("target").set({roles: ["super_admin"], tier: "premium"}));
  });
}
test("analytics recompute coordination is inaccessible to clients", async () => {
  await seed(async (db) => db.collection("_user_analytics_recompute")
      .doc("user-a").set({
        requestedGeneration: 2,
        processedGeneration: 1,
      }));
  const owner = dbFor("user-a").collection("_user_analytics_recompute")
      .doc("user-a");
  await assertFails(owner.get());
  await assertFails(owner.update({processedGeneration: 2}));
});
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

test("saved events, discovery preferences, and group follows require full accounts", async () => {
  await seed(async (db) => {
    await db.collection("Customers").doc("user-a").set({uid: "user-a"});
    await db.collection("Organizations").doc("org-a").set({createdBy: "owner"});
  });
  const full = dbFor("user-a");
  await assertSucceeds(full.collection("Customers").doc("user-a")
      .collection("SavedEvents").doc("event-a").set({
        eventId: "event-a", userId: "user-a",
      }));
  await assertSucceeds(full.collection("Customers").doc("user-a")
      .collection("Discovery").doc("preferences").set({chosenCity: "Boston"}));
  await assertSucceeds(full.collection("Organizations").doc("org-a")
      .collection("Followers").doc("user-a").set({
        userId: "user-a", organizationId: "org-a",
      }));
  const anonymous = env.authenticatedContext("guest", {
    firebase: {sign_in_provider: "anonymous"},
  }).firestore();
  await assertFails(anonymous.collection("Customers").doc("guest")
      .collection("SavedEvents").doc("event-a").set({
        eventId: "event-a", userId: "guest",
      }));
  await assertFails(anonymous.collection("Customers").doc("guest")
      .collection("Discovery").doc("preferences").set({chosenCity: "Boston"}));
  await assertFails(anonymous.collection("Organizations").doc("org-a")
      .collection("Followers").doc("guest").set({
        userId: "guest", organizationId: "org-a",
      }));
});

test("signed clients can read but cannot alter the Discovery rollback switch", async () => {
  await seed(async (db) => db.collection("AppConfig").doc("discovery")
      .set({useLegacyFeed: false}));
  const config = dbFor("user-a").collection("AppConfig").doc("discovery");
  await assertSucceeds(config.get());
  await assertFails(config.update({useLegacyFeed: true}));
});

test("event wizard drafts, templates, and series remain server-only", async () => {
  await seed(async (db) => {
    await db.collection("EventDrafts").doc("draft-a").set({ownerUid: "owner"});
    await db.collection("EventTemplates").doc("template-a").set({ownerUid: "owner"});
    await db.collection("EventSeries").doc("series-a").set({ownerUid: "owner"});
  });
  const owner = dbFor("owner");
  for (const [collection, id] of [
    ["EventDrafts", "draft-a"],
    ["EventTemplates", "template-a"],
    ["EventSeries", "series-a"],
  ]) {
    await assertFails(owner.collection(collection).doc(id).get());
    await assertFails(owner.collection(collection).doc(`${id}-forged`).set({ownerUid: "owner"}));
  }
});

test("event owners cannot grant themselves paid or featured entitlements", async () => {
  await seed(async (db) => db.collection("Events").doc("event-a").set({
    customerUid: "owner", private: false, isFeatured: false, issuedTickets: 0,
  }));
  const event = dbFor("owner").collection("Events").doc("event-a");
  await assertFails(event.update({isFeatured: true}));
  await assertFails(event.update({issuedTickets: 999}));
  await assertFails(event.update({reservedTickets: 1}));
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

test("private event access requests require a full account", async () => {
  await seed(async (db) => db.collection("Events").doc("private-event").set({
    customerUid: "owner", private: true, accessList: [],
  }));
  const request = {userId: "requester", status: "pending"};
  await assertSucceeds(dbFor("requester").collection("Events")
      .doc("private-event").collection("AccessRequests").doc("requester").set(request));
  const anonymousDb = env.authenticatedContext("anonymous-user", {
    firebase: {sign_in_provider: "anonymous"},
  }).firestore();
  await assertFails(anonymousDb.collection("Events").doc("private-event")
      .collection("AccessRequests").doc("anonymous-user").set({
        userId: "anonymous-user", status: "pending",
      }));
});

test("attendance writes are server-only and event staff can operate the console", async () => {
  await seed(async (db) => {
    await db.collection("Events").doc("event-a").set({
      customerUid: "owner", private: false, coHosts: ["cohost"],
      checkInStaff: ["door-staff"],
    });
    await db.collection("Attendance").doc("attendance-a").set({
      eventId: "event-a", customerUid: "attendee", status: "checked_in",
    });
    await db.collection("CheckInSessions").doc("session-a").set({
      eventId: "event-a", status: "active",
    });
    await db.collection("CheckInAudit").doc("audit-a").set({
      eventId: "event-a", action: "checked_in",
    });
  });

  for (const uid of ["owner", "cohost", "door-staff"]) {
    const db = dbFor(uid);
    await assertSucceeds(db.collection("Attendance").doc("attendance-a").get());
    await assertSucceeds(db.collection("CheckInSessions").doc("session-a").get());
    await assertSucceeds(db.collection("CheckInAudit").doc("audit-a").get());
    await assertFails(db.collection("Attendance").doc(`${uid}-forged`).set({
      eventId: "event-a", customerUid: uid,
    }));
  }

  await assertFails(dbFor("stranger").collection("CheckInSessions")
      .doc("session-a").get());
  await assertFails(dbFor("stranger").collection("CheckInAudit")
      .doc("audit-a").get());
});

test("messages require conversation participation and authenticated sender identity", async () => {
  await seed(async (db) => db.collection("Conversations").doc("conversation-a").set({
    participantIds: ["user-a", "user-b"], lastMessage: "", lastMessageTime: new Date(),
  }));
  const validMessage = {
    senderId: "user-a", receiverId: "user-b", conversationId: "conversation-a", content: "Hello", timestamp: new Date(),
  };
  await assertFails(dbFor("user-a").collection("Messages").doc("message-a").set(validMessage));
  await seed(async (db) => db.collection("Messages").doc("server-message").set(validMessage));
  await assertSucceeds(dbFor("user-a").collection("Messages").where("conversationId", "==", "conversation-a").orderBy("timestamp").get());
  await assertSucceeds(dbFor("user-a").collection("Conversations").where("participantIds", "array-contains", "user-a").orderBy("lastMessageTime", "desc").get());
  await assertFails(dbFor("user-a").collection("Conversations").where("participant1Id", "==", "user-a").get());
  await assertFails(dbFor("user-a").collection("Conversations").doc("conversation-a").update({unreadCounts: {"user-b": 0}}));
  await assertFails(dbFor("user-a").collection("Messages").doc("server-message").update({senderId: "user-b"}));
  await assertFails(dbFor("stranger").collection("Messages").where("conversationId", "==", "conversation-a").get());
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


test("group composer can create only an empty versioned conversation", async () => {
  const group = {isGroup: true, participantIds: ["user-a", "user-b", "user-c"], messagingVersion: 2,
    lastMessage: "", lastMessageTime: new Date(), sequence: 0, receivedTotals: {}, readTotals: {}, readSequences: {}, unreadCounts: {}};
  await assertSucceeds(dbFor("user-a").collection("Conversations").doc("group").set(group));
  await assertFails(dbFor("user-a").collection("Conversations").doc("forged").set({...group, unreadCounts: {"user-b": 99}}));
  for (const field of ["redirectConversationId", "migrationState", "formerParticipant"]) {
    await assertFails(dbFor("user-a").collection("Conversations").doc(`forged-${field}`).set({...group, [field]: "forged"}));
  }
  await seed(async (db) => {
    await db.collection("Conversations").doc("alias").set({...group, redirectConversationId: "group", migrationState: "complete"});
    await db.collection("Conversations").doc("moving").set({...group, migrationState: "moving"});
  });
  await assertSucceeds(dbFor("user-a").collection("Conversations").doc("alias").get());
  await assertFails(dbFor("user-a").collection("Conversations").doc("alias").update({groupName: "Forged"}));
  await assertFails(dbFor("user-a").collection("Conversations").doc("moving").update({groupName: "Forged"}));
  await assertFails(dbFor("stranger").collection("Conversations").doc("outsider").set(group));
  await assertFails(dbFor("user-a").collection("Conversations").doc("group").update({participantIds: ["user-a", "stranger"]}));
  await assertFails(dbFor("user-a", {firebase: {sign_in_provider: "anonymous"}}).collection("Conversations").doc("group").get());
});

test("even event owners cannot bypass audited history access or permanently delete events", async () => {
  await seed(async (db) => {
    await db.collection("Events").doc("launch-event").set({customerUid: "owner", private: false});
    await db.collection("HistoricalAttendance").doc("history").set({eventId: "launch-event"});
    await db.collection("AttendanceHistoryIdentities").doc("history").set({eventId: "launch-event", ownerUid: "attendee"});
  });
  await assertFails(dbFor("owner").collection("Events").doc("launch-event").delete());
  for (const collection of ["HistoricalAttendance", "AttendanceHistoryIdentities"]) {
    await assertFails(dbFor("owner").collection(collection).doc("history").get());
    await assertFails(dbFor("attendee").collection(collection).doc("history").get());
  }
});


test("event owners cannot bypass callable publication, lifecycle, roles or counters", async () => {
  await seed((db) => db.collection("Events").doc("protected-event").set({customerUid: "owner", private: false}));
  const event = dbFor("owner").collection("Events").doc("protected-event");
  for (const patch of [
    {confirmedRegistrationCount: 0}, {organizationId: "other-org"},
    {selectedDateTime: new Date()}, {eventDurationMinutes: 10},
    {eventTimeZone: "UTC"}, {status: "cancelled"}, {cancelled: true},
    {registrationPolicy: {capacity: 500}}, {maxTickets: 500},
    {coHosts: ["stranger"]}, {checkInStaff: ["stranger"]},
    {launchScheduleNeedsReview: false}, {capacityActivation: "active"},
  ]) await assertFails(event.update(patch));
  await assertFails(dbFor("owner").collection("Events").doc("new-event")
      .set({customerUid: "owner", status: "active"}));
  await assertSucceeds(event.get());
});

test("deleting accounts cannot recreate client data", async () => {
  await seed(async (db) => {
    await db.collection("Customers").doc("deleting").set({uid: "deleting", name: "Before"});
    await db.collection("account_deletion_jobs").doc("deleting").set({status: "running"});
    await db.collection("Events").doc("owned").set({customerUid: "deleting", private: false});
  });
  const db = dbFor("deleting");
  await assertFails(db.collection("Customers").doc("deleting").update({name: "Recreated"}));
  await assertFails(db.collection("Events").doc("owned").update({title: "Recreated"}));
  await assertFails(db.collection("Customers").doc("other").collection("Followers").doc("deleting").set({}));
});

test("qualification capture policy and evidence are server-only even for administrators", async () => {
  for (const name of ["QualificationScopes", "QualificationBindings", "QualificationCaptures"]) {
    await seed((db) => db.collection(name).doc("fixture").set({runId: "fixture-run", state: "bound"}));
    for (const db of [dbFor("user-a"), dbFor("admin", {admin: true})]) {
      await assertFails(db.collection(name).doc("fixture").get());
      await assertFails(db.collection(name).doc("fixture").set({state: "ordinary"}));
      await assertFails(db.collection(name).doc("fixture").delete());
    }
  }
});
