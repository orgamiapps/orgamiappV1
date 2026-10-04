"use strict";
// All delivery tests use local fake storage and unsupported channels, never a provider.
process.env.GCLOUD_PROJECT = "orgami-66nxok";
delete process.env.GOOGLE_CLOUD_PROJECT;
const test = require("node:test");
const assert = require("node:assert/strict");
const {createResolveOutboundDeliveryUnknownV1, markAbandonedDeliveryUnknown, processMessage,
  requireCurrentDeliveryRecipient, templateFor} = require("../communications/delivery");

function fixture() {
  const deleted = Symbol("deleted");
  const data = new Map([
    ["admin_roles/admin", {active: true, roles: ["support"]}],
    ["OutboundMessages/message", {status: "delivery_unknown", ownerUid: "attendee", registrationId: "original-registration",
      payload: {calendarUid: "original-calendar"}, attempts: 1}],
  ]);
  const ref = (path) => ({path, id: path.split("/").at(-1),
    get: async () => { const row = data.get(path); return {exists: Boolean(row), get: (field) => row?.[field], data: () => row}; },
    set: async (row) => { data.set(path, row); }});
  let beforeTransaction;
  const db = {collection: (path) => ({doc: (id) => ref(`${path}/${id}`)}), runTransaction: async (work) => {
    if (beforeTransaction) beforeTransaction();
    const writes = [];
    const result = await work({get: async (target) => {
      assert.equal(writes.length, 0, "Firestore forbids reads after writes");
      const row = data.get(target.path);
      return {exists: Boolean(row), ref: target, get: (field) => row?.[field], data: () => row};
    }, update: (target, patch) => writes.push([target.path, patch]),
    delete: (target) => writes.push([target.path, deleted]),
    create: (target, patch) => { assert.equal(data.has(target.path), false); writes.push([target.path, patch]); }});
    for (const [path, patch] of writes) {
      if (patch === deleted) { data.delete(path); continue; }
      const row = {...data.get(path)};
      for (const [field, value] of Object.entries(patch)) {
        if (value === deleted) delete row[field]; else row[field] = value;
      }
      data.set(path, row);
    }
    return result;
  }};
  const firestore = () => db;
  firestore.FieldValue = {serverTimestamp: () => ({toMillis: () => Date.now()}), delete: () => deleted};
  const admin = {firestore};
  const resolve = createResolveOutboundDeliveryUnknownV1(admin);
  return {data, admin, db, ref: ref("OutboundMessages/message"), before: (callback) => { beforeTransaction = callback; },
    resolve: (changes = {}, auth = {uid: "admin", token: {admin: true}}) => resolve.run({auth, data: {
      messageId: "message", idempotencyKey: "resolution-request", resolution: "accepted",
      reason: "Provider log confirms the final outcome", evidenceReference: "protected-case/123", ...changes,
    }})};
}

test("operator resolution atomically audits accepted outcome and keeps issued identities", async () => {
  const f = fixture(); const result = await f.resolve();
  const message = f.data.get("OutboundMessages/message");
  assert.equal(message.status, "accepted");
  assert.equal(message.registrationId, "original-registration");
  assert.equal(message.payload.calendarUid, "original-calendar");
  assert.equal(message.nextAttemptAt, undefined);
  assert.equal(f.data.get(`admin_audit_logs/${result.auditId}`).before.status, "delivery_unknown");
  assert.equal(f.data.get(`OutboundDeliveryResolutions/${result.resolutionId}`).resolution, "accepted");
  assert.deepEqual(await f.resolve(), result);
  assert.equal([...f.data.keys()].filter((path) => path.startsWith("admin_audit_logs/")).length, 1);
});
test("failed resolution is terminal and does not queue a resend", async () => {
  const f = fixture(); await f.resolve({resolution: "failed"});
  await processMessage(f.admin, f.ref);
  assert.equal(f.data.get(f.ref.path).status, "failed");
  assert.equal(f.data.get(f.ref.path).attempts, 1);
});
test("conflicting request keys and another resolution of the same outcome are rejected", async () => {
  const f = fixture(); await f.resolve();
  await assert.rejects(f.resolve({resolution: "failed"}), {code: "already-exists"});
  await assert.rejects(f.resolve({idempotencyKey: "other-request"}), {code: "failed-precondition"});
});
test("admin claim plus current active communications role is mandatory, including replay", async () => {
  const f = fixture();
  await assert.rejects(f.resolve({}, {uid: "admin", token: {}}), {code: "permission-denied"});
  f.data.set("admin_roles/admin", {active: true, roles: ["analyst"]});
  await assert.rejects(f.resolve(), {code: "permission-denied"});
  f.data.set("admin_roles/admin", {active: true, roles: ["support"]});
  await f.resolve();
  f.data.set("admin_roles/admin", {active: false, roles: ["support"]});
  await assert.rejects(f.resolve(), {code: "permission-denied"});
});
test("actor and recipient deletion guards block resolution in the write transaction", async () => {
  for (const uid of ["admin", "attendee"]) {
    const f = fixture(); f.data.set(`account_deletion_jobs/${uid}`, {status: "running"});
    await assert.rejects(f.resolve(), {code: "failed-precondition"});
    assert.equal(f.data.get(f.ref.path).status, "delivery_unknown");
  }
});
test("guest-owner deletion guard applies when outbound record has no ownerUid", async () => {
  const f = fixture(); delete f.data.get(f.ref.path).ownerUid;
  f.data.get(f.ref.path).guestId = "guest";
  f.data.set("GuestAttendees/guest", {ownerUid: "attendee"});
  f.data.set("account_deletion_jobs/attendee", {status: "running"});
  await assert.rejects(f.resolve(), {code: "failed-precondition"});
});
test("only unknown messages and documented accepted/failed resolutions are allowed", async () => {
  for (const status of ["pending", "sending", "accepted", "failed"]) {
    const f = fixture(); f.data.get(f.ref.path).status = status;
    await assert.rejects(f.resolve(), {code: "failed-precondition"});
  }
  for (const changes of [{resolution: "retry"}, {reason: "short"}, {evidenceReference: ""}, {messageId: "../escape"}]) {
    await assert.rejects(fixture().resolve(changes), {code: "invalid-argument"});
  }
});
test("abandoned sweep rechecks status and timestamp before marking an outcome unknown", async () => {
  const cutoff = new Date(2000);
  for (const [status, lastAttemptAt] of [["accepted", 1000], ["sending", 3000], ["sending", 2000]]) {
    const f = fixture(); Object.assign(f.data.get(f.ref.path), {status, lastAttemptAt: {toMillis: () => lastAttemptAt}});
    assert.equal(await markAbandonedDeliveryUnknown(f.admin, f.ref, cutoff), false);
    assert.equal(f.data.get(f.ref.path).status, status);
  }
  const f = fixture(); Object.assign(f.data.get(f.ref.path), {status: "sending", deliveryAttemptId: "old", lastAttemptAt: {toMillis: () => 1000}});
  assert.equal(await markAbandonedDeliveryUnknown(f.admin, f.ref, cutoff), true);
  assert.equal(f.data.get(f.ref.path).status, "delivery_unknown");
  assert.equal(f.data.get(f.ref.path).deliveryAttemptId, undefined);
});
test("late worker failure cannot overwrite an accepted result or operator resolution", async () => {
  for (const status of ["accepted", "failed", "delivery_unknown"]) {
    const f = fixture(); Object.assign(f.data.get(f.ref.path), {status: "pending", channel: "unsupported"});
    let transactions = 0;
    f.before(() => { if (++transactions === 2) f.data.get(f.ref.path).status = status; });
    // Unsupported channel fails before decryption/provider calls, exercising
    // final-write fencing without sending any message.
    await processMessage(f.admin, f.ref);
    assert.equal(f.data.get(f.ref.path).status, status);
  }
});

test("outbound resolution and reservation fence every guest identity after a claim", async () => {
  for (const deletingUid of ["attendee", "guest-owner", "claimed-owner"]) {
    const f = fixture(); f.data.get(f.ref.path).guestId = "guest";
    f.data.set("GuestAttendees/guest", {ownerUid: "guest-owner", claimedByUid: "claimed-owner"});
    f.data.set(`account_deletion_jobs/${deletingUid}`, {status: "running"});
    await assert.rejects(f.resolve(), {code: "failed-precondition"});
    f.data.get(f.ref.path).status = "pending";
    await processMessage(f.admin, f.ref);
    assert.equal(f.data.has(f.ref.path), false, "unavailable recipient must never reach decryption or delivery");
  }
});

test("provider handoff rechecks deletion and worker ownership", async () => {
  for (const change of [
    (f) => f.data.set("account_deletion_jobs/attendee", {status: "running"}),
    (f) => { f.data.get(f.ref.path).deliveryAttemptId = "replacement"; },
    (f) => { f.data.get(f.ref.path).status = "delivery_unknown"; },
  ]) {
    const f = fixture(); Object.assign(f.data.get(f.ref.path), {status: "sending", deliveryAttemptId: "original"});
    const message = {...f.data.get(f.ref.path)}; change(f);
    await assert.rejects(requireCurrentDeliveryRecipient(f.db, f.ref, message, "a@example.test"), {deliverySuppressed: true});
  }
});

test("provider handoff refuses a changed guest address but accepts equal addresses with different ciphertext", async (t) => {
  const previous = {emulator: process.env.FUNCTIONS_EMULATOR, key: process.env.GUEST_CONTACT_KMS_KEY_NAME};
  process.env.FUNCTIONS_EMULATOR = "true"; process.env.GUEST_CONTACT_KMS_KEY_NAME = "emulator";
  t.after(() => {
    for (const [name, value] of [["FUNCTIONS_EMULATOR", previous.emulator], ["GUEST_CONTACT_KMS_KEY_NAME", previous.key]]) {
      if (value === undefined) delete process.env[name]; else process.env[name] = value;
    }
  });
  const f = fixture();
  Object.assign(f.data.get(f.ref.path), {status: "sending", deliveryAttemptId: "original", guestId: "guest", encryptedEmail: "original-ciphertext"});
  f.data.set("GuestAttendees/guest", {ownerUid: "attendee", encryptedEmail: Buffer.from("changed@example.test").toString("base64")});
  const message = {...f.data.get(f.ref.path)};
  await assert.rejects(requireCurrentDeliveryRecipient(f.db, f.ref, message, "original@example.test"), {deliverySuppressed: true});
  f.data.get("GuestAttendees/guest").encryptedEmail = Buffer.from("original@example.test").toString("base64");
  await requireCurrentDeliveryRecipient(f.db, f.ref, message, "original@example.test");
});

test("published HTML templates escape attendee and event data while text remains readable", async () => {
  const source = {status: "published", subject: "{{eventTitle}}", text: "Hello {{firstName}}", html: "<h1>{{eventTitle}}</h1><a href=\"{{manageUrl}}\">{{firstName}}</a>"};
  const db = {collection: () => ({doc: () => ({get: async () => ({exists: true, get: (field) => source[field]})})})};
  const template = await templateFor(db, {payload: {eventTitle: "<img src=x onerror=\"alert(1)\">", firstName: "A&B", manageUrl: "https://attendus.app/manage/test?next=\"test\""}});
  assert.equal(template.subject, "<img src=x onerror=\"alert(1)\">");
  assert.equal(template.text, "Hello A&B");
  assert.doesNotMatch(template.html, /<img|href="[^"]*"test"/);
  assert.match(template.html, /&lt;img/); assert.match(template.html, /A&amp;B/); assert.match(template.html, /&quot;test&quot;/);
});

test("demo emulator captures a genuine accepted delivery without any provider request", async (t) => {
  const settings = {FUNCTIONS_EMULATOR: "true", GCLOUD_PROJECT: "demo-attendus-admin", GOOGLE_CLOUD_PROJECT: "demo-attendus-admin",
    FIRESTORE_EMULATOR_HOST: "127.0.0.1:8180", GUEST_CONTACT_KMS_KEY_NAME: "emulator"};
  const original = Object.fromEntries(Object.keys(settings).map((name) => [name, process.env[name]]));
  Object.assign(process.env, settings);
  t.after(() => { for (const [name, value] of Object.entries(original)) { if (value === undefined) delete process.env[name]; else process.env[name] = value; } });
  t.mock.method(global, "fetch", async () => assert.fail("A demo delivery must not make a provider request"));
  const f = fixture(); Object.assign(f.data.get(f.ref.path), {status: "pending", attempts: 0,
    templateId: "event_announcement", channel: "email", encryptedEmail: Buffer.from("fixture@example.test").toString("base64"),
    eventId: "event", payload: {title: "Fixture update", body: "Captured locally"}});
  await processMessage(f.admin, f.ref);
  assert.equal(f.data.get(f.ref.path).status, "accepted");
  assert.equal(f.data.get(f.ref.path).provider, "emulator_capture");
  assert.equal(f.data.get("EmulatorOutboundDeliveries/message").recipient, "fixture@example.test");
  assert.match(f.data.get("EmulatorOutboundDeliveries/message").html, /Captured locally/);
  const {demoDeliveryCaptureEnabled} = require("../communications/delivery");
  for (const [name, unsafe] of [["GCLOUD_PROJECT", "orgami-66nxok"], ["GOOGLE_CLOUD_PROJECT", "attendus-staging"], ["FUNCTIONS_EMULATOR", "false"], ["FIRESTORE_EMULATOR_HOST", "remote.example:8180"]]) {
    process.env[name] = unsafe;
    assert.equal(demoDeliveryCaptureEnabled(), false);
    process.env[name] = settings[name];
  }
});
