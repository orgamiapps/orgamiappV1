"use strict";
const test = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const vm = require("node:vm");
const {memoryAdmin} = require("./helpers/community-memory");
const {createTriggerAIInsights, createTriggerAIInsightsV2} = require("../analytics/insights");

// Execute the actual exported handler bodies without starting unrelated index
// integrations or initializing a real Firebase application.
function actualUserAnalyticsHandlers(admin) {
  const source = fs.readFileSync(path.join(__dirname, "../index.js"), "utf8").replace(/\r\n/g, "\n");
  const start = source.indexOf("exports.aggregateUserAnalyticsV2 =");
  const end = source.indexOf("/**\n * Send scheduled notifications", start);
  assert.ok(start >= 0 && end > start);
  const exports = {};
  const context = {exports, admin, ...require("../analytics/user-analytics"),
    onDocumentWritten: (_, handler) => handler, onDocumentCreated: (_, handler) => handler,
    onDocumentDeleted: (_, handler) => handler, logger: {info() {}, error() {}}};
  vm.runInNewContext(source.slice(start, end), context);
  return exports;
}

function analyticsAdmin(initial = {}) {
  const admin = memoryAdmin(initial);
  admin.firestore.Timestamp.now = () => new Date();
  const collection = admin.db.collection;
  admin.db.collection = (name) => {
    const result = collection(name), doc = result.doc;
    result.doc = (id) => ({...doc(id), delete: async () => admin.db.values.delete(`${name}/${id}`)});
    return result;
  };
  return admin;
}

function delivery(owner = "owner") {
  return {params: {eventId: "event"}, data: {data: () => ({customerUid: owner})}};
}

function retryAfterReads(admin, change) {
  const run = admin.db.runTransaction;
  let first = true;
  admin.db.runTransaction = async (callback) => {
    if (first) {
      first = false;
      await callback({get: (ref) => ref.get(), set() {}, create() {}, delete() {}, update() {}});
      change(admin.db.values);
    }
    return run(callback);
  };
}

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

test("actual delayed create and duplicate delete handlers cannot resurrect cleaned analytics", async () => {
  for (const name of ["updateUserAnalyticsOnEventCreateV2", "updateUserAnalyticsOnEventDeleteV2"]) {
    const admin = analyticsAdmin();
    await actualUserAnalyticsHandlers(admin)[name](delivery());
    assert.equal(admin.db.values.size, 0, `${name} recreated deleted analytics state`);
  }
});

test("old delete preserves analytics of a recreated event under its current owner", async () => {
  const analytics = {totalAttendees: 27, repeatAttendees: 3};
  const admin = analyticsAdmin({"Events/event": {customerUid: "new-owner"}, "event_analytics/event": analytics});
  await actualUserAnalyticsHandlers(admin).updateUserAnalyticsOnEventDeleteV2(delivery("old-owner"));
  assert.deepEqual(admin.db.values.get("event_analytics/event"), analytics);
  assert.equal(admin.db.values.has("_user_analytics_recompute/old-owner"), false);
});

test("stale create owner and account deletion fence initialization and enqueue", async () => {
  for (const initial of [{"Events/event": {customerUid: "new-owner"}},
    {"Events/event": {customerUid: "owner"}, "account_deletion_jobs/owner": {status: "requested"}}]) {
    const admin = analyticsAdmin(initial);
    await actualUserAnalyticsHandlers(admin).updateUserAnalyticsOnEventCreateV2(delivery());
    assert.equal(admin.db.values.has("event_analytics/event"), false);
    assert.equal(admin.db.values.has("_user_analytics_recompute/owner"), false);
  }
});

test("actual aggregate write rechecks Event inside the enqueue transaction", async () => {
  const admin = analyticsAdmin({"Events/event": {customerUid: "owner"}});
  const run = admin.db.runTransaction;
  admin.db.runTransaction = (callback) => {admin.db.values.delete("Events/event"); return run(callback);};
  await actualUserAnalyticsHandlers(admin).aggregateUserAnalyticsV2(delivery());
  assert.equal(admin.db.values.has("_user_analytics_recompute/owner"), false);
});

test("retried create transaction honors source removal and newly requested account deletion", async () => {
  for (const change of [(values) => values.delete("Events/event"),
    (values) => values.set("account_deletion_jobs/owner", {status: "requested"})]) {
    const admin = analyticsAdmin({"Events/event": {customerUid: "owner"}});
    retryAfterReads(admin, change);
    await actualUserAnalyticsHandlers(admin).updateUserAnalyticsOnEventCreateV2(delivery());
    assert.equal(admin.db.values.has("event_analytics/event"), false);
    assert.equal(admin.db.values.has("_user_analytics_recompute/owner"), false);
  }
});

test("current create preserves totals and cleanup followed by delayed deliveries stays empty", async () => {
  const admin = analyticsAdmin({"Events/event": {customerUid: "owner"},
    "event_analytics/event": {totalAttendees: 19, repeatAttendees: 4}});
  const handlers = actualUserAnalyticsHandlers(admin);
  await handlers.updateUserAnalyticsOnEventCreateV2(delivery());
  assert.equal(admin.db.values.get("event_analytics/event").totalAttendees, 19);
  assert.equal(admin.db.values.get("_user_analytics_recompute/owner").requestedGeneration, 1);
  admin.db.values.set("user_analytics/owner", {totalEvents: 1});
  admin.db.values.delete("Events/event");
  await handlers.updateUserAnalyticsOnEventDeleteV2(delivery());
  const terminal = admin.db.values.get("_user_analytics_recompute/owner");
  assert.equal(terminal.requestedGeneration, 2);
  assert.equal(terminal.processedGeneration, 2);
  // The isolated canary explicitly removes its terminal fence during cleanup.
  admin.db.values.delete("_user_analytics_recompute/owner");
  await handlers.updateUserAnalyticsOnEventDeleteV2(delivery());
  await handlers.aggregateUserAnalyticsV2(delivery());
  await handlers.updateUserAnalyticsOnEventCreateV2(delivery());
  assert.equal(admin.db.values.size, 0);
});

test("last-delete and new-event creation cannot reuse an old worker generation", async () => {
  const {commitUserAnalyticsGeneration, processUserAnalyticsRecompute} = require("../analytics/user-analytics");
  const admin = analyticsAdmin({"Events/event": {customerUid: "owner"}});
  const handlers = actualUserAnalyticsHandlers(admin);
  await handlers.updateUserAnalyticsOnEventCreateV2(delivery());
  const originalGeneration = admin.db.values.get("_user_analytics_recompute/owner").requestedGeneration;
  admin.db.values.delete("Events/event");
  await handlers.updateUserAnalyticsOnEventDeleteV2(delivery());
  admin.db.values.set("Events/new-event", {customerUid: "owner", title: "Current event"});
  await handlers.updateUserAnalyticsOnEventCreateV2({...delivery(), params: {eventId: "new-event"}});
  const requested = admin.db.values.get("_user_analytics_recompute/owner").requestedGeneration;
  assert.ok(requested > originalGeneration);
  assert.notEqual(await commitUserAnalyticsGeneration(admin, "owner", originalGeneration,
      {totalEvents: 999, eventAnalytics: {event: {attendees: 999}}}), "committed");
  assert.equal(admin.db.values.has("user_analytics/owner"), false);
  await processUserAnalyticsRecompute(admin, "owner");
  const current = admin.db.values.get("user_analytics/owner");
  assert.equal(current.totalEvents, 1);
  assert.deepEqual(Object.keys(current.eventAnalytics), ["new-event"]);
});

test("deletion still requests recompute for an owner with another current event", async () => {
  const admin = analyticsAdmin({"Events/other": {customerUid: "owner"},
    "event_analytics/event": {totalAttendees: 19}, "event_analytics/other": {totalAttendees: 7},
    "_user_analytics_recompute/owner": {requestedGeneration: 4, processedGeneration: 4}});
  await actualUserAnalyticsHandlers(admin).updateUserAnalyticsOnEventDeleteV2(delivery());
  assert.equal(admin.db.values.has("event_analytics/event"), false);
  assert.equal(admin.db.values.get("event_analytics/other").totalAttendees, 7);
  assert.equal(admin.db.values.get("_user_analytics_recompute/owner").requestedGeneration, 5);
});

test("retried delete preserves analytics when event is recreated between attempts", async () => {
  const admin = analyticsAdmin({"event_analytics/event": {totalAttendees: 19}});
  retryAfterReads(admin, (values) => {
    values.set("Events/event", {customerUid: "new-owner"});
    values.set("event_analytics/event", {totalAttendees: 2});
  });
  await actualUserAnalyticsHandlers(admin).updateUserAnalyticsOnEventDeleteV2(delivery());
  assert.equal(admin.db.values.get("event_analytics/event").totalAttendees, 2);
  assert.equal(admin.db.values.has("_user_analytics_recompute/owner"), false);
});

test("all account deletion states fence generic analytics request, processor, and stale commit", async () => {
  const {requestUserAnalyticsRecompute, processUserAnalyticsRecompute, commitUserAnalyticsGeneration} = require("../analytics/user-analytics");
  for (const status of ["requested", "processing", "review_required", "complete"]) {
    const admin = analyticsAdmin({"account_deletion_jobs/owner": {status},
      "_user_analytics_recompute/owner": {requestedGeneration: 1, processedGeneration: 0},
      "Events/event": {customerUid: "owner"}});
    assert.equal(await requestUserAnalyticsRecompute(admin, "owner", "admin_backfill"), null);
    assert.equal((await processUserAnalyticsRecompute(admin, "owner")).status, "account_deleting");
    assert.equal(await commitUserAnalyticsGeneration(admin, "owner", 1, {totalEvents: 999}), "account_deleting");
    assert.equal(admin.db.values.has("user_analytics/owner"), false);
    admin.db.values.delete("_user_analytics_recompute/owner");
    assert.equal(await requestUserAnalyticsRecompute(admin, "owner", "admin_backfill"), null);
    assert.equal(admin.db.values.has("_user_analytics_recompute/owner"), false);
  }
});

test("account deletion appearing during request or commit transaction retry suppresses all new writes", async () => {
  const {requestUserAnalyticsRecompute, commitUserAnalyticsGeneration} = require("../analytics/user-analytics");
  for (const kind of ["request", "commit"]) {
    const admin = analyticsAdmin(kind === "commit" ? {"_user_analytics_recompute/owner": {requestedGeneration: 1, processedGeneration: 0}} : {});
    retryAfterReads(admin, (values) => values.set("account_deletion_jobs/owner", {status: "complete"}));
    if (kind === "request") assert.equal(await requestUserAnalyticsRecompute(admin, "owner", "admin_backfill"), null);
    else assert.equal(await commitUserAnalyticsGeneration(admin, "owner", 1, {totalEvents: 999}), "account_deleting");
    assert.equal(admin.db.values.has("user_analytics/owner"), false);
    assert.equal(admin.db.values.has("_user_analytics_recompute/owner"), kind === "commit");
  }
});
