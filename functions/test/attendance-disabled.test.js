"use strict";
process.env.GCLOUD_PROJECT = "demo-attendus-admin";
process.env.FUNCTIONS_EMULATOR = "true";
const test = require("node:test");
const assert = require("node:assert/strict");
const {memoryAdmin} = require("./helpers/community-memory");
const v2 = require("../attendance/v2");
const arrival = require("../attendance/arrival");
const {createSubmitGuestAttendance} = require("../guest/attendance");
const disabled = (error) => error.code === "failed-precondition" && /disabled/.test(error.message);
const request = (data, guest = false) => ({auth: {uid: "owner", token: {
  firebase: {sign_in_provider: guest ? "anonymous" : "password"}}}, data});
function fixture() {
  const admin = memoryAdmin({"Events/event": {id: "event", customerUid: "owner", status: "active",
    checkInPolicy: {version: 3, profile: "none", staffFallback: true}},
  "Attendance/history": {eventId: "event", customerUid: "person", status: "active"},
  "RegisterAttendance/rsvp": {eventId: "event", status: "confirmed"},
  "CheckInSessions/session": {eventId: "event", status: "active"},
  "check_in_session_secrets/session": {secret: "old-secret"}});
  const collection = admin.db.collection;
  admin.db.collection = (name) => {
    const result = collection(name);
    result.add = async (data) => {
      assert.equal(name, "CheckInAudit");
      admin.db.values.set(`${name}/${admin.db.values.size}`, data);
    };
    return result;
  };
  return admin;
}
test("all callable attendance methods reject none and preserve history and RSVP", async () => {
  const admin = fixture();
  const before = [...admin.db.values.entries()];
  for (const type of ["location", "attendance_pass", "venue_token", "personal_pass", "staff_roster", "staff_guest", "checkout"]) {
    for (const offline of [false, true]) {
      await assert.rejects(() => v2.createSubmitCheckIn(admin).run(request({eventId: "event", sessionId: "session",
        credential: {type, value: "previously-issued"}, offline, observedAt: new Date().toISOString(), offlineKitRevision: "old-kit", idempotencyKey: "disabled-check", answers: []})), disabled);
    }
  }
  await assert.rejects(() => v2.createStartCheckInSession(admin).run(request({eventId: "event"})), disabled);
  await assert.rejects(() => v2.createMintVenueCredential(admin).run(request({sessionId: "session"})), disabled);
  await assert.rejects(() => createSubmitGuestAttendance(admin).run(request({eventId: "event", method: "manual_code",
    fullName: "Guest Attendee", answers: []}, true)), disabled);
  await assert.rejects(() => arrival.commitAttendance(admin.db, {input: {eventId: "event"}}), disabled);
  await assert.rejects(() => arrival.offlineKit(admin.db, "event", "session", "owner"), disabled);
  for (const [key, value] of before) assert.deepEqual(admin.db.values.get(key), value);
  assert.equal([...admin.db.values.keys()].filter((key) => key.startsWith("Attendance/")).length, 1);
});
