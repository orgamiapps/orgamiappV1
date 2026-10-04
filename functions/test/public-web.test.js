"use strict";
process.env.GCLOUD_PROJECT = "demo-attendus-admin";
process.env.GOOGLE_CLOUD_PROJECT = "demo-attendus-admin";
process.env.FUNCTIONS_EMULATOR = "true";

const assert = require("node:assert/strict");
const test = require("node:test");
const {memoryAdmin} = require("./helpers/community-memory");
const {
  communityEligibility,
  createMaintainPublicCommunityPage,
  createMaintainPublicEventPage,
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
  assert.equal(ticketState({...future, ticketsEnabled: false}).state, "rsvp");
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
