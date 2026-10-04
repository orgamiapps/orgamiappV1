"use strict";

const crypto = require("node:crypto");
const {defineSecret} = require("firebase-functions/params");
const {onDocumentCreated} = require("firebase-functions/v2/firestore");
const {onSchedule} = require("firebase-functions/v2/scheduler");
const {onCall, HttpsError} = require("firebase-functions/v2/https");
const {ROLE_PERMISSIONS, ROLES} = require("../admin/constants");
const logger = require("firebase-functions/logger");
const {qualificationDecision, interceptQualification} = require("./qualification-isolation");
const {CONTACT_KMS_KEY_NAME, decryptEmail} =
  require("../public-web/accountless");

const MICROSOFT_TENANT_ID = defineSecret("MICROSOFT_TENANT_ID");
const MICROSOFT_CLIENT_ID = defineSecret("MICROSOFT_CLIENT_ID");
const MICROSOFT_CERT_THUMBPRINT = defineSecret("MICROSOFT_CERT_THUMBPRINT");
const MICROSOFT_PRIVATE_KEY = defineSecret("MICROSOFT_PRIVATE_KEY");
const SUPPORT_EMAIL = "support@attendus.app";
const DELIVERY_SECRETS = [CONTACT_KMS_KEY_NAME, MICROSOFT_TENANT_ID,
  MICROSOFT_CLIENT_ID, MICROSOFT_CERT_THUMBPRINT, MICROSOFT_PRIVATE_KEY];

function secret(secretParam, label) {
  const value = secretParam.value().trim();
  if (!value) throw new Error(`${label} is not configured`);
  return value;
}

function base64url(value) {
  return Buffer.from(value).toString("base64url");
}

function graphAssertion(nowSeconds = Math.floor(Date.now() / 1000)) {
  const tenant = secret(MICROSOFT_TENANT_ID, "Microsoft tenant");
  const clientId = secret(MICROSOFT_CLIENT_ID, "Microsoft client");
  const tokenUrl = `https://login.microsoftonline.com/${tenant}/oauth2/v2.0/token`;
  const header = {alg: "RS256", typ: "JWT",
    x5t: secret(MICROSOFT_CERT_THUMBPRINT, "Microsoft certificate thumbprint")};
  const payload = {aud: tokenUrl, iss: clientId, sub: clientId,
    jti: crypto.randomUUID(), nbf: nowSeconds - 30, exp: nowSeconds + 300};
  const unsigned = `${base64url(JSON.stringify(header))}.${base64url(JSON.stringify(payload))}`;
  const signature = crypto.sign("RSA-SHA256", Buffer.from(unsigned),
      secret(MICROSOFT_PRIVATE_KEY, "Microsoft private key")).toString("base64url");
  return {tokenUrl, assertion: `${unsigned}.${signature}`, clientId};
}

async function graphAccessToken() {
  const {tokenUrl, assertion, clientId} = graphAssertion();
  const body = new URLSearchParams({client_id: clientId, scope: "https://graph.microsoft.com/.default",
    grant_type: "client_credentials", client_assertion_type:
      "urn:ietf:params:oauth:client-assertion-type:jwt-bearer", client_assertion: assertion});
  const response = await fetch(tokenUrl, {method: "POST",
    headers: {"content-type": "application/x-www-form-urlencoded"}, body});
  if (!response.ok) throw new Error(`Microsoft token request failed (${response.status})`);
  return (await response.json()).access_token;
}

function escapeHtml(value) {
  return String(value ?? "").replaceAll("&", "&amp;").replaceAll("<", "&lt;")
      .replaceAll(">", "&gt;").replaceAll("\"", "&quot;").replaceAll("'", "&#39;");
}

function calendarInvite(message, method = "PUBLISH") {
  const identity = message.registrationId || message.ticketId;
  if (typeof identity !== "string" || !/^[A-Za-z0-9._:-]{1,500}$/.test(identity)) return null;
  return require("../events/schedule").calendar(message.payload || {}, {
    uid: `${identity}@attendus.app`,
    url: message.payload?.manageUrl, method,
  });
}

function shouldAttachCalendar(templateId) {
  return ["guest_registration_confirmation", "guest_registration_cancelled", "event_rescheduled", "event_cancelled"].includes(templateId);
}

async function calendarAttachmentEligible(db, message) {
  const payload = message.payload || {};
  const validId = (value) => typeof value === "string" && /^[A-Za-z0-9._:-]{1,500}$/.test(value);
  if (!shouldAttachCalendar(message.templateId) || payload.duplicate === true || payload.calendarEligible === false ||
      (!validId(message.registrationId) && !validId(message.ticketId)) ||
      (message.registrationId && !validId(message.registrationId)) || (message.ticketId && !validId(message.ticketId)) ||
      !validId(message.eventId)) return false;
  const cancellation = ["guest_registration_cancelled", "event_cancelled"].includes(message.templateId);
  if (cancellation && payload.calendarPreviouslyConfirmed !== true) return false;
  const {activeEvent, confirmedRegistration, validTicket} = require("../attendance/arrival-core");
  return db.runTransaction(async (tx) => {
    const [event, registration] = await Promise.all([
      tx.get(db.collection("Events").doc(message.eventId)),
      message.registrationId ? tx.get(db.collection("RegisterAttendance").doc(message.registrationId)) : {exists: false},
    ]);
    if (!event.exists || (!cancellation && !activeEvent(event.data()))) return false;
    if (registration.exists && registration.get("eventId") !== message.eventId) return false;
    let tickets = [];
    if (registration.exists) {
      const reverse = await tx.get(db.collection("Tickets").where("eventId", "==", message.eventId)
          .where("registrationId", "==", registration.id).limit(2));
      tickets = reverse.docs;
      if (registration.get("ticketId")) {
        const forward = await tx.get(db.collection("Tickets").doc(registration.get("ticketId")));
        if (!forward.exists || forward.get("eventId") !== message.eventId ||
            (forward.get("registrationId") && forward.get("registrationId") !== registration.id)) return false;
        tickets = [...new Map([...tickets, forward].map((ticket) => [ticket.id, ticket])).values()];
      }
    } else if (!message.registrationId && message.ticketId) {
      const ticket = await tx.get(db.collection("Tickets").doc(message.ticketId));
      if (!ticket.exists || ticket.get("eventId") !== message.eventId) return false;
      tickets = [ticket];
    } else return false;
    if (message.ticketId && !tickets.some((ticket) => ticket.id === message.ticketId)) return false;
    const identity = registration.exists ? registration.data() : tickets[0].data();
    if (message.guestId ? identity.guestId !== message.guestId :
      (!message.ownerUid || (identity.customerUid || identity.userId) !== message.ownerUid)) return false;
    const guest = message.guestId ? await tx.get(db.collection("GuestAttendees").doc(message.guestId)) : null;
    if (guest && (!guest.exists || !message.encryptedEmail || guest.get("encryptedEmail") !== message.encryptedEmail)) return false;
    const uids = [...new Set([message.ownerUid, identity.customerUid || identity.userId,
      guest?.get("ownerUid"), guest?.get("claimedByUid")].filter(Boolean))];
    for (const uid of uids) if ((await tx.get(db.collection("account_deletion_jobs").doc(uid))).exists) return false;
    if (cancellation) {
      // The trusted producer captured confirmed eligibility atomically before
      // cancellation. Current revocation is expected, but a stale cancellation
      // must not cancel a subsequently reinstated registration/event.
      return message.templateId === "event_cancelled" ? event.get("cancelled") === true || ["cancelled", "canceled"].includes(event.get("status")) :
        registration.exists && (registration.get("cancelled") === true || ["cancelled", "canceled"].includes(registration.get("status")));
    }
    if (registration.exists && !confirmedRegistration(identity)) return false;
    if ((event.get("ticketsEnabled") || identity.ticketId) && tickets.length === 0) return false;
    return tickets.length === 0 || tickets.some((ticket) => validTicket(ticket.data(), event.data()));
  });
}

function fallbackTemplate(message) {
  const payload = message.payload || {};
  if (["event_announcement", "event_rescheduled", "event_cancelled"].includes(message.templateId)) {
    const subject = payload.title || `${message.templateId === "event_cancelled" ? "Cancelled" : "Update"}: ${payload.eventTitle}`;
    return {subject, text: `${subject}\n${payload.body || ""}`,
      html: `<h1>${escapeHtml(subject)}</h1><p>${escapeHtml(payload.body || "").replaceAll("\n", "<br>")}</p>`};
  }
  const cancelled = message.templateId === "guest_registration_cancelled";
  const declined = message.templateId === "guest_registration_declined";
  const pending = message.templateId === "guest_registration_pending";
  const waitlisted = message.templateId === "guest_registration_waitlisted";
  const duplicate = payload.duplicate === true;
  const subject = duplicate ? `Your registration: ${payload.eventTitle}` : cancelled ? `Registration cancelled: ${payload.eventTitle}` :
    declined ? `Registration update: ${payload.eventTitle}` :
    pending ? `Registration received: ${payload.eventTitle}` :
      waitlisted ? `You're on the waitlist for ${payload.eventTitle}` :
        `You're confirmed for ${payload.eventTitle}`;
  const action = duplicate ? "Use your secure link to view the current registration status." : cancelled ? "Your registration has been cancelled." :
    declined ? "The organizer was unable to approve your registration." :
    pending ? "Your registration is awaiting organizer approval." :
      waitlisted ? "A place is not currently available, so you have been added to the waitlist." :
        `Your ${message.payload?.kind === "rsvp" ? "RSVP" : "ticket"} is confirmed.`;
  const actionable = !cancelled && !declined && !pending;
  const text = `Hi ${payload.firstName || "there"}, ${action} ${payload.eventTitle}. ` +
    `${actionable ? `View your registration: ${payload.manageUrl}` : ""}`;
  const html = `<h1>${escapeHtml(subject)}</h1><p>Hi ${escapeHtml(payload.firstName || "there")},</p>` +
    `<p>${escapeHtml(action)}</p><p><strong>${escapeHtml(payload.eventTitle)}</strong></p>` +
    (actionable ? `<p><a href="${escapeHtml(payload.manageUrl)}">View registration</a></p>` : "") +
    `<p>Questions? Contact <a href="mailto:${SUPPORT_EMAIL}">${SUPPORT_EMAIL}</a>.</p>`;
  return {subject, text, html};
}

async function templateFor(db, message) {
  const snapshot = await db.collection("CommunicationTemplates").doc(message.templateId).get();
  if (!snapshot.exists || snapshot.get("status") !== "published") {
    return {...fallbackTemplate(message), attachCalendar: shouldAttachCalendar(message.templateId)};
  }
  const fallback = fallbackTemplate(message);
  const values = {firstName: message.payload?.firstName || "there",
    eventTitle: message.payload?.eventTitle || "Event", manageUrl: message.payload?.manageUrl || "",
    supportEmail: SUPPORT_EMAIL};
  const render = (source, html = false) => String(source || "").replace(/\{\{(firstName|eventTitle|manageUrl|supportEmail)\}\}/g,
      (_, key) => html ? escapeHtml(values[key]) : values[key]);
  return {subject: render(snapshot.get("subject")) || fallback.subject,
    text: render(snapshot.get("text")) || fallback.text,
    html: render(snapshot.get("html"), true) || fallback.html,
    attachCalendar: shouldAttachCalendar(message.templateId)};
}

async function readDeliveryRecipient(db, transaction, message) {
  const guest = message.guestId ? await transaction.get(db.collection("GuestAttendees").doc(message.guestId)) : null;
  if (message.guestId && !guest?.exists) return {available: false, guest};
  const uids = new Set([message.ownerUid, guest?.get("ownerUid"), guest?.get("claimedByUid")].filter(Boolean));
  for (const uid of uids) {
    if ((await transaction.get(db.collection("account_deletion_jobs").doc(uid))).exists) return {available: false, guest};
  }
  return {available: true, guest};
}

async function requireCurrentDeliveryRecipient(db, ref, message, email) {
  const recipient = await db.runTransaction(async (transaction) => {
    const current = await transaction.get(ref);
    if (!current.exists || current.get("status") !== "sending" || current.get("deliveryAttemptId") !== message.deliveryAttemptId) return {available: false};
    return readDeliveryRecipient(db, transaction, current.data());
  });
  if (!recipient.available) throw Object.assign(Error("Recipient changed or is unavailable; delivery withheld."), {deliverySuppressed: true});
  const encrypted = recipient.guest?.get("encryptedEmail");
  // Ciphertext is randomized by KMS; a duplicate email-proof request can carry
  // different ciphertext for the same address. Compare plaintext only in memory.
  const currentEmail = encrypted === message.encryptedEmail ? email : encrypted ? await decryptEmail(encrypted) : null;
  if (recipient.guest && (!currentEmail || currentEmail.toLowerCase() !== email.toLowerCase())) {
    throw Object.assign(Error("Recipient changed or is unavailable; delivery withheld."), {deliverySuppressed: true});
  }
}

async function sendEmail(db, ref, message, contact) {
  const template = await templateFor(db, message);
  const cancelled = ["guest_registration_cancelled", "event_cancelled"].includes(message.templateId);
  const attach = template.attachCalendar && require("../events/schedule").schedule(message.payload || {}).end && await calendarAttachmentEligible(db, message);
  const invite = attach ? calendarInvite(message, cancelled ? "CANCEL" : "PUBLISH") : null;
  const attachments = attach ? [{"@odata.type": "#microsoft.graph.fileAttachment",
    name: "attendus-event.ics", contentType: cancelled ?
      "text/calendar; method=CANCEL" : "text/calendar; method=PUBLISH",
    contentBytes: Buffer.from(invite).toString("base64")}] : [];
  await requireCurrentDeliveryRecipient(db, ref, message, contact.value);
  const context = {recipientUid: message.ownerUid, eventId: message.eventId, recipientEmail: contact.value};
  const isolation = await interceptQualification(db, context, `email:${ref.id}`, {
    messageId: ref.id, templateId: message.templateId, eventId: message.eventId || null,
    subject: template.subject, text: template.text, html: template.html, attachments,
  });
  if (isolation.mode === "capture") return {provider: "qualification_capture", providerStatus: "accepted", captureId: isolation.captureId};
  if (isolation.mode !== "normal") throw Object.assign(Error("Qualification delivery policy withheld this message."), {deliverySuppressed: true});
  if (demoDeliveryCaptureEnabled()) {
    await requireCurrentDeliveryRecipient(db, ref, message, contact.value);
    await db.collection("EmulatorOutboundDeliveries").doc(ref.id).set({
      messageId: ref.id, deliveryAttemptId: message.deliveryAttemptId,
      templateId: message.templateId, eventId: message.eventId || null,
      registrationId: message.registrationId || null, guestId: message.guestId || null,
      recipient: contact.value, subject: template.subject, html: template.html,
      attachments, capturedAt: new Date(), provider: "emulator_capture",
    });
    return {provider: "emulator_capture", providerStatus: "accepted"};
  }
  const token = await graphAccessToken();
  // Recheck after asynchronous template/token/calendar work, immediately before
  // handing contact information to the provider. Provider IO cannot be atomic
  // with Firestore; a later concurrent deletion remains a reconciliation case.
  await requireCurrentDeliveryRecipient(db, ref, message, contact.value);
  if ((await qualificationDecision(db, context)).mode !== "normal") {
    throw Object.assign(Error("Qualification delivery policy changed; delivery withheld."), {deliverySuppressed: true});
  }
  let response;
  try { response = await fetch(`https://graph.microsoft.com/v1.0/users/${encodeURIComponent(SUPPORT_EMAIL)}/sendMail`, {
    method: "POST", headers: {authorization: `Bearer ${token}`, "content-type": "application/json"},
    signal: AbortSignal.timeout(30000),
    body: JSON.stringify({message: {subject: template.subject,
      body: {contentType: "HTML", content: template.html},
      toRecipients: [{emailAddress: {address: contact.value}}],
      attachments}, saveToSentItems: true}),
  }); } catch (error) { error.deliveryUncertain = true; throw error; }
  if (response.status !== 202) {
    const error = new Error(`Microsoft Graph rejected email (${response.status})`);
    error.deliveryUncertain = response.status >= 500;
    throw error;
  }
  return {provider: "microsoft_graph", providerStatus: "accepted"};
}

async function processMessage(admin, ref) {
  const db = admin.firestore();
  const deliveryAttemptId = crypto.randomUUID();
  const reserved = await db.runTransaction(async (transaction) => {
    const snapshot = await transaction.get(ref);
    if (!snapshot.exists || !["pending", "retry"].includes(snapshot.get("status"))) return;
    const recipient = await readDeliveryRecipient(db, transaction, snapshot.data());
    if (!recipient.available) {
      transaction.delete(ref);
      return;
    }
    const next = snapshot.get("nextAttemptAt")?.toDate?.();
    if (next && next > new Date()) return;
    const isolation = await qualificationDecision(db, {recipientUid: snapshot.get("ownerUid"), eventId: snapshot.get("eventId"), deferRecipientEmail: true}, transaction);
    if (isolation.mode === "suppress") {
      transaction.update(ref, {status: "suppressed", lastError: isolation.reason});
      return;
    }
    const attempts = Number(snapshot.get("attempts") || 0) + 1;
    transaction.update(ref, {status: "sending", attempts, deliveryAttemptId,
      lastAttemptAt: admin.firestore.FieldValue.serverTimestamp()});
    return {...snapshot.data(), attempts, deliveryAttemptId};
  });
  if (!reserved) return;
  const message = reserved;
  let providerAccepted = false;
  async function finish(fields, guestFields) {
    return db.runTransaction(async (tx) => {
      const current = await tx.get(ref);
      if (!current.exists || current.get("status") !== "sending" || current.get("deliveryAttemptId") !== deliveryAttemptId) return false;
      const recipient = await readDeliveryRecipient(db, tx, current.data());
      tx.update(ref, {...fields, deliveryAttemptId: admin.firestore.FieldValue.delete()});
      if (recipient.guest?.exists && recipient.available) tx.update(recipient.guest.ref, guestFields);
      return true;
    });
  }
  try {
    if (message.channel !== "email" || !message.encryptedEmail) {
      throw new Error("Unsupported outbound delivery channel");
    }
    const email = await decryptEmail(message.encryptedEmail);
    const result = await sendEmail(db, ref, message, {value: email});
    providerAccepted = true;
    await finish({...result, status: "accepted",
      acceptedAt: admin.firestore.FieldValue.serverTimestamp(), lastError: null}, {
      deliveryStatus: "accepted", deliveryChannel: message.channel,
      deliveryUpdatedAt: admin.firestore.FieldValue.serverTimestamp()});
  } catch (error) {
    const attempts = Number(message.attempts || 1);
    const uncertain = providerAccepted || error.deliveryUncertain === true;
    const terminal = attempts >= 5 || uncertain || error.deliverySuppressed === true;
    await finish({status: providerAccepted ? "accepted" : uncertain ? "delivery_unknown" : error.deliverySuppressed ? "failed" : terminal ? "dead_letter" : "retry",
      nextAttemptAt: new Date(Date.now() + Math.min(3600000, 30000 * (2 ** attempts))),
      lastError: String(error.message || error).slice(0, 500)}, {deliveryStatus: providerAccepted ? "accepted" : uncertain ? "unknown" : terminal ? "failed" : "retrying",
      deliveryUpdatedAt: admin.firestore.FieldValue.serverTimestamp()});
    logger.warn("Guest confirmation delivery failed", {messageId: ref.id, attempts, terminal,
      error: error.message});
  }
}

function demoDeliveryCaptureEnabled() {
  return process.env.FUNCTIONS_EMULATOR === "true" &&
    process.env.GCLOUD_PROJECT === "demo-attendus-admin" &&
    (!process.env.GOOGLE_CLOUD_PROJECT || process.env.GOOGLE_CLOUD_PROJECT === "demo-attendus-admin") &&
    /^(127\.0\.0\.1|localhost):\d+$/.test(process.env.FIRESTORE_EMULATOR_HOST || "");
}

function createResolveOutboundDeliveryUnknownV1(admin) {
  const db = admin.firestore();
  return onCall({region: "us-central1", enforceAppCheck: process.env.FUNCTIONS_EMULATOR !== "true", maxInstances: 10}, async (request) => {
    const uid = request.auth?.uid;
    if (!uid || request.auth.token?.admin !== true) throw new HttpsError("permission-denied", "Administrator access is required.");
    const {messageId, idempotencyKey, resolution} = request.data || {};
    const reason = typeof request.data?.reason === "string" ? request.data.reason.trim() : "";
    const evidenceReference = typeof request.data?.evidenceReference === "string" ? request.data.evidenceReference.trim() : "";
    if (typeof messageId !== "string" || !/^[A-Za-z0-9._:-]{1,500}$/.test(messageId) ||
        typeof idempotencyKey !== "string" || !/^[A-Za-z0-9._:-]{8,128}$/.test(idempotencyKey) ||
        !["accepted", "failed"].includes(resolution) || reason.length < 10 || reason.length > 1000 ||
        evidenceReference.length < 1 || evidenceReference.length > 500) {
      throw new HttpsError("invalid-argument", "Supply an unknown message, accepted or failed outcome, request key, reason and evidence reference.");
    }
    const id = crypto.createHash("sha256").update(`outbound-resolution\0${uid}\0${idempotencyKey}`).digest("hex");
    const fingerprint = crypto.createHash("sha256").update(JSON.stringify([messageId, resolution, reason, evidenceReference])).digest("hex");
    const ref = db.collection("OutboundMessages").doc(messageId);
    const resolutionRef = db.collection("OutboundDeliveryResolutions").doc(id);
    const auditRef = db.collection("admin_audit_logs").doc(`outbound_resolution_${id}`);
    return db.runTransaction(async (tx) => {
      const [role, deleting, prior, message] = await Promise.all([
        tx.get(db.collection("admin_roles").doc(uid)), tx.get(db.collection("account_deletion_jobs").doc(uid)),
        tx.get(resolutionRef), tx.get(ref),
      ]);
      const roles = Array.isArray(role.get("roles")) ? role.get("roles").filter((value) => ROLES.includes(value)) : [];
      if (!role.exists || role.get("active") !== true || !roles.some((value) => ROLE_PERMISSIONS[value].includes("*") || ROLE_PERMISSIONS[value].includes("communications.mutate"))) {
        throw new HttpsError("permission-denied", "An active communications administrator role is required.");
      }
      if (deleting.exists) throw new HttpsError("failed-precondition", "Administrator account deletion is in progress.");
      if (prior.exists) {
        if (prior.get("fingerprint") !== fingerprint) throw new HttpsError("already-exists", "The request key was already used for a different resolution.");
        return {messageId, status: prior.get("resolution"), resolutionId: id, auditId: auditRef.id};
      }
      if (!message.exists) throw new HttpsError("not-found", "Outbound message not found.");
      if (message.get("status") !== "delivery_unknown") throw new HttpsError("failed-precondition", "Only an unknown delivery outcome can be resolved.");
      if (!(await readDeliveryRecipient(db, tx, message.data())).available) {
        throw new HttpsError("failed-precondition", "The recipient is unavailable or being deleted.");
      }
      const createdAt = admin.firestore.FieldValue.serverTimestamp();
      tx.update(ref, {status: resolution, resolvedAt: createdAt, resolutionId: id, resolutionSource: "operator",
        deliveryAttemptId: admin.firestore.FieldValue.delete(), nextAttemptAt: admin.firestore.FieldValue.delete()});
      tx.create(resolutionRef, {messageId, actorUid: uid, resolution, fingerprint, reason, evidenceReference, createdAt});
      tx.create(auditRef, {actorUid: uid, actorEmail: request.auth.token.email || null, actorRoles: roles,
        action: "communications.delivery_unknown.resolve", targetType: "outbound_message", targetId: messageId,
        reason, requestId: idempotencyKey, before: {status: "delivery_unknown"}, after: {status: resolution},
        metadata: {evidenceReference, resolutionId: id}, createdAt,
        integrityKey: crypto.createHash("sha256").update(`${id}:${uid}:communications.delivery_unknown.resolve:${messageId}`).digest("hex")});
      return {messageId, status: resolution, resolutionId: id, auditId: auditRef.id};
    });
  });
}

async function markAbandonedDeliveryUnknown(admin, ref, cutoff) {
  const db = admin.firestore();
  return db.runTransaction(async (tx) => {
    const current = await tx.get(ref);
    const lastAttempt = current.get("lastAttemptAt")?.toMillis?.();
    if (!current.exists || current.get("status") !== "sending" || !Number.isFinite(lastAttempt) || lastAttempt >= cutoff.getTime()) return false;
    tx.update(ref, {status: "delivery_unknown", deliveryAttemptId: admin.firestore.FieldValue.delete(),
      lastError: "Provider outcome requires review; automatic retry withheld."});
    return true;
  });
}

function createDeliverOutboundMessage(admin) {
  return onDocumentCreated({document: "OutboundMessages/{messageId}", region: "us-central1",
    secrets: DELIVERY_SECRETS, maxInstances: 20}, async (event) => {
    await processMessage(admin, event.data.ref);
  });
}

function createRetryOutboundMessages(admin) {
  return onSchedule({schedule: "every 5 minutes", timeZone: "UTC", region: "us-central1",
    secrets: DELIVERY_SECRETS, timeoutSeconds: 240}, async () => {
    // A crashed send may already have been accepted. Do not blindly send it again.
    const cutoff = new Date(Date.now() - 15 * 60000);
    const abandoned = await admin.firestore().collection("OutboundMessages").where("status", "==", "sending")
        .where("lastAttemptAt", "<", cutoff).limit(100).get();
    for (const doc of abandoned.docs) await markAbandonedDeliveryUnknown(admin, doc.ref, cutoff);
    const snapshot = await admin.firestore().collection("OutboundMessages")
        .where("status", "in", ["pending", "retry"]).where("nextAttemptAt", "<=", new Date())
        .limit(100).get();
    for (const document of snapshot.docs) {
      try { await processMessage(admin, document.ref); }
      catch (error) { logger.error("Outbound job processing failed", {messageId: document.id, code: String(error.code || "unknown")}); }
    }
  });
}

module.exports = {calendarInvite, calendarAttachmentEligible, createDeliverOutboundMessage,
  createRetryOutboundMessages, createResolveOutboundDeliveryUnknownV1, markAbandonedDeliveryUnknown,
  fallbackTemplate, graphAssertion, processMessage, templateFor, requireCurrentDeliveryRecipient, demoDeliveryCaptureEnabled};
