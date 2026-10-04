"use strict";
const test = require("node:test");
const assert = require("node:assert/strict");
const {randomUUID} = require("node:crypto");
if (!/^127\.0\.0\.1:\d+$/.test(process.env.FIRESTORE_EMULATOR_HOST || "")) throw Error("Local Firestore emulator required");
process.env.GCLOUD_PROJECT = "demo-attendus-admin";
process.env.FUNCTIONS_EMULATOR = "true";
const admin = require("../firebase-admin-compat");
const db = admin.firestore();
const {createEventStaffLookupHandler} = require("../profiles/staff-lookup");
const {limitProfileReads} = require("../profiles/access");
test.after(async () => { await db.terminate(); });

async function fixture() {
  const suffix = randomUUID();
  const host = `lookup-host-${suffix}`, target = `lookup-target-${suffix}`, forger = `lookup-forger-${suffix}`;
  const event = db.doc(`Events/lookup-event-${suffix}`);
  const email = `${suffix}@example.test`;
  await event.set({customerUid: host});
  await db.doc(`Customers/${target}`).set({name: "Authoritative Account", username: "target", email: "different-editable@example.test", phoneNumber: "private", fcmToken: "private"});
  await db.doc(`Customers/${forger}`).set({name: "Forged Email", email});
  let beforeReturn = async () => {};
  let lookupCount = 0;
  const auth = {getUserByEmail: async (actual) => {
    assert.equal(actual, email);
    lookupCount++;
    await beforeReturn();
    return {uid: target, email, emailVerified: true, disabled: false, providerData: [{providerId: "password"}]};
  }};
  const request = {auth: {uid: host, token: {firebase: {sign_in_provider: "password"}}}, data: {eventId: event.id, email}};
  const windowTime = Date.now();
  const call = createEventStaffLookupHandler(db, auth, {rateLimit: (database, uid, operation, limit) => limitProfileReads(database, uid, operation, limit, windowTime)});
  return {host, target, forger, event, request, call, lookupCount: () => lookupCount,
    duringLookup: (callback) => { beforeReturn = callback; }};
}

test("staff lookup uses the Auth UID despite forged Customer email and returns no private fields", async () => {
  const f = await fixture();
  assert.deepEqual(await f.call(f.request), {profile: {uid: f.target, name: "Authoritative Account", username: "target", profilePictureUrl: null}});
  assert.equal((await db.doc(`ProfileReadLimits/${f.host}`).get()).get("buckets.staff.count"), 1);
});

test("organization manager removal during Auth lookup blocks the final transactional response", async () => {
  const f = await fixture();
  const organization = db.doc(`Organizations/lookup-org-${randomUUID()}`);
  const membership = organization.collection("Members").doc(f.host);
  await organization.set({createdBy: "other"});
  await membership.set({role: "admin", status: "approved"});
  await f.event.set({customerUid: "other", organizationId: organization.id});
  f.duringLookup(() => membership.update({status: "removed"}));
  await assert.rejects(f.call(f.request), {code: "permission-denied"});
});

test("actor and target deletion begun during lookup are fenced before profile delivery", async () => {
  for (const subject of ["actor", "target", "soft-deleted-target"]) {
    const f = await fixture();
    f.duringLookup(() => subject === "soft-deleted-target" ? db.doc(`Customers/${f.target}`).update({isDeleted: true}) :
      db.doc(`account_deletion_jobs/${subject === "actor" ? f.host : f.target}`).set({status: "requested"}));
    if (subject === "actor") await assert.rejects(f.call(f.request), {code: "permission-denied"});
    else assert.deepEqual(await f.call(f.request), {profile: null});
  }
});

test("concurrent staff lookup requests consume the actual committed ten-per-minute allowance", async () => {
  const f = await fixture();
  const results = await Promise.allSettled(Array.from({length: 12}, () => f.call(f.request)));
  assert.equal(results.filter((result) => result.status === "fulfilled").length, 10);
  assert.equal(results.filter((result) => result.status === "rejected" && result.reason.code === "resource-exhausted").length, 2);
  assert.equal(f.lookupCount(), 10);
  assert.equal((await db.doc(`ProfileReadLimits/${f.host}`).get()).get("buckets.staff.count"), 10);
});
