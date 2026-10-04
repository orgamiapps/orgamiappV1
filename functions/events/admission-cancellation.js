"use strict";
const {HttpsError} = require("firebase-functions/v2/https");
const {confirmedDelta} = require("./capacity");
const {buildRoster} = require("./roster");

// Follow only explicit record identities. Unlinked legacy tickets require review;
// never free a place while a possibly-related admission remains usable.
async function cancellationAdmissions(db, tx, registration, event) {
  const data = registration.data();
  const reverse = await tx.get(db.collection("Tickets").where("eventId", "==", event.id)
      .where("registrationId", "==", registration.id));
  const tickets = new Map(reverse.docs.map((doc) => [doc.id, doc]));
  if (data.ticketId) {
    const forward = await tx.get(db.collection("Tickets").doc(data.ticketId));
    if (!forward.exists || forward.get("eventId") !== event.id ||
        (forward.get("registrationId") && forward.get("registrationId") !== registration.id)) {
      throw new HttpsError("failed-precondition", "Admission links require organizer review.");
    }
    tickets.set(forward.id, forward);
  }
  if (event.get("ticketsEnabled") && tickets.size === 0 && (!data.status || data.status === "confirmed")) {
    throw new HttpsError("failed-precondition", "Legacy admission links require organizer review before cancellation.");
  }
  const activeTickets = [...tickets.values()].filter((doc) => !doc.get("revoked"));
  if (activeTickets.some((doc) => doc.get("isPaid") === true || Number(doc.get("price") ?? event.get("ticketPrice") ?? 0) > 0)) {
    throw new HttpsError("failed-precondition", "Paid ticket refunds require organizer support.");
  }
  const confirmed = buildRoster([{...data, id: registration.id}], [...tickets.values()].map((doc) => ({...doc.data(), id: doc.id})), [], [], event.data())
      .filter((row) => row.status === "confirmed").length;
  return {activeTickets, previouslyConfirmed: confirmed > 0, eventUpdate: {
    issuedTickets: Math.max(0, Number(event.get("issuedTickets") || 0) - activeTickets.length),
    ...confirmedDelta(event.data(), -confirmed),
  }};
}
module.exports = {cancellationAdmissions};
