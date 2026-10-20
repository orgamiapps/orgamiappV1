"use strict";
const test = require("node:test");
const assert = require("node:assert/strict");
const crypto = require("node:crypto");
if (!/^127\.0\.0\.1:\d+$/.test(process.env.FIRESTORE_EMULATOR_HOST || "")) throw Error("Local Firestore emulator required");
process.env.GCLOUD_PROJECT = "demo-attendus-admin";
process.env.FUNCTIONS_EMULATOR = "true";
process.env.GUEST_CONTACT_KMS_KEY_NAME = "emulator";
process.env.GUEST_CONTACT_HMAC_KEY = "local-removal-fixture-only";
const admin = require("../firebase-admin-compat");
const {createLaunchOperations} = require("../events/launch-operations");
const {createMaintainPublicEventPage} = require("../public-web/renderer");
const db = admin.firestore();
const operations = createLaunchOperations(admin);
const suffix = crypto.randomUUID();
const owner = `removal-owner-${suffix}`;
const stranger = `removal-stranger-${suffix}`;
const request = (uid, data, anonymous = false) => ({
  auth: {uid, token: {firebase: {sign_in_provider: anonymous ? "anonymous" : "password"}}}, data,
});
const seed = async (name, fields = {}) => {
  const id = `removal-${name}-${suffix}`;
  await db.doc(`Events/${id}`).set({
    title: "Removal fixture", customerUid: owner, private: false, status: "active", eventRevision: 3,
    selectedDateTime: new Date(Date.now() + 86400000), eventDurationMinutes: 60,
    eventTimeZone: "America/New_York", ...fields,
  });
  return id;
};
const eligibility = (eventId, uid = owner) =>
  operations.getEventCapabilitiesV1.run(request(uid, {eventId, includeRemovalEligibility: true}));
test.after(async () => { await db.terminate(); });

test("removal eligibility is optional and only exposed to event managers", async () => {
  const staff = `removal-door-${suffix}`;
  const id = await seed("eligibility", {checkInStaff: [staff]});
  const ordinary = await operations.getEventCapabilitiesV1.run(request(owner, {eventId: id}));
  assert.equal(Object.hasOwn(ordinary, "removalEligibility"), false);
  assert.deepEqual((await eligibility(id)).removalEligibility, {canDelete: true, eventRevision: 3});
  for (const uid of [stranger, staff]) {
    const result = await eligibility(id, uid);
    assert.equal(result.permissions.manageEvent, false);
    assert.equal(Object.hasOwn(result, "removalEligibility"), false);
  }
});

test("every preserved record type blocks preflight eligibility and authoritative deletion", async () => {
  const id = await seed("records");
  for (const name of ["RegisterAttendance", "Tickets", "Attendance", "HistoricalAttendance",
    "TicketPayments", "TicketUpgradePayments", "EventFeaturePayments", "FeaturePayments", "Payments"]) {
    const ref = db.collection(name).doc(`removal-record-${suffix}`);
    await ref.set({eventId: id});
    try {
      assert.equal((await eligibility(id)).removalEligibility.canDelete, false, name);
      await assert.rejects(operations.deleteEmptyEventV1.run(request(owner, {
        eventId: id, expectedEventRevision: 3, requestId: `record-${name}-${suffix}`,
      })), {code: "failed-precondition"});
      assert.equal((await db.doc(`Events/${id}`).get()).exists, true);
    } finally {
      await ref.delete();
    }
  }
  assert.equal((await eligibility(id)).removalEligibility.canDelete, true);
});

test("deletion atomically removes its projection and returns the same result for concurrent and later retries", async () => {
  const id = await seed("success");
  const projection = db.doc(`PublicWebEvents/${id}`);
  await projection.set({title: "Removal fixture"});
  const data = {eventId: id, expectedEventRevision: 3, requestId: `success-${suffix}`};
  const expected = {status: "deleted", affectedEventIds: [id]};
  const results = await Promise.all([
    operations.deleteEmptyEventV1.run(request(owner, data)),
    operations.deleteEmptyEventV1.run(request(owner, data)),
  ]);
  for (const result of results) assert.deepEqual(result, expected);
  assert.equal((await db.doc(`Events/${id}`).get()).exists, false);
  assert.equal((await projection.get()).exists, false);
  assert.deepEqual(await operations.deleteEmptyEventV1.run(request(owner, data)), expected);
  const receipts = await db.collection("EventDeletionReceipts").where("eventId", "==", id).get();
  assert.equal(receipts.size, 1);
  assert.equal(receipts.docs[0].get("actorUid"), owner);
  // A delayed public-page delivery cannot resurrect the removed projection.
  await createMaintainPublicEventPage(admin).run({params: {eventId: id}});
  assert.equal((await projection.get()).exists, false);
});

test("deletion receipts cannot be reused for a different event, revision, actor, or anonymous session", async () => {
  const id = await seed("receipt-source");
  const other = await seed("receipt-other");
  const data = {eventId: id, expectedEventRevision: 3, requestId: `bound-${suffix}`};
  await operations.deleteEmptyEventV1.run(request(owner, data));
  for (const mismatch of [{...data, eventId: other}, {...data, expectedEventRevision: 4}]) {
    await assert.rejects(operations.deleteEmptyEventV1.run(request(owner, mismatch)), {code: "failed-precondition"});
  }
  assert.equal((await db.doc(`Events/${other}`).get()).exists, true);
  await assert.rejects(operations.deleteEmptyEventV1.run(request(stranger, data)), {code: "not-found"});
  await assert.rejects(operations.deleteEmptyEventV1.run(request(owner, data, true)), {code: "unauthenticated"});
  const deletion = db.collection("account_deletion_jobs").doc(owner);
  await deletion.set({status: "running"});
  try {
    await assert.rejects(operations.deleteEmptyEventV1.run(request(owner, data)), {code: "failed-precondition"});
  } finally {
    await deletion.delete();
  }
});

test("stale revisions and a registration arriving after preflight leave the event intact", async () => {
  const id = await seed("race");
  assert.deepEqual((await eligibility(id)).removalEligibility, {canDelete: true, eventRevision: 3});
  await db.doc(`Events/${id}`).update({eventRevision: 4});
  await assert.rejects(operations.deleteEmptyEventV1.run(request(owner, {
    eventId: id, expectedEventRevision: 3, requestId: `stale-${suffix}`,
  })), {code: "aborted"});
  assert.equal((await db.doc(`Events/${id}`).get()).exists, true);
  assert.equal((await eligibility(id)).removalEligibility.canDelete, true);
  await db.collection("RegisterAttendance").doc(`arrived-${suffix}`).set({eventId: id, customerUid: stranger});
  await assert.rejects(operations.deleteEmptyEventV1.run(request(owner, {
    eventId: id, expectedEventRevision: 4, requestId: `arrived-${suffix}`,
  })), {code: "failed-precondition"});
  assert.equal((await db.doc(`Events/${id}`).get()).exists, true);
  assert.equal((await db.collection("EventDeletionReceipts").where("eventId", "==", id).get()).empty, true);
});

test("legacy deletion callers retain stable retry results without a request ID", async () => {
  const id = await seed("legacy");
  const data = {eventId: id, expectedEventRevision: 3};
  const expected = {status: "deleted", affectedEventIds: [id]};
  assert.deepEqual(await operations.deleteEmptyEventV1.run(request(owner, data)), expected);
  assert.deepEqual(await operations.deleteEmptyEventV1.run(request(owner, data)), expected);
});

test("series cancellation returns all affected IDs on commit and retry without duplicate notices", async () => {
  const seriesId = `removal-series-${suffix}`;
  const now = Date.now();
  const earlier = await seed("series-earlier", {seriesId, selectedDateTime: new Date(now + 86400000)});
  const current = await seed("series-current", {seriesId, selectedDateTime: new Date(now + 2 * 86400000)});
  const later = await seed("series-later", {seriesId, selectedDateTime: new Date(now + 3 * 86400000)});
  const preview = await operations.previewEventCancellationV1.run(request(owner, {
    eventId: current, recurrenceScope: "this_and_future",
  }));
  const data = {eventId: current, previewToken: preview.previewToken, reason: "Fixture cancellation"};
  for (let attempt = 0; attempt < 2; attempt++) {
    const result = await operations.cancelEventV1.run(request(owner, data));
    assert.equal(result.status, "cancelled");
    assert.deepEqual(result.affectedEventIds.sort(), [current, later].sort());
  }
  assert.equal((await db.doc(`Events/${earlier}`).get()).get("status"), "active");
  for (const id of [current, later]) {
    const event = await db.doc(`Events/${id}`).get();
    assert.equal(event.get("status"), "cancelled");
    assert.equal(event.get("eventRevision"), 4);
    assert.equal((await db.collection("EventAnnouncements").where("eventId", "==", id).get()).size, 1);
  }
});
