"use strict";

const assert = require("node:assert/strict");
const test = require("node:test");
const {
  PLACES_RATE_LIMIT,
  PLACES_RATE_WINDOW_MS,
  enforceSharedPlacesRateLimit,
  nextRateState,
} = require("../places/rate-limit");

test("shared Places rate state enforces the limit", () => {
  const now = 100000;
  assert.deepEqual(nextRateState(null, now), {
    count: 1,
    windowStartedAtMs: now,
  });
  assert.equal(nextRateState({
    count: PLACES_RATE_LIMIT,
    windowStartedAtMs: now,
  }, now + 100), null);
});

test("shared Places rate state resets after its window", () => {
  const startedAt = 100000;
  const now = startedAt + PLACES_RATE_WINDOW_MS;
  assert.deepEqual(nextRateState({
    count: PLACES_RATE_LIMIT,
    windowStartedAtMs: startedAt,
  }, now), {
    count: 1,
    windowStartedAtMs: now,
  });
});

test("Places permission comes from the committed retry, not a discarded transaction", async () => {
  const now = 100000;
  let attemptedWrites = 0;
  const db = {
    collection: () => ({doc: () => ({id: "rate"})}),
    runTransaction: async (callback) => {
      // Another request fills the last slot after the first attempt's read.
      await callback({get: async () => ({exists: true, data: () => ({count: 59, windowStartedAtMs: now})}), set: () => attemptedWrites++});
      return callback({get: async () => ({exists: true, data: () => ({count: 60, windowStartedAtMs: now})}), set: () => assert.fail("denied retry cannot write")});
    },
  };
  await assert.rejects(enforceSharedPlacesRateLimit(db, "user", now), (error) => error.code === "resource-exhausted");
  assert.equal(attemptedWrites, 1);
});

test("Places successful retry commits exactly the current window state", async () => {
  const now = 100000;
  let committed;
  const db = {
    collection: () => ({doc: () => ({id: "rate"})}),
    runTransaction: async (callback) => {
      await callback({get: async () => ({exists: true, data: () => ({count: 10, windowStartedAtMs: now})}), set: () => {}});
      return callback({get: async () => ({exists: true, data: () => ({count: 11, windowStartedAtMs: now})}), set: (_, data) => { committed = data; }});
    },
  };
  await enforceSharedPlacesRateLimit(db, "user", now);
  assert.equal(committed.count, 12);
});
