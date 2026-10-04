"use strict";
const test = require("node:test");
const assert = require("node:assert/strict");
const arrival = require("../attendance/arrival");

function database({auditFailure = false} = {}) {
  const audits = [];
  return {audits, collection: name => ({doc: () => name === "AppConfig" ? {
    get: async () => ({data: () => ({corePasses: {enabled: false}})}),
  } : {set: async value => {
    assert.equal(name, "CheckInAudit");
    if (auditFailure) throw Error("Audit storage unavailable");
    audits.push(value);
  }}})};
}

test("issuance failure records only safe funnel fields and timing", async () => {
  const db = database();
  const input = {kind: "event", eventId: "pilot-event", token: "private-token",
    position: {latitude: 40.123456, longitude: -74.654321}, answers: ["private-answer"]};
  await assert.rejects(() => arrival.issuePass(db, "pilot-attendee", input), error => error.code === "failed-precondition");
  assert.equal(db.audits.length, 1);
  const audit = db.audits[0];
  assert.deepEqual(Object.keys(audit).sort(), ["action", "actorUid", "createdAt", "durationMs", "eventId", "failureCode", "kind"]);
  assert.equal(audit.action, "attendance_pass_issue_failed");
  assert.equal(audit.failureCode, "failed-precondition");
  assert.equal(audit.actorUid, "pilot-attendee");
  assert.equal(audit.eventId, "pilot-event");
  assert.ok(Number.isFinite(audit.durationMs) && audit.durationMs >= 0);
  assert.doesNotMatch(JSON.stringify(audit), /private-token|private-answer|latitude|longitude|40\.123456/);
});

test("audit write failure preserves the original issuance denial", async () => {
  await assert.rejects(() => arrival.issuePass(database({auditFailure: true}), "attendee", {kind: "identity"}),
      error => error.code === "unauthenticated" && error.message === "Sign in to get your reusable Attendus pass.");
});
