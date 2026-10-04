"use strict";
const test = require("node:test");
const assert = require("node:assert/strict");
const crypto = require("node:crypto");
if (!/^127\.0\.0\.1:\d+$/.test(process.env.FIRESTORE_EMULATOR_HOST || "")) throw Error("Local Firestore emulator required");
process.env.GCLOUD_PROJECT = "demo-attendus-admin";
process.env.FUNCTIONS_EMULATOR = "true";
const admin = require("../firebase-admin-compat");
const db = admin.firestore();
const {createCommunityOperations} = require("../community/operations");
const {createLegacyAnalyticsHandlers} = require("../analytics/legacy-operations");
const {createPushTokenOperations, canDeliverPush, tokenHash} = require("../notifications/push-tokens");
const {createDiscoveryNotificationHandlers} = require("../discovery/notifications");
const {createDiscoveryMaintenanceHandlers} = require("../discovery/maintenance");
const {createInsightsHandler} = require("../analytics/insights");
const {createNaturalSearchHandler} = require("../discovery/natural-search");
const operation = createCommunityOperations(admin).communityMutationV1;
const analytics = createLegacyAnalyticsHandlers(admin);
const suffix = crypto.randomUUID();
const orgId = `community-${suffix}`;
const owner = `owner-${suffix}`;
const member = `member-${suffix}`;
const second = `second-${suffix}`;
const eventId = `community-event-${suffix}`;
const group = db.collection("Organizations").doc(orgId);
const request = (uid, data) => ({auth: {uid, token: {firebase: {sign_in_provider: "password"}}}, data});
const call = (uid, action, data = {}) => operation.run(request(uid, {organizationId: orgId, action, ...data}));
test.before(async () => {
  await group.set({createdBy: owner});
  for (const uid of [owner, member, second]) await group.collection("Members").doc(uid).set({userId: uid, role: uid === owner ? "Owner" : "Member", status: "approved"});
  await db.collection("Customers").doc(member).set({name: "Actual Member"});
  await db.collection("Events").doc(eventId).set({customerUid: owner, organizationId: orgId, private: false, status: "pending_approval", eventTimeZone: "America/New_York"});
});
test.after(async () => { await db.terminate(); });

test("profile callables return bounded public cards without raw private fields or opted-out search results", async () => {
  const {createPublicProfileOperations} = require("../profiles/public-profiles");
  const handlers = createPublicProfileOperations(admin);
  const viewer = `profile-viewer-${suffix}`, visible = `profile-visible-${suffix}`, hidden = `profile-hidden-${suffix}`;
  const deleting = `profile-deleting-${suffix}`, prefix = `Profile${suffix.replaceAll("-", "")}`;
  const hiddenUsername = `private_${suffix.replaceAll("-", "")}`;
  for (const [uid, isDiscoverable] of [[visible, true], [hidden, false], [deleting, true]]) {
    await db.doc(`Customers/${uid}`).set({uid, name: `${prefix} ${uid}`, username: uid === hidden ? hiddenUsername : uid, isDiscoverable,
      email: "fixture-secret@example.test", phoneNumber: "private-phone", favorites: [eventId], age: 25,
      bio: "Public biography", internal: {private: true}});
  }
  await db.doc(`account_deletion_jobs/${deleting}`).set({status: "requested"});
  const direct = await handlers.getPublicProfilesV1.run(request(viewer, {userIds: [visible, hidden, deleting]}));
  assert.deepEqual(direct.profiles.map((profile) => profile.uid), [visible, hidden]);
  for (const profile of direct.profiles) assert.deepEqual(Object.keys(profile).sort(),
      ["uid", "name", "username", "isDiscoverable", "profilePictureUrl", "bannerUrl", "bio"].sort());
  const found = await handlers.searchPublicProfilesV1.run(request(viewer, {query: prefix, limit: 50}));
  assert.deepEqual(found.profiles.map((profile) => profile.uid), [visible]);
  assert.deepEqual(await handlers.checkUsernameAvailabilityV1.run(request(viewer, {username: hiddenUsername})), {username: hiddenUsername, available: false});
  await assert.rejects(handlers.searchPublicProfilesV1.run(request(viewer, {query: "fixture-secret@example.test"})), {code: "invalid-argument"});
  await db.doc(`account_deletion_jobs/${viewer}`).set({status: "requested"});
  await assert.rejects(handlers.getPublicProfilesV1.run(request(viewer, {userIds: [visible]})), {code: "failed-precondition"});
});

test("saved counters and metadata use authoritative current Firestore state under concurrent retries", async () => {
  const uid = `save-member-${suffix}`, id = `saved-${suffix}`;
  const ref = db.collection("Events").doc(id), source = db.doc(`Customers/${uid}/SavedEvents/${id}`);
  await ref.set({saveCount: 0, title: "Saved", latitude: 35, longitude: -80, city: "Charlotte", regionCode: "NC", countryCode: "US", locationType: "in_person"});
  await source.set({eventId: id});
  const handlers = createDiscoveryMaintenanceHandlers(admin), event = {params: {uid, eventId: id}};
  await Promise.all([handlers.saved(event), handlers.saved(event), handlers.metadata(event)]);
  assert.equal((await ref.get()).get("saveCount"), 1); assert.ok((await ref.get()).get("geohash"));
  await source.delete();
  await Promise.all([handlers.saved(event), handlers.saved(event)]);
  assert.equal((await ref.get()).get("saveCount"), 0);
  await ref.delete();
  await Promise.all([handlers.saved(event), handlers.metadata(event)]);
  assert.equal((await ref.get()).exists, false);
});

test("cloud natural search returns public DTOs and insights respond to feedback-only source updates", async () => {
  const id = `search-public-${suffix}`, pending = `search-pending-${suffix}`;
  const title = `isolation${suffix.replaceAll("-", "")}`;
  const event = {title, customerUid: owner, private: false, status: "scheduled", selectedDateTime: new Date(Date.now() + 86400000),
    accessList: ["must-not-return"], experience: {publicContact: {visible: false, email: "hidden@example.test"}}};
  await db.collection("Events").doc(id).set(event);
  await db.collection("Events").doc(pending).set({...event, status: "pending_approval"});
  const result = await createNaturalSearchHandler(admin)({data: {query: title, limit: 10}, auth: {uid: owner, token: {firebase: {sign_in_provider: "password"}}}});
  assert.deepEqual(result.events.map((entry) => entry.id), [id]);
  assert.equal(result.events[0].accessList, undefined); assert.equal(result.events[0].experience.publicContact.email, undefined);
  const analyticsRef = db.collection("event_analytics").doc(id), insightsRef = db.collection("ai_insights").doc(id);
  const handler = createInsightsHandler(admin), trigger = {params: {docId: id}};
  await analyticsRef.set({totalAttendees: 5, feedbackAnalytics: {commentSummaries: ["great"]}});
  await handler(trigger);
  await analyticsRef.update({feedbackAnalytics: {commentSummaries: ["terrible"]}});
  await handler(trigger);
  assert.equal((await insightsRef.get()).get("sentimentAnalysis").negativeCount, 1);
  await analyticsRef.delete(); await handler(trigger);
  assert.equal((await insightsRef.get()).exists, false);
});

test("discovery delivery rechecks privacy and serializes competing workers while preserving new events", async () => {
  const uid = `discovery-${suffix}`, creator = `discovery-owner-${suffix}`;
  const root = db.collection("discovery_notification_batches").doc(uid);
  const now = Date.now(), due = now + 45 * 60 * 1000;
  const ids = ["first", "private", "later"].map((name) => `discovery-${name}-${suffix}`);
  await db.collection("users").doc(uid).set({name: "Discovery fixture"});
  await db.doc(`Customers/${creator}/followers/${uid}`).set({userId: uid});
  for (const id of ids) await db.collection("Events").doc(id).set({private: false, status: "scheduled", customerUid: creator,
    title: id, selectedDateTime: new Date(now + 86400000), eventDuration: 2, locationType: "online"});
  const handlers = createDiscoveryNotificationHandlers(admin);
  await handlers.enqueue(uid, ids[0], now);
  await handlers.enqueue(uid, ids[1], now);
  const claim = await handlers.prepare(root, due);
  await db.collection("Events").doc(ids[1]).update({private: true, title: "Private title must not leak"});
  await handlers.enqueue(uid, ids[2], due);
  assert.equal((await root.get()).get("activeDeliveryId"), claim.id);
  await Promise.all([handlers.deliverUser(uid, due), handlers.deliverUser(uid, due)]);
  const notifications = await db.collection("users").doc(uid).collection("notifications").get();
  assert.equal(notifications.size, 1);
  assert.deepEqual(notifications.docs[0].get("eventIds"), [ids[0]]);
  assert.ok(!(notifications.docs[0].get("body") || "").includes("Private title"));
  await handlers.deliverUser(uid, due + 3600000);
  const final = await db.collection("users").doc(uid).collection("notifications").get();
  assert.equal(final.size, 2);
  assert.deepEqual(final.docs.flatMap((doc) => doc.get("eventIds")).sort(), [ids[0], ids[2]].sort());
  assert.equal((await root.get()).get("deliverAfter"), undefined);
});

test("discovery prepared delivery resumes safely and account deletion suppresses inbox creation", async () => {
  const uid = `discovery-deleting-${suffix}`, creator = `discovery-owner-${suffix}`;
  const id = `discovery-delete-event-${suffix}`, now = Date.now(), due = now + 45 * 60 * 1000;
  await db.collection("users").doc(uid).set({name: "Fixture"});
  await db.doc(`Customers/${creator}/followers/${uid}`).set({userId: uid});
  await db.collection("Events").doc(id).set({private: false, status: "scheduled", customerUid: creator,
    title: "Delete test", selectedDateTime: new Date(now + 86400000), eventDuration: 2, locationType: "online"});
  const handlers = createDiscoveryNotificationHandlers(admin);
  await handlers.enqueue(uid, id, now);
  const root = db.collection("discovery_notification_batches").doc(uid);
  const prepared = await handlers.prepare(root, due);
  assert.equal((await prepared.get()).get("state"), "prepared");
  await db.collection("account_deletion_jobs").doc(uid).set({status: "requested"});
  await handlers.deliverUser(uid, due);
  assert.equal((await db.collection("users").doc(uid).collection("notifications").get()).size, 0);
  assert.equal(await handlers.enqueue(uid, id, due), false);
});

test("push ownership transfer fences late old registration and revoke against real Firestore", async () => {
  const operations = createPushTokenOperations(admin);
  const token = `fixture-push-token-${suffix}`;
  const installationId = `fixture-installation-${suffix}`;
  const input = (uid, generation) => request(uid, {token, installationId, generation, expectedUid: uid});
  await operations.registerPushTokenV1.run(input(owner, 1));
  await operations.registerPushTokenV1.run(input(second, 2));
  await Promise.all([
    assert.rejects(operations.registerPushTokenV1.run(input(owner, 1)), {code: "failed-precondition"}),
    operations.revokePushTokenV1.run(input(owner, 99)),
  ]);
  assert.equal((await db.doc(`users/${owner}`).get()).get("fcmToken"), undefined);
  assert.equal(await canDeliverPush(db, second, token), true);
  assert.equal((await db.collection("PushTokenBindings").doc(tokenHash(token)).get()).get("ownerUid"), second);
});

test("Firestore conflicts serialize concurrent poll retries and preserve one vote per account", async () => {
  const postId = "poll";
  await call(owner, "createFeed", {postId, post: {type: "poll", question: "Choice?", options: ["One", "Two"]}});
  await Promise.all([call(member, "votePoll", {postId, optionIndex: 0}), call(member, "votePoll", {postId, optionIndex: 0}), call(second, "votePoll", {postId, optionIndex: 1})]);
  const post = await group.collection("Feed").doc(postId).get();
  assert.equal(post.get("totalVotes"), 2);
  assert.deepEqual(post.get("options").map((option) => option.voteCount), [1, 1]);
  await assert.rejects(call(member, "votePoll", {postId, optionIndex: 1}), {code: "already-exists"});
  await call(owner, "updateFeed", {postId, updates: {isClosed: true}});
  await assert.rejects(call(second, "votePoll", {postId, optionIndex: 1}), {code: "failed-precondition"});
});

test("comments commit with their counters and concurrent desired likes never clobber another member", async () => {
  const postId = "photo";
  await call(member, "createFeed", {postId, post: {type: "photo", imageUrls: ["https://example.test/photo.jpg"], authorId: owner}});
  await Promise.all([call(member, "addComment", {postId, commentId: "one", comment: "Hello"}), call(member, "addComment", {postId, commentId: "one", comment: "Hello"})]);
  await Promise.all([call(member, "setLike", {postId, liked: true}), call(second, "setLike", {postId, liked: true})]);
  const post = await group.collection("Feed").doc(postId).get();
  assert.equal(post.get("authorId"), member); assert.equal(post.get("commentCount"), 1);
  assert.deepEqual(post.get("likes").sort(), [member, second].sort());
  await assert.rejects(call(second, "deleteComment", {postId, commentId: "one"}), {code: "permission-denied"});
  await call(member, "deleteComment", {postId, commentId: "one"});
  assert.equal((await post.ref.get()).get("commentCount"), 0);
});

test("moderation requires current approved admin membership and cannot bypass cancellation safeguards", async () => {
  await assert.rejects(call(member, "approveEvent", {eventId}), {code: "permission-denied"});
  await call(owner, "approveEvent", {eventId});
  assert.equal((await db.collection("Events").doc(eventId).get()).get("status"), "scheduled");
  await assert.rejects(call(owner, "updateEvent", {eventId, updates: {status: "cancelled"}}), {code: "invalid-argument"});
  await group.collection("Members").doc(owner).update({status: "pending"});
  await assert.rejects(call(owner, "updateEvent", {eventId, updates: {isHidden: true}}), {code: "permission-denied"});
  await group.collection("Members").doc(owner).update({status: "approved"});
});

test("feedback submission and aggregation are retry-safe and anonymous identity remains private", async () => {
  const data = {action: "submitFeedback", eventId, rating: 5, comment: "Great", isAnonymous: true};
  await assert.rejects(operation.run(request(member, data)), {code: "permission-denied"});
  const attendanceRef = db.collection("Attendance").doc(`community-attendance-${suffix}`);
  await attendanceRef.set({eventId, customerUid: member, checkedInAt: new Date("2026-10-03T14:00:00Z")});
  const [first, replay] = await Promise.all([operation.run(request(member, data)), operation.run(request(member, data))]);
  assert.equal(first.feedbackId, replay.feedbackId);
  const feedback = await db.collection("event_feedback").doc(first.feedbackId).get();
  assert.equal(feedback.get("userId"), null);
  const trigger = {params: {docId: first.feedbackId}, data: feedback};
  await Promise.all([analytics.aggregateFeedback(trigger), analytics.aggregateFeedback(trigger)]);
  const attendanceTrigger = {params: {docId: attendanceRef.id}, data: await attendanceRef.get()};
  await Promise.all([analytics.aggregateAttendance(attendanceTrigger), analytics.aggregateAttendance(attendanceTrigger)]);
  const result = await db.collection("event_analytics").doc(eventId).get();
  assert.equal(result.get("feedbackAnalytics").totalRatings, 1);
  assert.equal(result.get("totalAttendees"), 1);
  await db.collection("account_deletion_jobs").doc(member).set({status: "requested"});
  await assert.rejects(operation.run(request(member, data)), {code: "failed-precondition"});
});

test("report submission cannot recreate personal metadata after account deletion begins", async () => {
  const uid = `reporter-${suffix}`;
  await db.collection("account_deletion_jobs").doc(uid).set({status: "requested"});
  const handler = require("../index").submitUserReport;
  await assert.rejects(handler.run(request(uid, {type: "event", contentId: eventId, reason: "Fixture report"})),
      {code: "failed-precondition"});
  assert.equal((await db.collection("reports").where("reporterUid", "==", uid).get()).size, 0);
});
