"use strict";

const crypto = require("node:crypto");
const {defineSecret} = require("firebase-functions/params");
const {onCall, onRequest, HttpsError} = require("firebase-functions/v2/https");
const {onSchedule} = require("firebase-functions/v2/scheduler");
const logger = require("firebase-functions/logger");

const STRIPE_SECRET_KEY = defineSecret("STRIPE_SECRET_KEY");
const STRIPE_WEBHOOK_SECRET = defineSecret("STRIPE_WEBHOOK_SECRET");
const RESERVATION_MINUTES = 15;

function digest(...values) {
  return crypto.createHash("sha256").update(values.join("\0")).digest("hex");
}

function fullUser(req) {
  const uid = req.auth?.uid;
  const provider = req.auth?.token?.firebase?.sign_in_provider;
  if (!uid || provider === "anonymous") {
    throw new HttpsError("unauthenticated", "A signed-in account is required.");
  }
  if (!req.app && process.env.FUNCTIONS_EMULATOR !== "true") {
    throw new HttpsError("failed-precondition", "App Check verification is required.");
  }
  return uid;
}

function requireId(value, label = "identifier") {
  const result = typeof value === "string" ? value.trim() : "";
  if (!/^[A-Za-z0-9_-]{1,500}$/.test(result)) {
    throw new HttpsError("invalid-argument", `A valid ${label} is required.`);
  }
  return result;
}

function requireIdempotencyKey(value) {
  const result = typeof value === "string" ? value.trim() : "";
  if (!/^[A-Za-z0-9._:-]{8,128}$/.test(result)) {
    throw new HttpsError("invalid-argument", "A valid idempotency key is required.");
  }
  return result;
}

function eventStart(data) {
  if (data.selectedDateTime?.toDate) return data.selectedDateTime.toDate();
  return new Date(data.selectedDateTime);
}

function validateActionableEvent(data, now = new Date()) {
  const status = String(data?.status || "").toLowerCase();
  if (!data || data.private === true ||
      (status !== "active" && status !== "scheduled")) {
    throw new HttpsError("not-found", "Event not found.");
  }
  const start = eventStart(data);
  if (Number.isNaN(start.getTime()) || start <= now) {
    throw new HttpsError("failed-precondition", "This event has ended.");
  }
}

async function publicWebConfig(db) {
  return (await db.collection("AppConfig").doc("publicWeb").get()).data() || {};
}

async function requireFeature(db, field) {
  const config = await publicWebConfig(db);
  if (config[field] !== true) {
    throw new HttpsError("failed-precondition", "This action is temporarily unavailable.");
  }
}

function customerName(req, profile) {
  const supplied = typeof profile?.fullName === "string" ? profile.fullName.trim() : "";
  const tokenName = typeof req.auth?.token?.name === "string" ? req.auth.token.name.trim() : "";
  return (supplied || tokenName || "Attendee").slice(0, 200);
}

async function ensureCustomer(db, req, profile) {
  const uid = req.auth.uid;
  const ref = db.collection("Customers").doc(uid);
  const snapshot = await ref.get();
  if (snapshot.exists) return snapshot.data();
  const email = String(req.auth.token.email || "").trim().toLowerCase();
  const name = customerName(req, profile);
  const data = {
    uid,
    name,
    email,
    username: `attendee_${uid.slice(0, 12).toLowerCase()}`,
    isDiscoverable: false,
    favorites: [],
    createdAt: new Date(),
    eventsCreated: 0,
    groupsCreated: 0,
    accountSource: "public_event_page",
    profileCompletionRequired: true,
  };
  await ref.create(data).catch(async (error) => {
    if (error.code !== 6 && error.code !== "already-exists") throw error;
  });
  return (await ref.get()).data() || data;
}

function ticketDocumentId(eventId, uid) {
  return `paid_${digest(eventId, uid)}`;
}

function registrationDocumentId(eventId, uid, source) {
  return `${source}_${digest(eventId, uid)}`;
}

function reservationDocumentId(eventId, uid) {
  return `reservation_${digest(eventId, uid)}`;
}

function createRegisterPublicEvent(admin) {
  return onCall({
    region: "us-central1",
    enforceAppCheck: process.env.FUNCTIONS_EMULATOR !== "true",
    maxInstances: 30,
  }, async (req) => {
    const uid = fullUser(req);
    const eventId = requireId(req.data?.eventId, "event ID");
    requireIdempotencyKey(req.data?.idempotencyKey);
    const db = admin.firestore();
    await requireFeature(db, "inlineRegistrationEnabled");
    const customer = await ensureCustomer(db, req, req.data?.profile);
    const eventRef = db.collection("Events").doc(eventId);
    const registrationId = registrationDocumentId(eventId, uid, "public");
    const registrationRef = db.collection("RegisterAttendance").doc(registrationId);
    return db.runTransaction(async (transaction) => {
      const [eventSnapshot, registrationSnapshot] = await Promise.all([
        transaction.get(eventRef), transaction.get(registrationRef),
      ]);
      if (registrationSnapshot.exists) {
        return {status: "already_registered", registrationId};
      }
      if (!eventSnapshot.exists) throw new HttpsError("not-found", "Event not found.");
      const event = eventSnapshot.data();
      validateActionableEvent(event);
      if (event.ticketsEnabled === true) {
        throw new HttpsError("failed-precondition", "A ticket is required for this event.");
      }
      transaction.create(registrationRef, {
        id: registrationId,
        eventId,
        userName: String(customer.name || "Attendee").slice(0, 200),
        realName: String(customer.name || "Attendee").slice(0, 200),
        customerUid: uid,
        attendanceDateTime: admin.firestore.FieldValue.serverTimestamp(),
        answers: [],
        isAnonymous: false,
        registrationSource: "public_event_page_v1",
      });
      return {status: "registered", registrationId};
    });
  });
}

function stripeClient() {
  const key = STRIPE_SECRET_KEY.value().trim();
  if (!key) throw new HttpsError("failed-precondition", "Paid checkout is not configured.");
  return new (require("stripe"))(key, {apiVersion: "2024-06-20"});
}

async function releaseReservation(admin, reservationId, reason, expectedAttemptId = null) {
  const db = admin.firestore();
  const ref = db.collection("TicketReservations").doc(reservationId);
  await db.runTransaction(async (transaction) => {
    const snapshot = await transaction.get(ref);
    if (!snapshot.exists) return;
    const data = snapshot.data();
    if (!["reserved", "payment_pending"].includes(data.status)) return;
    if (expectedAttemptId && data.attemptId !== expectedAttemptId) return;
    const eventRef = db.collection("Events").doc(data.eventId);
    transaction.update(ref, {
      status: "released",
      releaseReason: reason,
      releasedAt: admin.firestore.FieldValue.serverTimestamp(),
    });
    transaction.update(eventRef, {
      reservedTickets: admin.firestore.FieldValue.increment(-1),
    });
  });
}

function createPublicTicketCheckout(admin) {
  return onCall({
    region: "us-central1",
    enforceAppCheck: process.env.FUNCTIONS_EMULATOR !== "true",
    secrets: [STRIPE_SECRET_KEY],
    maxInstances: 30,
  }, async (req) => {
    const uid = fullUser(req);
    const eventId = requireId(req.data?.eventId, "event ID");
    const key = requireIdempotencyKey(req.data?.idempotencyKey);
    const db = admin.firestore();
    await requireFeature(db, "paidTicketCheckoutEnabled");
    const customer = await ensureCustomer(db, req, req.data?.profile);
    const eventRef = db.collection("Events").doc(eventId);
    const reservationId = reservationDocumentId(eventId, uid);
    const reservationRef = db.collection("TicketReservations").doc(reservationId);
    const ticketRef = db.collection("Tickets").doc(ticketDocumentId(eventId, uid));
    const now = new Date();
    const expiresAt = new Date(now.getTime() + RESERVATION_MINUTES * 60000);
    const idempotencyHash = digest(eventId, uid, key);
    const attemptId = digest(idempotencyHash, now.toISOString());
    const reservation = await db.runTransaction(async (transaction) => {
      const [eventSnapshot, existingReservation, ticketSnapshot] = await Promise.all([
        transaction.get(eventRef),
        transaction.get(reservationRef),
        transaction.get(ticketRef),
      ]);
      if (ticketSnapshot.exists && ticketSnapshot.data().revoked !== true) {
        throw new HttpsError("already-exists", "You already have a ticket.");
      }
      if (existingReservation.exists) {
        const existing = existingReservation.data();
        if (existing.clientSecret && existing.paymentIntentId &&
            ["reserved", "payment_pending"].includes(existing.status)) {
          return existing;
        }
        if (["reserved", "payment_pending"].includes(existing.status) &&
            existing.idempotencyHash !== idempotencyHash) {
          throw new HttpsError("aborted", "A checkout is already being prepared.");
        }
        if (existing.status === "completed") {
          throw new HttpsError("already-exists", "You already have a ticket.");
        }
      }
      if (!eventSnapshot.exists) throw new HttpsError("not-found", "Event not found.");
      const event = eventSnapshot.data();
      validateActionableEvent(event, now);
      if (event.ticketsEnabled !== true || Number(event.ticketPrice || 0) <= 0) {
        throw new HttpsError("failed-precondition", "This is not a paid event.");
      }
      const maximum = Number(event.maxTickets || 0);
      const issued = Number(event.issuedTickets || 0);
      const reserved = Math.max(0, Number(event.reservedTickets || 0));
      if (!Number.isSafeInteger(maximum) || maximum <= 0 || issued + reserved >= maximum) {
        throw new HttpsError("resource-exhausted", "No tickets are available.");
      }
      const amount = Math.round(Number(event.ticketPrice) * 100);
      if (!Number.isSafeInteger(amount) || amount < 50 || amount > 100000000) {
        throw new HttpsError("failed-precondition", "The event price is invalid.");
      }
      const created = {
        id: reservationId,
        eventId,
        customerUid: uid,
        amount,
        currency: "usd",
        status: "reserved",
        attemptId,
        idempotencyHash,
        eventTitle: String(event.title || "Event").slice(0, 300),
        eventImageUrl: String(event.imageUrl || "").slice(0, 2000),
        eventLocation: String(event.location || "").slice(0, 500),
        eventDateTime: event.selectedDateTime,
        customerName: String(customer.name || "Attendee").slice(0, 200),
        customerEmail: String(customer.email || req.auth.token.email || "").slice(0, 320),
        creatorUid: String(event.customerUid || ""),
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
        expiresAt,
      };
      transaction.set(reservationRef, created);
      transaction.update(eventRef, {
        reservedTickets: admin.firestore.FieldValue.increment(1),
      });
      return created;
    });
    if (reservation.clientSecret && reservation.paymentIntentId) {
      return {
        checkoutId: reservationId,
        clientSecret: reservation.clientSecret,
        amount: reservation.amount,
        currency: reservation.currency,
      };
    }
    try {
      const intent = await stripeClient().paymentIntents.create({
        amount: reservation.amount,
        currency: "usd",
        automatic_payment_methods: {enabled: true},
        receipt_email: reservation.customerEmail || undefined,
        description: `Ticket for ${reservation.eventTitle}`,
        metadata: {reservationId, attemptId: reservation.attemptId,
          eventId, customerUid: uid},
      }, {idempotencyKey: `attendus_${idempotencyHash}`});
      await Promise.all([
        reservationRef.update({
          status: "payment_pending",
          paymentIntentId: intent.id,
          attemptId: reservation.attemptId,
          clientSecret: intent.client_secret,
          updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        }),
        db.collection("TicketPayments").doc(intent.id).set({
          id: intent.id,
          paymentIntentId: intent.id,
          reservationId,
          eventId,
          eventTitle: reservation.eventTitle,
          customerUid: uid,
          customerName: reservation.customerName,
          customerEmail: reservation.customerEmail,
          creatorUid: reservation.creatorUid,
          amount: reservation.amount / 100,
          amountCents: reservation.amount,
          currency: "usd",
          status: "pending",
          createdAt: admin.firestore.FieldValue.serverTimestamp(),
        }),
      ]);
      return {
        checkoutId: reservationId,
        clientSecret: intent.client_secret,
        amount: reservation.amount,
        currency: "usd",
      };
    } catch (error) {
      await releaseReservation(admin, reservationId, "payment_intent_error",
          reservation.attemptId);
      logger.error("Unable to create paid event checkout", {eventId, uid, error});
      if (error instanceof HttpsError) throw error;
      throw new HttpsError("internal", "Unable to start checkout.");
    }
  });
}

function createGetPublicTicketCheckoutStatus(admin) {
  return onCall({
    region: "us-central1",
    enforceAppCheck: process.env.FUNCTIONS_EMULATOR !== "true",
    maxInstances: 30,
  }, async (req) => {
    const uid = fullUser(req);
    const eventId = requireId(req.data?.eventId, "event ID");
    const checkoutId = requireId(req.data?.checkoutId, "checkout ID");
    const snapshot = await admin.firestore().collection("TicketReservations")
        .doc(checkoutId).get();
    if (!snapshot.exists) throw new HttpsError("not-found", "Checkout not found.");
    const data = snapshot.data();
    if (data.customerUid !== uid || data.eventId !== eventId) {
      throw new HttpsError("permission-denied", "Checkout access is denied.");
    }
    return {
      status: data.status,
      ticketId: data.ticketId || null,
      checkoutId,
    };
  });
}

function paidTicketData(admin, reservation, paymentIntentId, ticketId) {
  return {
    id: ticketId,
    eventId: reservation.eventId,
    eventTitle: reservation.eventTitle,
    eventImageUrl: reservation.eventImageUrl,
    eventLocation: reservation.eventLocation,
    eventDateTime: reservation.eventDateTime,
    customerUid: reservation.customerUid,
    guestId: reservation.guestId || null,
    identityType: reservation.identityType || "account",
    customerName: reservation.customerName,
    ticketCode: crypto.randomBytes(4).toString("hex").toUpperCase(),
    issuedDateTime: admin.firestore.FieldValue.serverTimestamp(),
    price: reservation.amount / 100,
    isPaid: true,
    isUsed: false,
    isSkipTheLine: false,
    paymentIntentId,
    issuanceSource: "stripe_webhook_v1",
    revoked: false,
  };
}

async function fulfillPayment(admin, stripeEvent) {
  const intent = stripeEvent.data.object;
  const reservationId = String(intent.metadata?.reservationId || "");
  const attemptId = String(intent.metadata?.attemptId || "");
  if (!reservationId) return;
  const db = admin.firestore();
  const processedRef = db.collection("stripe_webhook_events").doc(stripeEvent.id);
  const reservationRef = db.collection("TicketReservations").doc(reservationId);
  await db.runTransaction(async (transaction) => {
    const [processed, reservationSnapshot] = await Promise.all([
      transaction.get(processedRef), transaction.get(reservationRef),
    ]);
    if (processed.exists) return;
    if (!reservationSnapshot.exists) throw new Error("Reservation not found");
    const reservation = reservationSnapshot.data();
    if (!attemptId || reservation.attemptId !== attemptId) {
      throw new Error("Payment did not match the active checkout attempt");
    }
    if (reservation.status === "completed") {
      transaction.create(processedRef, {type: stripeEvent.type, processedAt: new Date()});
      return;
    }
    if (!["reserved", "payment_pending"].includes(reservation.status)) {
      throw new Error(`Reservation is ${reservation.status}`);
    }
    if (Number(intent.amount_received) !== Number(reservation.amount) ||
        intent.currency !== reservation.currency) {
      throw new Error("Payment amount or currency did not match reservation");
    }
    const ticketId = ticketDocumentId(
        reservation.eventId, reservation.guestId || reservation.customerUid,
    );
    const ticketRef = db.collection("Tickets").doc(ticketId);
    const eventRef = db.collection("Events").doc(reservation.eventId);
    const registrationId = reservation.registrationId || registrationDocumentId(
        reservation.eventId, reservation.customerUid, "ticket",
    );
    transaction.set(ticketRef,
        paidTicketData(admin, reservation, intent.id, ticketId), {merge: false});
    transaction.set(db.collection("RegisterAttendance").doc(registrationId), {
      id: registrationId,
      eventId: reservation.eventId,
      userName: reservation.customerName,
      realName: reservation.customerName,
      customerUid: reservation.customerUid,
      guestId: reservation.guestId || null,
      identityType: reservation.identityType || "account",
      emailRef: reservation.guestId ? `GuestAttendees/${reservation.guestId}` : null,
      attendanceDateTime: admin.firestore.FieldValue.serverTimestamp(),
      answers: [],
      isAnonymous: false,
      registrationSource: "stripe_webhook_v1",
      status: "confirmed",
    }, {merge: true});
    transaction.update(eventRef, {
      reservedTickets: admin.firestore.FieldValue.increment(-1),
      issuedTickets: admin.firestore.FieldValue.increment(1),
    });
    transaction.update(reservationRef, {
      status: "completed",
      ticketId,
      completedAt: admin.firestore.FieldValue.serverTimestamp(),
    });
    transaction.set(db.collection("TicketPayments").doc(intent.id), {
      status: "completed",
      ticketId,
      completedAt: admin.firestore.FieldValue.serverTimestamp(),
    }, {merge: true});
    if (reservation.guestId) {
      const manageUrl = `https://attendus.app/manage/${reservation.manageToken}`;
      transaction.set(db.collection("OutboundMessages")
          .doc(`confirmation_${registrationId}`), {
        templateId: "guest_registration_confirmation",
        channel: "email",
        status: "pending",
        attempts: 0,
        registrationId,
        guestId: reservation.guestId,
        eventId: reservation.eventId,
        encryptedEmail: reservation.encryptedEmail,
        payload: {
          firstName: String(reservation.customerName || "Attendee").split(" ")[0],
          eventTitle: reservation.eventTitle,
          eventStart: reservation.eventDateTime,
          eventLocation: reservation.eventLocation,
          kind: "paid_ticket",
          manageUrl,
        },
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
        nextAttemptAt: new Date(),
      });
      transaction.set(db.collection("PublicRegistrationFlows")
          .doc(`flow_${reservation.idempotencyHash}`), {
        status: "confirmed", ticketId, registrationId,
        completedAt: admin.firestore.FieldValue.serverTimestamp(),
      }, {merge: true});
      transaction.set(db.collection("GuestEventEmailClaims")
          .doc(reservation.emailClaimId || `unlinked_${reservation.guestId}`), {
        status: "confirmed", ticketId,
        completedAt: admin.firestore.FieldValue.serverTimestamp(),
      }, {merge: true});
    }
    transaction.create(processedRef, {
      type: stripeEvent.type,
      processedAt: admin.firestore.FieldValue.serverTimestamp(),
    });
  });
}

async function releaseFromStripeEvent(admin, stripeEvent) {
  const intent = stripeEvent.data.object;
  const reservationId = String(intent.metadata?.reservationId || "");
  const attemptId = String(intent.metadata?.attemptId || "");
  if (!reservationId) return;
  const processedRef = admin.firestore().collection("stripe_webhook_events")
      .doc(stripeEvent.id);
  if ((await processedRef.get()).exists) return;
  await releaseReservation(admin, reservationId, stripeEvent.type, attemptId);
  await processedRef.create({type: stripeEvent.type, processedAt: new Date()})
      .catch(() => undefined);
  await admin.firestore().collection("TicketPayments").doc(intent.id).set({
    status: stripeEvent.type === "payment_intent.canceled" ? "cancelled" : "failed",
    updatedAt: admin.firestore.FieldValue.serverTimestamp(),
  }, {merge: true});
}

async function handleRefund(admin, stripeEvent) {
  const charge = stripeEvent.data.object;
  const paymentIntentId = String(charge.payment_intent || "");
  if (!paymentIntentId) return;
  const db = admin.firestore();
  const processedRef = db.collection("stripe_webhook_events").doc(stripeEvent.id);
  const paymentRef = db.collection("TicketPayments").doc(paymentIntentId);
  await db.runTransaction(async (transaction) => {
    const [processed, paymentSnapshot] = await Promise.all([
      transaction.get(processedRef), transaction.get(paymentRef),
    ]);
    if (processed.exists) return;
    if (!paymentSnapshot.exists) throw new Error("Payment record not found");
    const payment = paymentSnapshot.data();
    const fullyRefunded = Number(charge.amount_refunded || 0) >=
      Number(charge.amount || payment.amountCents || 0);
    if (!fullyRefunded) {
      transaction.update(paymentRef, {
        status: "partial_refund_review",
        amountRefundedCents: Number(charge.amount_refunded || 0),
      });
    } else if (payment.status !== "refunded") {
      transaction.update(paymentRef, {
        status: "refunded",
        refundedAt: admin.firestore.FieldValue.serverTimestamp(),
      });
      if (payment.ticketId) {
        transaction.set(db.collection("Tickets").doc(payment.ticketId), {
          revoked: true,
          revokedReason: "refunded",
          revokedAt: admin.firestore.FieldValue.serverTimestamp(),
        }, {merge: true});
        transaction.update(db.collection("Events").doc(payment.eventId), {
          issuedTickets: admin.firestore.FieldValue.increment(-1),
        });
      }
    }
    transaction.create(processedRef, {
      type: stripeEvent.type,
      processedAt: admin.firestore.FieldValue.serverTimestamp(),
    });
  });
}

async function handleDispute(admin, stripeEvent) {
  const dispute = stripeEvent.data.object;
  const chargeId = typeof dispute.charge === "string" ? dispute.charge : dispute.charge?.id;
  await admin.firestore().collection("payment_review_queue").doc(stripeEvent.id).set({
    type: "stripe_dispute",
    stripeEventId: stripeEvent.id,
    chargeId: chargeId || null,
    status: "open",
    createdAt: admin.firestore.FieldValue.serverTimestamp(),
  });
  await admin.firestore().collection("stripe_webhook_events").doc(stripeEvent.id)
      .set({type: stripeEvent.type, processedAt: new Date()});
}

function createStripeWebhook(admin) {
  return onRequest({
    region: "us-central1",
    secrets: [STRIPE_SECRET_KEY, STRIPE_WEBHOOK_SECRET],
    maxInstances: 20,
    timeoutSeconds: 30,
  }, async (req, res) => {
    res.set("Cache-Control", "no-store");
    if (req.method !== "POST") return res.status(405).send("Method not allowed");
    let stripeEvent;
    try {
      stripeEvent = stripeClient().webhooks.constructEvent(
          req.rawBody, req.get("stripe-signature"), STRIPE_WEBHOOK_SECRET.value(),
      );
    } catch (error) {
      logger.warn("Rejected Stripe webhook signature", {message: error.message});
      return res.status(400).send("Invalid signature");
    }
    try {
      if (stripeEvent.type === "payment_intent.succeeded") {
        await fulfillPayment(admin, stripeEvent);
      } else if (["payment_intent.payment_failed", "payment_intent.canceled"]
          .includes(stripeEvent.type)) {
        await releaseFromStripeEvent(admin, stripeEvent);
      } else if (stripeEvent.type === "charge.refunded") {
        await handleRefund(admin, stripeEvent);
      } else if (stripeEvent.type === "charge.dispute.created") {
        await handleDispute(admin, stripeEvent);
      }
      return res.status(200).json({received: true});
    } catch (error) {
      logger.error("Stripe webhook processing failed", {
        stripeEventId: stripeEvent.id,
        type: stripeEvent.type,
        error,
      });
      return res.status(500).json({received: false});
    }
  });
}

function createReleaseExpiredTicketReservations(admin) {
  return onSchedule({
    region: "us-central1",
    schedule: "every 5 minutes",
    timeZone: "UTC",
    secrets: [STRIPE_SECRET_KEY],
    timeoutSeconds: 240,
    memory: "256MiB",
  }, async () => {
    const snapshot = await admin.firestore().collection("TicketReservations")
        .where("status", "in", ["reserved", "payment_pending"])
        .where("expiresAt", "<=", new Date()).limit(200).get();
    const stripe = stripeClient();
    for (const entry of snapshot.docs) {
      const data = entry.data();
      if (data.paymentIntentId) {
        await stripe.paymentIntents.cancel(data.paymentIntentId)
            .catch((error) => logger.warn("Unable to cancel expired intent", {
              paymentIntentId: data.paymentIntentId,
              message: error.message,
            }));
      }
      await releaseReservation(admin, entry.id, "expired", data.attemptId);
    }
    logger.info("Expired ticket reservations released", {count: snapshot.size});
  });
}

module.exports = {
  createGetPublicTicketCheckoutStatus,
  createPublicTicketCheckout,
  createRegisterPublicEvent,
  createReleaseExpiredTicketReservations,
  createStripeWebhook,
  digest,
  fullUser,
  registrationDocumentId,
  releaseReservation,
  reservationDocumentId,
  ticketDocumentId,
  validateActionableEvent,
};
