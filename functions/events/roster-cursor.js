"use strict";
const {createHmac, timingSafeEqual} = require("node:crypto");
const {HttpsError} = require("firebase-functions/v2/https");
const ROSTER_CURSOR_TTL_MS = 15 * 60000;
const DOMAIN = "attendus/roster-cursor/v1\0";
const fields = ["eventId", "actorUid", "generation", "filterKey", "id", "issuedAt", "expiresAt"];
const invalid = () => new HttpsError("invalid-argument", "Invalid roster page cursor. Refresh the first page.");

function signingKey(secret) {
  if ((!Buffer.isBuffer(secret) && typeof secret !== "string") || !secret.length ||
      (typeof secret === "string" && !secret.trim())) {
    throw new HttpsError("failed-precondition", "Roster page signing is unavailable.");
  }
  return secret;
}
function validString(value, pattern) { return typeof value === "string" && pattern.test(value); }
function validActor(value) {
  return typeof value === "string" && value.length > 0 && value.length <= 128 &&
    [...value].every((char) => char !== "/" && char.charCodeAt(0) >= 32 && char.charCodeAt(0) !== 127);
}
function validate(payload, now) {
  if (!payload || typeof payload !== "object" || Array.isArray(payload) ||
      Object.keys(payload).length !== fields.length || fields.some((field) => !Object.hasOwn(payload, field)) ||
      !validString(payload.eventId, /^[A-Za-z0-9._:-]{1,500}$/) ||
      !validActor(payload.actorUid) ||
      !validString(payload.generation, /^[A-Za-z0-9_-]{1,160}$/) ||
      !validString(payload.filterKey, /^[a-f0-9]{64}$/) ||
      !validString(payload.id, /^[A-Za-z0-9_-]{1,160}$/) ||
      !Number.isSafeInteger(payload.issuedAt) || payload.issuedAt < 0 ||
      !Number.isSafeInteger(payload.expiresAt) || !Number.isSafeInteger(now) ||
      payload.expiresAt <= payload.issuedAt || payload.expiresAt - payload.issuedAt > ROSTER_CURSOR_TTL_MS ||
      payload.issuedAt > now) throw invalid();
  if (payload.expiresAt <= now) throw new HttpsError("aborted", "Roster page expired. Refresh the first page.");
  return payload;
}
function signature(message, secret) {
  return createHmac("sha256", secret).update(DOMAIN).update(message).digest();
}
function issueRosterCursor(payload, secret, now = Date.now()) {
  const key = signingKey(secret);
  validate(payload, now);
  const encoded = Buffer.from(JSON.stringify(Object.fromEntries(fields.map((field) => [field, payload[field]])))).toString("base64url");
  const message = `v1.${encoded}`;
  return `${message}.${signature(message, key).toString("base64url")}`;
}
function verifyRosterCursor(token, expected, secret, now = Date.now()) {
  const key = signingKey(secret);
  if (typeof token !== "string" || token.length > 4096) throw invalid();
  const parts = token.split(".");
  if (parts.length !== 3 || parts[0] !== "v1" || !/^[A-Za-z0-9_-]+$/.test(parts[1]) || !/^[A-Za-z0-9_-]{43}$/.test(parts[2])) throw invalid();
  const supplied = Buffer.from(parts[2], "base64url");
  const message = `${parts[0]}.${parts[1]}`;
  if (supplied.length !== 32 || supplied.toString("base64url") !== parts[2] ||
      !timingSafeEqual(supplied, signature(message, key))) throw invalid();
  const decoded = Buffer.from(parts[1], "base64url");
  if (decoded.toString("base64url") !== parts[1]) throw invalid();
  let payload;
  try { payload = JSON.parse(decoded.toString("utf8")); } catch (_) { throw invalid(); }
  validate(payload, now);
  if (!expected || payload.eventId !== expected.eventId || payload.actorUid !== expected.actorUid || payload.filterKey !== expected.filterKey) throw invalid();
  return payload;
}
module.exports = {issueRosterCursor, verifyRosterCursor, ROSTER_CURSOR_TTL_MS};
