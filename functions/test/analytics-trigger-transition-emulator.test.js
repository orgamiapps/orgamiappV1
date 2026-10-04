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
test.after(async () => { await db.terminate(); });

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
