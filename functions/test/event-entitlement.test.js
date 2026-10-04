"use strict";
const test = require("node:test");
const assert = require("node:assert/strict");
const {consumePublicationAllowance} = require("../events/wizard");
function context(grant, count, tier = "free") {
  const writes = [];
  const db = {collection: (name) => ({doc: (uid) => `${name}/${uid}`})};
  const tx = {get: async (_ref) => ({get: (key) => key === "unlimitedEventCreation" ? grant : count,
    data: () => _ref.startsWith("subscriptions/") ? {tier, status: "active", eventsCreatedThisMonth: count} : {eventsCreated: count}}),
    set: (...args) => writes.push(args), update: (...args) => writes.push(args)};
  const customer = {ref: "Customers/owner", data: () => ({eventsCreated: count})};
  return {writes, db, tx, customer};
}
test("owner entitlement skips free and basic quota without changing counters", async () => {
  for (const tier of ["free", "basic"]) {
    const c = context(true, 100, tier);
    await consumePublicationAllowance(c.tx, c.db, "owner", tier, c.customer);
    assert.deepEqual(c.writes, []);
  }
});
test("missing, false, and nonboolean grants do not bypass quotas", async () => {
  for (const grant of [undefined, false, "true", 1]) {
    for (const tier of ["free", "basic"]) {
      const c = context(grant, 5, tier);
      await assert.rejects(consumePublicationAllowance(c.tx, c.db, "owner", tier, c.customer),
          {code: "resource-exhausted"});
    }
  }
});
test("ordinary free account still consumes its allowance", async () => {
  const c = context(false, 2);
  await consumePublicationAllowance(c.tx, c.db, "owner", "free", c.customer);
  assert.equal(c.writes[0][1].eventsCreated, 3);
});

test("invalid historical quota values fail closed rather than granting publication", async () => {
  for (const count of [undefined, -100, -1, "0", "-100", null, false, NaN, Infinity, 0.5, Number.MAX_SAFE_INTEGER + 1]) {
    for (const tier of ["free", "basic"]) {
      const c = context(false, count, tier);
      await assert.rejects(consumePublicationAllowance(c.tx, c.db, "owner", tier, c.customer),
          {code: "failed-precondition"});
      assert.deepEqual(c.writes, []);
    }
  }
});

test("initialized counters and valid final allowance increment exactly once", async () => {
  for (const tier of ["free", "basic"]) {
    for (const count of [0, 4]) {
      const c = context(false, count, tier);
      await consumePublicationAllowance(c.tx, c.db, "owner", tier, c.customer);
      assert.equal(c.writes.length, 1);
      assert.equal(c.writes[0][1][tier === "free" ? "eventsCreated" : "eventsCreatedThisMonth"],
          count + 1);
    }
  }
});

test("free publication rereads the counter instead of trusting an earlier organizer snapshot", async () => {
  const {memoryAdmin} = require("./helpers/community-memory");
  const admin = memoryAdmin({"Customers/owner": {eventsCreated: 4}});
  const stale = {ref: admin.db.doc("Customers/owner"), data: () => ({eventsCreated: 0})};
  const results = await Promise.allSettled([1, 2].map(() => admin.db.runTransaction((tx) =>
    consumePublicationAllowance(tx, admin.db, "owner", "free", stale))));
  assert.equal(results.filter((result) => result.status === "fulfilled").length, 1);
  assert.equal(results.find((result) => result.status === "rejected").reason.code, "resource-exhausted");
  assert.equal(admin.db.values.get("Customers/owner").eventsCreated, 5);
});

test("subscription changes after preflight abort before consuming a different tier allowance", async () => {
  for (const [preflight, current] of [["premium", "free"], ["free", "premium"], ["basic", "free"]]) {
    const c = context(false, 0, current);
    await assert.rejects(consumePublicationAllowance(c.tx, c.db, "owner", preflight, c.customer), {code: "aborted"});
    assert.deepEqual(c.writes, []);
  }
});

test("preflight and transactional tier parsing preserve active cancellation-period and legacy active records", () => {
  const {tierFromSubscription} = require("../events/wizard");
  for (const data of [{tier: "premium", status: "active", cancelAtPeriodEnd: true},
    {subscriptionTier: "premium", isActive: true}]) assert.equal(tierFromSubscription({data: () => data}), "premium");
  assert.equal(tierFromSubscription({data: () => ({tier: "premium", status: "cancelled"})}), "free");
});
