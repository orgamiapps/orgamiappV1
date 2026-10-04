"use strict";
const crypto = require("node:crypto");
const {FieldValue} = require("firebase-admin/firestore");
const LEASE_MS = 10 * 60000;
const MAX_ATTEMPTS = 5;
const delays = [60000, 300000, 900000, 3600000];
const permanent = new Set(["permission-denied", "unauthenticated", "invalid-argument", "not-found", "failed-precondition"]);
const terminalStates = new Set(["complete", "failed", "cancelled", "delivery_unknown", "needs_review"]);
const millis = (value) => value?.toMillis?.() ?? (value instanceof Date ? value.getTime() : NaN);
const leaseLost = () => Object.assign(Error("Job lease expired or lost"), {code: "aborted"});

async function runJob(db, ref, work, {now = Date.now} = {}) {
  const token = crypto.randomUUID();
  const attempt = await db.runTransaction(async (tx) => {
    const job = await tx.get(ref);
    if (!job.exists || terminalStates.has(job.get("status")) || millis(job.get("leaseUntil")) > now() || millis(job.get("nextAttemptAt")) > now()) return;
    const attempts = Number(job.get("attempts") ?? 0);
    if (!Number.isSafeInteger(attempts) || attempts < 0 || attempts >= MAX_ATTEMPTS) {
      tx.update(ref, {status: "failed", error: attempts >= MAX_ATTEMPTS ? "attempt_limit" : "invalid_attempts", leaseToken: FieldValue.delete(), leaseUntil: FieldValue.delete()}); return;
    }
    const nextAttempt = attempts + 1;
    tx.update(ref, {leaseToken: token, leaseUntil: new Date(now() + LEASE_MS), attempts: nextAttempt, lastAttemptAt: new Date(now())});
    return nextAttempt;
  });
  if (!attempt) return;
  const owned = (job) => job.exists && job.get("leaseToken") === token && millis(job.get("leaseUntil")) > now();
  const assert = async (tx) => {
    const job = await tx.get(ref);
    if (!owned(job) || terminalStates.has(job.get("status"))) throw leaseLost();
    return job;
  };
  const heartbeat = async () => db.runTransaction(async (tx) => {
    await assert(tx);
    tx.update(ref, {leaseUntil: new Date(now() + LEASE_MS)});
  });
  // All durable work writes must use this transaction or assert(tx) before
  // reading other documents. The job read also fences concurrent lease claims.
  heartbeat.assert = assert;
  heartbeat.token = token;
  heartbeat.transaction = (callback) => db.runTransaction(async (tx) => {
    const job = await assert(tx);
    const result = await callback(tx, job);
    // A long callback must not publish after its lease expired while awaiting IO.
    if (!owned(job)) throw leaseLost();
    return result;
  });
  try {
    await work(ref, heartbeat);
    await db.runTransaction(async (tx) => {
      const job = await tx.get(ref);
      if (owned(job)) tx.update(ref, {leaseToken: FieldValue.delete(), leaseUntil: FieldValue.delete()});
    });
  } catch (error) {
    await db.runTransaction(async (tx) => {
      const job = await tx.get(ref);
      if (!owned(job)) return;
      // A callback can commit completion and then fail during local cleanup.
      // Never turn that committed outcome back into queued/failed work.
      if (terminalStates.has(job.get("status"))) {
        tx.update(ref, {leaseToken: FieldValue.delete(), leaseUntil: FieldValue.delete()});
        return;
      }
      const terminal = attempt >= MAX_ATTEMPTS || permanent.has(error.code);
      tx.update(ref, {status: terminal ? "failed" : "queued", error: String(error.code || "transient_failure"),
        nextAttemptAt: terminal ? FieldValue.delete() : new Date(now() + delays[Math.min(attempt - 1, delays.length - 1)]),
        leaseToken: FieldValue.delete(), leaseUntil: FieldValue.delete()});
    });
  }
}
module.exports = {runJob, LEASE_MS, MAX_ATTEMPTS};
