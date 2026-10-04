"use strict";

const test = require("node:test");
const assert = require("node:assert/strict");
const {distanceMeters, validateInput} = require("../guest/attendance");
const {validate: validateFunnel, createRecordProductFunnelEvent, createAggregateProductFunnelDaily} = require("../product/funnel");
const {Firestore} = require("@google-cloud/firestore");

test("guest attendance input accepts a safe named check-in", () => {
  assert.deepEqual(validateInput({
    eventId: "event-a",
    method: "manual_code",
    fullName: "Renée O'Neil",
    answers: ["Dietary needs--ans--None"],
  }), {
    eventId: "event-a",
    method: "manual_code",
    fullName: "Renée O'Neil",
    answers: ["Dietary needs--ans--None"],
  });
});

test("guest attendance input rejects unsupported methods and unsafe names", () => {
  assert.throws(() => validateInput({
    eventId: "event-a", method: "facial_recognition", fullName: "Guest User", answers: [],
  }));
  assert.throws(() => validateInput({
    eventId: "event-a", method: "qr_code", fullName: "<script>", answers: [],
  }));
});

test("server geofence distance calculation is stable", () => {
  assert.equal(distanceMeters(40, -75, 40, -75), 0);
  assert.ok(distanceMeters(40, -75, 40.001, -75) > 100);
});

test("funnel validation rejects sensitive and unknown dimensions", () => {
  assert.deepEqual(validateFunnel({
    event: "guest_checkin_completed",
    sessionId: "a".repeat(32),
    dimensions: {checkInMethod: "qr_code", result: "success"},
  }).event, "guest_checkin_completed");
  assert.throws(() => validateFunnel({
    event: "guest_checkin_completed",
    sessionId: "a".repeat(32),
    dimensions: {fullName: "Jordan Lee"},
  }));
});

test("funnel rate limit rejects a final denied retry without writing an event", async () => {
  let attemptedWrites = 0;
  const db = {
    collection: (name) => {
      assert.equal(name, "service_rate_limits", "rejected calls must not append analytics");
      return {doc: () => ({id: "rate"})};
    },
    runTransaction: async (callback) => {
      const now = Date.now();
      await callback({get: async () => ({exists: true, data: () => ({count: 119, windowStartedAtMs: now})}), set: () => attemptedWrites++});
      return callback({get: async () => ({exists: true, data: () => ({count: 120, windowStartedAtMs: now})}), set: () => assert.fail("denied retry cannot write")});
    },
  };
  const callable = createRecordProductFunnelEvent({firestore: () => db});
  await assert.rejects(callable.run({auth: {uid: "user"}, data: {
    event: "guest_discover_view", sessionId: "a".repeat(32), dimensions: {},
  }}), (error) => error.code === "resource-exhausted");
  assert.equal(attemptedWrites, 1);
});

test("funnel successful retry appends one event after committed rate reservation", async () => {
  const events = [];
  let committed;
  const db = {
    collection: (name) => name === "service_rate_limits" ? {doc: () => ({id: "rate"})} : {add: async (data) => events.push(data)},
    runTransaction: async (callback) => {
      const now = Date.now();
      await callback({get: async () => ({exists: true, data: () => ({count: 2, windowStartedAtMs: now})}), set: () => {}});
      return callback({get: async () => ({exists: true, data: () => ({count: 3, windowStartedAtMs: now})}), set: (_, data) => { committed = data; }});
    },
  };
  const callable = createRecordProductFunnelEvent({firestore: () => db});
  const result = await callable.run({auth: {uid: "user", token: {firebase: {sign_in_provider: "anonymous"}}}, data: {
    event: "guest_discover_view", sessionId: "b".repeat(32), dimensions: {entryPoint: "home"},
  }});
  assert.deepEqual(result, {accepted: true});
  assert.equal(committed.count, 4);
  assert.equal(events.length, 1);
  assert.equal(events[0].accessMode, "guest");
});

test("daily funnel safely counts prototype-named dimensions through Firestore serialization", async () => {
  const values = ["__proto__", "constructor", "toString", "__proto__"];
  const docs = values.map((value, index) => ({data: () => validateFunnel({
    event: index % 2 ? "discovery_card_open" : "discovery_view",
    sessionId: String(index).repeat(32),
    dimensions: {entryPoint: value, checkInMethod: value, feature: value},
  })}));
  let summary;
  const query = {where: () => query, get: async () => ({docs})};
  const db = {collection: (name) => name === "product_funnel_events" ? query : {
    doc: () => ({set: async (data) => { summary = data; }}),
  }};
  await createAggregateProductFunnelDaily({firestore: () => db}).run({});
  const reservedKey = `%${Buffer.from("__proto__").toString("base64url")}`;
  const serializer = new Firestore({projectId: "demo-attendus-admin"})._serializer;
  for (const counts of [summary.byEntryPoint, summary.byCheckInMethod, summary.byFeature]) {
    assert.equal(Object.getPrototypeOf(counts), null);
    assert.deepEqual(JSON.parse(JSON.stringify(counts)), {[reservedKey]: 2, constructor: 1, toString: 1});
    const encoded = serializer.encodeFields(counts);
    assert.deepEqual(Object.keys(encoded).sort(), [reservedKey, "constructor", "toString"].sort());
    assert.equal(Number(encoded[reservedKey].integerValue), 2);
    assert.equal(Object.getPrototypeOf(encoded), Object.prototype);
  }
  assert.equal(summary.dimensionKeyEncoding, "reserved-base64url-v1");
  assert.equal(summary.counts.discovery_view, 2);
  assert.equal(summary.counts.discovery_card_open, 2);
  assert.equal(summary.discovery.eventDetailCtr, 1);
  assert.equal(summary.sessions, 4);
  assert.equal({}.polluted, undefined);
});
