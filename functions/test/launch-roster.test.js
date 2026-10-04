"use strict";
const test = require("node:test");
const assert = require("node:assert/strict");
const {buildRoster, metrics, key} = require("../events/roster");
const {evidence} = require("../account/attendance-history");

test("roster retains 650 distinct admissions with repeated names and purchasers", () => {
  const registrations = Array.from({length: 650}, (_, index) => ({id: `r${index}`, customerUid: "buyer",
    realName: "Same Name", ticketId: `t${index}`, status: "confirmed"}));
  const tickets = registrations.map((r) => ({id: r.ticketId, registrationId: r.id, customerUid: "buyer"}));
  const attendance = [{id: "a1", ticketId: "t601", attendanceDateTime: "2026-01-01T00:00:00Z"}];
  const rows = buildRoster(registrations, tickets, attendance);
  assert.equal(rows.length, 650);
  assert.equal(rows.filter((row) => row.attendanceIds.length).length, 1);
  const summary = metrics(rows, {selectedDateTime: "2026-01-01T00:00:00Z", eventDurationMinutes: 90});
  assert.equal(summary.confirmed, 650); assert.equal(summary.remaining, 649); assert.equal(summary.noShow, 649);
  assert.equal(metrics(rows, {status: "cancelled", selectedDateTime: "2026-01-01", eventDurationMinutes: 90}).noShow, null);
});
test("multiple tickets on one registration stay separate and archive does not double count", () => {
  const rows = buildRoster([{id: "r", status: "confirmed"}], [{id: "t1", registrationId: "r"}, {id: "t2", registrationId: "r"}],
      [{id: "a", ticketId: "t2", checkedInAt: "2026-01-01"}], [{id: key("a"), sourceAttendanceHash: key("a"), checkedInAt: "2026-01-01"}]);
  assert.equal(rows.length, 2); assert.equal(rows.filter((row) => row.attendanceIds.length).length, 1);
});
test("attendance evidence excludes unused admissions and identifying information", () => {
  assert.equal(evidence("unused", {eventId: "e", customerUid: "private"}), null);
  const stamp = evidence("a", {eventId: "e", customerUid: "private", realName: "Original Name", email: "private@example.com", checkedInAt: "2026-01-01"});
  assert.equal(stamp.eventId, "e");
  assert.equal(JSON.stringify(stamp).includes("private"), false);
  assert.equal(JSON.stringify(stamp).includes("Original Name"), false);
});

test("inside state folds transitions chronologically and leaves unknown evidence outside", () => {
  const rows = buildRoster([{id: "r", status: "confirmed"}], [], [
    {id: "a", registrationId: "r", checkedInAt: "2026-09-27T10:00:00Z", checkedOutAt: "2026-09-27T12:00:00Z"},
    {id: "b", registrationId: "r", checkedInAt: "2026-09-27T11:00:00Z"},
    {id: "unknown", admissionGroupId: "old", timestampQuality: "unknown"},
  ]);
  assert.equal(rows.find((row) => row.registrationId === "r").attendanceStatus, "checked_out");
  assert.equal(rows.find((row) => !row.registrationId).attendanceStatus, "attended_unknown");
  assert.equal(metrics(rows, {checkInPolicy: {checkoutEnabled: true}}).inside, 0);
});

test("unpaid and revoked admissions never count as confirmed", () => {
  const rows = buildRoster([{id: "r", status: "confirmed", paymentStatus: "unpaid"}], [
    {id: "unpaid", price: 10, paymentStatus: "unpaid"},
    {id: "revoked", status: "revoked"},
    {id: "paid", price: 10, paymentStatus: "paid"},
  ], []);
  assert.equal(metrics(rows, {}).confirmed, 1);
  assert.equal(rows.find((row) => row.ticketId === "revoked").status, "cancelled");
});
