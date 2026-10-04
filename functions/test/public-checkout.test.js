"use strict";

const assert = require("node:assert/strict");
const test = require("node:test");
const {HttpsError} = require("firebase-functions/v2/https");
const {
  digest,
  registrationDocumentId,
  reservationDocumentId,
  ticketDocumentId,
  validateActionableEvent,
} = require("../public-web/checkout");

test("ticket and registration identifiers are deterministic per account", () => {
  assert.equal(ticketDocumentId("event-a", "user-a"),
      ticketDocumentId("event-a", "user-a"));
  assert.notEqual(ticketDocumentId("event-a", "user-a"),
      ticketDocumentId("event-a", "user-b"));
  assert.equal(registrationDocumentId("event-a", "user-a", "ticket"),
      `ticket_${digest("event-a", "user-a")}`);
  assert.equal(reservationDocumentId("event-a", "user-a"),
      reservationDocumentId("event-a", "user-a"));
  assert.notEqual(reservationDocumentId("event-a", "user-a"),
      reservationDocumentId("event-a", "user-b"));
});

test("checkout validation rejects private, ended, and inactive events", () => {
  const valid = {
    private: false,
    status: "active",
    selectedDateTime: "2030-01-01T00:00:00Z",
  };
  assert.doesNotThrow(() => validateActionableEvent(valid,
      new Date("2029-01-01T00:00:00Z")));
  assert.doesNotThrow(() => validateActionableEvent({...valid, status: "scheduled"},
      new Date("2029-01-01T00:00:00Z")));
  for (const event of [
    {...valid, private: true},
    {...valid, status: "draft"},
    {...valid, selectedDateTime: "2020-01-01T00:00:00Z"},
  ]) {
    assert.throws(() => validateActionableEvent(event,
        new Date("2029-01-01T00:00:00Z")), HttpsError);
  }
});
