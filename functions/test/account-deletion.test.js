"use strict";

const assert = require("node:assert/strict");
const test = require("node:test");
const {
  DELETE_QUERIES,
  COLLECTION_GROUP_QUERIES,
  PAYMENT_COLLECTIONS,
  ROOT_DOCUMENTS,
  STORAGE_PREFIXES,
  accountHash,
} = require("../account/deletion");

test("account deletion contract covers sensitive user data", () => {
  const deletedCollections = new Set(DELETE_QUERIES.map(([name]) => name));
  for (const required of [
    "Attendance",
    "FaceEnrollments",
    "Messages",
    "RegisterAttendance",
    "Tickets",
  ]) {
    assert.equal(deletedCollections.has(required), true, `${required} is covered`);
  }
  assert.equal(ROOT_DOCUMENTS.includes("users"), true);
  assert.equal(deletedCollections.has("Conversations"), false, "shared conversations require selective cleanup");
  assert.equal(ROOT_DOCUMENTS.includes("Customers"), true);
  assert.equal(ROOT_DOCUMENTS.includes("_user_analytics_recompute"), true);
  assert.equal(COLLECTION_GROUP_QUERIES.some(([collection, field]) => collection === "AccessRequests" && field === "userId"), true);
  assert.equal(PAYMENT_COLLECTIONS.includes("TicketPayments"), true);
  assert.equal(STORAGE_PREFIXES.some((prefix) => prefix.startsWith("profile_")), true);
});

test("deleted account hashes are stable and do not expose the uid", () => {
  const uid = "user-sensitive-123";
  const hash = accountHash(uid);
  assert.equal(hash, accountHash(uid));
  assert.equal(hash.length, 64);
  assert.equal(hash.includes(uid), false);
  assert.notEqual(hash, accountHash("different-user"));
});

const {assertLease, claimDeletion} = require("../account/deletion-lease");
const {evidence, evidenceFingerprint, sourceCorrectionId, verifyArchivedEvidence} = require("../account/attendance-history");
const {requireClearInventory} = require("../account/dispositions");

test("deletion fencing rejects expired, replaced and completed workers", () => {
  const live = {status: "running", leaseToken: "owner", leaseUntil: new Date(1001)};
  assert.doesNotThrow(() => assertLease(live, "owner", 1000));
  assert.throws(() => assertLease(live, "owner", 1001), /expired/);
  assert.throws(() => assertLease(live, "stale", 1000), /replaced/);
  assert.throws(() => assertLease({...live, status: "complete"}, "owner", 1000));
});

test("deletion checkpoints preserve winner and bounded retry states", async () => {
  let data = {status: "failed", attempts: 2, partialCounts: {documentsDeleted: 17}};
  const db = {runTransaction: async (work) => work({get: async () => ({data: () => data}),
    set: (_ref, patch) => { data = {...data, ...patch}; }})};
  const lease = await claimDeletion(db, {}, "fixture-hash");
  assert.equal(lease.counts.documentsDeleted, 17);
  assert.equal(data.attempts, 3);
  await lease.checkpoint({phase: "fixture"});
  data.leaseToken = "new-worker";
  await assert.rejects(lease.finish({status: "failed"}), /replaced/);
  assert.equal(data.status, "running");
  for (const status of ["review_required", "terminal_failed"]) {
    data = {status};
    await assert.rejects(claimDeletion(db, {}, "fixture-hash"), /operator review/);
  }
  data = {status: "failed", attempts: 5};
  await assert.rejects(claimDeletion(db, {}, "fixture-hash"), /operator review/);
});

test("deletion rejects malformed leases and attempt counters", async () => {
  for (const leaseUntil of [new Date(NaN), {toMillis: () => NaN}]) {
    assert.throws(() => assertLease({status: "running", leaseToken: "owner", leaseUntil}, "owner"), {code: "aborted"});
  }
  for (const attempts of [-1, 1.5, "2", "invalid", NaN, Infinity]) {
    let data = {status: "failed", attempts};
    const db = {runTransaction: (work) => work({get: async () => ({data: () => data}),
      set: (_ref, patch) => { data = {...data, ...patch}; }})};
    await assert.rejects(claimDeletion(db, {}, "fixture-hash"), {code: "failed-precondition"});
    assert.equal(data.status, "terminal_failed");
    assert.equal(data.lastErrorCode, "deletion/invalid-attempts");
  }
});

test("deletion discards writes when the lease expires during asynchronous work", async (t) => {
  let time = Date.now(); t.mock.method(Date, "now", () => time);
  let data = {};
  const db = {runTransaction: async (work) => {
    const pending = [];
    const value = await work({get: async () => { const snapshot = {...data}; return {data: () => snapshot}; },
      set: (_ref, patch) => pending.push(patch)});
    for (const patch of pending) data = {...data, ...patch};
    return value;
  }};
  const lease = await claimDeletion(db, {}, "fixture-hash");
  await assert.rejects(lease.transaction(async (tx) => {
    tx.set({}, {phase: "must-not-commit"});
    time += 10 * 60000;
  }), {code: "aborted"});
  assert.equal(data.phase, undefined);
});

test("every reported disposition blocks authentication until clear", () => {
  for (const category of ["storage:user_banners/{uid}/", "tree:users", "payment:Payments:userId", "review:Organizations:createdBy"]) {
    assert.throws(() => requireClearInventory({remaining: [category]}), {code: "deletion/review-required"});
  }
  assert.doesNotThrow(() => requireClearInventory({remaining: []}));
  assert.ok(STORAGE_PREFIXES.includes("user_banners/{uid}/"));
  assert.ok(STORAGE_PREFIXES.includes("event-drafts/{uid}/"));
});

test("archive verification rejects original and correction tampering while preserving unknown time", () => {
  const stamp = {...evidence("source", {eventId: "event", checkedIn: true}), admissionGroupId: "group"};
  assert.equal(stamp.checkedInAt, null);
  const original = {...stamp, evidenceFingerprint: evidenceFingerprint(stamp)};
  const reordered = Object.fromEntries(Object.entries(original).reverse());
  assert.equal(verifyArchivedEvidence(reordered, [], stamp), true);
  assert.throws(() => verifyArchivedEvidence({...original, voided: true}, [], stamp), /fingerprint changed/);
  const changed = {...stamp, status: "checked_out"};
  const correction = {id: sourceCorrectionId(changed), data: {source: "attendance_record_update", evidence: changed}};
  assert.equal(verifyArchivedEvidence(original, [correction], changed), true);
  correction.data.evidence = {...changed, checkedInAt: "fabricated"};
  assert.throws(() => verifyArchivedEvidence(original, [correction], changed), /chain verification/);
  assert.throws(() => verifyArchivedEvidence({...stamp, voided: true}, [], stamp), /requires review/);
});
