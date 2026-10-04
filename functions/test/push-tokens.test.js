"use strict";
const test = require("node:test");
const assert = require("node:assert/strict");
const {memoryAdmin} = require("./helpers/community-memory");
const {createPushTokenOperations, canDeliverPush, cleanupPushTokenAccountData, tokenHash} = require("../notifications/push-tokens");
const installationId = "fixture-installation-0123456789";
const token = "fixture-token-0123456789";
function fixture() {
  const admin = memoryAdmin();
  const operations = createPushTokenOperations(admin);
  const request = (uid, generation, fields = {}) => ({auth: {uid, token: {firebase: {sign_in_provider: "password"}}}, data: {expectedUid: uid, generation, token, installationId, ...fields}});
  return {admin, db: admin.db, operations, request,
    register: (uid, generation, fields) => operations.registerPushTokenV1.run(request(uid, generation, fields)),
    revoke: (uid, generation, fields) => operations.revokePushTokenV1.run(request(uid, generation, fields))};
}
test("token ownership atomically transfers across accounts and old revoke cannot disturb new owner", async () => {
  const f = fixture();
  await f.register("first", 1); await f.register("second", 2);
  assert.equal(f.db.values.get("users/first").fcmToken, undefined);
  assert.equal(await canDeliverPush(f.db, "first", token), false);
  assert.equal(await canDeliverPush(f.db, "second", token), true);
  assert.equal((await f.revoke("first", 99)).stale, true);
  assert.equal(await canDeliverPush(f.db, "second", token), true);
  await assert.rejects(f.register("first", 1), (error) => error.details.code === "stale-installation-generation");
});
test("generations fence rotated tokens and same-generation payload reuse", async () => {
  const f = fixture();
  await f.register("first", 1);
  assert.deepEqual(await f.register("first", 1), {registered: true, generation: 1});
  await assert.rejects(f.register("first", 1, {token: "changed-token-0123456789"}), {code: "failed-precondition"});
  const rotated = "rotated-token-0123456789";
  await f.register("second", 2, {token: rotated});
  assert.equal(f.db.values.get("users/first").fcmToken, undefined);
  assert.equal(f.db.values.has(`PushTokenBindings/${tokenHash(token)}`), false);
  assert.equal(await canDeliverPush(f.db, "second", rotated), true);
  await f.revoke("second", 3, {token: rotated});
  assert.equal(await canDeliverPush(f.db, "second", rotated), false);
  await assert.rejects(f.register("second", 2, {token: rotated}), {code: "failed-precondition"});
});
test("a token rebound to a new installation invalidates late old installation registrations", async () => {
  const f = fixture();
  await f.register("first", 1);
  await f.register("second", 1, {installationId: "fresh-installation-0123456789"});
  await assert.rejects(f.register("first", 100), (error) => error.details.code === "installation-reset-required");
  assert.equal(await canDeliverPush(f.db, "second", token), true);
});
test("registration checks current account, rejects anonymous or deleting actor and delivery fails closed for legacy tokens", async () => {
  const f = fixture();
  await assert.rejects(f.register("first", 1, {expectedUid: "second"}), {code: "permission-denied"});
  const anonymous = f.request("first", 1); anonymous.auth.token.firebase.sign_in_provider = "anonymous";
  await assert.rejects(f.operations.registerPushTokenV1.run(anonymous), {code: "unauthenticated"});
  f.db.values.set("users/first", {fcmToken: token});
  assert.equal(await canDeliverPush(f.db, "first", token), false);
  f.db.values.set("account_deletion_jobs/first", {status: "running"});
  await assert.rejects(f.register("first", 1), {code: "failed-precondition"});
  f.db.values.delete("account_deletion_jobs/first");
  await f.register("first", 1);
  f.db.values.set("account_deletion_jobs/first", {status: "running"});
  assert.equal(await canDeliverPush(f.db, "first", token), false);
});
test("deletion rechecks ownership after query so concurrent account handoff preserves rebound registry", async () => {
  const f = fixture(); await f.register("first", 1);
  const job = f.db.doc("account_deletion_jobs/first");
  let transferred = false;
  const counts = {job, lease: {transaction: async (work) => {
    if (!transferred) { transferred = true; await f.register("second", 2); }
    return f.db.runTransaction(work);
  }}};
  await cleanupPushTokenAccountData(f.db, "first", counts);
  assert.equal(await canDeliverPush(f.db, "second", token), true);
  assert.equal(f.db.values.get(`PushTokenBindings/${tokenHash(token)}`).ownerUid, "second");
  await cleanupPushTokenAccountData(f.db, "second", {job: f.db.doc("account_deletion_jobs/second"), lease: {transaction: f.db.runTransaction}});
  assert.equal(await canDeliverPush(f.db, "second", token), false);
});
