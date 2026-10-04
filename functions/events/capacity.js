"use strict";
const {HttpsError} = require("firebase-functions/v2/https");
const {schedule} = require("./schedule");

function capacityState(event) {
  const capacity = Number(event.registrationPolicy?.capacity ?? event.maxTickets ?? 0);
  const confirmed = Number(event.confirmedRegistrationCount);
  if (!Number.isSafeInteger(confirmed) || confirmed < 0 || event.confirmedRegistrationCount === null || event.confirmedRegistrationCount === undefined) {
    throw new HttpsError("failed-precondition", "Registration totals are being reconciled. Please retry later.");
  }
  if (!Number.isSafeInteger(capacity) || capacity < 0) throw new HttpsError("failed-precondition", "The organizer must correct event capacity.");
  const reserved = Number(event.reservedTickets ?? 0);
  if (!Number.isSafeInteger(reserved) || reserved < 0) throw new HttpsError("failed-precondition", "Reservation totals need review.");
  return {capacity, confirmed, reserved, full: capacity > 0 && confirmed + reserved >= capacity};
}

function assertDecidable(event, now = new Date()) {
  if (event?.launchScheduleNeedsReview === true) throw new HttpsError("failed-precondition", "The organizer must confirm the event schedule before registration or check-in.");
  const end = schedule(event).end;
  if (event.cancelled || ["cancelled", "canceled", "ended", "completed", "deleted"].includes(event.status) || !end || end <= now) {
    throw new HttpsError("failed-precondition", "Registration decisions require an active event with a confirmed end time.");
  }
}
// Compatibility boundary: existing ticket-only paths retain their issued/reserved
// counters until migration supplies a confirmed counter. Never persist a guessed
// confirmed count. Once present, every path uses the reconciled admission total.
function ticketCapacityState(event) {
  if (event.confirmedRegistrationCount !== undefined && event.confirmedRegistrationCount !== null) return capacityState(event);
  const capacity = Number(event.maxTickets || 0);
  const confirmed = Number(event.issuedTickets || 0);
  const reserved = Number(event.reservedTickets ?? 0);
  if (!Number.isSafeInteger(capacity) || capacity <= 0 ||
      !Number.isSafeInteger(confirmed) || confirmed < 0 ||
      !Number.isSafeInteger(reserved) || reserved < 0) {
    throw new HttpsError("failed-precondition", "Ticket totals need review.");
  }
  return {capacity, confirmed, reserved, full: confirmed + reserved >= capacity};
}
function confirmedDelta(event, delta) {
  if (event.confirmedRegistrationCount === undefined || event.confirmedRegistrationCount === null) return {};
  const {confirmed} = capacityState(event);
  if (confirmed + delta < 0) throw new HttpsError("failed-precondition", "Registration totals need review.");
  return {confirmedRegistrationCount: confirmed + delta};
}
module.exports = {capacityState, ticketCapacityState, confirmedDelta, assertDecidable};
