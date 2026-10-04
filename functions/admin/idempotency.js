"use strict";

const crypto = require("node:crypto");
const {fail} = require("./errors");

function documentId(uid, key) {
  return crypto.createHash("sha256").update(`${uid}:${key}`).digest("hex");
}

function canonical(value) {
  if (Array.isArray(value)) return value.map(canonical);
  if (value && typeof value === "object") return Object.fromEntries(Object.keys(value).sort().map((name) => [name, canonical(value[name])]));
  return value;
}

const reviewRequired = () => fail(409, "OPERATION_REVIEW_REQUIRED", "This operation's outcome requires review. Do not submit it with a new request key.");

async function runIdempotent(db, adminSdk, uid, key, operation, request) {
  if (typeof key !== "string" || key.length < 12 || key.length > 200) fail(400, "IDEMPOTENCY_KEY_REQUIRED", "A unique Idempotency-Key of at least 12 characters is required.");
  if (!request?.action || !request?.method || !request?.path) fail(500, "IDEMPOTENCY_CONTEXT_REQUIRED", "Operation identity is unavailable.");
  const fingerprint = crypto.createHash("sha256").update(JSON.stringify(canonical(request))).digest("hex");
  const ref = db.collection("admin_idempotency").doc(documentId(uid, key));
  const claim = await db.runTransaction(async (tx) => {
    const existing = await tx.get(ref);
    if (existing.exists) {
      const data = existing.data();
      if (!data.fingerprint) return reviewRequired();
      if (data.fingerprint !== fingerprint) fail(409, "IDEMPOTENCY_KEY_CONFLICT", "This request key belongs to a different operation or payload.");
      if (data.state === "complete") return {response: data.response};
      if (data.state === "started" && Number.isFinite(data.startedAtMs) &&
          data.startedAtMs <= Date.now() && Date.now() - data.startedAtMs < 120000) {
        fail(409, "REQUEST_IN_PROGRESS", "An operation with this idempotency key is in progress.");
      }
      return reviewRequired();
    }
    tx.create(ref, {uid, fingerprint, state: "started", startedAtMs: Date.now(), createdAt: adminSdk.firestore.FieldValue.serverTimestamp()});
    return {claimed: true};
  });
  if (!claim.claimed) return claim.response;
  try {
    const response = await operation();
    await ref.update({state: "complete", response, completedAt: adminSdk.firestore.FieldValue.serverTimestamp()});
    return response;
  } catch (error) {
    // A lost acknowledgement can follow a successful durable completion. Do
    // not overwrite that result or repeat a provider mutation to recover it.
    try {
      const current = await ref.get();
      const completed = current.data();
      if (completed?.state === "complete" && completed.fingerprint === fingerprint) return completed.response;
      await db.runTransaction(async (tx) => {
        const record = await tx.get(ref);
        if (record.data()?.state === "started" && record.data()?.fingerprint === fingerprint) {
          tx.update(ref, {state: "needs_review", errorCode: String(error.code || "INTERNAL").slice(0, 120), failedAt: adminSdk.firestore.FieldValue.serverTimestamp()});
        }
      });
    } catch (_) {
      // An unavailable store cannot establish whether any side effect ran.
      // The reserved key stays non-replayable even if this marker write fails.
    }
    return reviewRequired();
  }
}

module.exports = {runIdempotent};
