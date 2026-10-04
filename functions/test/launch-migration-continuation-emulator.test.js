"use strict";
const test = require("node:test");
const assert = require("node:assert/strict");
const {randomUUID} = require("node:crypto");
if (!/^127\.0\.0\.1:\d+$/.test(process.env.FIRESTORE_EMULATOR_HOST || "")) throw Error("Local Firestore emulator required");
process.env.GCLOUD_PROJECT = "demo-attendus-admin";
process.env.FUNCTIONS_EMULATOR = "true";
process.env.GUEST_CONTACT_KMS_KEY_NAME = "emulator";
process.env.GUEST_CONTACT_HMAC_KEY = "migration-fixture-only";
const db = require("../firebase-admin-compat").firestore();
const {applyEvent, sourceDocuments} = require("../tools/complete-launch-migration");
const {inspectEvent} = require("../events/migration");
const {key} = require("../events/roster");

test("migration checkpoints verify resulting revisions and preserved archive corrections before replay", async () => {
  const id = `migration-${randomUUID()}`;
  const ref = db.collection("Events").doc(id);
  await ref.set({title: "Migration fixture", selectedDateTime: new Date(), eventTimeZone: "UTC", eventDurationMinutes: 60});
  await db.collection("Attendance").doc(id).set({eventId: id, customerUid: `owner-${id}`, checkedIn: true});
  const event = await ref.get();
  const sources = await sourceDocuments(db, id);
  const approved = inspectEvent(id, event.data(), sources);
  const args = {db, event, approved, inspected: approved, sources, backup: {fixtureOnly: true}};
  assert.equal(await applyEvent(args), "complete_sources_preserved");
  const checkpoint = db.collection("LaunchMigrationCheckpoints").doc(key(`${id}:${approved.fingerprint}`));
  assert.equal((await checkpoint.collection("attendance").doc(key(id)).get()).get("status"), "verified");
  assert.equal((await db.collection("Attendance").doc(id).get()).exists, true);
  assert.equal(await applyEvent(args), "already_complete_verified");
  await ref.update({eventRevision: 8});
  assert.equal(await applyEvent(args), "blocked_completed_checkpoint_changed");
  await ref.update({eventRevision: require("firebase-admin/firestore").FieldValue.delete()});
  await db.collection("HistoricalAttendance").doc(key(id)).collection("corrections").doc("tampered").set({source: "attendance_record_update", evidence: {eventId: id}});
  await assert.rejects(applyEvent(args), /correction chain verification/);
});

test("interrupted archival resumes verified items without losing sources or duplicating attendance", async () => {
  const id = `migration-resume-${randomUUID()}`;
  const ref = db.collection("Events").doc(id);
  await ref.set({title: "Resume fixture", selectedDateTime: new Date(), eventTimeZone: "UTC", eventDurationMinutes: 60});
  for (const suffix of ["first", "second"]) {
    await db.collection("Attendance").doc(`${id}-${suffix}`).set({eventId: id, customerUid: `${id}-${suffix}`, checkedIn: true});
  }
  const event = await ref.get();
  const sources = await sourceDocuments(db, id);
  const approved = inspectEvent(id, event.data(), sources);
  const args = {db, event, approved, inspected: approved, sources, backup: {fixtureOnly: true}};
  const history = require("../account/attendance-history");
  const original = history.archiveAttendance;
  let calls = 0;
  try {
    history.archiveAttendance = async (...values) => {
      if (++calls === 2) throw Error("Injected worker interruption");
      return original(...values);
    };
    await assert.rejects(applyEvent(args), /Injected worker interruption/);
  } finally { history.archiveAttendance = original; }
  const checkpoint = db.collection("LaunchMigrationCheckpoints").doc(key(`${id}:${approved.fingerprint}`));
  assert.equal((await checkpoint.get()).get("status"), "archiving");
  assert.equal((await checkpoint.collection("attendance").get()).size, 1);
  assert.equal(await applyEvent(args), "complete_sources_preserved");
  assert.equal(await applyEvent(args), "already_complete_verified");
  assert.equal((await checkpoint.collection("attendance").get()).size, 2);
  assert.equal((await db.collection("Attendance").where("eventId", "==", id).get()).size, 2);
  assert.equal((await db.collection("HistoricalAttendance").where("eventId", "==", id).get()).size, 2);
});
