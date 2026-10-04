"use strict";
const test = require("node:test");
const assert = require("node:assert/strict");
const {calendarAttachmentEligible, calendarInvite} = require("../communications/delivery");

function fixture() {
  const data = new Map([
    ["Events/event", {status: "active", ticketsEnabled: false}],
    ["RegisterAttendance/reg", {eventId: "event", status: "confirmed", customerUid: "owner", guestId: "guest"}],
    ["GuestAttendees/guest", {ownerUid: "owner", encryptedEmail: "encrypted-original-contact"}],
  ]);
  const ref = (path) => ({path, id: path.split("/").at(-1)});
  const collection = (path, filters = [], maximum = Infinity) => ({path, filters, maximum,
    doc: (id) => ref(`${path}/${id}`),
    where: (field, op, value) => { assert.equal(op, "=="); return collection(path, [...filters, [field, value]], maximum); },
    limit: (count) => collection(path, filters, count),
  });
  const snapshot = (path) => ({exists: data.has(path), id: ref(path).id,
    get: (field) => data.get(path)?.[field], data: () => data.get(path)});
  const db = {collection, runTransaction: (work) => work({get: async (query) => {
    if (!query.filters) return snapshot(query.path);
    const docs = [...data.entries()].filter(([path, row]) => path.startsWith(query.path + "/") &&
      query.filters.every(([field, value]) => row[field] === value)).slice(0, query.maximum).map(([path]) => snapshot(path));
    return {docs, size: docs.length};
  }})};
  const message = {eventId: "event", registrationId: "reg", guestId: "guest", encryptedEmail: "encrypted-original-contact",
    templateId: "guest_registration_confirmation", payload: {eventTitle: "Fixture", eventStart: "2030-01-01T12:00:00Z",
      eventDurationMinutes: 60, eventTimeZone: "UTC", eventRevision: 3}};
  return {data, message, eligible: () => calendarAttachmentEligible(db, message)};
}

test("current confirmed RSVP can attach while duplicate proof, announcements and pending states cannot", async () => {
  const f = fixture(); assert.equal(await f.eligible(), true);
  f.message.payload.duplicate = true; assert.equal(await f.eligible(), false);
  delete f.message.payload.duplicate;
  f.message.templateId = "event_announcement"; assert.equal(await f.eligible(), false);
  f.message.templateId = "guest_registration_confirmation";
  for (const status of ["pending", "waitlisted", "declined", "cancelled"]) {
    f.data.get("RegisterAttendance/reg").status = status;
    assert.equal(await f.eligible(), false);
  }
});
test("ticket confirmations require proven, currently valid linked admission", async () => {
  const f = fixture(); f.data.get("Events/event").ticketsEnabled = true;
  assert.equal(await f.eligible(), false);
  f.data.get("RegisterAttendance/reg").ticketId = "ticket";
  f.data.set("Tickets/ticket", {eventId: "event", registrationId: "reg", guestId: "guest", price: 0});
  assert.equal(await f.eligible(), true);
  for (const patch of [{revoked: true}, {status: "refunded"}, {price: 10, isPaid: false}]) {
    f.data.set("Tickets/ticket", {eventId: "event", registrationId: "reg", guestId: "guest", ...patch});
    assert.equal(await f.eligible(), false);
  }
});
test("missing and changed event, identity, contact and deletion records suppress attachments", async () => {
  for (const change of [
    (f) => f.data.delete("Events/event"),
    (f) => { f.data.get("Events/event").cancelled = true; },
    (f) => { f.data.get("RegisterAttendance/reg").eventId = "other-event"; },
    (f) => { f.message.guestId = "other-guest"; },
    (f) => { f.data.get("GuestAttendees/guest").encryptedEmail = "changed-contact"; },
    (f) => f.data.set("account_deletion_jobs/owner", {status: "running"}),
    (f) => f.data.delete("RegisterAttendance/reg"),
  ]) {
    const f = fixture(); change(f); assert.equal(await f.eligible(), false);
  }
});
test("previously confirmed cancellation preserves UID despite current revocation", async () => {
  const f = fixture(); f.message.templateId = "guest_registration_cancelled";
  f.data.get("RegisterAttendance/reg").status = "cancelled";
  f.data.get("RegisterAttendance/reg").ticketId = "ticket";
  f.data.set("Tickets/ticket", {eventId: "event", registrationId: "reg", revoked: true});
  assert.equal(await f.eligible(), false);
  f.message.payload.calendarPreviouslyConfirmed = true;
  assert.equal(await f.eligible(), true);
  const invitation = calendarInvite(f.message, "CANCEL");
  assert.match(invitation, /UID:reg@attendus.app/);
  assert.match(invitation, /METHOD:CANCEL/);
  f.data.get("RegisterAttendance/reg").status = "confirmed";
  assert.equal(await f.eligible(), false, "stale cancellation after reinstatement must be suppressed");
});
test("pending cancellation cannot gain calendar attachment without confirmed evidence", async () => {
  const f = fixture(); f.message.templateId = "guest_registration_cancelled";
  f.data.get("RegisterAttendance/reg").status = "cancelled";
  f.message.payload.calendarPreviouslyConfirmed = false;
  assert.equal(await f.eligible(), false);
});
test("event cancellation requires explicit confirmed evidence and matching cancelled event", async () => {
  const f = fixture(); f.message.templateId = "event_cancelled";
  f.message.payload.calendarPreviouslyConfirmed = true;
  assert.equal(await f.eligible(), false);
  f.data.get("Events/event").status = "cancelled";
  assert.equal(await f.eligible(), true);
});
test("ticket-only lifecycle retains its prior ticket UID and never makes an undefined UID", async () => {
  const f = fixture(); delete f.message.registrationId; f.message.ticketId = "ticket";
  f.message.templateId = "event_rescheduled";
  f.data.set("Tickets/ticket", {eventId: "event", guestId: "guest", price: 0, customerUid: "owner"});
  assert.equal(await f.eligible(), true);
  assert.match(calendarInvite(f.message), /UID:ticket@attendus.app/);
  delete f.message.ticketId;
  assert.equal(await f.eligible(), false);
  assert.equal(calendarInvite(f.message), null);
});
test("account attachment checks exact owner and linked ticket event identities", async () => {
  const f = fixture(); delete f.message.guestId; f.message.ownerUid = "wrong-owner";
  assert.equal(await f.eligible(), false);
  f.message.ownerUid = "owner"; assert.equal(await f.eligible(), true);
  f.data.get("RegisterAttendance/reg").ticketId = "ticket";
  f.data.set("Tickets/ticket", {eventId: "different-event", registrationId: "reg", price: 0});
  assert.equal(await f.eligible(), false);
});
