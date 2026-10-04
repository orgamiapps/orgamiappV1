"use strict";

const assert = require("node:assert/strict");
const test = require("node:test");
const {HttpsError} = require("firebase-functions/v2/https");
const {
  canReadEvent,
  ticketDocumentId,
  validateFreeTicketEvent,
} = require("../tickets/issuance");

const freeEvent = {
  ticketsEnabled: true,
  ticketPrice: 0,
  maxTickets: 10,
  issuedTickets: 2,
  status: "active",
  selectedDateTime: new Date("2100-01-01T00:00:00Z"),
};

test("free ticket identifiers are stable without exposing user IDs", () => {
  const id = ticketDocumentId("event-a", "sensitive-user");
  assert.equal(id, ticketDocumentId("event-a", "sensitive-user"));
  assert.equal(id.includes("sensitive-user"), false);
  assert.notEqual(id, ticketDocumentId("event-a", "another-user"));
});

test("paid prices cannot enter the free ticket path", () => {
  assert.throws(
      () => validateFreeTicketEvent({...freeEvent, ticketPrice: 0.01}),
      (error) => error instanceof HttpsError &&
        error.code === "failed-precondition",
  );
});

test("capacity and event configuration are server validated", () => {
  assert.throws(
      () => validateFreeTicketEvent({...freeEvent, issuedTickets: 10}),
      (error) => error instanceof HttpsError &&
        error.code === "resource-exhausted",
  );
  assert.doesNotThrow(() => validateFreeTicketEvent(freeEvent));
});

test("scheduled public events can issue tickets", () => {
  assert.doesNotThrow(() => validateFreeTicketEvent({
    ...freeEvent,
    status: "scheduled",
  }));
});

test("private event access requires ownership or invitation", () => {
  const event = {private: true, customerUid: "owner", accessList: ["invitee"]};
  assert.equal(canReadEvent(event, "owner"), true);
  assert.equal(canReadEvent(event, "invitee"), true);
  assert.equal(canReadEvent(event, "stranger"), false);
});


test("reconciled capacity includes reservations without double counting issued tickets", () => {
  const {capacityState, ticketCapacityState, confirmedDelta} = require("../events/capacity");
  const event = {...freeEvent, maxTickets: 3, confirmedRegistrationCount: 2, issuedTickets: 2, reservedTickets: 1};
  assert.equal(capacityState(event).full, true);
  assert.throws(() => validateFreeTicketEvent(event), {code: "resource-exhausted"});
  assert.equal(capacityState({...event, reservedTickets: 0}).full, false);
  assert.equal(ticketCapacityState({...freeEvent, maxTickets: 3, reservedTickets: 1}).full, true);
  assert.deepEqual(confirmedDelta(freeEvent, 1), {});
  assert.throws(() => capacityState(freeEvent), {code: "failed-precondition"});
  assert.throws(() => capacityState({...event, reservedTickets: -1}), {code: "failed-precondition"});
  assert.throws(() => confirmedDelta({...event, confirmedRegistrationCount: 0}, -1), {code: "failed-precondition"});
});

test("legacy issuance cannot bypass manual approval", () => {
  assert.throws(() => validateFreeTicketEvent({...freeEvent, registrationPolicy: {approvalMode: "manual"}}), {code: "failed-precondition"});
});


test("migration schedule review gates admission until organizer correction", () => {
  const event = {...freeEvent, launchScheduleNeedsReview: true};
  assert.throws(() => validateFreeTicketEvent(event), {code: "failed-precondition"});
  assert.throws(() => require("../public-web/accountless").validateEvent(event), {code: "failed-precondition"});
  assert.throws(() => require("../public-web/checkout").validateActionableEvent(event), {code: "failed-precondition"});
  assert.equal(require("../attendance/arrival-core").activeEvent(event), false);
});
