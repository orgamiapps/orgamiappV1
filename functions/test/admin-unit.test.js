"use strict";
const test = require("node:test");
const assert = require("node:assert/strict");
const {authorize} = require("../admin/auth");
const validate = require("../admin/validation");
const {writeAudit} = require("../admin/audit");
const {canAssignRoles} = require("../admin/rbac");
const {planForPrice, tierForPlan} = require("../admin/subscriptions");

function roleDb(data) {
  return {collection: () => ({doc: () => ({get: async () => ({exists: Boolean(data), data: () => data})})})};
}
function sdk(token) {
  return {auth: () => ({verifyIdToken: async () => token}), firestore: {FieldValue: {serverTimestamp: () => "SERVER_TIME"}}};
}
const req = {get: () => "Bearer valid"};

test("non-admin ID token cannot call an admin endpoint", async () => {
  await assert.rejects(authorize(req, sdk({uid: "user", admin: false}), roleDb({active: true, roles: ["support"]}), "accounts.read"), (error) => error.code === "ADMIN_CLAIM_REQUIRED");
});
test("coarse claim without active role is rejected", async () => {
  await assert.rejects(authorize(req, sdk({uid: "user", admin: true}), roleDb({active: false, roles: ["support"]}), "accounts.read"), (error) => error.code === "ADMIN_ROLE_REQUIRED");
});
test("billing role cannot grant super-admin access", () => {
  assert.equal(canAssignRoles(["billing_admin"], ["super_admin"]), false);
  assert.equal(canAssignRoles(["super_admin"], ["support"]), true);
});
test("destructive validation requires confirmation and meaningful reason", () => {
  assert.throws(() => validate.mutation({reason: "too short", confirmed: true}, true));
  assert.throws(() => validate.mutation({reason: "A sufficiently clear reason", confirmed: false}, true));
  assert.equal(validate.mutation({reason: "A sufficiently clear reason", confirmed: true}, true), "A sufficiently clear reason");
});
test("audit logging uses create and sanitizes secrets", async () => {
  let written; const db = {collection: () => ({doc: () => ({id: "audit-1", create: async (data) => {
    written = data;
  }})})};
  const id = await writeAudit(db, sdk({}), {actor: {uid: "admin-1", email: "a@example.com", roles: ["support"]}, action: "account.disable", targetType: "account", targetId: "u1", reason: "Confirmed support request", requestId: "r1", metadata: {token: "hidden", caseId: "c1"}});
  assert.equal(id, "audit-1"); assert.equal(written.metadata.token, undefined); assert.equal(written.metadata.caseId, "c1");
});
test("subscription entitlements derive only from configured Stripe price", () => {
  const env = {STRIPE_PRICE_PREMIUM_MONTHLY: "price_premium"};
  assert.equal(planForPrice("price_premium", env), "premium_monthly"); assert.equal(tierForPlan("premium_monthly"), "premium"); assert.equal(tierForPlan("arbitrary"), "free");
});

function idempotencyFixture(initial) {
  let data = initial;
  let failCompleteAck = false;
  let tail = Promise.resolve();
  const snapshot = () => ({exists: Boolean(data), data: () => data && {...data}});
  const reference = {get: async () => snapshot(), create: async (patch) => {
    if (data) throw Object.assign(Error("exists"), {code: 6}); data = {...patch};
  }, update: async (patch) => {
    data = {...data, ...patch};
    if (failCompleteAck && patch.state === "complete") { failCompleteAck = false; throw Error("Completion acknowledgement lost"); }
  }};
  const db = {collection: () => ({doc: () => reference}), runTransaction: (work) => {
    const pending = tail.then(async () => {
      const writes = [];
      const result = await work({get: async () => snapshot(), create: (_ref, patch) => writes.push(patch), update: (_ref, patch) => writes.push(patch)});
      for (const patch of writes) data = {...data, ...patch};
      return result;
    });
    tail = pending.catch(() => {});
    return pending;
  }};
  const binding = {method: "POST", path: "/v1/accounts/target/disable", action: "account.disable", targetId: "target", body: {confirmed: true, reason: "Verified support request"}};
  return {data: () => data, replace: (value) => { data = value; }, loseCompleteAck: () => { failCompleteAck = true; },
    run: (operation, changes = {}) => require("../admin/idempotency").runIdempotent(db, sdk({}), "actor", "request-key-123", operation, {...binding, ...changes})};
}

test("admin idempotency binds action, path and canonical payload before replay", async () => {
  const f = idempotencyFixture(); let calls = 0;
  const operation = async () => { calls++; return {ok: true, auditId: "audit"}; };
  const original = await f.run(operation);
  assert.deepEqual(await f.run(operation, {body: {reason: "Verified support request", confirmed: true}}), original);
  for (const changes of [{action: "account.enable"}, {path: "/v1/accounts/other/disable"}, {method: "DELETE"}, {body: {confirmed: true, reason: "Another support case"}}]) {
    await assert.rejects(f.run(operation, changes), {code: "IDEMPOTENCY_KEY_CONFLICT"});
  }
  assert.equal(calls, 1);
});

test("failed and abandoned admin operations require review and never rerun", async () => {
  const f = idempotencyFixture(); let calls = 0;
  const operation = async () => { calls++; throw Error("Provider outcome unknown"); };
  await assert.rejects(f.run(operation), {code: "OPERATION_REVIEW_REQUIRED"});
  await assert.rejects(f.run(operation), {code: "OPERATION_REVIEW_REQUIRED"});
  f.replace({...f.data(), state: "started", startedAtMs: Date.now() - 121000});
  await assert.rejects(f.run(operation), {code: "OPERATION_REVIEW_REQUIRED"});
  assert.equal(calls, 1);
});

test("legacy admin markers without a request fingerprint cannot claim another operation succeeded", async () => {
  const f = idempotencyFixture({state: "complete", response: {ok: true}});
  await assert.rejects(f.run(async () => assert.fail("must not rerun")), {code: "OPERATION_REVIEW_REQUIRED"});
});

test("concurrent admin retries run the side effect only once", async () => {
  const f = idempotencyFixture(); let start; let finish; let calls = 0;
  const started = new Promise((resolve) => { start = resolve; });
  const held = new Promise((resolve) => { finish = resolve; });
  const first = f.run(async () => { calls++; start(); await held; return {ok: true}; });
  await started;
  await assert.rejects(f.run(async () => { calls++; }), {code: "REQUEST_IN_PROGRESS"});
  finish(); await first;
  assert.equal(calls, 1);
});

test("lost completion acknowledgement preserves and returns the committed admin result", async () => {
  const f = idempotencyFixture(); f.loseCompleteAck(); let calls = 0;
  const operation = async () => { calls++; return {ok: true, auditId: "audit"}; };
  assert.deepEqual(await f.run(operation), {ok: true, auditId: "audit"});
  assert.deepEqual(await f.run(operation), {ok: true, auditId: "audit"});
  assert.equal(f.data().state, "complete");
  assert.equal(calls, 1);
});
