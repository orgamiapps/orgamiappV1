"use strict";
const test = require("node:test");
const assert = require("node:assert/strict");
const {randomUUID} = require("node:crypto");
if (!/^127\.0\.0\.1:\d+$/.test(process.env.FIRESTORE_EMULATOR_HOST || "")) throw Error("Local Firestore emulator required");
process.env.GCLOUD_PROJECT = "demo-attendus-admin";
process.env.FUNCTIONS_EMULATOR = "true";
process.env.GUEST_CONTACT_KMS_KEY_NAME = "emulator";
process.env.GUEST_CONTACT_HMAC_KEY = "local-deletion-fixture-only";
const db = require("../firebase-admin-compat").firestore();
const {runAccountDeletion} = require("../account/deletion");
const bucket = {getFiles: async () => [[]], file: () => ({delete: async () => {}})};

test("ownership review blocks destructive phases and authentication removal", async () => {
  const uid = `deletion-owner-${randomUUID()}`;
  const event = db.collection("Events").doc(uid);
  const profile = db.collection("Customers").doc(uid);
  await event.set({customerUid: uid}); await profile.set({name: "Fixture"});
  let authDeleted = false;
  await assert.rejects(runAccountDeletion({uid, db, bucket, auth: {deleteUser: async () => { authDeleted = true; }}}), {code: "deletion/review-required"});
  assert.equal(authDeleted, false);
  assert.equal((await profile.get()).exists, true);
  assert.equal((await event.get()).get("customerUid"), uid);
  assert.equal((await db.collection("account_deletion_jobs").doc(uid).get()).get("status"), "review_required");
});

test("residual storage blocks Auth deletion and records verified category", async () => {
  const uid = `deletion-storage-${randomUUID()}`;
  let authDeleted = false;
  const stubborn = {getFiles: async ({prefix}) => [prefix === `user_banners/${uid}/` ? [{delete: async () => {}}] : []],
    file: () => ({delete: async () => {}})};
  await assert.rejects(runAccountDeletion({uid, db, bucket: stubborn, auth: {deleteUser: async () => { authDeleted = true; }}}), {code: "deletion/review-required"});
  assert.equal(authDeleted, false);
  const job = await db.collection("account_deletion_jobs").doc(uid).get();
  assert.equal(job.get("status"), "review_required");
  assert.ok(job.get("verification.remaining").includes("storage:user_banners/{uid}/"));
});

test("non-shared fixture deletion clears registry and preserves cumulative counts", async () => {
  const uid = `deletion-clear-${randomUUID()}`;
  await db.collection("Customers").doc(uid).set({name: "Fixture"});
  await db.collection("notifications").doc(uid).set({userId: uid});
  await db.collection("EventDrafts").doc(uid).set({ownerUid: uid});
  const analytics = db.collection("user_analytics").doc(uid);
  const recompute = db.collection("_user_analytics_recompute").doc(uid);
  await analytics.set({totalEvents: 0});
  await recompute.set({requestedGeneration: 2, processedGeneration: 1});
  let calls = 0;
  const auth = {deleteUser: async () => {
    assert.equal((await analytics.get()).exists, false, "Analytics must be removed before Auth");
    assert.equal((await recompute.get()).exists, false, "Recompute identity must be removed before Auth");
    calls++;
  }};
  const result = await runAccountDeletion({uid, db, bucket, auth});
  assert.equal(result.status, "complete");
  assert.equal(result.documentsDeleted, 2);
  assert.equal(calls, 1);
  assert.deepEqual(await runAccountDeletion({uid, db, bucket, auth}), result);
  assert.equal(calls, 1);
  const job = await db.collection("account_deletion_jobs").doc(uid).get();
  assert.equal(job.get("verification.remaining").length, 0);
  assert.ok(job.get("verification.fingerprint"));
  assert.equal(job.get("leaseToken"), undefined);
});
