"use strict";
const test = require("node:test");
const assert = require("node:assert/strict");
const {randomUUID} = require("node:crypto");
if (!/^127\.0\.0\.1:\d+$/.test(process.env.FIRESTORE_EMULATOR_HOST || "")) throw Error("Local Firestore emulator required");
process.env.GCLOUD_PROJECT = "demo-attendus-admin";
process.env.FUNCTIONS_EMULATOR = "true";
const admin = require("../firebase-admin-compat"), db = admin.firestore();
const {createTriggerAIInsights, createTriggerAIInsightsV2} = require("../analytics/insights");
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
