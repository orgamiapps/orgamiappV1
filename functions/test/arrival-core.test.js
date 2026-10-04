"use strict";

const test = require("node:test");
const assert = require("node:assert/strict");
const crypto = require("node:crypto");
const core = require("../attendance/arrival-core");

const now = Date.now();
const event = {locationType: "in_person", location: "Test venue", checkInPolicy: {version: 3, profile: "hybrid", openingMode: "scheduled",
  smartArrival: {enabled: true, latitude: 40, longitude: -74, radiusMeters: 150}}};
const position = {latitude: 40, longitude: -74, accuracy: 10, sampledAt: new Date(now).toISOString()};

test("Smart Arrival never activates from legacy location flags", () => {
  assert.equal(core.arrivalPolicy({version: 2, proximityAssist: true, smartArrival: {enabled: true}}).enabled, false);
  assert.throws(() => core.verifyLocation({getLocation: true, latitude: 40, longitude: -74}, position, now));
  assert.equal(core.verifyLocation(event, position, now).verificationLevel, "location_assisted");
});

test("fresh location requires accuracy circle inside boundary", () => {
  for (const patch of [{accuracy: 51}, {accuracy: -1}, {latitude: 100}, {mocked: true},
    {sampledAt: new Date(now - 30001).toISOString()}, {sampledAt: new Date(now + 5001).toISOString()},
    {latitude: 40.0013, accuracy: 20}]) assert.throws(() => core.verifyLocation(event, {...position, ...patch}, now));
  assert.doesNotThrow(() => core.verifyLocation(event, {...position, accuracy: 50}, now));
});

test("boundary rejects staff-only, online, and out-of-range policy", () => {
  assert.throws(() => core.validateBoundary({...event, locationType: "online"}));
  assert.throws(() => core.validateBoundary({...event, checkInPolicy: {...event.checkInPolicy, profile: "staff_entry"}}));
  for (const radiusMeters of [49, 501]) assert.throws(() => core.validateBoundary({...event,
    checkInPolicy: {...event.checkInPolicy, smartArrival: {...event.checkInPolicy.smartArrival, radiusMeters}}}));
});

test("pause history preserves offline observation semantics after resume", () => {
  const state = {transitions: [{atMs: 1000, status: "open"}, {atMs: 2000, status: "paused"}, {atMs: 3000, status: "open"}]};
  const window = {opensAtMs: 1000, closesAtMs: 4000};
  assert.doesNotThrow(() => core.assertWindow(window, state, 1500));
  assert.throws(() => core.assertWindow(window, state, 2500));
  assert.doesNotThrow(() => core.assertWindow(window, state, 3500));
  assert.throws(() => core.assertWindow(window, state, 999));
  assert.throws(() => core.assertWindow(window, state, 4001));
});

test("signed passes reject tampering, expiry, and revoked signing keys", () => {
  const pair = crypto.generateKeyPairSync("ed25519");
  const key = {kid: "test", privateKey: pair.privateKey};
  const keys = {test: {publicKey: pair.publicKey.export({format: "jwk"}).x, revoked: false}};
  const record = {id: core.digest("test"), kind: "event", credentialVersion: 1, expiresAtMs: now + 1000};
  const token = core.signPass(record, key);
  assert.equal(core.verifyPass(token, keys, now).id, record.id);
  assert.throws(() => core.verifyPass(token.slice(0, -5) + "xxxxx", keys, now));
  assert.throws(() => core.verifyPass(token, keys, now + 1001));
  assert.throws(() => core.verifyPass(token, {test: {...keys.test, revoked: true}}, now));
  assert.throws(() => core.verifyPass(token, {}, now));
});

test("pending and cancelled registrations or revoked tickets never qualify", () => {
  for (const status of ["pending", "waitlisted", "declined", "cancelled"]) assert.equal(core.confirmedRegistration({status}), false);
  assert.equal(core.confirmedRegistration({status: "confirmed"}), true);
  assert.equal(core.validTicket({revoked: true}), false);
  assert.equal(core.validTicket({paymentStatus: "unpaid"}), false);
  assert.equal(core.validTicket({paymentStatus: "paid"}), true);
});


test("paid ticket entitlements require payment while free legacy tickets remain valid", () => {
  assert.equal(core.validTicket({price: 20, isPaid: false}), false);
  assert.equal(core.validTicket({price: 20, isPaid: true}), true);
  assert.equal(core.validTicket({isPaid: false}, {ticketPrice: 20}), false);
  assert.equal(core.validTicket({price: 0, isPaid: false}), true);
  assert.equal(core.confirmedRegistration({status: "confirmed", paymentStatus: "unpaid"}), false);
});
