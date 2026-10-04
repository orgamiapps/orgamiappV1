"use strict";
const test = require("node:test");
const assert = require("node:assert/strict");
const {buildRoster, metrics, key} = require("../events/roster");
const {evidence} = require("../account/attendance-history");
const {createLaunchOperations} = require("../events/launch-operations");
const {memoryAdmin} = require("./helpers/community-memory");

function rosterAdmin(initial = {}) {
  const admin = memoryAdmin(initial), db = admin.db;
  admin.firestore.FieldValue.increment = (amount) => ({increment: amount});
  const transaction = db.runTransaction;
  db.runTransaction = (callback) => transaction((tx) => callback({...tx, set: (ref, data, options) => {
    const resolved = Object.fromEntries(Object.entries(data).map(([field, value]) => [field,
      value?.increment === 1 ? (db.values.get(ref.path)?.[field] || 0) + 1 : value]));
    tx.set(ref, resolved, options);
  }}));
  // Exercise the old unconditional .set as well as the corrected transaction.
  const collection = db.collection;
  const wrapQuery = (query) => {
    const doc = query.doc;
    query.count = () => ({get: async () => {
      const count = (await query.get()).size;
      return {data: () => ({count})};
    }});
    query.doc = (id) => {
      const ref = doc(id);
      const wrapped = {...ref, collection: (name) => wrapQuery(ref.collection(name)),
        set: (data, options) => db.runTransaction((tx) => tx.set(ref, data, options))};
      wrapped.get = async () => {
        const value = db.values.get(ref.path), snapshot = structuredClone(value);
        return {ref: wrapped, id: ref.id, exists: value !== undefined, data: () => structuredClone(snapshot),
          get: (field) => structuredClone(snapshot?.[field]), updateTime: {value, isEqual: (other) => other?.value === value}};
      };
      return wrapped;
    };
    return query;
  };
  db.collection = (name) => wrapQuery(collection(name));
  db.recursiveDelete = async (ref) => {
    for (const key of db.values.keys()) if (key === ref.path || key.startsWith(ref.path + "/")) db.values.delete(key);
  };
  return admin;
}
const changedEvent = (before, after) => ({params: {id: "source"}, data: {
  before: {get: (field) => field === "eventId" ? before : undefined},
  after: {get: (field) => field === "eventId" ? after : undefined},
}});

test("actual roster triggers do not recreate a deleted event marker from delayed deliveries", async () => {
  const admin = rosterAdmin({
    "RegisterAttendance/registration": {eventId: "gone", customerUid: "person", guestId: "guest"},
    "Tickets/ticket": {eventId: "gone", customerUid: "person", guestId: "guest"},
    "HistoricalAttendance/history": {eventId: "gone"},
  });
  const handlers = createLaunchOperations(admin);
  const deliveries = [["refreshRosterEvent", {params: {id: "gone"}}],
    ["refreshRosterCorrection", {params: {id: "history", correction: "correction"}}],
    ...["RegisterAttendance", "Attendance", "Tickets", "HistoricalAttendance"].map((name) =>
      [`refreshRoster${name}`, changedEvent("gone", undefined)]),
    ["refreshRosterCustomers", {params: {id: "person"}}],
    ["refreshRosterGuestAttendees", {params: {id: "guest"}}]];
  for (const [name, delivery] of deliveries) {
    await handlers[name].run(delivery);
    assert.equal(admin.db.values.has("EventRosters/gone"), false, name);
  }
});

test("normal event and admission invalidations preserve roster data and affect both current parents", async () => {
  const admin = rosterAdmin({"Events/first": {status: "active"}, "Events/second": {status: "cancelled"},
    "EventRosters/first": {revision: 7, ready: true, generation: "retained", count: 10}});
  const handlers = createLaunchOperations(admin);
  await handlers.refreshRosterEvent.run({params: {id: "first"}});
  await handlers.refreshRosterTickets.run(changedEvent("first", "second"));
  assert.deepEqual(admin.db.values.get("EventRosters/first"), {revision: 9, ready: false, generation: "retained", count: 10});
  assert.deepEqual(admin.db.values.get("EventRosters/second"), {revision: 1, ready: false});
  await handlers.refreshRosterAttendance.run(changedEvent("first", "first"));
  assert.equal(admin.db.values.get("EventRosters/first").revision, 10);
  await handlers.refreshRosterRegisterAttendance.run(changedEvent("missing", "second"));
  assert.equal(admin.db.values.has("EventRosters/missing"), false);
  assert.equal(admin.db.values.get("EventRosters/second").revision, 2);
});

test("event deletion between transaction attempts fences delayed event and admission markers", async () => {
  for (const name of ["refreshRosterEvent", "refreshRosterAttendance"]) {
    const admin = rosterAdmin({"Events/current": {status: "active"}}), db = admin.db;
    const transaction = db.runTransaction;
    let attempts = 0;
    db.runTransaction = async (callback) => {
      attempts++;
      // The first SDK attempt is discarded after a competing source deletion.
      await callback({get: (ref) => ref.get(), set: () => {}});
      db.values.delete("Events/current"); db.values.delete("EventRosters/current");
      return transaction(callback);
    };
    const handler = createLaunchOperations(admin)[name];
    await handler.run(name === "refreshRosterEvent" ? {params: {id: "current"}} : changedEvent("current", undefined));
    assert.equal(attempts, 1);
    assert.equal(db.values.has("EventRosters/current"), false, name);
  }
});

test("a delayed former delete only invalidates a recreated current event", async () => {
  const admin = rosterAdmin({"Events/current": {customerUid: "new-owner"},
    "EventRosters/current": {generation: "current-generation", count: 3, revision: 12, ready: true}});
  const handlers = createLaunchOperations(admin);
  await handlers.refreshRosterEvent.run({params: {id: "current"}, data: {after: {exists: false}}});
  assert.deepEqual(admin.db.values.get("EventRosters/current"), {generation: "current-generation", count: 3, revision: 13, ready: false});
});

test("actual roster rebuild publishes a stable current parent", async (t) => {
  t.mock.method(require("../public-web/accountless").CONTACT_HMAC_KEY, "value", () => "unit-roster-only");
  const admin = rosterAdmin({"Events/current": {customerUid: "owner", status: "active"}});
  const result = await createLaunchOperations(admin).listEventRosterV2.run({auth: {uid: "owner"}, data: {eventId: "current"}});
  assert.equal(result.total, 0);
  assert.equal(result.nextCursor, null);
  assert.equal(admin.db.values.get("EventRosters/current").ready, true);
});

for (const replacement of [false, true]) test(`actual roster rebuild cannot publish after event ${replacement ? "replacement" : "deletion"}`, async (t) => {
  t.mock.method(require("../public-web/accountless").CONTACT_HMAC_KEY, "value", () => "unit-roster-only");
  const admin = rosterAdmin({"Events/current": {customerUid: "owner", status: "active"}}), db = admin.db;
  const transaction = db.runTransaction;
  let intercepted = false;
  db.runTransaction = async (callback) => {
    // Generation materialization precedes the final publication transaction.
    if (!intercepted && [...db.values.keys()].some((key) => key.startsWith("EventRosters/current/generations/"))) {
      intercepted = true;
      // A first successful callback must not leak its published=true outcome
      // after Firestore discards it and retries against changed parent state.
      await callback({get: (ref) => ref.get(), set: () => {}});
      db.values.delete("Events/current"); db.values.delete("EventRosters/current");
      if (replacement) db.values.set("Events/current", {customerUid: "other-owner", status: "active"});
    }
    return transaction(callback);
  };
  const error = await createLaunchOperations(admin).listEventRosterV2.run({auth: {uid: "owner"}, data: {eventId: "current"}})
      .then(() => null, (error) => error);
  assert.equal(intercepted, true);
  assert.equal([...db.values.keys()].some((key) => key.startsWith("EventRosters/")), false,
      "A discarded publication attempt must neither resurrect a roster nor retain its unpublished generation");
  assert.equal(error?.code, "unavailable");
  if (replacement) assert.equal(db.values.get("Events/current").customerUid, "other-owner");
});

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
