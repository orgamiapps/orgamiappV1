"use strict";

const assert = require("node:assert/strict");
const test = require("node:test");

const {
  decodePersonalPass,
  decodeSigned,
  encodeSigned,
  normalizePolicy,
  policyWindow,
  rateLimitForActor,
  validateSubmitInput,
  venueCode,
} = require("../attendance/v2");

test("staff capacity supports event-day load and offline replay", () => {
  assert.ok(rateLimitForActor(true) >= 600);
  assert.ok(rateLimitForActor(false) < rateLimitForActor(true));
});

test("legacy attendance tiers migrate to supported profiles", () => {
  assert.equal(normalizePolicy({signInSecurityTier: "regular"}).profile,
      "self_check_in");
  assert.equal(normalizePolicy({signInSecurityTier: "all"}).profile, "hybrid");
  for (const tier of ["most_secure", "geofence_only"]) {
    const policy = normalizePolicy({signInSecurityTier: tier});
    assert.equal(policy.profile, "hybrid");
    assert.equal(policy.needsOrganizerReview, true);
  }
});

test("policy normalization applies safe defaults and bounds", () => {
  const policy = normalizePolicy({
    checkInPolicy: {
      profile: "unsupported",
      eligibility: "ticket_required",
      opensBeforeMinutes: 9999,
      closesAfterMinutes: -10,
      staffFallback: false,
    },
  });
  assert.equal(policy.profile, "hybrid");
  assert.equal(policy.eligibility, "ticket_required");
  assert.equal(policy.opensBeforeMinutes, 1440);
  assert.equal(policy.closesAfterMinutes, 0);
  assert.equal(policy.staffFallback, false);
});

test("policy window includes configured lead, duration, and grace", () => {
  const start = Date.UTC(2026, 7, 2, 18, 0, 0);
  const window = policyWindow({
    selectedDateTime: new Date(start).toISOString(),
    eventDuration: 2,
  }, {
    opensBeforeMinutes: 60,
    closesAfterMinutes: 60,
  });
  assert.equal(window.opensAtMs, start - 60 * 60 * 1000);
  assert.equal(window.closesAtMs, start + 3 * 60 * 60 * 1000);
});

test("venue codes are six characters and rotate by minute", () => {
  const first = venueCode("session-secret", 100);
  assert.match(first, /^[23456789A-HJ-NP-Z]{6}$/);
  assert.equal(first, venueCode("session-secret", 100));
  assert.notEqual(first, venueCode("session-secret", 101));
});

test("signed credentials reject tampering, wrong type, and expiration", () => {
  const secret = "session-secret";
  const token = encodeSigned({v: 1, t: "venue", exp: 2000}, secret);
  assert.equal(decodeSigned(token, secret, "venue", 1000).t, "venue");
  assert.throws(() => decodeSigned(token, "wrong-secret", "venue", 1000));
  assert.throws(() => decodeSigned(token, secret, "pass", 1000));
  assert.throws(() => decodeSigned(token, secret, "venue", 3000));
});

test("personal passes use a public-key signature staff devices can verify", () => {
  const crypto = require("node:crypto");
  const {publicKey, privateKey} = crypto.generateKeyPairSync("ed25519");
  const token = require("../attendance/v2").personalPassToken({
    eventId: "event-1",
    sessionId: "session-1",
    uid: "attendee-1",
    expiresAtMs: 5000,
    privateKey: privateKey.export({format: "pem", type: "pkcs8"}),
  });
  const rawPublicKey = publicKey.export({format: "jwk"}).x;
  const payload = decodePersonalPass(token, rawPublicKey, 1000);
  assert.equal(payload.u, "attendee-1");
  assert.throws(() => decodePersonalPass(`${token}x`, rawPublicKey, 1000));
  assert.throws(() => decodePersonalPass(token, rawPublicKey, 6000));
});

test("submit contract rejects fabricated credential methods", () => {
  const base = {
    eventId: "event-1",
    sessionId: "session-1",
    idempotencyKey: "attempt-1",
    answers: [],
  };
  assert.equal(validateSubmitInput({
    ...base,
    credential: {type: "venue_token", token: "credential"},
  }).credential.type, "venue_token");
  assert.throws(() => validateSubmitInput({
    ...base,
    credential: {type: "facial_recognition"},
  }));
  assert.throws(() => validateSubmitInput({
    ...base,
    idempotencyKey: "",
    credential: {type: "venue_token"},
  }));
});
