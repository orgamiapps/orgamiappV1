"use strict";
const test = require("node:test");
const assert = require("node:assert/strict");
const {FieldValue} = require("firebase-admin/firestore");
const {runJob, LEASE_MS, MAX_ATTEMPTS} = require("../events/jobs");

// Deterministic transactional fixture: buffered writes are discarded if the
// callback rejects, as Firestore requires. No network or production credentials.
function fixture(initial = {}) {
  let time = 1000000;
  let state = {status: "queued", ...initial};
  const deleted = FieldValue.delete();
  const ref = {id: "job"};
  const db = {runTransaction: async (callback) => {
    const pending = [];
    const tx = {
      get: async () => { const snapshot = {...state}; return {exists: true, get: (field) => snapshot[field]}; },
      update: (_ref, data) => pending.push(data),
    };
    const value = await callback(tx);
    for (const data of pending) for (const [field, val] of Object.entries(data)) {
      if (val?.isEqual?.(deleted)) delete state[field]; else state[field] = val;
    }
    return value;
  }};
  return {db, ref, now: () => time, advance: (ms) => { time += ms; },
    state: () => state, replace: (next) => { state = next; },
    run: (work) => runJob(db, ref, work, {now: () => time})};
}

test("renewal extends an active ten-minute lease; completed work releases ownership", async () => {
  const f = fixture();
  await f.run(async (ref, lease) => {
    assert.equal(f.state().leaseUntil.getTime(), f.now() + LEASE_MS);
    f.advance(LEASE_MS - 1);
    await lease();
    assert.equal(f.state().leaseUntil.getTime(), f.now() + LEASE_MS);
    await lease.transaction(async (tx, job) => {
      assert.equal(job.get("leaseToken"), lease.token);
      tx.update(ref, {status: "complete", count: 4});
    });
  });
  assert.equal(f.state().status, "complete");
  assert.equal(f.state().count, 4);
  assert.equal(f.state().leaseToken, undefined);
  assert.equal(f.state().leaseUntil, undefined);
});

test("expired worker cannot renew, checkpoint, finalize or clean ownership", async () => {
  const f = fixture();
  await f.run(async (ref, lease) => {
    f.advance(LEASE_MS);
    await assert.rejects(lease(), {code: "aborted"});
    await assert.rejects(lease.transaction(async (tx) => tx.update(ref, {status: "complete"})), {code: "aborted"});
  });
  assert.equal(f.state().status, "queued");
  assert.ok(f.state().leaseToken);
  assert.equal(f.state().attempts, 1);
});

test("lease expiration during callback discards checkpoint and final writes", async () => {
  const f = fixture();
  await f.run(async (ref, lease) => {
    await assert.rejects(lease.transaction(async (tx) => {
      tx.update(ref, {status: "complete", cursor: "recipient-50"});
      f.advance(LEASE_MS);
    }), {code: "aborted"});
  });
  assert.equal(f.state().cursor, undefined);
  assert.equal(f.state().status, "queued");
});

test("a competing reclaimed worker completes; stale failure cannot overwrite it", async () => {
  const f = fixture();
  await f.run(async (ref, oldLease) => {
    f.advance(LEASE_MS);
    await f.run(async (_ref, lease) => {
      assert.notEqual(lease.token, oldLease.token);
      await assert.rejects(oldLease.transaction(async (tx) => tx.update(ref, {cursor: "stale"})), {code: "aborted"});
      await lease.transaction(async (tx) => tx.update(ref, {status: "complete", cursor: "final"}));
    });
    throw Error("stale failure");
  });
  assert.equal(f.state().status, "complete");
  assert.equal(f.state().cursor, "final");
  assert.equal(f.state().attempts, 2);
});

test("error after committed completion cannot requeue or erase the outcome", async () => {
  const f = fixture();
  await f.run(async (ref, lease) => {
    await lease.transaction(async (tx) => tx.update(ref, {status: "complete", count: 7}));
    throw Error("cleanup failure");
  });
  assert.equal(f.state().status, "complete");
  assert.equal(f.state().count, 7);
  assert.equal(f.state().error, undefined);
  assert.equal(f.state().leaseToken, undefined);
});

test("transient failures back off and stop after five attempts", async () => {
  const f = fixture(); let calls = 0;
  const fail = async () => { calls++; throw Error("transient"); };
  for (let i = 0; i < MAX_ATTEMPTS; i++) {
    await f.run(fail);
    await f.run(fail);
    assert.equal(calls, i + 1);
    if (i < MAX_ATTEMPTS - 1) f.advance(f.state().nextAttemptAt.getTime() - f.now());
  }
  assert.equal(f.state().status, "failed");
  assert.equal(f.state().attempts, MAX_ATTEMPTS);
  assert.equal(f.state().nextAttemptAt, undefined);
});

test("permanent errors do not retry; terminal and ambiguous outcomes do not run", async () => {
  const f = fixture();
  await f.run(async () => { throw Object.assign(Error("removed actor"), {code: "permission-denied"}); });
  assert.equal(f.state().status, "failed");
  assert.equal(f.state().nextAttemptAt, undefined);
  for (const status of ["complete", "failed", "cancelled", "delivery_unknown", "needs_review"]) {
    f.replace({status});
    await f.run(async () => assert.fail("terminal work ran"));
  }
});

test("poisoned attempt counters fail closed and exhausted crashes cannot run again", async () => {
  for (const attempts of ["invalid", -1, 1.5, MAX_ATTEMPTS, Infinity]) {
    const f = fixture({attempts});
    await f.run(async () => assert.fail("poisoned job ran"));
    assert.equal(f.state().status, "failed");
  }
});

test("unexpired competing lease and future retry prevent duplicate work", async () => {
  for (const initial of [{leaseUntil: new Date(2000000)}, {nextAttemptAt: new Date(2000000)}]) {
    await fixture(initial).run(async () => assert.fail("ineligible job ran"));
  }
});
