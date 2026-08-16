"use strict";

const {createHash} = require("node:crypto");
const {Timestamp} = require("firebase-admin/firestore");
const {HttpsError} = require("firebase-functions/v2/https");

const PLACES_RATE_LIMIT = 60;
const PLACES_RATE_WINDOW_MS = 60 * 1000;

function nextRateState(existing, nowMs, limit = PLACES_RATE_LIMIT) {
  const windowStartedAt = Number(existing?.windowStartedAtMs || 0);
  const withinWindow = nowMs - windowStartedAt < PLACES_RATE_WINDOW_MS;
  const count = withinWindow ? Number(existing?.count || 0) : 0;
  if (count >= limit) return null;
  return {
    count: count + 1,
    windowStartedAtMs: withinWindow ? windowStartedAt : nowMs,
  };
}

async function enforceSharedPlacesRateLimit(
    db,
    uid,
    nowMs = Date.now(),
    limit = PLACES_RATE_LIMIT,
) {
  const id = createHash("sha256").update(uid).digest("hex").slice(0, 32);
  const reference = db.collection("service_rate_limits").doc(`places_${id}`);
  let allowed = false;
  await db.runTransaction(async (transaction) => {
    const snapshot = await transaction.get(reference);
    const next = nextRateState(
        snapshot.exists ? snapshot.data() : null,
        nowMs,
        limit,
    );
    if (!next) return;
    allowed = true;
    transaction.set(reference, {
      service: "places",
      ...next,
      expiresAt: Timestamp.fromMillis(nowMs + (2 * PLACES_RATE_WINDOW_MS)),
    }, {merge: true});
  });
  if (!allowed) {
    throw new HttpsError(
        "resource-exhausted",
        "Too many location searches. Please wait a moment and try again.",
    );
  }
}

module.exports = {
  PLACES_RATE_LIMIT,
  PLACES_RATE_WINDOW_MS,
  enforceSharedPlacesRateLimit,
  nextRateState,
};
