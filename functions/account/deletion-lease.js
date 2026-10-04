"use strict";

const {randomUUID} = require("node:crypto");
const {FieldValue} = require("firebase-admin/firestore");
const {HttpsError} = require("firebase-functions/v2/https");
const LEASE_MS = 10 * 60000;
const MAX_ATTEMPTS = 5;

function millis(value) {
  return value?.toMillis ? value.toMillis() : value instanceof Date ? value.getTime() : 0;
}

function assertLease(data, token, now = Date.now()) {
  const expires = millis(data?.leaseUntil);
  if (data?.status !== "running" || data.leaseToken !== token || !Number.isFinite(expires) || expires <= now) {
    throw new HttpsError("aborted", "Account deletion lease expired or was replaced.");
  }
}

async function claimDeletion(db, job, hash) {
  const token = randomUUID();
  const outcome = await db.runTransaction(async (tx) => {
    const current = await tx.get(job);
    const data = current.data() || {};
    if (data.status === "complete") return {result: data.result};
    if (data.status === "review_required" || data.status === "terminal_failed") {
      throw new HttpsError("failed-precondition", "Account deletion requires operator review.");
    }
    if (data.status === "running" && millis(data.leaseUntil) > Date.now()) {
      throw new HttpsError("aborted", "Deletion is already running. Please retry shortly to check its result.");
    }
    const attempts = data.attempts ?? 0;
    if (!Number.isSafeInteger(attempts) || attempts < 0 || attempts >= MAX_ATTEMPTS) {
      tx.set(job, {status: "terminal_failed", lastErrorCode: Number.isSafeInteger(attempts) && attempts >= MAX_ATTEMPTS ? "deletion/retry-limit" : "deletion/invalid-attempts",
        leaseToken: FieldValue.delete(), leaseUntil: FieldValue.delete()}, {merge: true});
      return {blocked: true};
    }
    tx.set(job, {status: "running", accountHash: hash, resumableVersion: 2,
      leaseToken: token, leaseUntil: new Date(Date.now() + LEASE_MS),
      startedAt: data.startedAt || new Date(), attempts: attempts + 1}, {merge: true});
    return {counts: data.partialCounts || {}, attempts: attempts + 1};
  });
  if (outcome.blocked) throw new HttpsError("failed-precondition", "Account deletion requires operator review.");
  const transaction = (work) => db.runTransaction(async (tx) => {
    const current = await tx.get(job);
    const leaseState = {...current.data()};
    assertLease(leaseState, token);
    const result = await work(tx, current);
    // A callback can wait on external IO while another worker becomes eligible
    // to reclaim the job. Never commit its buffered writes after expiry.
    assertLease(leaseState, token);
    return result;
  });
  const checkpoint = (patch) => transaction(async (tx) => {
    tx.set(job, {leaseUntil: new Date(Date.now() + LEASE_MS), ...patch}, {merge: true});
  });
  const finish = (patch) => checkpoint({...patch, leaseToken: FieldValue.delete(), leaseUntil: FieldValue.delete()});
  return {...outcome, token, transaction, checkpoint, finish};
}

module.exports = {LEASE_MS, MAX_ATTEMPTS, millis, assertLease, claimDeletion};
