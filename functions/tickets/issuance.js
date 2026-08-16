"use strict";

const crypto = require("node:crypto");
const admin = require("../firebase-admin-compat");
const {onCall, HttpsError} = require("firebase-functions/v2/https");

function ticketDocumentId(eventId, uid) {
  return `free_${crypto.createHash("sha256")
      .update(`${eventId}\0${uid}`)
      .digest("hex")}`;
}

function validateFreeTicketEvent(event) {
  if (event.ticketsEnabled !== true) {
    throw new HttpsError("failed-precondition", "Tickets are not enabled.");
  }
  if (Number(event.ticketPrice || 0) > 0) {
    throw new HttpsError(
        "failed-precondition",
        "Paid tickets must be issued from a verified Stripe webhook.",
    );
  }
  const maximum = Number(event.maxTickets || 0);
  const issued = Number(event.issuedTickets || 0);
  const reserved = Math.max(0, Number(event.reservedTickets || 0));
  if (!Number.isSafeInteger(maximum) || maximum <= 0 ||
      !Number.isSafeInteger(issued) || issued < 0 ||
      issued + reserved >= maximum) {
    throw new HttpsError("resource-exhausted", "No tickets are available.");
  }
  if (!event.selectedDateTime) {
    throw new HttpsError("failed-precondition", "The event date is missing.");
  }
  const start = event.selectedDateTime?.toDate ?
    event.selectedDateTime.toDate() : new Date(event.selectedDateTime);
  const status = String(event.status || "").toLowerCase();
  if ((status !== "active" && status !== "scheduled") ||
      Number.isNaN(start.getTime()) || start <= new Date()) {
    throw new HttpsError("failed-precondition", "This event has ended.");
  }
}

function canReadEvent(event, uid) {
  return event.private !== true || event.customerUid === uid ||
    (Array.isArray(event.accessList) && event.accessList.includes(uid));
}

function createIssueFreeTicket() {
  return onCall({
    region: "us-central1",
    enforceAppCheck: process.env.FUNCTIONS_EMULATOR !== "true",
    maxInstances: 20,
  }, async (req) => {
    const uid = req.auth?.uid;
    const provider = req.auth?.token?.firebase?.sign_in_provider;
    if (!uid || provider === "anonymous") {
      throw new HttpsError("unauthenticated", "A signed-in account is required.");
    }
    const eventId = typeof req.data?.eventId === "string" ?
      req.data.eventId.trim() : "";
    if (!eventId || eventId.length > 500 || eventId.includes("/")) {
      throw new HttpsError("invalid-argument", "A valid eventId is required.");
    }

    const db = admin.firestore();
    const eventRef = db.collection("Events").doc(eventId);
    const ticketId = ticketDocumentId(eventId, uid);
    const ticketRef = db.collection("Tickets").doc(ticketId);
    const registrationRef = db.collection("RegisterAttendance")
        .doc(`ticket_${ticketId}`);
    const customerRef = db.collection("Customers").doc(uid);

    const result = await db.runTransaction(async (transaction) => {
      const [eventSnapshot, ticketSnapshot, customerSnapshot] =
        await Promise.all([
          transaction.get(eventRef),
          transaction.get(ticketRef),
          transaction.get(customerRef),
        ]);
      if (ticketSnapshot.exists) {
        return {ticketId, created: false};
      }
      if (!eventSnapshot.exists) {
        throw new HttpsError("not-found", "Event not found.");
      }
      const event = eventSnapshot.data();
      if (!canReadEvent(event, uid)) {
        throw new HttpsError("permission-denied", "Event access is required.");
      }
      validateFreeTicketEvent(event);

      const now = admin.firestore.Timestamp.now();
      const customer = customerSnapshot.data() || {};
      const customerName = typeof customer.name === "string" &&
        customer.name.trim() ? customer.name.trim().slice(0, 200) : "Attendee";
      const ticketCode = crypto.randomBytes(4).toString("hex").toUpperCase();
      transaction.create(ticketRef, {
        id: ticketId,
        eventId,
        eventTitle: String(event.title || "Event").slice(0, 300),
        eventImageUrl: String(event.imageUrl || "").slice(0, 2000),
        eventLocation: String(event.location || "").slice(0, 500),
        eventDateTime: event.selectedDateTime,
        customerUid: uid,
        customerName,
        ticketCode,
        issuedDateTime: now,
        price: 0,
        isPaid: false,
        isUsed: false,
        isSkipTheLine: false,
        issuanceSource: "server_free_ticket_v1",
      });
      transaction.update(eventRef, {
        issuedTickets: admin.firestore.FieldValue.increment(1),
      });
      transaction.set(registrationRef, {
        id: registrationRef.id,
        eventId,
        userName: customerName,
        realName: customerName,
        customerUid: uid,
        attendanceDateTime: now,
        answers: [],
        isAnonymous: false,
        registrationSource: "server_free_ticket_v1",
      });
      return {ticketId, created: true};
    });
    return result;
  });
}

module.exports = {
  canReadEvent,
  createIssueFreeTicket,
  ticketDocumentId,
  validateFreeTicketEvent,
};
