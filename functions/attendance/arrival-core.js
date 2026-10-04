"use strict";

const crypto = require("node:crypto");
const {HttpsError} = require("firebase-functions/v2/https");

const DAY = 86400000;
const PREFIX = "attendus_pass:v2:";
const fail = (message, code = "failed-precondition", details) => {
  throw new HttpsError(code, message, details);
};
const millis = (value) => value?.toMillis ? value.toMillis() :
  value instanceof Date ? value.getTime() : Date.parse(value);
const digest = (value) => crypto.createHash("sha256").update(value).digest("hex");

function arrivalPolicy(raw = {}) {
  const input = raw.smartArrival || {};
  const enabled = raw.version >= 3 && input.enabled === true;
  return {
    enabled,
    latitude: typeof input.latitude === "number" ? input.latitude : null,
    longitude: typeof input.longitude === "number" ? input.longitude : null,
    radiusMeters: Number.isFinite(input.radiusMeters) ? input.radiusMeters : 150,
    openingMode: enabled && raw.openingMode === "scheduled" ? "scheduled" : "manual",
  };
}

function validCoordinates(latitude, longitude) {
  return Number.isFinite(latitude) && Math.abs(latitude) <= 90 &&
    Number.isFinite(longitude) && Math.abs(longitude) <= 180;
}

function validateBoundary(event) {
  const policy = arrivalPolicy(event.checkInPolicy);
  if (!policy.enabled || event.locationType === "online" ||
      typeof event.location !== "string" || !event.location.trim() ||
      event.checkInPolicy?.profile === "staff_entry" ||
      !validCoordinates(policy.latitude, policy.longitude) ||
      policy.radiusMeters < 50 || policy.radiusMeters > 500) {
    fail("The organizer must enable Smart Arrival and confirm its venue boundary.");
  }
  return policy;
}

function distanceMeters(a, b) {
  const rad = Math.PI / 180;
  const dLat = (b.latitude - a.latitude) * rad;
  const dLng = (b.longitude - a.longitude) * rad;
  const h = Math.sin(dLat / 2) ** 2 + Math.cos(a.latitude * rad) *
    Math.cos(b.latitude * rad) * Math.sin(dLng / 2) ** 2;
  return 6371000 * 2 * Math.atan2(Math.sqrt(h), Math.sqrt(Math.max(0, 1 - h)));
}

function validatePosition(position, now = Date.now()) {
  if (!position || !validCoordinates(position.latitude, position.longitude) ||
      !Number.isFinite(position.accuracy) || position.accuracy < 0 ||
      position.accuracy > 50) fail("Location is not accurate enough. Retry or use the venue code.", "failed-precondition", {reason: "inaccurate"});
  const sampled = millis(position.sampledAt);
  if (!Number.isFinite(sampled) || sampled > now + 5000 || now - sampled > 30000) {
    fail("Get a fresh location reading and try again.", "failed-precondition", {reason: "stale"});
  }
  if (position.mocked === true) fail("Use the venue code or ask staff to check you in.", "failed-precondition", {reason: "mocked"});
  return position;
}

function verifyLocation(event, position, now = Date.now()) {
  const boundary = validateBoundary(event);
  validatePosition(position, now);
  if (distanceMeters(position, boundary) + position.accuracy > boundary.radiusMeters) {
    fail("Your location could not be confirmed inside the venue. Retry or use the venue code.", "failed-precondition", {reason: "outside_boundary"});
  }
  return {verificationLevel: "location_assisted"};
}

function activeEvent(event) {
  return event && event.launchScheduleNeedsReview !== true && !event.deleted && !event.isDeleted && !event.cancelled &&
    !["cancelled", "canceled", "draft", "deleted", "archived"].includes(event.status);
}

function confirmedRegistration(data) {
  return Boolean(data) && (!data.status || data.status === "confirmed") &&
    !data.cancelled && !data.revoked &&
    !["pending", "failed", "refunded", "unpaid"].includes(data.paymentStatus);
}

function validTicket(data, event = {}) {
  return Boolean(data) && !data.revoked && !data.cancelled &&
    !["cancelled", "canceled", "refunded", "revoked", "pending", "failed", "unpaid", "waitlisted"].includes(data.status) &&
    !["pending", "failed", "refunded", "unpaid"].includes(data.paymentStatus) &&
    (!(Number(data.price ?? event.ticketPrice ?? 0) > 0) || data.isPaid === true || ["paid", "succeeded"].includes(data.paymentStatus));
}

function windowRevision(event, window) {
  return digest(JSON.stringify([window.opensAtMs, window.closesAtMs,
    event.checkInPolicy || {}, event.status || ""])).slice(0, 24);
}

function controlAt(transitions = [], at = Date.now()) {
  return [...transitions].reverse().filter((item) => item.atMs <= at)
      .sort((a, b) => b.atMs - a.atMs)[0]?.status || "scheduled";
}

function assertWindow(window, state, at) {
  if (at < window.opensAtMs || at > window.closesAtMs) fail("Check-in is outside its window.");
  if (["paused", "closed"].includes(controlAt(state?.transitions, at))) fail("Check-in is paused or closed.");
}

function signPass(record, key) {
  const payload = Buffer.from(JSON.stringify({v: 2, kind: record.kind,
    id: record.id, cv: record.credentialVersion, kid: key.kid,
    exp: record.expiresAtMs})).toString("base64url");
  return PREFIX + payload + "." + crypto.sign(null, Buffer.from(payload), key.privateKey).toString("base64url");
}

function verifyPass(value, keys, now = Date.now()) {
  try {
    if (typeof value !== "string" || !value.startsWith(PREFIX) || value.length > 4096) throw Error();
    const [encoded, signature, extra] = value.slice(PREFIX.length).split(".");
    if (!encoded || !signature || extra) throw Error();
    const payload = JSON.parse(Buffer.from(encoded, "base64url").toString());
    const key = keys[payload.kid];
    if (!key || key.revoked || payload.v !== 2 || !["event", "identity"].includes(payload.kind) ||
        !/^[a-f0-9]{64}$/.test(payload.id) || !Number.isInteger(payload.cv) ||
        !Number.isFinite(payload.exp) || payload.exp < now) throw Error();
    const publicKey = crypto.createPublicKey({key: {kty: "OKP", crv: "Ed25519", x: key.publicKey}, format: "jwk"});
    if (!crypto.verify(null, Buffer.from(encoded), publicKey, Buffer.from(signature, "base64url"))) throw Error();
    return payload;
  } catch (_) {
    fail("This pass is invalid, replaced, or expired. Ask the attendee to refresh it.", "permission-denied");
  }
}

module.exports = {DAY, PREFIX, fail, millis, digest, arrivalPolicy, validCoordinates,
  validateBoundary, validatePosition, distanceMeters, verifyLocation, activeEvent,
  confirmedRegistration, validTicket, windowRevision, controlAt, assertWindow, signPass, verifyPass};
