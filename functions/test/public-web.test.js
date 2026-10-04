"use strict";
process.env.GCLOUD_PROJECT = "demo-attendus-admin";
process.env.GOOGLE_CLOUD_PROJECT = "demo-attendus-admin";
process.env.FUNCTIONS_EMULATOR = "true";

const assert = require("node:assert/strict");
const crypto = require("node:crypto");
const test = require("node:test");
const {memoryAdmin} = require("./helpers/community-memory");
const {
  communityEligibility,
  createMaintainPublicCommunityPage,
  createMaintainPublicEventPage,
  createPublicWeb,
  escapeHtml,
  eventEligibility,
  eventDescription,
  eventJsonLd,
  eventState,
  isoInTimeZone,
  projectionForCommunity,
  projectionForEvent,
  safeJson,
  ticketState,
} = require("../public-web/renderer");

function manageFixture({registration = {}, event = {}, ticket = null} = {}) {
  const raw = "synthetic_manage_session_1234567890";
  const sessionId = crypto.createHash("sha256").update(raw).digest("hex");
  const admin = memoryAdmin({
    "AppConfig/publicWeb": {publicPagesEnabled: true},
    [`GuestManageSessions/${sessionId}`]: {status: "active", registrationId: "registration", guestId: "guest",
      csrfToken: "synthetic-csrf", expiresAt: new Date(Date.now() + 60000)},
    "RegisterAttendance/registration": {eventId: "event", guestId: "guest", customerUid: "person", realName: "Fixture", ...registration},
    "GuestAttendees/guest": {maskedEmail: "f***@example.test"},
    "Events/event": {title: "Fixture event", status: "active", selectedDateTime: new Date(Date.now() + 86400000),
      eventDurationMinutes: 90, eventTimeZone: "UTC", ...event},
    ...(ticket ? {"Tickets/ticket": {eventId: "event", registrationId: "registration", guestId: "guest", ticketCode: "FIXTURECODE", ...ticket}} : {}),
  });
  const handler = createPublicWeb(admin);
  return {admin, sessionId, async get(route, cookie = raw) {
    let status = 200, body = "";
    const headers = {};
    const res = {set(key, value) { headers[key] = value; return this; },
      status(value) { status = value; return this; }, type(value) { headers.type = value; return this; },
      send(value) { body = value; return this; }, end() { return this; }};
    await handler({method: "GET", path: route, get: (name) => name === "cookie" ? `attendus_guest_manage=${cookie}` : undefined}, res);
    return {status, body, headers};
  }};
}

for (const [status, label] of [["pending", "Pending approval"], ["waitlisted", "Waitlisted"], ["declined", "Declined"],
  ["unrecognized", "Unavailable"], [false, "Unavailable"], [0, "Unavailable"], [{confirmed: true}, "Unavailable"]]) {
  test(`manage HTTP accurately renders nonconfirmed ${JSON.stringify(status)} and blocks admission artifacts`, async () => {
    const fixture = manageFixture({registration: {status}, ticket: {}});
    const page = await fixture.get("/manage");
    assert.equal(page.status, 200);
    assert.ok(page.body.includes(`<dt>Status</dt><dd>${label}</dd>`));
    assert.equal(page.body.includes("FIXTURECODE"), false);
    assert.equal(page.body.includes("href=\"/manage/attendance\""), false);
    assert.equal(page.body.includes("href=\"/manage/calendar.ics\""), false);
    assert.equal((await fixture.get("/manage/calendar.ics")).status, 409);
    assert.equal((await fixture.get("/manage/ticket.svg")).status, 404);
  });
}

test("manage HTTP preserves confirmed and legacy RSVP calendar/pass controls and session boundaries", async () => {
  for (const status of [undefined, null, "", "confirmed"]) {
    const fixture = manageFixture({registration: {status}});
    const page = await fixture.get("/manage");
    assert.ok(page.body.includes("<dt>Status</dt><dd>Confirmed</dd>"));
    assert.ok(page.body.includes("href=\"/manage/attendance\""));
    const calendar = await fixture.get("/manage/calendar.ics");
    assert.equal(calendar.status, 200);
    assert.match(calendar.body, /METHOD:PUBLISH/);
    assert.match(calendar.body, /UID:registration@attendus.app/);
    assert.equal((await fixture.get("/manage/ticket.svg")).status, 404);
    assert.equal((await fixture.get("/manage", "foreign_session_12345678901234567890")).status, 404);
    fixture.admin.db.values.get(`GuestManageSessions/${fixture.sessionId}`).expiresAt = new Date(0);
    assert.equal((await fixture.get("/manage")).status, 404);
  }
});

test("manage HTTP exposes only confirmed currently valid linked tickets", async () => {
  for (const ticket of [{price: 0}, {price: 10, isPaid: true}, {price: 0, registrationId: undefined}]) {
    const fixture = manageFixture({event: {ticketsEnabled: true}, registration: {status: "confirmed", ticketId: "ticket"}, ticket});
    assert.match((await fixture.get("/manage")).body, /FIXTURECODE/);
    assert.equal((await fixture.get("/manage/ticket.svg")).status, 200);
    assert.match((await fixture.get("/manage/calendar.ics")).body, /METHOD:PUBLISH/);
  }
  for (const ticket of [null, {revoked: true}, {cancelled: true}, {status: "pending"}, {price: 10, isPaid: false}, {registrationId: "another_registration"}]) {
    const fixture = manageFixture({event: {ticketsEnabled: true}, registration: {status: "confirmed", ticketId: "ticket"}, ticket});
    const page = await fixture.get("/manage");
    assert.equal(page.body.includes("FIXTURECODE"), false);
    assert.equal(page.body.includes("href=\"/manage/attendance\""), false);
    assert.equal((await fixture.get("/manage/ticket.svg")).status, 404);
    assert.doesNotMatch((await fixture.get("/manage/calendar.ics")).body, /METHOD:PUBLISH/);
  }
});

test("manage HTTP preserves cancellation calendars but never presents cancelled admission as usable", async () => {
  for (const patch of [{registration: {status: "cancelled"}}, {registration: {cancelled: true}},
    {registration: {status: "canceled"}}, {event: {status: "cancelled"}}, {event: {cancelled: true}}, {ticket: {revoked: true}}]) {
    const fixture = manageFixture({registration: {status: "confirmed", ...patch.registration}, event: patch.event, ticket: {price: 0, ...patch.ticket}});
    const page = await fixture.get("/manage");
    assert.ok(page.body.includes("<dt>Status</dt><dd>Cancelled</dd>"));
    assert.equal(page.body.includes("FIXTURECODE"), false);
    assert.equal(page.body.includes("href=\"/manage/attendance\""), false);
    assert.equal(page.body.includes("Cancel registration</button>"), false);
    const calendar = await fixture.get("/manage/calendar.ics");
    assert.equal(calendar.status, 200);
    assert.match(calendar.body, /METHOD:CANCEL/);
    assert.equal((await fixture.get("/manage/ticket.svg")).status, 404);
  }
});

test("manage HTTP does not advertise admission for unavailable events or unpaid registration", async () => {
  for (const patch of [{event: {status: "draft"}}, {event: {deleted: true}}, {event: {launchScheduleNeedsReview: true}},
    {registration: {paymentStatus: "pending"}}]) {
    const fixture = manageFixture({registration: {status: "confirmed", ...patch.registration}, event: patch.event});
    const page = await fixture.get("/manage");
    assert.ok(page.body.includes("<dt>Status</dt><dd>Unavailable</dd>"));
    assert.equal(page.body.includes("href=\"/manage/attendance\""), false);
    assert.equal((await fixture.get("/manage/calendar.ics")).status, 409);
  }
});

const future = {
  title: "Summer Social",
  description: "Meet neighbors and local organizers.",
  private: false,
  status: "active",
  selectedDateTime: "2030-07-01T23:00:00Z",
  eventDuration: 2,
  eventTimeZone: "America/New_York",
  locationType: "in_person",
  locationName: "Civic Hall",
  location: "100 Main St, Miami, FL 33101",
  streetAddress: "100 Main St",
  city: "Miami",
  regionCode: "FL",
  postalCode: "33101",
  countryCode: "US",
  groupName: "Miami Neighbors",
  imageUrl: "https://example.com/event.jpg",
  ticketsEnabled: true,
  ticketPrice: 12.5,
  maxTickets: 10,
  issuedTickets: 3,
  reservedTickets: 1,
};

test("event eligibility rejects private, unpublished, and malformed events", () => {
  assert.equal(eventEligibility(future), true);
  assert.equal(eventEligibility({...future, private: true}), false);
  assert.equal(eventEligibility({...future, private: undefined}), false);
  assert.equal(eventEligibility({...future, isHidden: true}), false);
  assert.equal(eventEligibility({...future, deleted: true}), false);
  assert.equal(eventEligibility({...future, status: "draft"}), false);
  assert.equal(eventEligibility({...future, selectedDateTime: null}), false);
});

test("completed and cancelled public events remain eligible archives", () => {
  assert.equal(eventEligibility({...future, status: "scheduled"}), true);
  assert.equal(eventEligibility({...future, status: "completed"}), true);
  assert.equal(eventEligibility({...future, status: "cancelled"}), true);
  assert.equal(eventState({...future, status: "cancelled"}), "cancelled");
});

test("ticket state accounts for reservations and server price", () => {
  assert.deepEqual(ticketState(future).state, "paid_ticket");
  assert.equal(ticketState({...future, issuedTickets: 9}).state, "sold_out");
  assert.equal(ticketState({...future, ticketsEnabled: false, confirmedRegistrationCount: 0}).state, "rsvp");
});

test("public event HTTP uses confirmed and reserved capacity rather than advertising a rejected registration", async () => {
  for (const event of [
    {ticketsEnabled: true, confirmedRegistrationCount: 1, issuedTickets: 0, reservedTickets: 0},
    {ticketsEnabled: false, confirmedRegistrationCount: 0, issuedTickets: 0, reservedTickets: 1},
  ]) {
    const fixture = manageFixture({event: {private: false, maxTickets: 1, ticketPrice: 0,
      registrationPolicy: {capacity: 1, waitlistEnabled: false}, ...event}});
    const response = await fixture.get("/event/event");
    assert.equal(response.status, 200);
    assert.match(response.body, event.ticketsEnabled ? /<p>Sold out<\/p>/ : /<p>Event full<\/p>/);
    assert.doesNotMatch(response.body, /data-public-action="(?:ticket|rsvp)"/);
  }
});

test("public event HTTP retains available and enabled waitlist entrypoints", async () => {
  for (const [confirmed, waitlist, label] of [[0, false, "Get free ticket"], [1, true, "Join waitlist"]]) {
    const fixture = manageFixture({event: {private: false, ticketsEnabled: true, ticketPrice: 0, maxTickets: 1,
      issuedTickets: 0, reservedTickets: 0, confirmedRegistrationCount: confirmed,
      registrationPolicy: {capacity: 1, waitlistEnabled: waitlist}}});
    const response = await fixture.get("/event/event");
    assert.equal(response.status, 200);
    assert.ok(response.body.includes(`<p>${label}</p>`));
    assert.match(response.body, /data-public-action="ticket"/);
  }
});

test("public capacity does not synthesize missing or invalid authoritative counters", () => {
  for (const confirmedRegistrationCount of [undefined, null, -1, "invalid"]) {
    assert.deepEqual(ticketState({...future, ticketsEnabled: false, confirmedRegistrationCount}),
        {state: "unavailable", label: "Availability unavailable"});
    assert.deepEqual(ticketState({...future, ticketPrice: 0, confirmedRegistrationCount}),
        {state: "unavailable", label: "Availability unavailable"});
  }
  assert.deepEqual(ticketState({...future, confirmedRegistrationCount: 0, reservedTickets: -1}),
      {state: "unavailable", label: "Availability unavailable"});
  // Paid V2 checkout retains its explicitly supported legacy issued/reserved
  // fallback, without persisting any guessed confirmed count.
  assert.equal(ticketState({...future, confirmedRegistrationCount: undefined, issuedTickets: 9}).state, "sold_out");
});

test("public free event with missing reconciled total renders unavailable without a 500 or purchase action", async () => {
  const fixture = manageFixture({event: {private: false, ticketsEnabled: true, ticketPrice: 0,
    maxTickets: 1, issuedTickets: 0, registrationPolicy: {capacity: 1, waitlistEnabled: true}}});
  const response = await fixture.get("/event/event");
  assert.equal(response.status, 200);
  assert.match(response.body, /<p>Availability unavailable<\/p>/);
  assert.doesNotMatch(response.body, /data-public-action="(?:ticket|rsvp)"/);
});

test("JSON-LD uses local offset and matching server-derived offer", () => {
  const value = eventJsonLd("event-1", future, null);
  assert.equal(value.startDate, "2030-07-01T19:00:00-04:00");
  assert.equal(value.location.address.postalCode, "33101");
  assert.equal(value.offers.price, 12.5);
  assert.equal(value.offers.priceCurrency, "USD");
});

test("HTML and JSON script contexts neutralize injected markup", () => {
  assert.equal(escapeHtml("<img onerror='x'>&"),
      "&lt;img onerror=&#39;x&#39;&gt;&amp;");
  const encoded = safeJson({value: "</script><script>alert(1)</script>"});
  assert.equal(encoded.includes("</script>"), false);
  assert.equal(encoded.includes("\\u003c"), true);
});

test("time zones fail closed to UTC", () => {
  assert.equal(isoInTimeZone(new Date("2030-01-01T12:00:00Z"), "not/a-zone"),
      "2030-01-01T12:00:00Z");
});

test("communities require explicit public-page opt in", () => {
  assert.equal(communityEligibility({name: "Group", publicPageEnabled: true}), true);
  assert.equal(communityEligibility({name: "Group"}), false);
});

test("missing archive descriptions receive a truthful visible metadata fallback", () => {
  const value = eventDescription({...future, description: ""}, null);
  assert.match(value, /Summer Social/);
  assert.match(value, /Miami Neighbors/);
});

// Include direct writes so these regressions exercise the old handler too;
// the transaction double separately rejects reads after pending writes.
function mirrorAdmin(initial) {
  const admin = memoryAdmin(initial), collection = admin.db.collection;
  admin.db.collection = (name) => {
    const result = collection(name), doc = result.doc;
    result.doc = (id) => ({...doc(id),
      set: async (data) => admin.db.values.set(`${name}/${id}`, data),
      delete: async () => admin.db.values.delete(`${name}/${id}`)});
    return result;
  };
  return admin;
}

const mirrorCases = [
  {name: "event", source: "Events", mirror: "PublicWebEvents", param: "eventId",
    factory: createMaintainPublicEventPage, project: projectionForEvent,
    publicData: {...future, createdAt: new Date("2026-01-01T00:00:00Z")},
    privateData: {...future, private: true}},
  {name: "community", source: "Organizations", mirror: "PublicWebCommunities", param: "organizationId",
    factory: createMaintainPublicCommunityPage, project: projectionForCommunity,
    publicData: {name: "Current community", publicPageEnabled: true, createdAt: new Date("2026-01-01T00:00:00Z")},
    privateData: {name: "Private community", publicPageEnabled: false}},
];
for (const item of mirrorCases) {
  const trigger = (data) => ({params: {[item.param]: "item"}, data: {after: {
    exists: data !== null, data: () => data,
  }}});
  for (const state of ["missing", "private"]) test(`${item.name} mirror cannot be resurrected by stale public delivery after parent becomes ${state}`, async () => {
    const admin = mirrorAdmin({[`${item.mirror}/item`]: {title: "Stale public value"},
      ...(state === "private" ? {[`${item.source}/item`]: item.privateData} : {})});
    await item.factory(admin).run(trigger(item.publicData));
    assert.equal(admin.db.values.has(`${item.mirror}/item`), false);
  });
  test(`${item.name} mirror old delete follows the current recreated public parent`, async () => {
    const admin = mirrorAdmin({[`${item.source}/item`]: item.publicData});
    const handler = item.factory(admin);
    await handler.run(trigger(null));
    assert.deepEqual(admin.db.values.get(`${item.mirror}/item`), item.project("item", item.publicData));
    await handler.run(trigger(item.privateData));
    assert.deepEqual(admin.db.values.get(`${item.mirror}/item`), item.project("item", item.publicData));
  });
  test(`${item.name} mirror rechecks source after a discarded transaction attempt`, async () => {
    const admin = mirrorAdmin({[`${item.source}/item`]: item.publicData});
    const run = admin.db.runTransaction;
    let discardedAttempts = 0;
    admin.db.runTransaction = async (callback) => {
      await callback({get: (ref) => ref.get(), set() {}, delete() {}});
      discardedAttempts++;
      admin.db.values.set(`${item.source}/item`, item.privateData);
      return run(callback);
    };
    await item.factory(admin).run(trigger(item.publicData));
    assert.equal(discardedAttempts, 1);
    assert.equal(admin.db.values.has(`${item.mirror}/item`), false);
  });
}
