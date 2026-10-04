"use strict";
const test = require("node:test");
const assert = require("node:assert/strict");
const {memoryAdmin} = require("./helpers/community-memory");
const {activePublicEvent, eventDto, decodeCursor, boundedNumber} = require("../discovery/marketplace");
const {createNaturalSearchHandler, parseQuerySimple, searchInput} = require("../discovery/natural-search");
const {createDiscoveryMaintenanceHandlers, cleanupDiscoveryAccountData} = require("../discovery/maintenance");
const {createInsightsHandler, analyzeSentiment, generateOptimizations} = require("../analytics/insights");
const {normalizeDraftForm} = require("../events/wizard-core");
const {eventDocument} = require("../events/wizard");
const {contactExposure, scrubHiddenPublishedContact} = require("../events/public-contact-privacy");

test("all discovery eligibility and DTO paths exclude unpublished events and private nested fields", () => {
  const event = {private: false, status: "scheduled", selectedDateTime: new Date(Date.now() + 86400000),
    checkInCode: "secret", accessList: ["private-member"], experience: {checkInStaff: ["staff"], coHosts: ["host"],
      publicContact: {visible: false, email: "hidden@example.test"}, agenda: [{title: "Welcome", privateNotes: "secret"}]},
    registrationPolicy: {mode: "rsvp", privateNotes: "secret"}};
  assert.equal(activePublicEvent(event), true);
  for (const update of [{status: "rejected"}, {status: undefined}, {private: undefined}, {isHidden: true}, {deleted: true}]) assert.equal(activePublicEvent({...event, ...update}), false);
  const dto = eventDto({id: "event", data: () => event});
  assert.equal(dto.checkInCode, undefined); assert.equal(dto.accessList, undefined);
  assert.equal(dto.experience.coHosts, undefined); assert.equal(dto.experience.checkInStaff, undefined);
  assert.equal(dto.experience.publicContact.email, undefined); assert.equal(dto.experience.agenda[0].privateNotes, undefined);
  assert.equal(dto.registrationPolicy.privateNotes, undefined);
});

test("natural-language cloud search remains guest accessible but only returns bounded public DTOs", async () => {
  const when = new Date(Date.now() + 86400000);
  const event = {private: false, status: "scheduled", title: "Music", categories: ["music"], selectedDateTime: when, accessList: ["secret-member"]};
  const admin = memoryAdmin({"Events/public": event, "Events/pending": {...event, status: "pending_approval"}, "Events/rejected": {...event, status: "rejected"},
    "Events/hidden": {...event, isHidden: true}, "Events/private": {...event, private: true}});
  const handler = createNaturalSearchHandler(admin);
  const result = await handler({data: {query: "music", limit: 1}, rawRequest: {ip: "192.0.2.1"}});
  assert.deepEqual(result.events.map((item) => item.id), ["public"]);
  assert.equal(result.events[0].accessList, undefined);
  for (let count = 1; count < 30; count++) await handler({data: {query: "events"}, rawRequest: {ip: "192.0.2.1"}});
  await assert.rejects(handler({data: {query: "events"}, rawRequest: {ip: "192.0.2.1"}}), {code: "resource-exhausted"});
});

test("search rejects malformed limits, coordinates and cursor offsets; temporal words are not title keywords", () => {
  for (const limit of [-1, 0, 1.5, "5", Infinity, 101]) assert.throws(() => searchInput({query: "events", limit}), {code: "invalid-argument"});
  assert.throws(() => searchInput({query: "near me", lat: null, lng: 0}), {code: "invalid-argument"});
  assert.throws(() => boundedNumber("invalid", 25, 1, 100), {code: "invalid-argument"});
  assert.throws(() => boundedNumber(2.5, 24, 1, 50, true), {code: "invalid-argument"});
  for (const offset of [-1, 1.5, "4", null, 10001]) assert.throws(() => decodeCursor(Buffer.from(JSON.stringify({offset})).toString("base64url")), {code: "invalid-argument"});
  assert.equal(decodeCursor(Buffer.from(JSON.stringify({offset: 24})).toString("base64url")), 24);
  assert.deepEqual(parseQuerySimple("events tomorrow near me within 25 miles").keywords, []);
  assert.deepEqual(parseQuerySimple("events today").keywords, []);
});

test("saved-event counters follow live state across duplicate and reordered triggers without resurrecting deleted events", async () => {
  const admin = memoryAdmin({"Events/event": {saveCount: 0}, "Customers/member/SavedEvents/event": {eventId: "event"}});
  const handlers = createDiscoveryMaintenanceHandlers(admin), trigger = {params: {uid: "member", eventId: "event"}};
  await Promise.all([handlers.saved(trigger), handlers.saved(trigger)]);
  assert.equal(admin.db.values.get("Events/event").saveCount, 1);
  admin.db.values.delete("Customers/member/SavedEvents/event");
  await handlers.saved(trigger); await handlers.saved(trigger);
  assert.equal(admin.db.values.get("Events/event").saveCount, 0);
  admin.db.values.set("Customers/member/SavedEvents/event", {eventId: "event"});
  await handlers.saved(trigger);
  assert.equal(admin.db.values.get("Events/event").saveCount, 1);
  admin.db.values.delete("Events/event");
  await handlers.saved(trigger);
  assert.equal(admin.db.values.has("Events/event"), false);
  assert.equal([...admin.db.values.keys()].filter((key) => key.startsWith("DiscoverySavedEventStates/")).length, 0);
});

test("saved-event deletion reconciliation is leased, idempotent and does not retain the account marker", async () => {
  const admin = memoryAdmin({"Events/event": {saveCount: 0}, "Customers/member/SavedEvents/event": {eventId: "event"}});
  const handler = createDiscoveryMaintenanceHandlers(admin).saved, trigger = {params: {uid: "member", eventId: "event"}};
  await handler(trigger);
  const job = admin.db.doc("account_deletion_jobs/member");
  admin.db.values.set(job.path, {status: "running"});
  await assert.rejects(cleanupDiscoveryAccountData(admin.db, "member", {job, lease: {transaction: async () => { throw Error("Lost lease"); }}}), /Lost lease/);
  assert.equal(admin.db.values.get("Events/event").saveCount, 1);
  const counts = {job, lease: {transaction: admin.db.runTransaction}};
  await cleanupDiscoveryAccountData(admin.db, "member", counts);
  await cleanupDiscoveryAccountData(admin.db, "member", counts);
  await handler(trigger);
  assert.equal(admin.db.values.get("Events/event").saveCount, 0);
  assert.equal([...admin.db.values.keys()].filter((key) => key.startsWith("DiscoverySavedEventStates/")).length, 0);
});

test("metadata triggers use current state and never recreate a missing event", async () => {
  const admin = memoryAdmin({"Events/event": {latitude: 35, longitude: -80, city: "Charlotte", regionCode: "nc", countryCode: "us", locationType: "in_person", categories: ["Music"]}});
  const handler = createDiscoveryMaintenanceHandlers(admin).metadata;
  const trigger = {params: {eventId: "event"}, data: {after: {exists: true, data: () => ({latitude: 1, longitude: 1, city: "Stale"})}}};
  await handler(trigger);
  const current = admin.db.values.get("Events/event");
  assert.equal(current.city, "Charlotte"); assert.equal(current.regionCode, "NC"); assert.ok(current.geohash);
  admin.db.values.delete("Events/event");
  await handler(trigger);
  assert.equal(admin.db.values.has("Events/event"), false);
});

test("insights refresh on feedback-only changes, use live analytics and remove deleted-source summaries", async () => {
  const admin = memoryAdmin({"Events/event": {customerUid: "owner"}, "event_analytics/event": {totalAttendees: 5, hourlySignIns: {"09:00": 5}, feedbackAnalytics: {commentSummaries: ["great event"]}}});
  const handler = createInsightsHandler(admin), trigger = {params: {docId: "event"}};
  await handler(trigger);
  let insight = admin.db.values.get("ai_insights/event");
  assert.equal(insight.sentimentAnalysis.positiveCount, 1); assert.equal(insight.isPredictiveModel, false);
  assert.equal((await handler(trigger)).replayed, true);
  admin.db.values.get("event_analytics/event").feedbackAnalytics.commentSummaries = ["terrible event"];
  await handler(trigger);
  insight = admin.db.values.get("ai_insights/event");
  assert.equal(insight.sentimentAnalysis.negativeCount, 1);
  assert.equal(insight.sentimentAnalysis.confidence, null); assert.equal(insight.sentimentAnalysis.confidenceAvailable, false);
  assert.equal(analyzeSentiment([{comment: "great"}]).positiveCount, 1);
  assert.ok(generateOptimizations({totalAttendees: 5, dropoutRate: 30, repeatAttendees: 1}, {peakHour: "09:00"}, {overallSentiment: "negative"})
      .every((item) => !/[+]?[0-9]+%/.test(item.description)));
  admin.db.values.delete("event_analytics/event");
  await handler(trigger);
  assert.equal(admin.db.values.has("ai_insights/event"), false);
});

test("new publication excludes hidden organizer contact while retaining it in the private draft", () => {
  const admin = memoryAdmin();
  const form = normalizeDraftForm({title: "Event", startAt: "2026-10-04T12:00:00Z", endAt: "2026-10-04T13:00:00Z", experience: {publicContact: {name: "Hidden", email: "hidden@example.test", visible: false}}});
  const event = eventDocument(admin, form, {eventId: "event", uid: "owner", groupName: "Group", authorName: "Owner", authorRole: "owner", createdAt: new Date(), status: "scheduled"});
  assert.equal(event.experience.publicContact.email, ""); assert.equal(event.experience.publicContact.name, "");
  assert.equal(form.experience.publicContact.email, "hidden@example.test");
});

test("historical hidden-contact inventory emits only paths and counts and a pure scrub preserves other data", () => {
  const legacy = {private: false, title: "Event", experience: {thingsToBring: ["Book"], publicContact: {visible: false, name: "Private person", email: "secret@example.test"}}};
  const report = contactExposure("event", legacy);
  assert.equal(report.path, "Events/event"); assert.equal(report.hiddenContactFieldCount, 2);
  assert.ok(!JSON.stringify(report).includes("Private person")); assert.ok(!JSON.stringify(report).includes("secret@example.test"));
  const candidate = scrubHiddenPublishedContact(legacy);
  assert.deepEqual(candidate.experience.publicContact, {visible: false, name: "", email: ""});
  assert.deepEqual(candidate.experience.thingsToBring, ["Book"]);
  assert.equal(legacy.experience.publicContact.email, "secret@example.test");
});
