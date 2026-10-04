"use strict";
const {test} = require("node:test");
const assert = require("node:assert/strict");
const {createEventStaffLookupHandler, normalizedStaffEmail} = require("../profiles/staff-lookup");

function fixture() {
  const records = new Map([
    ["Events/event", {customerUid: "host", checkInStaff: ["door"]}],
    ["Customers/target", {name: "Target", username: "target", email: "private@example.com", phoneNumber: "private",
      profilePictureUrl: "https://example.com/avatar.png", fcmToken: "secret-token", stripeCustomerId: "private", bio: "excluded"}],
    ["Customers/forger", {name: "Forged", email: "target@example.com"}],
  ]);
  const snapshot = (ref) => ({ref, id: ref.id, exists: records.has(ref.path), data: () => records.get(ref.path), get: (key) => records.get(ref.path)?.[key]});
  const doc = (path) => ({path, id: path.split("/").at(-1), get: async () => snapshot(doc(path)), collection: (key) => collection(`${path}/${key}`)});
  const collection = (path) => ({doc: (id) => doc(`${path}/${id}`)});
  const reads = [];
  const db = {collection, runTransaction: async (callback) => callback({get: async (ref) => { reads.push(ref.path); return snapshot(ref); }})};
  const account = {uid: "target", email: "target@example.com", emailVerified: true, disabled: false, providerData: [{providerId: "password"}]};
  const lookups = [];
  let authFailure;
  let beforeLookup = () => {};
  const auth = {getUserByEmail: async (email) => {
    lookups.push(email);
    beforeLookup();
    if (authFailure) throw authFailure;
    return account;
  }};
  const limits = [];
  let limitFailure;
  const handler = createEventStaffLookupHandler(db, auth, {rateLimit: async (_db, uid, operation, limit) => {
    limits.push({uid, operation, limit});
    if (limitFailure) throw limitFailure;
  }});
  const request = (uid = "host") => ({app: {appId: "attested-app"}, auth: {uid, token: {firebase: {sign_in_provider: "password"}}}, data: {eventId: "event", email: " Target@Example.com "}});
  return {records, account, lookups, limits, reads, handler, request,
    authFails: (error) => { authFailure = error; }, limitFails: (error) => { limitFailure = error; },
    afterPermission: (callback) => { beforeLookup = callback; }};
}

test("staff lookup resolves Auth email identity and returns only the bounded public fields", async () => {
  const f = fixture();
  assert.deepEqual(await f.handler(f.request()), {profile: {uid: "target", name: "Target", username: "target", profilePictureUrl: "https://example.com/avatar.png"}});
  assert.deepEqual(f.lookups, ["target@example.com"]);
  assert.deepEqual(f.limits, [{uid: "host", operation: "staff", limit: 10}]);
  assert.ok(f.reads.includes("Customers/target"));
  assert.equal(f.reads.includes("Customers/forger"), false, "forged editable profile email never determines the returned UID");
});

test("only an attested full-account event manager can perform the email lookup", async () => {
  for (const change of [
    (request) => { request.auth = null; },
    (request) => { request.auth.token.firebase.sign_in_provider = "anonymous"; },
    (request) => { request.app = null; },
    (request) => { request.auth.uid = "outsider"; },
    (request) => { request.auth.uid = "door"; },
  ]) {
    const f = fixture();
    const request = f.request();
    change(request);
    await assert.rejects(f.handler(request), (error) => ["unauthenticated", "failed-precondition", "permission-denied"].includes(error.code));
    assert.deepEqual(f.lookups, []);
  }
});

test("email validation and the shared limit fail before any Auth lookup", async () => {
  for (const email of [null, 42, "", "prefix*", "name@example", "a..b@example.com", "a@-example.com", "a@exam_ple.com", `${"a".repeat(65)}@example.com`, `${"x".repeat(255)}@example.com`]) {
    assert.throws(() => normalizedStaffEmail(email), (error) => error.code === "invalid-argument");
  }
  const f = fixture();
  f.limitFails(Object.assign(Error("limited"), {code: "resource-exhausted"}));
  await assert.rejects(f.handler(f.request()), {code: "resource-exhausted"});
  assert.deepEqual(f.lookups, []);
});

test("missing, unverified, disabled, anonymous, deleting and absent-profile targets are indistinguishable", async () => {
  for (const change of [
    (f) => f.authFails({code: "auth/user-not-found"}),
    (f) => { f.account.emailVerified = false; },
    (f) => { f.account.disabled = true; },
    (f) => { f.account.providerData = []; },
    (f) => { f.account.providerData = [{providerId: "anonymous"}]; },
    (f) => { f.account.email = "other@example.com"; },
    (f) => f.records.set("account_deletion_jobs/target", {status: "running"}),
    (f) => f.records.set("Customers/target", {name: "Deleted", isDeleted: true}),
    (f) => f.records.delete("Customers/target"),
  ]) {
    const f = fixture();
    change(f);
    assert.deepEqual(await f.handler(f.request()), {profile: null});
  }
});

test("valid imported Firebase UIDs retain punctuation without allowing document paths", async () => {
  const f = fixture();
  f.account.uid = "imported:user@example.com";
  f.records.set(`Customers/${f.account.uid}`, {name: "Imported"});
  assert.equal((await f.handler(f.request())).profile.uid, f.account.uid);
  for (const uid of ["parent/child", "bad\u0000uid", "x".repeat(129)]) {
    f.account.uid = uid;
    assert.deepEqual(await f.handler(f.request()), {profile: null});
  }
});

test("permission removal and actor deletion during Auth lookup cannot return a profile", async () => {
  for (const change of [
    (f) => f.records.set("Events/event", {customerUid: "other"}),
    (f) => f.records.delete("Events/event"),
    (f) => f.records.set("account_deletion_jobs/host", {status: "running"}),
  ]) {
    const f = fixture();
    f.afterPermission(() => change(f));
    await assert.rejects(f.handler(f.request()), {code: "permission-denied"});
    assert.equal(f.reads.includes("Customers/target"), false);
  }
});

test("organization manager membership is rechecked inside the final transaction", async () => {
  const f = fixture();
  f.records.set("Events/event", {customerUid: "other", organizationId: "organization"});
  f.records.set("Organizations/organization", {createdBy: "other"});
  f.records.set("Organizations/organization/Members/host", {status: "approved", role: "admin"});
  f.afterPermission(() => f.records.set("Organizations/organization/Members/host", {status: "removed", role: "admin"}));
  await assert.rejects(f.handler(f.request()), {code: "permission-denied"});
});

test("Auth provider errors become retryable without leaking private provider detail", async () => {
  const f = fixture();
  f.authFails(Object.assign(Error("private provider details"), {code: "auth/internal-error"}));
  await assert.rejects(f.handler(f.request()), (error) => error.code === "unavailable" && !error.message.includes("private"));
});
