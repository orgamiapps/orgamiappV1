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
  decryptEmail,
  maskedEmail,
  normalizeRegistrationIdentity,
  ticketQrSvg,
  validateEvent,
  validateRegistrationWindow,
} = require("../public-web/accountless");

const {publicOrigin} = require("../public-web/origin");

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
    const flowId = `flow_${digest("v3", eventId, actor.uid, idempotencyKey)}`;
    const flowRef = db.collection("PublicRegistrationFlows").doc(flowId);
    const rawAnswers = request.data?.answers || {};
    const fingerprint = digest(fullName, email, JSON.stringify(Object.keys(rawAnswers).sort()
        .map((key) => [key, rawAnswers[key]])));
    async function response(flow) {
      if (flow.requestFingerprint !== fingerprint) {
        throw new HttpsError("already-exists", "This submission key was already used for different information.");
      }
      const token = flow.encryptedManageToken ? await decryptEmail(flow.encryptedManageToken) : null;
      return {...flow.result, flowId, ticketQrSvg: await ticketQrSvg(flow.result?.ticketCode),
        ...(token ? {claimToken: token, manageUrl: `${publicOrigin()}/manage/${token}`} : {})};
    }
    const deletionGuard = await db.collection("account_deletion_jobs").doc(actor.uid).get();
    if (deletionGuard.exists) throw new HttpsError("failed-precondition", "This account is being deleted.");
    const previous = await flowRef.get();
    if (previous.exists) return response(previous.data());
    const eventRef = db.collection("Events").doc(eventId);
    const [configSnapshot, eventSnapshot, deletion] = await Promise.all([
      db.collection("AppConfig").doc("publicWeb").get(), eventRef.get(),
      db.collection("account_deletion_jobs").doc(actor.uid).get(),
    ]);
    if (deletion.exists) throw new HttpsError("failed-precondition", "Account deletion is in progress.");
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
    const answers = await registrationAnswers(eventRef, rawAnswers);
    const hash = emailHash(email);
    const claimRef = db.collection("GuestEventEmailClaims").doc(digest(eventId, hash));
    const encryptedEmail = await encryptEmail(email);
    const guestId = `guest_${crypto.randomUUID()}`;
    const registrationId = `registration_${digest(eventId, guestId)}`;
    const rawManageToken = crypto.randomBytes(32).toString("base64url");
    const encryptedManageToken = await encryptEmail(rawManageToken);
    const ticketCode = crypto.randomBytes(4).toString("hex").toUpperCase();
    const now = admin.firestore.Timestamp.now();
    const result = await db.runTransaction(async (transaction) => {
      const [prior, freshEvent, freshClaim, deleting] = await Promise.all([
        transaction.get(flowRef), transaction.get(eventRef), transaction.get(claimRef),
        transaction.get(db.collection("account_deletion_jobs").doc(actor.uid)),
      ]);
      if (deleting.exists) throw new HttpsError("failed-precondition", "Account deletion is in progress.");
      if (prior.exists) return prior.data();
      const current = freshEvent.data();
      validateEvent(current);
      validateRegistrationWindow(current);
      const currentPolicy = current.registrationPolicy || {};
      const currentMode = currentPolicy.mode || (current.ticketsEnabled ?
        (Number(current.ticketPrice || 0) > 0 ? "paid_ticket" : "free_ticket") : "rsvp");
      if (currentMode !== mode || current.eventRevision !== event.eventRevision) {
        throw new HttpsError("aborted", "The event changed. Refresh before registering.");
      }
      let status = currentPolicy.approvalMode === "manual" ? "pending" : "confirmed";
      let ticketId = null;
      let ownedRegistrationId = registrationId;
      let recipientGuestId = guestId;
      if (freshClaim.exists) {
        // Never reveal a registration belonging to another session through an email match.
        status = "confirmation_pending";
        ownedRegistrationId = freshClaim.get("registrationId");
        recipientGuestId = freshClaim.get("guestId");
      } else {
        const {full, confirmed} = require("./capacity").capacityState(current);
        if (status === "confirmed" && full) {
          if (currentPolicy.waitlistEnabled === false) {
            throw new HttpsError("resource-exhausted", "This event is full.");
          }
          status = "waitlisted";
        }
        if (status === "confirmed" && mode === "free_ticket") ticketId = `free_${digest(eventId, guestId)}`;
        transaction.create(db.collection("GuestAttendees").doc(guestId), {
          id: guestId, ownerUid: actor.uid, fullName, greetingName, emailHash: hash,
          emailHashVersion: 1, encryptedEmail, maskedEmail: maskedEmail(email),
          verificationStatus: "pending", claimedByUid: actor.isAnonymous ? null : actor.uid,
          createdAt: now, retentionAt: new Date(Date.now() + 180 * 86400000),
        });
        transaction.create(claimRef, {eventId, guestId, registrationId, emailHash: hash, status, createdAt: now});
        transaction.create(db.collection("RegisterAttendance").doc(registrationId), {
          id: registrationId, eventId, userName: fullName, realName: fullName,
          customerUid: actor.uid, guestId, ticketId, emailHash: hash,
          identityType: actor.isAnonymous ? "guest" : "account", emailRef: `GuestAttendees/${guestId}`,
          attendanceDateTime: now, answers, isAnonymous: actor.isAnonymous,
          registrationSource: "public_event_page_v3", status,
        });
        if (status === "confirmed") {
          transaction.update(eventRef, {confirmedRegistrationCount: confirmed + 1,
            ...(ticketId ? {issuedTickets: admin.firestore.FieldValue.increment(1)} : {})});
        }
        if (ticketId) transaction.create(db.collection("Tickets").doc(ticketId), {
          id: ticketId, eventId, registrationId, eventTitle: String(current.title || "Event"),
          eventImageUrl: String(current.imageUrl || ""), eventLocation: String(current.location || ""),
          eventDateTime: current.selectedDateTime, customerUid: actor.uid, guestId,
          identityType: actor.isAnonymous ? "guest" : "account", customerName: fullName,
          ticketCode, issuedDateTime: now, price: 0, isPaid: false, isUsed: false,
          isSkipTheLine: false, issuanceSource: "server_guest_ticket_v3", revoked: false,
        });
      }
      transaction.create(db.collection("GuestManageTokens").doc(digest(rawManageToken)), {
        guestId: recipientGuestId, registrationId: ownedRegistrationId,
        ownerUid: status === "confirmation_pending" ? "email_proof_only" : actor.uid,
        status: "active", createdAt: now, expiresAt: new Date(Date.now() + 72 * 3600000),
      });
      const flow = {id: flowId, eventId, ownerUid: actor.uid, kind: mode, status,
        requestFingerprint: fingerprint, createdAt: now,
        ...(status === "confirmation_pending" ? {} : {
          guestId, registrationId, ticketId, encryptedManageToken,
        }),
        result: {status, kind: mode, deliveryStatus: "pending",
          ...(status === "confirmation_pending" ? {} : {registrationId, ticketId,
            ticketCode: ticketId ? ticketCode : null})},
      };
      transaction.create(flowRef, flow);
      transaction.create(db.collection("OutboundMessages").doc(`registration_${flowId}`), {
        templateId: status === "pending" ? "guest_registration_pending" :
          status === "waitlisted" ? "guest_registration_waitlisted" : "guest_registration_confirmation",
        channel: "email", status: "pending", attempts: 0, registrationId: ownedRegistrationId,
        guestId: recipientGuestId, eventId, encryptedEmail, maskedEmail: maskedEmail(email),
        payload: {firstName: greetingName, eventTitle: String(current.title || "Event"),
          eventStart: current.selectedDateTime, eventDurationMinutes: current.eventDurationMinutes || null,
          eventDuration: current.eventDuration || null, eventTimeZone: current.eventTimeZone || "UTC",
          eventRevision: current.eventRevision || 0, eventLocation: String(current.location || ""),
          kind: mode, duplicate: status === "confirmation_pending",
          manageUrl: `${publicOrigin()}/manage/${rawManageToken}`},
        createdAt: now, nextAttemptAt: new Date(),
      });
      return flow;
    });
    return response(result);
  });
}

module.exports = {createStartPublicRegistrationV3, normalizeAnswer};
