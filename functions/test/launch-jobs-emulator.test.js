"use strict";
const test = require("node:test");
const assert = require("node:assert/strict");
const crypto = require("node:crypto");
if (!process.env.FIRESTORE_EMULATOR_HOST) throw new Error("Firestore emulator required");
process.env.GCLOUD_PROJECT = "demo-attendus-admin";
const admin = require("../firebase-admin-compat");
const {runJob, LEASE_MS} = require("../events/jobs");
const db = admin.firestore();
const refs = [];
test.after(async () => {
  for (const ref of refs) await db.recursiveDelete(ref);
  await db.terminate();
});
async function job() {
  const ref = db.collection("LaunchJobLeaseFixtures").doc(crypto.randomUUID());
  refs.push(ref);
  await ref.set({status: "queued"});
  return ref;
}

test("Firestore expired worker cannot commit recipient marker or checkpoint", async () => {
  const ref = await job(); let time = Date.now();
  await runJob(db, ref, async (_ref, lease) => {
    await assert.rejects(lease.transaction(async (tx) => {
      tx.create(ref.collection("recipients").doc("recipient"), {disposition: "queued"});
      tx.update(ref, {cursor: "recipient", status: "complete"});
      time += LEASE_MS;
    }), {code: "aborted"});
    await assert.rejects(lease(), {code: "aborted"});
  }, {now: () => time});
  assert.equal((await ref.collection("recipients").doc("recipient").get()).exists, false);
  const result = await ref.get();
  assert.equal(result.get("cursor"), undefined);
  assert.equal(result.get("status"), "queued");
});

test("Firestore renewed claimant completes while expired claimant is fenced", async () => {
  const ref = await job(); let time = Date.now();
  await runJob(db, ref, async (_ref, stale) => {
    time += LEASE_MS;
    await runJob(db, ref, async (_nextRef, current) => {
      await assert.rejects(stale.transaction(async (tx) => tx.update(ref, {cursor: "stale"})), {code: "aborted"});
      await current.transaction(async (tx) => tx.update(ref, {status: "complete", count: 1}));
    }, {now: () => time});
    throw Error("late stale failure");
  }, {now: () => time});
  const result = await ref.get();
  assert.equal(result.get("status"), "complete");
  assert.equal(result.get("count"), 1);
  assert.equal(result.get("attempts"), 2);
  assert.equal(result.get("leaseToken"), undefined);
  assert.equal(result.get("cursor"), undefined);
});

test("Firestore terminal commit survives callback error and releases valid lease", async () => {
  const ref = await job();
  await runJob(db, ref, async (_ref, lease) => {
    await lease.transaction(async (tx) => {
      tx.create(ref.collection("recipients").doc("recipient"), {disposition: "unreachable"});
      tx.update(ref, {status: "complete", count: 1, unreachable: 1});
    });
    throw Error("cleanup failed after commit");
  });
  const result = await ref.get();
  assert.equal(result.get("status"), "complete");
  assert.equal(result.get("count"), 1);
  assert.equal(result.get("leaseToken"), undefined);
  assert.equal((await ref.collection("recipients").doc("recipient").get()).exists, true);
});
