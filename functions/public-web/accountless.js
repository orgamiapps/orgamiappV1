"use strict";

const crypto = require("node:crypto");
const {GoogleAuth} = require("google-auth-library");
const {defineSecret} = require("firebase-functions/params");
const {onCall, HttpsError} = require("firebase-functions/v2/https");
const {onSchedule} = require("firebase-functions/v2/scheduler");
const QRCode = require("qrcode");
const {registrationAnswers} = require("../events/question-answers");

const CONTACT_HMAC_KEY = defineSecret("GUEST_CONTACT_HMAC_KEY");
const CONTACT_KMS_KEY_NAME = defineSecret("GUEST_CONTACT_KMS_KEY_NAME");
const STRIPE_SECRET_KEY = defineSecret("STRIPE_SECRET_KEY");
const PUBLIC_ORIGIN = "https://attendus.app";
const MANAGE_TOKEN_HOURS = 72;
const RATE_WINDOW_MS = 60 * 1000;
const RATE_LIMIT = 8;

function digest(...values) {
  return crypto.createHash("sha256").update(values.join("\0")).digest("hex");
}

function secretValue(secret, label) {
  const value = secret.value().trim();
  if (!value) throw new HttpsError("failed-precondition", `${label} is not configured.`);
  return value;
}

function requireCaller(req, {full = false} = {}) {
  const uid = req.auth?.uid;
  const provider = req.auth?.token?.firebase?.sign_in_provider;
  if (!uid || (full && provider === "anonymous")) {
    throw new HttpsError("unauthenticated", full ?
      "A signed-in account is required." : "A secure guest session is required.");
  }
  if (!req.app && process.env.FUNCTIONS_EMULATOR !== "true") {
    throw new HttpsError("failed-precondition", "App Check verification is required.");
  }
  return {uid, provider, isAnonymous: provider === "anonymous"};
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

function normalizeName(value, label = "full name") {
  const result = typeof value === "string" ? value.trim().replace(/\s+/g, " ") : "";
  if (result.length < 1 || result.length > 160 ||
      !/^[\p{L}\p{M}][\p{L}\p{M}\s.'’-]*$/u.test(result)) {
    throw new HttpsError("invalid-argument", `Enter a valid ${label}.`);
  }
  return result;
}

function normalizeEmail(value) {
  const raw = typeof value === "string" ? value.trim() : "";
  const email = raw.toLowerCase();
  if (email.length > 254 || !/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email)) {
    throw new HttpsError("invalid-argument", "Enter a valid email address.");
  }
  return email;
}

function normalizeRegistrationIdentity(data) {
  if (["firstName", "lastName", "contactType", "contactValue"].some((field) =>
    Object.prototype.hasOwnProperty.call(data || {}, field))) {
    throw new HttpsError("invalid-argument", "Use fullName and email for registration.");
  }
  const fullName = normalizeName(data?.fullName);
  return {fullName, greetingName: fullName.split(" ")[0], email: normalizeEmail(data?.email)};
}

function emailHash(email) {
  return crypto.createHmac("sha256", secretValue(CONTACT_HMAC_KEY, "Guest contact protection"))
      .update(`v1\0email\0${email}`).digest("hex");
}

function maskedEmail(email) {
  const [local, domain] = email.split("@");
  return `${local.slice(0, 1)}***@${domain}`;
}

async function kmsCrypt(operation, value) {
  const keyName = secretValue(CONTACT_KMS_KEY_NAME, "Guest contact KMS key");
  if (process.env.FUNCTIONS_EMULATOR === "true" && keyName === "emulator") {
    return operation === "encrypt" ? Buffer.from(value, "utf8").toString("base64") :
      Buffer.from(value, "base64").toString("utf8");
  }
  const auth = new GoogleAuth({scopes: ["https://www.googleapis.com/auth/cloud-platform"]});
  const client = await auth.getClient();
  const token = await client.getAccessToken();
  const body = operation === "encrypt" ?
    {plaintext: Buffer.from(value, "utf8").toString("base64")} : {ciphertext: value};
  const response = await fetch(`https://cloudkms.googleapis.com/v1/${keyName}:${operation}`, {
    method: "POST",
    headers: {authorization: `Bearer ${token.token}`, "content-type": "application/json"},
    body: JSON.stringify(body),
  });
  if (!response.ok) throw new Error(`Cloud KMS ${operation} failed (${response.status})`);
  const result = await response.json();
  return operation === "encrypt" ? result.ciphertext :
    Buffer.from(result.plaintext, "base64").toString("utf8");
}

async function encryptEmail(email) {
  return kmsCrypt("encrypt", email);
}

async function decryptEmail(ciphertext) {
  return kmsCrypt("decrypt", ciphertext);
}

function eventStart(event) {
  if (event.selectedDateTime?.toDate) return event.selectedDateTime.toDate();
  return new Date(event.selectedDateTime);
}

function validateEvent(event, now = new Date()) {
  const status = String(event?.status || "").toLowerCase();
  const start = eventStart(event || {});
  if (!event || event.private === true || !["active", "scheduled"].includes(status)) {
    throw new HttpsError("not-found", "Event not found.");
  }
  if (Number.isNaN(start.getTime()) || start <= now) {
    throw new HttpsError("failed-precondition", "This event has ended.");
  }
}

function validateRegistrationWindow(event, now = new Date()) {
  const policy = event?.registrationPolicy || {};
  const parse = (value) => value?.toDate ? value.toDate() : value ? new Date(value) : null;
  const opens = parse(policy.opensAt);
  const closes = parse(policy.closesAt);
  if (opens && !Number.isNaN(opens.getTime()) && now < opens) {
    throw new HttpsError("failed-precondition", "Registration has not opened yet.");
  }
  if (closes && !Number.isNaN(closes.getTime()) && now > closes) {
    throw new HttpsError("failed-precondition", "Registration is closed.");
  }
}

function registrationKind(event) {
  if (event.ticketsEnabled !== true) return "rsvp";
  return Number(event.ticketPrice || 0) > 0 ? "paid_ticket" : "free_ticket";
}

async function requireFeature(db, field) {
  const config = (await db.collection("AppConfig").doc("publicWeb").get()).data() || {};
  if (config[field] !== true) {
    throw new HttpsError("failed-precondition", "This action is temporarily unavailable.");
  }
  return config;
}

async function enforceRateLimit(db, uid, operation) {
  const ref = db.collection("service_rate_limits")
      .doc(`accountless_${digest(uid, operation).slice(0, 32)}`);
  const now = Date.now();
  let allowed = false;
  await db.runTransaction(async (transaction) => {
    const snapshot = await transaction.get(ref);
    const data = snapshot.data() || {};
    const active = now - Number(data.windowStartedAtMs || 0) < RATE_WINDOW_MS;
    const count = active ? Number(data.count || 0) : 0;
    if (count >= RATE_LIMIT) return;
    allowed = true;
    transaction.set(ref, {service: operation, count: count + 1,
      windowStartedAtMs: active ? data.windowStartedAtMs : now,
      expiresAt: new Date(now + 2 * RATE_WINDOW_MS)}, {merge: true});
  });
  if (!allowed) throw new HttpsError("resource-exhausted", "Too many attempts. Try again shortly.");
}

function ticketCode() {
  return crypto.randomBytes(4).toString("hex").toUpperCase();
}

async function ticketQrSvg(code) {
  return code ? QRCode.toString(code, {type: "svg", margin: 1, width: 220,
    errorCorrectionLevel: "M"}) : null;
}

function manageTokenData(admin, guestId, registrationId, ownerUid) {
  const raw = crypto.randomBytes(32).toString("base64url");
  return {raw, id: digest(raw), document: {guestId, registrationId, ownerUid,
    status: "active", createdAt: admin.firestore.FieldValue.serverTimestamp(),
    expiresAt: new Date(Date.now() + MANAGE_TOKEN_HOURS * 3600000)}};
}

function queueConfirmation(transaction, db, admin, {registrationId, guestId, eventId,
  encryptedEmail, masked, greetingName, manageToken, kind, event}) {
  const ref = db.collection("OutboundMessages").doc(`confirmation_${registrationId}`);
  transaction.set(ref, {id: ref.id, templateId: "guest_registration_confirmation",
    channel: "email", status: "pending", attempts: 0,
    registrationId, guestId, eventId, encryptedEmail, maskedEmail: masked,
    payload: {firstName: greetingName, eventTitle: String(event.title || "Event").slice(0, 300),
      eventStart: event.selectedDateTime, eventLocation: String(event.location || ""), kind,
      manageUrl: `${PUBLIC_ORIGIN}/manage/${manageToken}`},
    createdAt: admin.firestore.FieldValue.serverTimestamp(), nextAttemptAt: new Date()},
  {merge: true});
}

function createStartPublicRegistrationV2(admin) {
  const db = admin.firestore();
  return onCall({region: "us-central1", enforceAppCheck: process.env.FUNCTIONS_EMULATOR !== "true",
    secrets: [CONTACT_HMAC_KEY, CONTACT_KMS_KEY_NAME, STRIPE_SECRET_KEY], maxInstances: 30}, async (req) => {
    const caller = requireCaller(req);
    const eventId = requireId(req.data?.eventId, "event ID");
    const key = requireIdempotencyKey(req.data?.idempotencyKey);
    const {fullName, greetingName, email} = normalizeRegistrationIdentity(req.data);
    const hash = emailHash(email);
    const encryptedEmail = await encryptEmail(email);
    await requireFeature(db, "accountlessRegistrationEnabled");
    await enforceRateLimit(db, caller.uid, "start_registration");
    const eventRef = db.collection("Events").doc(eventId);
    const eventSnapshot = await eventRef.get();
    if (!eventSnapshot.exists) throw new HttpsError("not-found", "Event not found.");
    const event = eventSnapshot.data();
    validateEvent(event);
    validateRegistrationWindow(event);
    const answers = await registrationAnswers(eventRef, req.data?.answers);
    const kind = registrationKind(event);
    if (kind === "paid_ticket") await requireFeature(db, "paidTicketCheckoutEnabled");

    const claimId = digest(eventId, hash);
    const claimRef = db.collection("GuestEventEmailClaims").doc(claimId);
    const existingClaim = await claimRef.get();
    if (existingClaim.exists) {
      const existing = existingClaim.data();
      const duplicateManage = manageTokenData(admin, existing.guestId,
          existing.registrationId, "email_proof_only");
      await Promise.all([
        db.collection("GuestManageTokens").doc(duplicateManage.id).set(duplicateManage.document),
        db.collection("OutboundMessages").doc(`resend_${crypto.randomUUID()}`).set({
        templateId: "guest_registration_confirmation", channel: "email",
        status: "pending", attempts: 0, registrationId: existing.registrationId,
        guestId: existing.guestId, eventId, encryptedEmail, maskedEmail: maskedEmail(email),
        payload: {firstName: greetingName, eventTitle: String(event.title || "Event"), duplicate: true,
          eventStart: event.selectedDateTime, eventLocation: String(event.location || ""),
          kind, manageUrl: `${PUBLIC_ORIGIN}/manage/${duplicateManage.raw}`},
        createdAt: admin.firestore.FieldValue.serverTimestamp(), nextAttemptAt: new Date(),
        }),
      ]);
      return {status: "confirmation_pending", kind};
    }

    const guestId = `guest_${crypto.randomUUID()}`;
    const flowId = `flow_${digest(eventId, caller.uid, key)}`;
    const registrationId = `${kind}_${digest(eventId, guestId)}`;
    const guestRef = db.collection("GuestAttendees").doc(guestId);
    const flowRef = db.collection("PublicRegistrationFlows").doc(flowId);
    const registrationRef = db.collection("RegisterAttendance").doc(registrationId);
    const manage = manageTokenData(admin, guestId, registrationId, caller.uid);
    const manageRef = db.collection("GuestManageTokens").doc(manage.id);
    const now = admin.firestore.Timestamp.now();
    const retentionMonths = kind === "paid_ticket" ? 24 : 3;
    const retentionAt = new Date(eventStart(event).getTime() + retentionMonths * 31 * 86400000);

    if (kind === "paid_ticket") {
      const maximum = Number(event.maxTickets || 0);
      const issued = Number(event.issuedTickets || 0);
      const reserved = Math.max(0, Number(event.reservedTickets || 0));
      if (!Number.isSafeInteger(maximum) || maximum <= 0 || issued + reserved >= maximum) {
        throw new HttpsError("resource-exhausted", "No tickets are available.");
      }
      const amount = Math.round(Number(event.ticketPrice) * 100);
      if (!Number.isSafeInteger(amount) || amount < 50) {
        throw new HttpsError("failed-precondition", "The event price is invalid.");
      }
      const reservationId = `reservation_${digest(eventId, guestId)}`;
      const reservationRef = db.collection("TicketReservations").doc(reservationId);
      await db.runTransaction(async (transaction) => {
        const [freshEvent, claim] = await Promise.all([
          transaction.get(eventRef), transaction.get(claimRef),
        ]);
        if (claim.exists) throw new HttpsError("already-exists", "Registration already exists.");
        const current = freshEvent.data(); validateEvent(current); validateRegistrationWindow(current);
        if (Number(current.issuedTickets || 0) + Number(current.reservedTickets || 0) >=
            Number(current.maxTickets || 0)) throw new HttpsError("resource-exhausted", "No tickets are available.");
        transaction.create(guestRef, {id: guestId, ownerUid: caller.uid, fullName, greetingName,
          emailHash: hash, emailHashVersion: 1, encryptedEmail, maskedEmail: maskedEmail(email),
          verificationStatus: "pending",
          claimedByUid: caller.isAnonymous ? null : caller.uid, createdAt: now, retentionAt});
        transaction.create(claimRef, {eventId, guestId, registrationId, emailHash: hash,
          status: "payment_pending", createdAt: now});
        transaction.create(manageRef, manage.document);
        transaction.create(flowRef, {id: flowId, eventId, guestId, registrationId,
          reservationId, ownerUid: caller.uid, kind, status: "payment_pending", createdAt: now});
        transaction.create(reservationRef, {id: reservationId, eventId, customerUid: caller.uid,
          guestId, identityType: caller.isAnonymous ? "guest" : "account",
          registrationId, emailClaimId: claimId,
          amount, currency: "usd", status: "reserved",
          attemptId: digest(flowId, key), idempotencyHash: digest(eventId, caller.uid, key),
          eventTitle: String(event.title || "Event"), eventImageUrl: String(event.imageUrl || ""),
          eventLocation: String(event.location || ""), eventDateTime: event.selectedDateTime,
          customerName: fullName, encryptedEmail,
          answers,
          manageToken: manage.raw, creatorUid: String(event.customerUid || ""), createdAt: now,
          expiresAt: new Date(Date.now() + 15 * 60000)});
        transaction.update(eventRef, {reservedTickets: admin.firestore.FieldValue.increment(1)});
      });
      const stripe = new (require("stripe"))(secretValue(STRIPE_SECRET_KEY, "Paid checkout"),
          {apiVersion: "2024-06-20"});
      let intent;
      try {
        intent = await stripe.paymentIntents.create({amount, currency: "usd",
          automatic_payment_methods: {enabled: true}, description: `Ticket for ${event.title || "Event"}`,
          receipt_email: email,
          metadata: {reservationId, attemptId: digest(flowId, key), eventId, customerUid: caller.uid,
            guestId, registrationId}}, {idempotencyKey: `attendus_guest_${digest(eventId, caller.uid, key)}`});
      } catch (error) {
        await db.runTransaction(async (transaction) => {
          const reservationSnapshot = await transaction.get(reservationRef);
          if (!reservationSnapshot.exists || reservationSnapshot.get("status") !== "reserved") return;
          transaction.update(reservationRef, {status: "released", releaseReason: "intent_error",
            releasedAt: admin.firestore.FieldValue.serverTimestamp()});
          transaction.update(eventRef, {reservedTickets: admin.firestore.FieldValue.increment(-1)});
          transaction.delete(claimRef);
          transaction.delete(guestRef);
          transaction.delete(manageRef);
          transaction.update(flowRef, {status: "failed"});
        });
        throw new HttpsError("internal", "Unable to start secure checkout.");
      }
      await Promise.all([
        reservationRef.update({status: "payment_pending", paymentIntentId: intent.id,
          clientSecret: intent.client_secret, updatedAt: now}),
        db.collection("TicketPayments").doc(intent.id).set({id: intent.id,
          paymentIntentId: intent.id, reservationId, eventId, customerUid: caller.uid, guestId,
          identityType: caller.isAnonymous ? "guest" : "account", customerName: fullName,
          encryptedEmail,
          amount: amount / 100, amountCents: amount, currency: "usd", status: "pending", createdAt: now}),
      ]);
      return {status: "payment_pending", kind, flowId, clientSecret: intent.client_secret,
        amount, currency: "usd", claimToken: manage.raw,
        manageUrl: `${PUBLIC_ORIGIN}/manage/${manage.raw}`};
    }

    let ticketId = null;
    let generatedTicketCode = null;
    await db.runTransaction(async (transaction) => {
      const [freshEvent, claim] = await Promise.all([
        transaction.get(eventRef), transaction.get(claimRef),
      ]);
      if (claim.exists) throw new HttpsError("already-exists", "Registration already exists.");
      const current = freshEvent.data(); validateEvent(current); validateRegistrationWindow(current);
      if (kind === "free_ticket" && Number(current.issuedTickets || 0) +
          Number(current.reservedTickets || 0) >= Number(current.maxTickets || 0)) {
        throw new HttpsError("resource-exhausted", "No tickets are available.");
      }
      transaction.create(guestRef, {id: guestId, ownerUid: caller.uid, fullName, greetingName,
        emailHash: hash, emailHashVersion: 1, encryptedEmail, maskedEmail: maskedEmail(email),
        verificationStatus: "pending",
        claimedByUid: caller.isAnonymous ? null : caller.uid, createdAt: now, retentionAt});
      transaction.create(claimRef, {eventId, guestId, registrationId, emailHash: hash,
        status: "confirmed", createdAt: now});
      transaction.create(manageRef, manage.document);
      transaction.create(flowRef, {id: flowId, eventId, guestId, registrationId,
        ownerUid: caller.uid, kind, status: "confirmed", createdAt: now});
      transaction.create(registrationRef, {id: registrationId, eventId, userName: fullName,
        realName: fullName, customerUid: caller.uid, guestId,
        identityType: caller.isAnonymous ? "guest" : "account",
        emailRef: guestRef.path, attendanceDateTime: now,
        answers, isAnonymous: caller.isAnonymous, registrationSource: "public_event_page_v2",
        status: "confirmed"});
      if (kind === "free_ticket") {
        ticketId = `free_${digest(eventId, guestId)}`;
        generatedTicketCode = ticketCode();
        transaction.create(db.collection("Tickets").doc(ticketId), {id: ticketId, eventId,
          eventTitle: String(event.title || "Event"), eventImageUrl: String(event.imageUrl || ""),
          eventLocation: String(event.location || ""), eventDateTime: event.selectedDateTime,
          customerUid: caller.uid, guestId,
          identityType: caller.isAnonymous ? "guest" : "account", customerName: fullName,
          ticketCode: generatedTicketCode, issuedDateTime: now, price: 0, isPaid: false, isUsed: false,
          isSkipTheLine: false, issuanceSource: "server_guest_ticket_v2", revoked: false});
        transaction.update(eventRef, {issuedTickets: admin.firestore.FieldValue.increment(1)});
      }
      queueConfirmation(transaction, db, admin, {registrationId, guestId, eventId,
        encryptedEmail, masked: maskedEmail(email), greetingName,
        manageToken: manage.raw, kind, event});
    });
    return {status: "confirmed", kind, flowId, registrationId, ticketId,
      ticketCode: generatedTicketCode, ticketQrSvg: await ticketQrSvg(generatedTicketCode),
      claimToken: manage.raw, manageUrl: `${PUBLIC_ORIGIN}/manage/${manage.raw}`,
      deliveryStatus: "pending"};
  });
}

function createGetPublicRegistrationStatusV2(admin) {
  const db = admin.firestore();
  return onCall({region: "us-central1", enforceAppCheck: process.env.FUNCTIONS_EMULATOR !== "true",
    maxInstances: 30}, async (req) => {
    const caller = requireCaller(req);
    const flowId = requireId(req.data?.flowId, "registration flow");
    const snapshot = await db.collection("PublicRegistrationFlows").doc(flowId).get();
    if (!snapshot.exists || snapshot.get("ownerUid") !== caller.uid) {
      throw new HttpsError("not-found", "Registration not found.");
    }
    const flow = snapshot.data();
    const ticket = flow.ticketId ? await db.collection("Tickets").doc(flow.ticketId).get() : null;
    const code = ticket?.exists ? ticket.get("ticketCode") : null;
    return {status: flow.status, kind: flow.kind, registrationId: flow.registrationId,
      ticketId: flow.ticketId || null, ticketCode: code, ticketQrSvg: await ticketQrSvg(code)};
  });
}

function createCancelPublicRegistrationV1(admin) {
  const db = admin.firestore();
  return onCall({region: "us-central1", enforceAppCheck: process.env.FUNCTIONS_EMULATOR !== "true",
    maxInstances: 20}, async (req) => {
    const caller = requireCaller(req);
    const registrationId = requireId(req.data?.registrationId, "registration");
    const ref = db.collection("RegisterAttendance").doc(registrationId);
    return db.runTransaction(async (transaction) => {
      const registration = await transaction.get(ref);
      if (!registration.exists || registration.get("customerUid") !== caller.uid) {
        throw new HttpsError("not-found", "Registration not found.");
      }
      const data = registration.data();
      if (data.status === "cancelled") return {status: "cancelled"};
      const eventRef = db.collection("Events").doc(data.eventId);
      const event = await transaction.get(eventRef);
      validateEvent(event.data());
      const guestRef = db.collection("GuestAttendees").doc(data.guestId);
      const guest = await transaction.get(guestRef);
      const ticketQuery = await db.collection("Tickets").where("eventId", "==", data.eventId)
          .where("customerUid", "==", caller.uid).limit(2).get();
      const activeTicket = ticketQuery.docs.find((doc) => doc.get("revoked") !== true);
      if (activeTicket?.get("isPaid") === true) {
        throw new HttpsError("failed-precondition", "Paid ticket refunds require organizer support.");
      }
      transaction.update(ref, {status: "cancelled",
        cancelledAt: admin.firestore.FieldValue.serverTimestamp()});
      if (activeTicket) {
        transaction.update(activeTicket.ref, {revoked: true, revokedReason: "guest_cancelled",
          revokedAt: admin.firestore.FieldValue.serverTimestamp()});
        transaction.update(eventRef, {issuedTickets: admin.firestore.FieldValue.increment(-1)});
      }
      if (guest.exists && guest.get("encryptedEmail")) {
        const messageRef = db.collection("OutboundMessages")
            .doc(`cancellation_${registrationId}`);
        transaction.set(messageRef, {id: messageRef.id,
          templateId: "guest_registration_cancelled",
          channel: "email",
          status: "pending", attempts: 0, registrationId, guestId: guest.id,
          eventId: event.id, encryptedEmail: guest.get("encryptedEmail"),
          maskedEmail: guest.get("maskedEmail"), payload: {
            firstName: guest.get("greetingName"), eventTitle: event.get("title"),
            eventStart: event.get("selectedDateTime"), eventLocation: event.get("location"),
          }, createdAt: admin.firestore.FieldValue.serverTimestamp(), nextAttemptAt: new Date()});
      }
      return {status: "cancelled"};
    });
  });
}

async function organizerAuthorized(db, uid, event) {
  if (event.customerUid === uid || (event.coHosts || []).includes(uid)) return true;
  if (!event.organizationId) return false;
  const member = await db.collection("Organizations").doc(event.organizationId)
      .collection("Members").doc(uid).get();
  return member.exists && member.get("status") === "approved" &&
    ["admin", "owner"].includes(String(member.get("role") || "").toLowerCase());
}

function createGetOrganizerEventRegistrationsV1(admin) {
  const db = admin.firestore();
  return onCall({region: "us-central1", enforceAppCheck: process.env.FUNCTIONS_EMULATOR !== "true",
    secrets: [CONTACT_KMS_KEY_NAME], maxInstances: 20}, async (req) => {
    const caller = requireCaller(req, {full: true});
    const eventId = requireId(req.data?.eventId, "event ID");
    const eventSnapshot = await db.collection("Events").doc(eventId).get();
    if (!eventSnapshot.exists || !await organizerAuthorized(db, caller.uid, eventSnapshot.data())) {
      throw new HttpsError("permission-denied", "Event organizer access is required.");
    }
    const registrations = await db.collection("RegisterAttendance").where("eventId", "==", eventId)
        .limit(500).get();
    const guestIds = registrations.docs.map((doc) => doc.get("guestId")).filter(Boolean);
    const guests = guestIds.length ? await db.getAll(...guestIds.map((id) =>
      db.collection("GuestAttendees").doc(id))) : [];
    const guestMap = new Map(guests.filter((doc) => doc.exists).map((doc) => [doc.id, doc.data()]));
    const rows = await Promise.all(registrations.docs.map(async (doc) => {
      const data = doc.data(); const guest = guestMap.get(data.guestId);
      const email = guest?.encryptedEmail ? await decryptEmail(guest.encryptedEmail) : null;
      return {id: doc.id, name: data.realName || data.userName || "Attendee",
        identityType: data.identityType || "account", status: data.status || "confirmed",
        email,
        deliveryStatus: guest?.deliveryStatus || "not_applicable",
        verificationStatus: guest?.verificationStatus || "not_applicable"};
    }));
    await db.collection("admin_audit_logs").add({action: "event.registration_emails.view",
      actorUid: caller.uid, targetType: "event", targetId: eventId, recordCount: rows.length,
      createdAt: admin.firestore.FieldValue.serverTimestamp()});
    return {registrations: rows};
  });
}

function csvCell(value) {
  return `"${String(value ?? "").replaceAll("\"", "\"\"")}"`;
}

function createExportOrganizerEventRegistrationsV1(admin) {
  const db = admin.firestore();
  return onCall({region: "us-central1", enforceAppCheck: process.env.FUNCTIONS_EMULATOR !== "true",
    secrets: [CONTACT_KMS_KEY_NAME], maxInstances: 10}, async (req) => {
    const caller = requireCaller(req, {full: true});
    const eventId = requireId(req.data?.eventId, "event ID");
    const event = await db.collection("Events").doc(eventId).get();
    if (!event.exists || !await organizerAuthorized(db, caller.uid, event.data())) {
      throw new HttpsError("permission-denied", "Event organizer access is required.");
    }
    const registrations = await db.collection("RegisterAttendance").where("eventId", "==", eventId)
        .limit(500).get();
    const rows = [["Name", "Email", "Status", "Identity"]];
    for (const document of registrations.docs) {
      const data = document.data();
      let email = null;
      if (data.guestId) {
        const guest = await db.collection("GuestAttendees").doc(data.guestId).get();
        if (guest.exists && guest.get("encryptedEmail")) {
          email = await decryptEmail(guest.get("encryptedEmail"));
        }
      }
      rows.push([data.realName || data.userName || "Attendee", email || "",
        data.status || "confirmed",
        data.identityType || "account"]);
    }
    const csv = rows.map((row) => row.map(csvCell).join(",")).join("\r\n");
    await db.collection("admin_audit_logs").add({action: "event.registration_emails.export",
      actorUid: caller.uid, targetType: "event", targetId: eventId,
      recordCount: rows.length - 1, createdAt: admin.firestore.FieldValue.serverTimestamp()});
    return {filename: `attendus-${eventId}-registrations.csv`,
      contentType: "text/csv", base64: Buffer.from(csv).toString("base64")};
  });
}

async function ownedRegistration(db, uid, registrationId) {
  const registration = await db.collection("RegisterAttendance").doc(registrationId).get();
  if (!registration.exists || registration.get("customerUid") !== uid || !registration.get("guestId")) {
    throw new HttpsError("not-found", "Registration not found.");
  }
  const guest = await db.collection("GuestAttendees").doc(registration.get("guestId")).get();
  if (!guest.exists || guest.get("ownerUid") !== uid) {
    throw new HttpsError("not-found", "Registration not found.");
  }
  const event = await db.collection("Events").doc(registration.get("eventId")).get();
  if (!event.exists) throw new HttpsError("not-found", "Event not found.");
  return {registration, guest, event};
}

function createResendPublicRegistrationConfirmationV1(admin) {
  const db = admin.firestore();
  return onCall({region: "us-central1", enforceAppCheck: process.env.FUNCTIONS_EMULATOR !== "true",
    secrets: [CONTACT_KMS_KEY_NAME], maxInstances: 20}, async (req) => {
    const caller = requireCaller(req);
    const registrationId = requireId(req.data?.registrationId, "registration");
    requireIdempotencyKey(req.data?.idempotencyKey);
    await enforceRateLimit(db, caller.uid, "resend_confirmation");
    const {registration, guest, event} = await ownedRegistration(db, caller.uid, registrationId);
    const manage = manageTokenData(admin, guest.id, registration.id, caller.uid);
    const messageRef = db.collection("OutboundMessages").doc(`resend_${crypto.randomUUID()}`);
    await Promise.all([
      db.collection("GuestManageTokens").doc(manage.id).set(manage.document),
      messageRef.set({templateId: "guest_registration_confirmation",
        channel: "email", status: "pending",
        attempts: 0, registrationId, guestId: guest.id, eventId: event.id,
        encryptedEmail: guest.get("encryptedEmail"), maskedEmail: guest.get("maskedEmail"),
        payload: {firstName: guest.get("greetingName"), eventTitle: event.get("title"),
          eventStart: event.get("selectedDateTime"), eventLocation: event.get("location"),
          kind: registration.get("registrationSource")?.includes("ticket") ? "ticket" : "rsvp",
          manageUrl: `${PUBLIC_ORIGIN}/manage/${manage.raw}`},
        createdAt: admin.firestore.FieldValue.serverTimestamp(), nextAttemptAt: new Date()}),
    ]);
    return {status: "pending", maskedEmail: guest.get("maskedEmail")};
  });
}

function createUpdatePublicRegistrationEmailV1(admin) {
  const db = admin.firestore();
  return onCall({region: "us-central1", enforceAppCheck: process.env.FUNCTIONS_EMULATOR !== "true",
    secrets: [CONTACT_HMAC_KEY, CONTACT_KMS_KEY_NAME], maxInstances: 20}, async (req) => {
    const caller = requireCaller(req);
    const registrationId = requireId(req.data?.registrationId, "registration");
    requireIdempotencyKey(req.data?.idempotencyKey);
    if (["contactType", "contactValue"].some((field) =>
      Object.prototype.hasOwnProperty.call(req.data || {}, field))) {
      throw new HttpsError("invalid-argument", "Use email to update this registration.");
    }
    const email = normalizeEmail(req.data?.email);
    const newHash = emailHash(email);
    const encrypted = await encryptEmail(email);
    await enforceRateLimit(db, caller.uid, "update_email");
    const {registration, guest, event} = await ownedRegistration(db, caller.uid, registrationId);
    const oldClaim = db.collection("GuestEventEmailClaims")
        .doc(digest(event.id, guest.get("emailHash")));
    const newClaim = db.collection("GuestEventEmailClaims").doc(digest(event.id, newHash));
    await db.runTransaction(async (transaction) => {
      const collision = await transaction.get(newClaim);
      if (collision.exists && collision.get("guestId") !== guest.id) {
        throw new HttpsError("already-exists", "A registration already uses that email.");
      }
      transaction.set(newClaim, {eventId: event.id, guestId: guest.id, registrationId,
        emailHash: newHash, status: registration.get("status") || "confirmed",
        updatedAt: admin.firestore.FieldValue.serverTimestamp()});
      if (oldClaim.id !== newClaim.id) transaction.delete(oldClaim);
      transaction.update(guest.ref, {emailHash: newHash,
        encryptedEmail: encrypted, maskedEmail: maskedEmail(email),
        verificationStatus: "pending", verifiedAt: null,
        updatedAt: admin.firestore.FieldValue.serverTimestamp()});
    });
    return {status: "updated", maskedEmail: maskedEmail(email)};
  });
}

function createClaimPublicRegistrationV1(admin) {
  const db = admin.firestore();
  return onCall({region: "us-central1", enforceAppCheck: process.env.FUNCTIONS_EMULATOR !== "true",
    maxInstances: 20}, async (req) => {
    const caller = requireCaller(req, {full: true});
    const registrationId = requireId(req.data?.registrationId, "registration");
    const claimToken = typeof req.data?.claimToken === "string" ? req.data.claimToken.trim() : "";
    if (!/^[A-Za-z0-9_-]{32,128}$/.test(claimToken)) {
      throw new HttpsError("invalid-argument", "A secure registration claim is required.");
    }
    const registration = await db.collection("RegisterAttendance").doc(registrationId).get();
    if (!registration.exists || !registration.get("guestId")) {
      throw new HttpsError("not-found", "Registration not found.");
    }
    const guest = await db.collection("GuestAttendees").doc(registration.get("guestId")).get();
    const tokenRef = db.collection("GuestManageTokens").doc(digest(claimToken));
    const tickets = await db.collection("Tickets").where("eventId", "==", registration.get("eventId"))
        .where("guestId", "==", guest.id).limit(2).get();
    const name = String(guest.get("fullName") || "Attendee").slice(0, 160);
    await db.runTransaction(async (transaction) => {
      const token = await transaction.get(tokenRef);
      if (!guest.exists || !token.exists || token.get("registrationId") !== registrationId ||
          token.get("guestId") !== guest.id || !["active", "exchanged"].includes(token.get("status")) ||
          token.get("expiresAt")?.toDate?.() <= new Date()) {
        throw new HttpsError("permission-denied", "This registration claim is invalid or expired.");
      }
      transaction.set(db.collection("Customers").doc(caller.uid), {uid: caller.uid, name,
        email: String(req.auth.token.email || "").toLowerCase(),
        username: `attendee_${caller.uid.slice(0, 12).toLowerCase()}`, isDiscoverable: false,
        accountSource: "guest_registration_upgrade", profileCompletionRequired: true,
        createdAt: admin.firestore.FieldValue.serverTimestamp()}, {merge: true});
      transaction.update(guest.ref, {ownerUid: caller.uid, claimedByUid: caller.uid,
        claimedAt: admin.firestore.FieldValue.serverTimestamp()});
      transaction.update(registration.ref, {customerUid: caller.uid,
        identityType: "account", isAnonymous: false,
        claimCompletedAt: admin.firestore.FieldValue.serverTimestamp()});
      for (const ticket of tickets.docs) transaction.update(ticket.ref, {
        customerUid: caller.uid, identityType: "account",
        claimCompletedAt: admin.firestore.FieldValue.serverTimestamp(),
      });
      transaction.update(tokenRef, {status: "claimed", claimedByUid: caller.uid,
        claimedAt: admin.firestore.FieldValue.serverTimestamp()});
    });
    return {status: "claimed"};
  });
}

function createFollowPublicEventOrganizerV1(admin) {
  const db = admin.firestore();
  return onCall({region: "us-central1", enforceAppCheck: process.env.FUNCTIONS_EMULATOR !== "true",
    maxInstances: 20}, async (req) => {
    const caller = requireCaller(req, {full: true});
    const eventId = requireId(req.data?.eventId, "event ID");
    const event = await db.collection("Events").doc(eventId).get();
    if (!event.exists || event.get("private") === true) {
      throw new HttpsError("not-found", "Event not found.");
    }
    const organizationId = String(event.get("organizationId") || "");
    const now = admin.firestore.FieldValue.serverTimestamp();
    if (organizationId) {
      await db.collection("Organizations").doc(organizationId).collection("Followers")
          .doc(caller.uid).set({userId: caller.uid, organizationId, createdAt: now});
      return {status: "following", type: "organization"};
    }
    const organizerUid = String(event.get("customerUid") || "");
    if (!organizerUid) throw new HttpsError("failed-precondition", "Organizer is unavailable.");
    const batch = db.batch();
    batch.set(db.collection("Customers").doc(organizerUid).collection("followers")
        .doc(caller.uid), {userId: caller.uid, organizerUid, createdAt: now});
    batch.set(db.collection("Customers").doc(caller.uid).collection("following")
        .doc(organizerUid), {userId: organizerUid, followerUid: caller.uid, createdAt: now});
    await batch.commit();
    return {status: "following", type: "organizer"};
  });
}

function createAnonymizeExpiredGuestContacts(admin) {
  const db = admin.firestore();
  return onSchedule({region: "us-central1", schedule: "every day 03:15",
    timeZone: "UTC", timeoutSeconds: 240}, async () => {
    const snapshot = await db.collection("GuestAttendees")
        .where("retentionAt", "<=", new Date()).limit(200).get();
    let anonymized = 0;
    for (const document of snapshot.docs) {
      if (document.get("claimedByUid") || document.get("anonymizedAt")) continue;
      await document.ref.update({fullName: "Former attendee", greetingName: null,
        encryptedEmail: null, maskedEmail: "Expired", emailHash: null,
        verificationStatus: "expired", anonymizedAt: admin.firestore.FieldValue.serverTimestamp()});
      anonymized += 1;
    }
    return {scanned: snapshot.size, anonymized};
  });
}

module.exports = {
  CONTACT_HMAC_KEY,
  CONTACT_KMS_KEY_NAME,
  STRIPE_SECRET_KEY,
  createCancelPublicRegistrationV1,
  createAnonymizeExpiredGuestContacts,
  createClaimPublicRegistrationV1,
  createExportOrganizerEventRegistrationsV1,
  createFollowPublicEventOrganizerV1,
  createGetOrganizerEventRegistrationsV1,
  createGetPublicRegistrationStatusV2,
  createResendPublicRegistrationConfirmationV1,
  createStartPublicRegistrationV2,
  createUpdatePublicRegistrationEmailV1,
  decryptEmail,
  digest,
  encryptEmail,
  emailHash,
  enforceRateLimit,
  maskedEmail,
  normalizeEmail,
  normalizeName,
  normalizeRegistrationIdentity,
  ticketQrSvg,
  validateEvent,
  validateRegistrationWindow,
};
