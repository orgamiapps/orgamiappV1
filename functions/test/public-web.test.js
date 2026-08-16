"use strict";

const assert = require("node:assert/strict");
const test = require("node:test");
const {
  communityEligibility,
  escapeHtml,
  eventEligibility,
  eventDescription,
  eventJsonLd,
  eventState,
  isoInTimeZone,
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
