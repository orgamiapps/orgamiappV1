"use strict";
const test = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");
const vm = require("node:vm");
const {createRequire} = require("node:module");
const filename = require.resolve("../public-web/checkout");
const localRequire = createRequire(filename);
const source = fs.readFileSync(filename, "utf8");
// Exercise the private webhook handler without adding a production export.
const handleRefund = vm.runInNewContext(`${source.slice(source.indexOf("async function handleRefund("), source.indexOf("async function handleDispute("))}\nhandleRefund`,
    {require: localRequire, Date, registrationDocumentId: localRequire(filename).registrationDocumentId});

function fixture({confirmed = 1, revoked = false, linked = true, guestId = null} = {}) {
  const data = new Map([
    ["TicketPayments/pi", {status: "completed", eventId: "event", ticketId: "ticket", amountCents: 1000, fee: 100}],
    ["Events/event", {issuedTickets: revoked ? 0 : 1, ...(confirmed === null ? {} : {confirmedRegistrationCount: confirmed})}],
    ["Tickets/ticket", {eventId: "event", paymentIntentId: "pi", price: 10, isPaid: true, revoked, guestId,
      ...(linked ? {registrationId: "reg"} : {})}],
    ...(linked ? [["RegisterAttendance/reg", {eventId: "event", ticketId: "ticket", status: "confirmed", customerUid: "owner"}]] : []),
  ]);
  const ref = (path) => ({path, id: path.split("/").at(-1)});
  const snapshot = (path) => ({exists: data.has(path), ref: ref(path), id: ref(path).id,
    get: (field) => data.get(path)?.[field], data: () => data.get(path)});
  const collection = (path, filters = [], maximum = Infinity) => ({path, filters, maximum,
    doc: (id) => ref(`${path}/${id}`),
    where: (field, op, value) => { assert.equal(op, "=="); return collection(path, [...filters, [field, value]], maximum); },
    limit: (count) => collection(path, filters, count),
  });
  const db = {collection, runTransaction: async (work) => {
    const writes = [];
    await work({get: async (query) => {
      assert.equal(writes.length, 0, "Firestore forbids reads after writes");
      if (!query.filters) return snapshot(query.path);
      const docs = [...data.entries()].filter(([path, row]) => path.startsWith(query.path + "/") &&
        query.filters.every(([field, value]) => row[field] === value)).slice(0, query.maximum).map(([path]) => snapshot(path));
      return {docs, size: docs.length, empty: docs.length === 0};
    }, update: (target, patch) => writes.push([target.path, patch]),
    create: (target, patch) => { assert.equal(data.has(target.path), false); writes.push([target.path, patch]); }});
    for (const [path, patch] of writes) data.set(path, {...data.get(path), ...patch});
  }};
  const firestore = () => db;
  firestore.FieldValue = {serverTimestamp: () => "server-time"};
  return {data, refund: (id = "refund", amount = 1000) => handleRefund({firestore}, {id, type: "charge.refunded",
    data: {object: {payment_intent: "pi", amount: 1000, amount_refunded: amount}}})};
}

test("full refund releases one confirmed admission and preserves payment fields; replay is inert", async () => {
  const f = fixture();
  await f.refund(); await f.refund(); await f.refund("second-notification");
  assert.equal(f.data.get("Events/event").confirmedRegistrationCount, 0);
  assert.equal(f.data.get("Events/event").issuedTickets, 0);
  assert.equal(f.data.get("RegisterAttendance/reg").status, "cancelled");
  assert.equal(f.data.get("Tickets/ticket").paymentStatus, "refunded");
  assert.equal(f.data.get("Tickets/ticket").isPaid, true);
  assert.equal(f.data.get("TicketPayments/pi").fee, 100);
});
test("already revoked admission never releases capacity a second time", async () => {
  const f = fixture({revoked: true, confirmed: 0});
  await f.refund();
  assert.equal(f.data.get("Events/event").confirmedRegistrationCount, 0);
  assert.equal(f.data.get("Events/event").issuedTickets, 0);
});
test("legacy missing confirmed counter is retained and standalone ticket releases once", async () => {
  const f = fixture({linked: false, confirmed: null});
  await f.refund();
  assert.equal(f.data.get("Events/event").confirmedRegistrationCount, undefined);
  assert.equal(f.data.get("Events/event").issuedTickets, 0);
});
test("partial refund does not revoke admission or release a place", async () => {
  const f = fixture();
  await f.refund("partial", 300);
  assert.equal(f.data.get("Events/event").confirmedRegistrationCount, 1);
  assert.equal(f.data.get("Tickets/ticket").revoked, false);
  assert.equal(f.data.get("TicketPayments/pi").status, "partial_refund_review");
});
test("conflicting registration link stops destructive refund updates", async () => {
  const f = fixture();
  f.data.get("RegisterAttendance/reg").ticketId = "someone-else";
  await assert.rejects(f.refund(), /identity requires review/);
  assert.equal(f.data.get("TicketPayments/pi").status, "completed");
  assert.equal(f.data.get("Events/event").confirmedRegistrationCount, 1);
});
test("pending linked registration is not counted as a confirmed admission", async () => {
  const f = fixture({confirmed: 0});
  f.data.get("RegisterAttendance/reg").status = "pending";
  await f.refund();
  assert.equal(f.data.get("Events/event").confirmedRegistrationCount, 0);
});
test("legacy guest-only link blocks instead of guessing the released registration", async () => {
  const f = fixture({linked: false, guestId: "guest"});
  f.data.set("RegisterAttendance/old", {eventId: "event", guestId: "guest", status: "confirmed"});
  await assert.rejects(f.refund(), /linkage review/);
  assert.equal(f.data.get("Tickets/ticket").revoked, false);
});
test("reordered partial notification cannot downgrade an already completed refund", async () => {
  const f = fixture();
  await f.refund(); await f.refund("late-partial", 100);
  assert.equal(f.data.get("TicketPayments/pi").status, "refunded");
  assert.equal(f.data.get("Events/event").confirmedRegistrationCount, 0);
});
test("explicit forward-only registration link is recovered transactionally", async () => {
  const f = fixture();
  delete f.data.get("Tickets/ticket").registrationId;
  await f.refund();
  assert.equal(f.data.get("RegisterAttendance/reg").status, "cancelled");
  assert.equal(f.data.get("Events/event").confirmedRegistrationCount, 0);
});
test("original reservation proves older admission link without contact matching", async () => {
  const f = fixture({linked: false});
  f.data.get("TicketPayments/pi").reservationId = "reservation";
  f.data.set("TicketReservations/reservation", {eventId: "event", ticketId: "ticket", registrationId: "old-reg", customerUid: "owner"});
  f.data.set("RegisterAttendance/old-reg", {eventId: "event", customerUid: "owner", status: "confirmed"});
  await f.refund();
  assert.equal(f.data.get("RegisterAttendance/old-reg").status, "cancelled");
  assert.equal(f.data.get("Events/event").confirmedRegistrationCount, 0);
});
