"use strict";

const test = require("node:test");
const assert = require("node:assert/strict");
const {distanceMeters, validateInput} = require("../guest/attendance");
const {validate: validateFunnel} = require("../product/funnel");

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
