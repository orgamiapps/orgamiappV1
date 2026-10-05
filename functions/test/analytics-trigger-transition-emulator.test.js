"use strict";
const test = require("node:test");
const assert = require("node:assert/strict");
const {randomUUID} = require("node:crypto");
if (!/^127\.0\.0\.1:\d+$/.test(process.env.FIRESTORE_EMULATOR_HOST || "")) throw Error("Local Firestore emulator required");
process.env.GCLOUD_PROJECT = "demo-attendus-admin";
process.env.FUNCTIONS_EMULATOR = "true";
const admin = require("../firebase-admin-compat"), db = admin.firestore();
const {createTriggerAIInsights, createTriggerAIInsightsV2} = require("../analytics/insights");
const {reconcileEventUserAnalytics, processUserAnalyticsRecompute,
  requestUserAnalyticsRecompute, commitUserAnalyticsGeneration} = require("../analytics/user-analytics");
const {createLegacyAnalyticsHandlers} = require("../analytics/legacy-operations");
test.after(async () => { await db.terminate(); });

for (const [collection, handler, payload] of [
  ["Attendance", "aggregateAttendance", {customerUid: "member", checkedInAt: new Date("2026-10-03T14:00:00Z")}],
  ["event_feedback", "aggregateFeedback", {rating: 5, isAnonymous: true}],
]) test(`real ${collection} delivery preserves event deletion after preflight`, async () => {
  const id = `legacy-parent-fence-${randomUUID()}`, eventRef = db.doc(`Events/${id}`);
  const sourceRef = db.doc(`${collection}/${id}`), analyticsRef = db.doc(`event_analytics/${id}`);
  try {
    await eventRef.set({customerUid: `owner-${id}`, eventTimeZone: "UTC"});
    await sourceRef.set({eventId: id, ...payload});
    const event = {params: {docId: id}, data: await sourceRef.get()};
    assert.equal((await createLegacyAnalyticsHandlers(admin)[handler](event)).processed, true);
    assert.equal((await analyticsRef.get()).exists, true);
    await db.recursiveDelete(analyticsRef);
    const firestore = Object.assign(() => ({collection: db.collection.bind(db), runTransaction: async (body) => {
      await eventRef.delete();
      return db.runTransaction(body);
    }}), {FieldValue: admin.firestore.FieldValue});
    assert.equal((await createLegacyAnalyticsHandlers({firestore})[handler](event)).skipped, true);
    await createLegacyAnalyticsHandlers(admin)[handler](event);
    assert.equal((await eventRef.get()).exists, false);
    assert.equal((await sourceRef.get()).exists, true);
    assert.equal((await analyticsRef.get()).exists, false);
    assert.deepEqual(await analyticsRef.listCollections(), []);
  } finally {
    await db.recursiveDelete(analyticsRef);
    await sourceRef.delete();
    await eventRef.delete();
  }
});

test("actual Firestore serializes overlapping legacy/written insight delivery and preserves deletion", async () => {
  const id = `insights-transition-${randomUUID()}`;
  await db.doc(`Events/${id}`).set({customerUid: "fixture-owner"});
  await db.doc(`event_analytics/${id}`).set({totalAttendees: 4, hourlySignIns: {"09:00": 4}});
  const legacy = createTriggerAIInsights(admin), replacement = createTriggerAIInsightsV2(admin);
  const event = {params: {docId: id}};
  const results = await Promise.all([legacy.run(event), replacement.run(event), replacement.run(event)]);
  assert.equal(results.filter((result) => result.updated).length, 1);
  assert.equal(results.filter((result) => result.replayed).length, 2);
  const initial = await db.doc(`ai_insights/${id}`).get();
  await legacy.run(event);
  assert.equal((await db.doc(`ai_insights/${id}`).get()).updateTime.toMillis(), initial.updateTime.toMillis());
  await db.doc(`event_analytics/${id}`).delete();
  await Promise.all([replacement.run(event), legacy.run(event)]);
  assert.equal((await db.doc(`ai_insights/${id}`).get()).exists, false);
});

test("real transactions preserve totals then remove final owner state without delayed-delivery resurrection", async () => {
  const suffix = randomUUID(), owner = `analytics-owner-${suffix}`;
  const ids = [`analytics-first-${suffix}`, `analytics-second-${suffix}`];
  const refs = [...ids.flatMap((id) => [`Events/${id}`, `event_analytics/${id}`]),
    `user_analytics/${owner}`, `_user_analytics_recompute/${owner}`].map((name) => db.doc(name));
  try {
    for (const [i, id] of ids.entries()) {
      await db.doc(`Events/${id}`).set({customerUid: owner});
      await db.doc(`event_analytics/${id}`).set({totalAttendees: i ? 3 : 7});
      await reconcileEventUserAnalytics(admin, id, {reason: "event_create", expectedOwner: owner, initialize: true});
    }
    await processUserAnalyticsRecompute(admin, owner);
    assert.equal((await db.doc(`user_analytics/${owner}`).get()).get("totalAttendees"), 10);
    await db.doc(`Events/${ids[0]}`).delete();
    await reconcileEventUserAnalytics(admin, ids[0], {reason: "event_delete", expectedOwner: owner, deleted: true});
    await processUserAnalyticsRecompute(admin, owner);
    const remaining = await db.doc(`user_analytics/${owner}`).get();
    assert.equal(remaining.get("totalEvents"), 1);
    assert.equal(remaining.get("totalAttendees"), 3);
    await db.doc(`Events/${ids[1]}`).delete();
    await reconcileEventUserAnalytics(admin, ids[1], {reason: "event_delete", expectedOwner: owner, deleted: true});
    const terminal = await db.doc(`_user_analytics_recompute/${owner}`).get();
    assert.equal(terminal.exists, true);
    assert.equal(terminal.get("processedGeneration"), terminal.get("requestedGeneration"));
    // Explicit cleanup of the unique synthetic owner removes its terminal fence.
    await db.doc(`_user_analytics_recompute/${owner}`).delete();
    for (const id of ids) {
      await reconcileEventUserAnalytics(admin, id, {reason: "event_delete", expectedOwner: owner, deleted: true});
      await reconcileEventUserAnalytics(admin, id, {reason: "event_create", expectedOwner: owner, initialize: true});
      await reconcileEventUserAnalytics(admin, id, {reason: "event_analytics_write"});
    }
    for (const ref of refs) assert.equal((await ref.get()).exists, false, ref.path);
  } finally {
    for (const ref of refs) await ref.delete();
  }
});

test("real current-event and deletion-job reads fence old owner deliveries", async () => {
  const suffix = randomUUID(), id = `analytics-recreated-${suffix}`;
  const oldOwner = `old-owner-${suffix}`, owner = `new-owner-${suffix}`;
  const refs = [`Events/${id}`, `event_analytics/${id}`, `account_deletion_jobs/${owner}`,
    ...[oldOwner, owner].flatMap((uid) => [`user_analytics/${uid}`, `_user_analytics_recompute/${uid}`])].map((name) => db.doc(name));
  try {
    await db.doc(`Events/${id}`).set({customerUid: owner});
    await db.doc(`event_analytics/${id}`).set({totalAttendees: 11});
    await reconcileEventUserAnalytics(admin, id, {reason: "event_delete", expectedOwner: oldOwner, deleted: true});
    await reconcileEventUserAnalytics(admin, id, {reason: "event_create", expectedOwner: oldOwner, initialize: true});
    assert.equal((await db.doc(`event_analytics/${id}`).get()).get("totalAttendees"), 11);
    assert.equal((await db.doc(`_user_analytics_recompute/${oldOwner}`).get()).exists, false);
    await db.doc(`account_deletion_jobs/${owner}`).set({status: "requested"});
    await reconcileEventUserAnalytics(admin, id, {reason: "event_create", expectedOwner: owner, initialize: true});
    await reconcileEventUserAnalytics(admin, id, {reason: "event_analytics_write"});
    assert.equal((await db.doc(`_user_analytics_recompute/${owner}`).get()).exists, false);
    assert.equal((await db.doc(`event_analytics/${id}`).get()).get("totalAttendees"), 11);
    assert.equal(await requestUserAnalyticsRecompute(admin, owner, "admin_backfill"), null);
    await db.doc(`_user_analytics_recompute/${owner}`).set({requestedGeneration: 1, processedGeneration: 0});
    assert.equal(await commitUserAnalyticsGeneration(admin, owner, 1, {totalEvents: 999}), "account_deleting");
    assert.equal((await processUserAnalyticsRecompute(admin, owner)).status, "account_deleting");
    assert.equal((await db.doc(`user_analytics/${owner}`).get()).exists, false);
  } finally {
    for (const ref of refs) await ref.delete();
  }
});
