"use strict";

const crypto = require("node:crypto");
const {onCall, HttpsError} = require("firebase-functions/v2/https");
const {normalizeAnswer, registrationAnswers} = require("./question-answers");
const {
  CONTACT_HMAC_KEY,
  CONTACT_KMS_KEY_NAME,
  digest,
  emailHash,
  enforceRateLimit,
  encryptEmail,
  maskedEmail,
  normalizeRegistrationIdentity,
  ticketQrSvg,
  validateEvent,
  validateRegistrationWindow,
} = require("../public-web/accountless");

const PUBLIC_ORIGIN = "https://attendus.app";

function caller(request) {
  const uid = request.auth?.uid;
  const provider = request.auth?.token?.firebase?.sign_in_provider;
  if (!uid) throw new HttpsError("unauthenticated", "A secure guest session is required.");
  if (!request.app && process.env.FUNCTIONS_EMULATOR !== "true") {
    throw new HttpsError("failed-precondition", "App Check verification is required.");
  }
  return {uid, isAnonymous: provider === "anonymous"};
}

function identifier(value, label) {
  const normalized = typeof value === "string" ? value.trim() : "";
  if (!/^[A-Za-z0-9._:-]{1,500}$/.test(normalized)) {
    throw new HttpsError("invalid-argument", `A valid ${label} is required.`);
  }
  return normalized;
}

function createStartPublicRegistrationV3(admin) {
  const db = admin.firestore();
  return onCall({region: "us-central1", enforceAppCheck: process.env.FUNCTIONS_EMULATOR !== "true",
    secrets: [CONTACT_HMAC_KEY, CONTACT_KMS_KEY_NAME], maxInstances: 30}, async (request) => {
    const actor = caller(request);
    const eventId = identifier(request.data?.eventId, "event ID");
    const idempotencyKey = identifier(request.data?.idempotencyKey, "idempotency key");
    if (idempotencyKey.length < 8 || idempotencyKey.length > 128) {
      throw new HttpsError("invalid-argument", "A valid idempotency key is required.");
    }
    const {fullName, greetingName, email} = normalizeRegistrationIdentity(request.data);
    const eventRef = db.collection("Events").doc(eventId);
    const [configSnapshot, eventSnapshot] = await Promise.all([
      db.collection("AppConfig").doc("publicWeb").get(), eventRef.get(),
    ]);
    if (configSnapshot.get("accountlessRegistrationEnabled") !== true) {
      throw new HttpsError("failed-precondition", "This action is temporarily unavailable.");
    }
    await enforceRateLimit(db, actor.uid, "start_registration_v3");
    if (!eventSnapshot.exists) throw new HttpsError("not-found", "Event not found.");
    const event = eventSnapshot.data();
    validateEvent(event);
    validateRegistrationWindow(event);
    const policy = event.registrationPolicy || {};
    const mode = policy.mode || (event.ticketsEnabled ?
      (Number(event.ticketPrice || 0) > 0 ? "paid_ticket" : "free_ticket") : "rsvp");
    if (mode === "paid_ticket") {
      throw new HttpsError("failed-precondition", "Paid guest checkout is not enabled for this registration flow.");
    }
    const answers = await registrationAnswers(eventRef, request.data?.answers);
    const hash = emailHash(email);
    const claimId = digest(eventId, hash);
    const claimRef = db.collection("GuestEventEmailClaims").doc(claimId);
    const existingClaim = await claimRef.get();
    if (existingClaim.exists) {
      const existing = existingClaim.data();
      const raw = crypto.randomBytes(32).toString("base64url");
      await Promise.all([
        db.collection("GuestManageTokens").doc(digest(raw)).set({
          guestId: existing.guestId, registrationId: existing.registrationId,
          ownerUid: "email_proof_only", status: "active",
          createdAt: admin.firestore.FieldValue.serverTimestamp(),
          expiresAt: new Date(Date.now() + 72 * 3600000),
        }),
        db.collection("OutboundMessages").doc(`resend_${crypto.randomUUID()}`).set({
          templateId: "guest_registration_confirmation", channel: "email", status: "pending",
          attempts: 0, registrationId: existing.registrationId, guestId: existing.guestId,
          eventId, encryptedEmail: await encryptEmail(email), maskedEmail: maskedEmail(email),
          payload: {firstName: greetingName, eventTitle: String(event.title || "Event"),
            eventStart: event.selectedDateTime, eventLocation: String(event.location || ""),
            kind: mode, duplicate: true, manageUrl: `${PUBLIC_ORIGIN}/manage/${raw}`},
          createdAt: admin.firestore.FieldValue.serverTimestamp(), nextAttemptAt: new Date(),
        }),
      ]);
      return {status: "confirmation_pending", kind: mode};
    }
    const encryptedEmail = await encryptEmail(email);
    const guestId = `guest_${crypto.randomUUID()}`;
    const flowId = `flow_${digest("v3", eventId, actor.uid, idempotencyKey)}`;
    const registrationId = `registration_${digest(eventId, guestId)}`;
    const registrationRef = db.collection("RegisterAttendance").doc(registrationId);
    const guestRef = db.collection("GuestAttendees").doc(guestId);
    const flowRef = db.collection("PublicRegistrationFlows").doc(flowId);
    const rawManageToken = crypto.randomBytes(32).toString("base64url");
    const manageTokenRef = db.collection("GuestManageTokens").doc(digest(rawManageToken));
    const now = admin.firestore.Timestamp.now();
    let resultStatus = policy.approvalMode === "manual" ? "pending" : "confirmed";
    let ticketId = null;
    let ticketCode = null;
    await db.runTransaction(async (transaction) => {
      const [freshEvent, freshClaim] = await Promise.all([
        transaction.get(eventRef), transaction.get(claimRef),
      ]);
      if (freshClaim.exists) throw new HttpsError("already-exists", "Registration already exists.");
      validateEvent(freshEvent.data());
      validateRegistrationWindow(freshEvent.data());
      const current = freshEvent.data();
      const currentPolicy = current.registrationPolicy || policy;
      const capacity = Number(currentPolicy.capacity || current.maxTickets || 0);
      const confirmed = Number(current.confirmedRegistrationCount || 0);
      if (resultStatus === "confirmed" && capacity > 0 && confirmed >= capacity) {
        if (currentPolicy.waitlistEnabled === false) {
          throw new HttpsError("resource-exhausted", "This event is full.");
        }
        resultStatus = "waitlisted";
      }
      transaction.create(guestRef, {id: guestId, ownerUid: actor.uid, fullName, greetingName,
        emailHash: hash, emailHashVersion: 1, encryptedEmail, maskedEmail: maskedEmail(email),
        verificationStatus: "pending", claimedByUid: actor.isAnonymous ? null : actor.uid,
        createdAt: now, retentionAt: new Date(Date.now() + 180 * 86400000)});
      transaction.create(claimRef, {eventId, guestId, registrationId, emailHash: hash,
        status: resultStatus, createdAt: now});
      transaction.create(manageTokenRef, {guestId, registrationId, ownerUid: actor.uid,
        status: "active", createdAt: now, expiresAt: new Date(Date.now() + 72 * 3600000)});
      transaction.create(flowRef, {id: flowId, eventId, guestId, registrationId,
        ownerUid: actor.uid, kind: mode, status: resultStatus, createdAt: now});
      transaction.create(registrationRef, {id: registrationId, eventId, userName: fullName,
        realName: fullName, customerUid: actor.uid, guestId,
        identityType: actor.isAnonymous ? "guest" : "account", emailRef: guestRef.path,
        attendanceDateTime: now, answers, isAnonymous: actor.isAnonymous,
        registrationSource: "public_event_page_v3", status: resultStatus});
      if (resultStatus === "confirmed") {
        transaction.update(eventRef, {confirmedRegistrationCount:
          admin.firestore.FieldValue.increment(1)});
        if (mode === "free_ticket") {
          ticketId = `free_${digest(eventId, guestId)}`;
          ticketCode = crypto.randomBytes(4).toString("hex").toUpperCase();
          transaction.create(db.collection("Tickets").doc(ticketId), {id: ticketId, eventId,
            eventTitle: String(current.title || "Event"), eventImageUrl: String(current.imageUrl || ""),
            eventLocation: String(current.location || ""), eventDateTime: current.selectedDateTime,
            customerUid: actor.uid, guestId, identityType: actor.isAnonymous ? "guest" : "account",
            customerName: fullName, ticketCode, issuedDateTime: now, price: 0,
            isPaid: false, isUsed: false, isSkipTheLine: false,
            issuanceSource: "server_guest_ticket_v3", revoked: false});
          transaction.update(eventRef, {issuedTickets: admin.firestore.FieldValue.increment(1)});
        }
      }
      transaction.create(db.collection("OutboundMessages").doc(`${resultStatus}_${registrationId}`), {
        templateId: resultStatus === "pending" ? "guest_registration_pending" :
          resultStatus === "waitlisted" ? "guest_registration_waitlisted" : "guest_registration_confirmation",
        channel: "email", status: "pending", attempts: 0, registrationId, guestId, eventId,
        encryptedEmail, maskedEmail: maskedEmail(email), payload: {firstName: greetingName,
          eventTitle: String(current.title || "Event"), eventStart: current.selectedDateTime,
          eventLocation: String(current.location || ""), kind: mode,
          manageUrl: `${PUBLIC_ORIGIN}/manage/${rawManageToken}`},
        createdAt: now, nextAttemptAt: new Date(),
      });
    });
    return {status: resultStatus, kind: mode, flowId, registrationId, ticketId, ticketCode,
      ticketQrSvg: await ticketQrSvg(ticketCode), claimToken: rawManageToken,
      manageUrl: `${PUBLIC_ORIGIN}/manage/${rawManageToken}`, deliveryStatus: "pending"};
  });
}

module.exports = {createStartPublicRegistrationV3, normalizeAnswer};
