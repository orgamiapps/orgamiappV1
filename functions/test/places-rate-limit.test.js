"use strict";

const assert = require("node:assert/strict");
const test = require("node:test");
const {
  PLACES_RATE_LIMIT,
  PLACES_RATE_WINDOW_MS,
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
