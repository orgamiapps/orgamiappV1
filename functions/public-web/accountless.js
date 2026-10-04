"use strict";
const {requireActiveAccounts, readGuestRegistration} = require("../account/mutation-guard");

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
const {publicOrigin} = require("./origin");
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
  if (event?.launchScheduleNeedsReview === true) throw new HttpsError("failed-precondition", "The organizer must confirm the event schedule before registration or check-in.");
  const status = String(event?.status || "").toLowerCase();
  const start = eventStart(event || {});
  if (!event || event.private === true || !["active", "scheduled"].includes(status)) {
    throw new HttpsError("not-found", "Event not found.");
  }
  const end = require("../events/schedule").schedule(event || {}).end || start;
  if (Number.isNaN(start.getTime()) || end <= now) {
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
      eventStart: event.selectedDateTime, eventLocation: String(event.location || ""),
      eventDurationMinutes: event.eventDurationMinutes || null, eventDuration: event.eventDuration || null,
      eventTimeZone: event.eventTimeZone || "UTC", eventRevision: event.eventRevision || 0, kind,
      manageUrl: `${publicOrigin()}/manage/${manageToken}`},
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
      await db.runTransaction(async (transaction) => {
        const claim = await transaction.get(claimRef);
        if (!claim.exists || claim.get("guestId") !== existing.guestId || claim.get("registrationId") !== existing.registrationId) {
          throw new HttpsError("not-found", "Registration not found.");
        }
        await readGuestRegistration(db, transaction, {registrationId: existing.registrationId, guestId: existing.guestId, eventId, actorUid: caller.uid});
        transaction.set(db.collection("GuestManageTokens").doc(duplicateManage.id), duplicateManage.document);
        transaction.set(db.collection("OutboundMessages").doc(`resend_${crypto.randomUUID()}`), {
        templateId: "guest_registration_confirmation", channel: "email",
        status: "pending", attempts: 0, registrationId: existing.registrationId,
        guestId: existing.guestId, eventId, encryptedEmail, maskedEmail: maskedEmail(email),
        payload: {firstName: greetingName, eventTitle: String(event.title || "Event"), duplicate: true,
          eventStart: event.selectedDateTime, eventLocation: String(event.location || ""),
      eventDurationMinutes: event.eventDurationMinutes || null, eventDuration: event.eventDuration || null,
      eventTimeZone: event.eventTimeZone || "UTC", eventRevision: event.eventRevision || 0,
          kind, manageUrl: `${publicOrigin()}/manage/${duplicateManage.raw}`},
        createdAt: admin.firestore.FieldValue.serverTimestamp(), nextAttemptAt: new Date(),
        });
      });
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
      if (require("../events/capacity").ticketCapacityState(event).full) {
        throw new HttpsError("resource-exhausted", "No tickets are available.");
      }
      const amount = Math.round(Number(event.ticketPrice) * 100);
      if (!Number.isSafeInteger(amount) || amount < 50) {
        throw new HttpsError("failed-precondition", "The event price is invalid.");
      }
      const reservationId = `reservation_${digest(eventId, guestId)}`;
      const reservationRef = db.collection("TicketReservations").doc(reservationId);
      await db.runTransaction(async (transaction) => {
        const [freshEvent, claim, deleting] = await Promise.all([
          transaction.get(eventRef), transaction.get(claimRef),
          transaction.get(db.collection("account_deletion_jobs").doc(caller.uid)),
        ]);
        if (deleting.exists) throw new HttpsError("failed-precondition", "Account deletion is in progress.");
        if (claim.exists) throw new HttpsError("already-exists", "Registration already exists.");
        const current = freshEvent.data(); validateEvent(current); validateRegistrationWindow(current);
        if (require("../events/capacity").ticketCapacityState(current).full) throw new HttpsError("resource-exhausted", "No tickets are available.");
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
      await db.runTransaction(async (transaction) => {
        const [reservation, guest, flow] = await Promise.all([transaction.get(reservationRef), transaction.get(guestRef), transaction.get(flowRef)]);
        await requireActiveAccounts(db, transaction, caller.uid, guest.get("ownerUid"), guest.get("claimedByUid"), reservation.get("customerUid"));
        if (!reservation.exists || !guest.exists || !flow.exists || reservation.get("status") !== "reserved" ||
            reservation.get("guestId") !== guest.id || reservation.get("customerUid") !== caller.uid || flow.get("ownerUid") !== caller.uid) {
          throw new HttpsError("failed-precondition", "Checkout is no longer available.");
        }
        transaction.update(reservationRef, {status: "payment_pending", paymentIntentId: intent.id,
          clientSecret: intent.client_secret, updatedAt: now});
        transaction.set(db.collection("TicketPayments").doc(intent.id), {id: intent.id,
          paymentIntentId: intent.id, reservationId, eventId, customerUid: caller.uid, guestId,
          identityType: caller.isAnonymous ? "guest" : "account", customerName: fullName,
          encryptedEmail,
          amount: amount / 100, amountCents: amount, currency: "usd", status: "pending", createdAt: now});
      });
      return {status: "payment_pending", kind, flowId, clientSecret: intent.client_secret,
        amount, currency: "usd", claimToken: manage.raw,
        manageUrl: `${publicOrigin()}/manage/${manage.raw}`};
    }

    let ticketId = null;
    let generatedTicketCode = null;
    await db.runTransaction(async (transaction) => {
      const [freshEvent, claim, deleting] = await Promise.all([
        transaction.get(eventRef), transaction.get(claimRef),
        transaction.get(db.collection("account_deletion_jobs").doc(caller.uid)),
      ]);
      if (deleting.exists) throw new HttpsError("failed-precondition", "Account deletion is in progress.");
      if (claim.exists) throw new HttpsError("already-exists", "Registration already exists.");
      const current = freshEvent.data(); validateEvent(current); validateRegistrationWindow(current);
      if (current.registrationPolicy?.approvalMode === "manual") throw new HttpsError("failed-precondition", "Update the app to request organizer approval.");
      const totals = kind === "free_ticket" ? require("../events/capacity").ticketCapacityState(current) :
        (current.confirmedRegistrationCount !== null && current.confirmedRegistrationCount !== undefined) ? require("../events/capacity").capacityState(current) : null;
      if (totals?.full) {
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
      const countUpdate = require("../events/capacity").confirmedDelta(current, 1);
      if (Object.keys(countUpdate).length) transaction.update(eventRef, countUpdate);
      transaction.create(registrationRef, {id: registrationId, eventId, ticketId: kind === "free_ticket" ? `free_${digest(eventId, guestId)}` : null, userName: fullName,
        realName: fullName, customerUid: caller.uid, guestId,
        identityType: caller.isAnonymous ? "guest" : "account",
        emailRef: guestRef.path, attendanceDateTime: now,
        answers, isAnonymous: caller.isAnonymous, registrationSource: "public_event_page_v2",
        status: "confirmed"});
      if (kind === "free_ticket") {
        ticketId = `free_${digest(eventId, guestId)}`;
        generatedTicketCode = ticketCode();
        transaction.create(db.collection("Tickets").doc(ticketId), {id: ticketId, eventId, registrationId,
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
      claimToken: manage.raw, manageUrl: `${publicOrigin()}/manage/${manage.raw}`,
      deliveryStatus: "pending"};
  });
}

function createGetPublicRegistrationStatusV2(admin) {
  const db = admin.firestore();
  return onCall({region: "us-central1", enforceAppCheck: process.env.FUNCTIONS_EMULATOR !== "true",
    maxInstances: 30}, async (req) => {
    const caller = requireCaller(req);
    if (Boolean(req.data?.flowId) === Boolean(req.data?.eventId)) {
      throw new HttpsError("invalid-argument", "Supply either a registration flow or event.");
    }
    let flow = null;
    let registration = null;
    if (req.data.flowId) {
      const snapshot = await db.collection("PublicRegistrationFlows")
          .doc(requireId(req.data.flowId, "registration flow")).get();
      if (!snapshot.exists || snapshot.get("ownerUid") !== caller.uid) {
        throw new HttpsError("not-found", "Registration not found.");
      }
      flow = snapshot.data();
      if (flow.status === "confirmation_pending") return {status: "confirmation_pending", kind: flow.kind};
      if (flow.registrationId) registration = await db.collection("RegisterAttendance").doc(flow.registrationId).get();
    } else {
      const eventId = requireId(req.data.eventId, "event ID");
      const event = await db.collection("Events").doc(eventId).get();
      const sources = await Promise.all(["RegisterAttendance", "Tickets"].map(async (collection) => {
        const snapshots = await Promise.all(["customerUid", "userId"].map((field) =>
          db.collection(collection).where("eventId", "==", eventId).where(field, "==", caller.uid).get()));
        return [...new Map(snapshots.flatMap((snapshot) => snapshot.docs).map((doc) => [doc.id, {...doc.data(), id: doc.id}])).values()]
            .filter((row) => (row.customerUid || row.userId) === caller.uid);
      }));
      const available = event.exists && require("../attendance/arrival-core").activeEvent(event.data());
      const admissions = require("../events/roster").buildRoster(...sources, [], [], event.data() || {})
          .map((row) => ({id: row.id, registrationId: row.registrationId, ticketId: row.ticketId,
            status: available ? row.status : "cancelled",
            ticketCode: available && row.status === "confirmed" ? row.ticketCode : null})).sort((a, b) => a.id.localeCompare(b.id));
      if (!admissions.length) return {status: "none", admissions: []};
      const requested = req.data.registrationId || req.data.ticketId;
      const selected = requested ? admissions.find((row) => req.data.registrationId ? row.registrationId === req.data.registrationId : row.ticketId === req.data.ticketId) :
        admissions.length === 1 ? admissions[0] : null;
      if (requested && !selected) throw new HttpsError("not-found", "Admission not found.");
      return {status: selected?.status || (admissions.some((row) => row.status === "confirmed") ? "confirmed" : admissions[0].status),
        eventStatus: event.get("status") || "unavailable", kind: selected?.ticketId ? "ticket" : "rsvp",
        registrationId: selected?.registrationId || null, ticketId: selected?.ticketId || null,
        ticketCode: selected?.ticketCode || null, ticketQrSvg: await ticketQrSvg(selected?.ticketCode), admissions};
    }
    if (!registration?.exists || (registration.get("customerUid") || registration.get("userId")) !== caller.uid) {
      return {status: "none"};
    }
    const record = registration.data();
    let ticket = null;
    if (record.ticketId || flow?.ticketId) {
      ticket = await db.collection("Tickets").doc(record.ticketId || flow.ticketId).get();
    } else {
      const tickets = await db.collection("Tickets").where("eventId", "==", record.eventId)
          .where("registrationId", "==", registration.id).get();
      if (tickets.size === 1) ticket = tickets.docs[0];
    }
    const currentEvent = await db.collection("Events").doc(record.eventId).get();
    const eventStatus = currentEvent.get("status") || "unavailable";
    const eventAvailable = currentEvent.exists && require("../attendance/arrival-core").activeEvent(currentEvent.data());
    const active = require("../attendance/arrival-core").confirmedRegistration(record) && eventAvailable;
    const ownedTicket = active && ticket?.exists && ticket.get("eventId") === record.eventId && (ticket.get("customerUid") || ticket.get("userId")) === caller.uid &&
      require("../attendance/arrival-core").validTicket(ticket.data(), currentEvent.data() || {});
    const code = ownedTicket ? ticket.get("ticketCode") : null;
    return {status: eventAvailable ? record.status || "confirmed" : "cancelled", eventStatus, kind: flow?.kind || (ownedTicket ? "free_ticket" : "rsvp"),
      registrationId: registration.id, ticketId: ownedTicket ? ticket.id : null,
      ticketCode: code, ticketQrSvg: await ticketQrSvg(code)};
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
      const [registration, deleting] = await Promise.all([transaction.get(ref), transaction.get(db.collection("account_deletion_jobs").doc(caller.uid))]);
      if (deleting.exists) throw new HttpsError("failed-precondition", "Account deletion is in progress.");
      if (!registration.exists || registration.get("customerUid") !== caller.uid) {
        throw new HttpsError("not-found", "Registration not found.");
      }
      const data = registration.data();
      if (data.status === "cancelled") return {status: "cancelled"};
      const eventRef = db.collection("Events").doc(data.eventId);
      const event = await transaction.get(eventRef);
      validateEvent(event.data());
      const guest = data.guestId ? await transaction.get(db.collection("GuestAttendees").doc(data.guestId)) : null;
      const {activeTickets, eventUpdate, previouslyConfirmed} = await require("../events/admission-cancellation").cancellationAdmissions(db, transaction, registration, event);
      transaction.update(ref, {status: "cancelled",
        cancelledAt: admin.firestore.FieldValue.serverTimestamp()});
      for (const activeTicket of activeTickets) {
        transaction.update(activeTicket.ref, {revoked: true, revokedReason: "guest_cancelled",
          revokedAt: admin.firestore.FieldValue.serverTimestamp()});
      }
      transaction.update(eventRef, eventUpdate);
      if (guest?.exists && guest.get("encryptedEmail")) {
        const messageRef = db.collection("OutboundMessages")
            .doc(`cancellation_${registrationId}`);
        transaction.set(messageRef, {id: messageRef.id,
          templateId: "guest_registration_cancelled",
          channel: "email",
          status: "pending", attempts: 0, registrationId, guestId: guest.id,
          eventId: event.id, encryptedEmail: guest.get("encryptedEmail"),
          maskedEmail: guest.get("maskedEmail"), payload: {
            calendarPreviouslyConfirmed: previouslyConfirmed === true,
            firstName: guest.get("greetingName"), eventTitle: event.get("title"),
            eventStart: event.get("selectedDateTime"), eventLocation: event.get("location") || "",
            eventDurationMinutes: event.get("eventDurationMinutes") || null, eventDuration: event.get("eventDuration") || null,
            eventTimeZone: event.get("eventTimeZone") || "UTC", eventRevision: event.get("eventRevision") || 0,
          }, createdAt: admin.firestore.FieldValue.serverTimestamp(), nextAttemptAt: new Date()});
      }
      return {status: "cancelled"};
    });
  });
}

async function organizerAuthorized(db, uid, event) {
  return (await require("../events/access").capabilities(db, uid, event)).manageEvent;
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
    const registrations = {docs: await require("../events/roster").allDocuments(db.collection("RegisterAttendance").where("eventId", "==", eventId))};
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
  const text = String(value ?? "");
  const safe = /^[\s]*[=+@-]/.test(text) ? `'${text}` : text;
  return `"${safe.replaceAll("\"", "\"\"")}"`;
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
    const registrations = {docs: await require("../events/roster").allDocuments(db.collection("RegisterAttendance").where("eventId", "==", eventId))};
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
    const idempotencyKey = requireIdempotencyKey(req.data?.idempotencyKey);
    await enforceRateLimit(db, caller.uid, "resend_confirmation");
    const {registration, guest, event} = await ownedRegistration(db, caller.uid, registrationId);
    const manage = manageTokenData(admin, guest.id, registration.id, caller.uid);
    const messageRef = db.collection("OutboundMessages").doc(`resend_${digest(caller.uid, registrationId, idempotencyKey)}`);
    await db.runTransaction(async (transaction) => {
      const fresh = await readGuestRegistration(db, transaction, {registrationId, guestId: guest.id, eventId: event.id, actorUid: caller.uid, requireOwnership: true});
      const previous = await transaction.get(messageRef);
      const currentEvent = await transaction.get(event.ref);
      if (!currentEvent.exists) throw new HttpsError("not-found", "Event not found.");
      if (previous.exists) return;
      const status = fresh.registration.get("status");
      const cancelled = currentEvent.get("cancelled") || ["cancelled", "canceled"].includes(currentEvent.get("status")) ||
        fresh.registration.get("cancelled") || fresh.registration.get("revoked") || ["cancelled", "canceled", "revoked", "refunded"].includes(status);
      const templateId = cancelled ? "guest_registration_cancelled" : status === "declined" ? "guest_registration_declined" :
        status === "waitlisted" ? "guest_registration_waitlisted" : require("../attendance/arrival-core").confirmedRegistration(fresh.registration.data()) ?
          "guest_registration_confirmation" : "guest_registration_pending";
      transaction.set(db.collection("GuestManageTokens").doc(manage.id), manage.document);
      transaction.create(messageRef, {templateId,
        channel: "email", status: "pending",
        attempts: 0, registrationId, guestId: guest.id, eventId: event.id,
        encryptedEmail: fresh.guest.get("encryptedEmail"), maskedEmail: fresh.guest.get("maskedEmail") || null,
        payload: {firstName: fresh.guest.get("greetingName") || "there", eventTitle: currentEvent.get("title") || "Event",
          eventStart: currentEvent.get("selectedDateTime") || null, eventLocation: currentEvent.get("location") || "",
            eventDurationMinutes: currentEvent.get("eventDurationMinutes") || null, eventDuration: currentEvent.get("eventDuration") || null,
            eventTimeZone: currentEvent.get("eventTimeZone") || "UTC", eventRevision: currentEvent.get("eventRevision") || 0,
          kind: fresh.registration.get("ticketId") || currentEvent.get("ticketsEnabled") ? "ticket" : "rsvp",
          manageUrl: `${publicOrigin()}/manage/${manage.raw}`},
        createdAt: admin.firestore.FieldValue.serverTimestamp(), nextAttemptAt: new Date()});
    });
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
    const newClaim = db.collection("GuestEventEmailClaims").doc(digest(event.id, newHash));
    await db.runTransaction(async (transaction) => {
      const fresh = await readGuestRegistration(db, transaction, {registrationId, guestId: guest.id, eventId: event.id, actorUid: caller.uid, requireOwnership: true});
      const freshOldClaim = db.collection("GuestEventEmailClaims").doc(digest(event.id, fresh.guest.get("emailHash")));
      const collision = await transaction.get(newClaim);
      if (collision.exists && collision.get("guestId") !== guest.id) {
        throw new HttpsError("already-exists", "A registration already uses that email.");
      }
      transaction.set(newClaim, {eventId: event.id, guestId: guest.id, registrationId,
        emailHash: newHash, status: registration.get("status") || "confirmed",
        updatedAt: admin.firestore.FieldValue.serverTimestamp()});
      if (freshOldClaim.id !== newClaim.id) transaction.delete(freshOldClaim);
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
    await db.runTransaction(async (transaction) => {
      const token = await transaction.get(tokenRef);
      const fresh = await readGuestRegistration(db, transaction, {registrationId, guestId: guest.id, actorUid: caller.uid});
      await requireActiveAccounts(db, transaction, token.get("ownerUid"), token.get("claimedByUid"));
      const linkedTickets = await transaction.get(db.collection("Tickets").where("guestId", "==", fresh.guest.id));
      for (const ticket of linkedTickets.docs) {
        if (ticket.get("eventId") !== fresh.registration.get("eventId") || ticket.get("registrationId") !== registrationId) {
          throw new HttpsError("failed-precondition", "Admission linkage requires review.");
        }
        await requireActiveAccounts(db, transaction, ticket.get("customerUid"), ticket.get("userId"));
      }
      if (fresh.guest.get("claimedByUid") && fresh.guest.get("claimedByUid") !== caller.uid) {
        throw new HttpsError("permission-denied", "This registration is already linked to an account.");
      }
      if (token.get("status") === "claimed" && token.get("claimedByUid") === caller.uid &&
          token.get("registrationId") === registrationId && token.get("guestId") === guest.id &&
          fresh.registration.get("customerUid") === caller.uid && fresh.guest.get("ownerUid") === caller.uid &&
          fresh.guest.get("claimedByUid") === caller.uid) return;
      if (!fresh.guest.exists || !token.exists || token.get("registrationId") !== registrationId ||
          token.get("guestId") !== guest.id || !["active", "exchanged"].includes(token.get("status")) ||
          (!token.get("expiresAt")?.toDate?.() || token.get("expiresAt").toDate() <= new Date())) {
        throw new HttpsError("permission-denied", "This registration claim is invalid or expired.");
      }
      const profileRef = db.collection("Customers").doc(caller.uid);
      const profile = await transaction.get(profileRef);
      if (!profile.exists) transaction.create(profileRef, {uid: caller.uid, name: String(fresh.guest.get("fullName") || "Attendee").slice(0, 160),
        email: String(req.auth.token.email || "").toLowerCase(),
        username: `attendee_${caller.uid.slice(0, 12).toLowerCase()}`, isDiscoverable: false,
        eventsCreated: 0, groupsCreated: 0,
        accountSource: "guest_registration_upgrade", profileCompletionRequired: true,
        createdAt: admin.firestore.FieldValue.serverTimestamp()});
      transaction.update(guest.ref, {ownerUid: caller.uid, claimedByUid: caller.uid,
        claimedAt: admin.firestore.FieldValue.serverTimestamp()});
      transaction.update(registration.ref, {customerUid: caller.uid,
        identityType: "account", isAnonymous: false,
        claimCompletedAt: admin.firestore.FieldValue.serverTimestamp()});
      for (const ticket of linkedTickets.docs) transaction.update(ticket.ref, {
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
    return db.runTransaction(async (transaction) => {
      const event = await transaction.get(db.collection("Events").doc(eventId));
      if (!event.exists || event.get("private") === true) throw new HttpsError("not-found", "Event not found.");
      const organizerUid = String(event.get("customerUid") || "");
      const organizationId = String(event.get("organizationId") || "");
      const organization = organizationId ? await transaction.get(db.collection("Organizations").doc(organizationId)) : null;
      await requireActiveAccounts(db, transaction, caller.uid, organizerUid, organization?.get("createdBy"));
      const now = admin.firestore.FieldValue.serverTimestamp();
      if (organizationId) {
        if (!organization.exists) throw new HttpsError("not-found", "Organizer is unavailable.");
        transaction.set(organization.ref.collection("Followers").doc(caller.uid), {userId: caller.uid, organizationId, createdAt: now});
        return {status: "following", type: "organization"};
      }
      if (!organizerUid) throw new HttpsError("failed-precondition", "Organizer is unavailable.");
      transaction.set(db.collection("Customers").doc(organizerUid).collection("followers")
          .doc(caller.uid), {userId: caller.uid, organizerUid, createdAt: now});
      transaction.set(db.collection("Customers").doc(caller.uid).collection("following")
          .doc(organizerUid), {userId: organizerUid, followerUid: caller.uid, createdAt: now});
      return {status: "following", type: "organizer"};
    });
  });
}

function createAnonymizeExpiredGuestContacts(admin) {
  return onSchedule({region: "us-central1", schedule: "every day 03:15",
    timeZone: "UTC", timeoutSeconds: 240}, () =>
    require("./guest-retention").anonymizeExpiredGuestContacts(admin));
}
module.exports = {
  CONTACT_HMAC_KEY,
  CONTACT_KMS_KEY_NAME,
  STRIPE_SECRET_KEY,
  requireCaller,
  csvCell,
  organizerAuthorized,
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
