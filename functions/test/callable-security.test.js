"use strict";

const assert = require("node:assert/strict");
const test = require("node:test");
const {HttpsError} = require("firebase-functions/v2/https");
const {
  requireConfirmedOperation,
  requireDataMap,
  requireStringArray,
} = require("../security/callable");

function expectCode(callback, code) {
  assert.throws(callback, (error) => error instanceof HttpsError && error.code === code);
}

test("destructive callables require confirmation, reason, and idempotency", () => {
  expectCode(() => requireConfirmedOperation({}), "failed-precondition");
  expectCode(() => requireConfirmedOperation({confirmation: true}), "invalid-argument");
  assert.deepEqual(requireConfirmedOperation({
    confirmation: true,
    reason: "Requested by the support lead",
    idempotencyKey: "dispatch-123",
  }), {
    reason: "Requested by the support lead",
    idempotencyKey: "dispatch-123",
  });
});

test("recipient lists are bounded, validated, and deduplicated", () => {
  assert.deepEqual(requireStringArray(["user-a", "user-a", "user-b"], "Users", {
    max: 10,
    pattern: /^[A-Za-z0-9_-]+$/,
  }), ["user-a", "user-b"]);
  expectCode(() => requireStringArray([], "Users", {max: 10}), "invalid-argument");
  expectCode(() => requireStringArray(["bad value"], "Users", {
    max: 10,
    pattern: /^[A-Za-z0-9_-]+$/,
  }), "invalid-argument");
});

test("notification data accepts only bounded scalar fields", () => {
  assert.deepEqual(requireDataMap({eventId: "event-1", count: 2}), {
    eventId: "event-1",
    count: "2",
  });
  expectCode(() => requireDataMap({nested: {unsafe: true}}), "invalid-argument");
});


test("idempotency keys bind payload and preserve unknown outcomes", async () => {
  const {memoryAdmin} = require("./helpers/community-memory");
  const {reserveIdempotencyKey} = require("../security/callable");
  const {db} = memoryAdmin();
  const input = {operation: "notify", uid: "admin", key: "request1", fingerprint: "original"};
  const reservation = await reserveIdempotencyKey(db, input);
  await assert.rejects(reserveIdempotencyKey(db, {...input, fingerprint: "changed"}), {code: "failed-precondition"});
  await assert.rejects(reserveIdempotencyKey(db, input), {code: "aborted"});
  db.values.set(reservation.ref.path, {...db.values.get(reservation.ref.path), status: "completed", result: {sent: 1}});
  assert.deepEqual((await reserveIdempotencyKey(db, input)).result, {sent: 1});
});
