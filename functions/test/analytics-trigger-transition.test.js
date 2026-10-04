"use strict";
const test = require("node:test");
const assert = require("node:assert/strict");
const {memoryAdmin} = require("./helpers/community-memory");
const {createTriggerAIInsights, createTriggerAIInsightsV2} = require("../analytics/insights");

test("analytics transition keeps the deployed updated trigger and adds a distinct written trigger", () => {
  const admin = memoryAdmin();
  for (const [factory, type] of [[createTriggerAIInsights, "updated"], [createTriggerAIInsightsV2, "written"]]) {
    const trigger = factory(admin).__endpoint;
    assert.equal(trigger.eventTrigger.eventType, `google.cloud.firestore.document.v1.${type}`);
    assert.equal(trigger.eventTrigger.eventFilterPathPatterns.document, "event_analytics/{docId}");
    assert.deepEqual(trigger.region, ["us-central1"]);
    assert.equal(trigger.eventTrigger.retry, true);
  }
});

test("deployed trigger completion logs bind source version and delivery without analytics content", async (t) => {
  const logs = [];
  t.mock.method(require("firebase-functions/logger"), "info", (message, fields) => logs.push({message, fields}));
  const admin = memoryAdmin({"Events/event": {customerUid: "owner"}, "event_analytics/event": {totalAttendees: 2}});
  await createTriggerAIInsights(admin).run({id: "delivery", params: {docId: "event"}, data: {after: {updateTime: {toDate: () => new Date("2026-10-04T10:00:00Z")}}}});
  assert.deepEqual(logs[0].fields, {eventId: "event", deliveryId: "delivery", triggerName: "triggerAIInsights", sourceVersion: "2026-10-04T10:00:00.000Z", outcome: "updated"});
  assert.equal(JSON.stringify(logs).includes("totalAttendees"), false);
});

test("old and new overlapping updates commit one insight generation and replay safely", async () => {
  const admin = memoryAdmin({"Events/event": {customerUid: "owner"}, "event_analytics/event": {
    totalAttendees: 3, hourlySignIns: {"09:00": 3}, feedbackAnalytics: {commentSummaries: ["great"]},
  }});
  const legacy = createTriggerAIInsights(admin), replacement = createTriggerAIInsightsV2(admin);
  const trigger = {params: {docId: "event"}};
  const result = await Promise.all([legacy.run(trigger), replacement.run(trigger)]);
  assert.equal(result.filter((item) => item.updated).length, 1);
  assert.equal(result.filter((item) => item.replayed).length, 1);
  const original = admin.db.values.get("ai_insights/event");
  assert.equal(original.sentimentAnalysis.positiveCount, 1);
  assert.deepEqual(await replacement.run(trigger), {replayed: true});
  assert.deepEqual(admin.db.values.get("ai_insights/event"), original);
  admin.db.values.get("event_analytics/event").feedbackAnalytics.commentSummaries = ["terrible"];
  await Promise.all([replacement.run(trigger), legacy.run(trigger)]);
  assert.equal(admin.db.values.get("ai_insights/event").sentimentAnalysis.negativeCount, 1);
});

test("written trigger handles creation/deletion and delayed legacy updates cannot resurrect removed data", async () => {
  const admin = memoryAdmin({"Events/event": {customerUid: "owner"}, "event_analytics/event": {totalAttendees: 1}});
  const legacy = createTriggerAIInsights(admin), replacement = createTriggerAIInsightsV2(admin);
  const trigger = {params: {docId: "event"}};
  assert.deepEqual(await replacement.run(trigger), {updated: true});
  admin.db.values.delete("event_analytics/event");
  assert.deepEqual(await replacement.run(trigger), {removed: true});
  await legacy.run(trigger);
  assert.equal(admin.db.values.has("ai_insights/event"), false);
  admin.db.values.set("event_analytics/event", {totalAttendees: 2});
  admin.db.values.set("account_deletion_jobs/owner", {status: "requested"});
  await Promise.all([replacement.run(trigger), legacy.run(trigger)]);
  assert.equal(admin.db.values.has("ai_insights/event"), false);
});
