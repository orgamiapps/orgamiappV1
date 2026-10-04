"use strict";
const test = require("node:test");
const assert = require("node:assert/strict");
const {memoryAdmin} = require("./helpers/community-memory");
const {createLegacyAnalyticsHandlers} = require("../analytics/legacy-operations");
const {attendeeRetentionRate} = require("../analytics/user-analytics");
async function trigger(admin, collection, id) { return {params: {docId: id}, data: await admin.db.collection(collection).doc(id).get()}; }

test("host retention counts distinct events rather than same-event reentry or voided attendance", () => {
  const docs = [
    {customerUid: "single", eventId: "one"}, {customerUid: "single", eventId: "one"},
    {customerUid: "single", eventId: "two", voided: true},
    {customerUid: "repeat", eventId: "one"}, {customerUid: "repeat", eventId: "two"},
    {customerUid: "pre-registered", eventId: "one"},
  ].map((data) => ({get: (field) => data[field]}));
  assert.equal(attendeeRetentionRate(docs), 50);
});

test("attendance trigger replay increments once and uses actual registration denominator", async () => {
  const admin = memoryAdmin({"Events/event": {customerUid: "host", eventTimeZone: "America/New_York"},
    "Attendance/attended": {eventId: "event", customerUid: "member", checkedInAt: new Date("2026-10-03T14:00:00Z")},
    "RegisterAttendance/member": {eventId: "event", status: "confirmed"}, "RegisterAttendance/second": {eventId: "event", status: "confirmed"}});
  const operations = createLegacyAnalyticsHandlers(admin);
  const event = await trigger(admin, "Attendance", "attended");
  await Promise.all([operations.aggregateAttendance(event), operations.aggregateAttendance(event)]);
  const analytics = admin.db.values.get("event_analytics/event");
  assert.equal(analytics.totalAttendees, 1); assert.equal(analytics.dropoutRate, 50); assert.equal(analytics.hourlySignIns["10:00"], 1);
});
test("feedback trigger replay is exact, malformed ratings are ignored, and deleted source is not resurrected", async () => {
  const admin = memoryAdmin({"event_feedback/good": {eventId: "event", rating: 5, isAnonymous: true, comment: "Good"},
    "event_feedback/bad": {eventId: "event", rating: "5"}, "event_feedback/deleted": {eventId: "event", rating: 1}});
  const operations = createLegacyAnalyticsHandlers(admin);
  const event = await trigger(admin, "event_feedback", "good");
  await Promise.all([operations.aggregateFeedback(event), operations.aggregateFeedback(event)]);
  await operations.aggregateFeedback(await trigger(admin, "event_feedback", "bad"));
  const removed = await trigger(admin, "event_feedback", "deleted");
  admin.db.values.delete("event_feedback/deleted");
  await operations.aggregateFeedback(removed);
  const analytics = admin.db.values.get("event_analytics/event").feedbackAnalytics;
  assert.equal(analytics.totalRatings, 1); assert.equal(analytics.averageRating, 5); assert.equal(analytics.anonymousCount, 1);
});
test("monthly reset handles over 500 subscriptions and retries preserve new usage and future periods", async () => {
  const initial = {};
  for (let index = 0; index < 501; index++) initial[`subscriptions/user-${String(index).padStart(4, "0")}`] = {tier: "basic", status: "active", currentMonthStart: new Date("2026-09-01"), eventsCreatedThisMonth: 4};
  initial["subscriptions/future"] = {tier: "basic", status: "active", currentMonthStart: new Date("2026-11-01"), eventsCreatedThisMonth: 3};
  const admin = memoryAdmin(initial);
  const reset = createLegacyAnalyticsHandlers(admin).resetMonthly;
  assert.equal((await reset({scheduleTime: "2026-10-01T00:00:00Z"})).count, 501);
  admin.db.values.get("subscriptions/user-0000").eventsCreatedThisMonth = 2;
  assert.equal((await reset({scheduleTime: "2026-10-01T00:00:00Z"})).count, 0);
  assert.equal(admin.db.values.get("subscriptions/user-0000").eventsCreatedThisMonth, 2);
  assert.equal(admin.db.values.get("subscriptions/future").eventsCreatedThisMonth, 3);
});
