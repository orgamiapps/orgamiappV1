"use strict";
const test = require("node:test"), assert = require("node:assert/strict");
const {memoryAdmin} = require("./helpers/community-memory");
const {MAX_LEASE_MS, bindingId, emailHash, qualificationDecision, interceptQualification} = require("../communications/qualification-isolation");
const {createLegacyNotificationSender} = require("../notifications/legacy-delivery");
const now = Date.now(), project = "orgami-66nxok", runId = "fixture-run-001";
const context = {actorUid: "actor", recipientUid: "recipient", eventId: "event"};
function fixture() {
  return memoryAdmin({
    [`QualificationBindings/${bindingId("event", "event")}`]: {schemaVersion: 1, projectId: project, runId, state: "bound"},
    [`QualificationScopes/${runId}`]: {schemaVersion: 1, projectId: project, status: "active", mode: "capture", createdAt: new Date(now - 1000), expiresAt: new Date(now + 60000),
      actorUids: ["actor"], recipientUids: ["recipient"], eventIds: ["event"], organizationIds: [], conversationIds: [], recipientEmailHashes: [emailHash("fixture@example.test")]},
  });
}
const options = {now, env: {GCLOUD_PROJECT: project}};
test("ordinary production remains enabled; staging and unknown runtimes fail closed", async () => {
  const {db} = memoryAdmin();
  assert.equal((await qualificationDecision(db, context, null, options)).mode, "normal");
  for (const env of [{GCLOUD_PROJECT: "attendus-staging"}, {}, {GCLOUD_PROJECT: project, GOOGLE_CLOUD_PROJECT: "other"}]) {
    assert.equal((await qualificationDecision(db, context, null, {...options, env})).mode, "suppress");
  }
});
test("only associated source and explicitly controlled recipient can capture", async () => {
  const {db} = fixture();
  assert.equal((await qualificationDecision(db, context, null, options)).mode, "capture");
  for (const patch of [{recipientUid: "real-user"}, {actorUid: "outside"}, {organizationId: "outside"}, {eventIds: ["outside"]}]) {
    assert.equal((await qualificationDecision(db, {...context, ...patch}, null, options)).mode, "suppress");
  }
  assert.equal((await qualificationDecision(db, {...context, recipientUid: "anonymous", recipientEmail: "Fixture@Example.test"}, null, options)).mode, "capture");
  assert.equal((await qualificationDecision(db, {...context, recipientUid: "anonymous", deferRecipientEmail: true}, null, options)).mode, "verify_email");
});
test("expired, absent, malformed, retired and mixed-run markers never fall through to production", async () => {
  for (const mutation of [
    (db) => db.values.delete(`QualificationScopes/${runId}`),
    (db) => { db.values.get(`QualificationScopes/${runId}`).expiresAt = new Date(now); },
    (db) => { db.values.get(`QualificationScopes/${runId}`).expiresAt = new Date(now + MAX_LEASE_MS + 1); },
    (db) => { db.values.get(`QualificationScopes/${runId}`).recipientUids = "recipient"; },
    (db) => { db.values.get(`QualificationBindings/${bindingId("event", "event")}`).state = "tombstone"; },
    (db) => db.values.set(`QualificationBindings/${bindingId("account", "recipient")}`, {schemaVersion: 1, projectId: project, runId: "another-run", state: "bound"}),
    (db) => db.values.set("account_deletion_jobs/recipient", {status: "running"}),
  ]) { const {db} = fixture(); mutation(db); assert.equal((await qualificationDecision(db, context, null, options)).mode, "suppress"); }
});
test("capture is atomic and replay-stable; changed source content is never silently overwritten", async () => {
  const {db} = fixture(), payload = {title: "Fixture"};
  const first = await interceptQualification(db, context, "stable-source", payload, options);
  assert.equal((await interceptQualification(db, context, "stable-source", payload, options)).captureId, first.captureId);
  assert.equal([...db.values.keys()].filter((path) => path.startsWith("QualificationCaptures/")).length, 1);
  await assert.rejects(interceptQualification(db, context, "stable-source", {title: "Changed"}, options), /different captured content/);
  assert.equal([...db.values.keys()].filter((path) => path.includes("/notifications/")).length, 0);
});
test("legacy fixture delivery captures before inbox/provider and remains suppressed after scope deletion", async (t) => {
  const previous = {GCLOUD_PROJECT: process.env.GCLOUD_PROJECT, GOOGLE_CLOUD_PROJECT: process.env.GOOGLE_CLOUD_PROJECT};
  process.env.GCLOUD_PROJECT = project; delete process.env.GOOGLE_CLOUD_PROJECT;
  t.after(() => { for (const [key, value] of Object.entries(previous)) { if (value === undefined) delete process.env[key]; else process.env[key] = value; } });
  const admin = fixture(); let calls = 0;
  admin.messaging = () => ({send: async () => { calls++; throw Error("Provider must not run"); }});
  const send = createLegacyNotificationSender(admin), payload = {actorUid: "actor", eventId: "event", title: "Fixture", body: "Body", type: "new_event"};
  assert.equal((await send("recipient", payload, admin.db, "source")).status, "qualification_capture");
  await send("recipient", payload, admin.db, "source");
  admin.db.values.delete(`QualificationScopes/${runId}`);
  assert.equal((await send("recipient", payload, admin.db, "later-source")).status, "qualification_suppress");
  assert.equal(calls, 0);
  assert.equal([...admin.db.values.keys()].filter((path) => path.includes("/notifications/")).length, 0);
  assert.equal([...admin.db.values.keys()].filter((path) => path.startsWith("QualificationCaptures/")).length, 1);
});
