"use strict";

const crypto = require("node:crypto");
const {defineSecret} = require("firebase-functions/params");
const {onDocumentCreated} = require("firebase-functions/v2/firestore");
const {onRequest} = require("firebase-functions/v2/https");
const {onSchedule} = require("firebase-functions/v2/scheduler");
const logger = require("firebase-functions/logger");
const {CONTACT_HMAC_KEY, CONTACT_KMS_KEY_NAME, contactHash, decryptContact,
  normalizeContact} = require("../public-web/accountless");

const MICROSOFT_TENANT_ID = defineSecret("MICROSOFT_TENANT_ID");
const MICROSOFT_CLIENT_ID = defineSecret("MICROSOFT_CLIENT_ID");
const MICROSOFT_CERT_THUMBPRINT = defineSecret("MICROSOFT_CERT_THUMBPRINT");
const MICROSOFT_PRIVATE_KEY = defineSecret("MICROSOFT_PRIVATE_KEY");
const TWILIO_ACCOUNT_SID = defineSecret("TWILIO_ACCOUNT_SID");
const TWILIO_AUTH_TOKEN = defineSecret("TWILIO_AUTH_TOKEN");
const TWILIO_MESSAGING_SERVICE_SID = defineSecret("TWILIO_MESSAGING_SERVICE_SID");
const SUPPORT_EMAIL = "support@attendus.app";
const PUBLIC_ORIGIN = "https://attendus.app";
const DELIVERY_SECRETS = [CONTACT_HMAC_KEY, CONTACT_KMS_KEY_NAME, MICROSOFT_TENANT_ID,
  MICROSOFT_CLIENT_ID, MICROSOFT_CERT_THUMBPRINT, MICROSOFT_PRIVATE_KEY,
  TWILIO_ACCOUNT_SID, TWILIO_AUTH_TOKEN, TWILIO_MESSAGING_SERVICE_SID];

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

function icsEscape(value) {
  return String(value ?? "").replaceAll("\\", "\\\\").replaceAll("\n", "\\n")
      .replaceAll(",", "\\,").replaceAll(";", "\\;");
}

function icsDate(value) {
  const date = value?.toDate ? value.toDate() : new Date(value);
  return date.toISOString().replace(/[-:]/g, "").replace(/\.\d{3}Z$/, "Z");
}

function calendarInvite(message, method = "PUBLISH") {
  const start = message.payload?.eventStart;
  const end = new Date((start?.toDate ? start.toDate() : new Date(start)).getTime() + 2 * 3600000);
  return ["BEGIN:VCALENDAR", "VERSION:2.0", "PRODID:-//Attendus//Guest Registration//EN",
    `METHOD:${method}`, "BEGIN:VEVENT", `UID:${message.registrationId}@attendus.app`,
    `DTSTAMP:${icsDate(new Date())}`, `DTSTART:${icsDate(start)}`, `DTEND:${icsDate(end)}`,
    `SUMMARY:${icsEscape(message.payload?.eventTitle)}`,
    `LOCATION:${icsEscape(message.payload?.eventLocation)}`,
    `URL:${icsEscape(message.payload?.manageUrl)}`, "END:VEVENT", "END:VCALENDAR", ""].join("\r\n");
}

function fallbackTemplate(message) {
  const payload = message.payload || {};
  const cancelled = message.templateId === "guest_registration_cancelled";
  const subject = cancelled ? `Registration cancelled: ${payload.eventTitle}` :
    `You're confirmed for ${payload.eventTitle}`;
  const action = cancelled ? "Your registration has been cancelled." :
    `Your ${message.payload?.kind === "rsvp" ? "RSVP" : "ticket"} is confirmed.`;
  const text = `Hi ${payload.firstName || "there"}, ${action} ${payload.eventTitle}. ` +
    `${cancelled ? "" : `View your registration: ${payload.manageUrl}`}`;
  const html = `<h1>${escapeHtml(subject)}</h1><p>Hi ${escapeHtml(payload.firstName || "there")},</p>` +
    `<p>${escapeHtml(action)}</p><p><strong>${escapeHtml(payload.eventTitle)}</strong></p>` +
    (cancelled ? "" : `<p><a href="${escapeHtml(payload.manageUrl)}">View ticket and registration</a></p>`) +
    `<p>Questions? Contact <a href="mailto:${SUPPORT_EMAIL}">${SUPPORT_EMAIL}</a>.</p>`;
  const sms = `Attendus: ${action} ${payload.eventTitle}. ${cancelled ? "" : payload.manageUrl} ` +
    `Help: ${SUPPORT_EMAIL}. Reply STOP to opt out.`;
  return {subject, text, html, sms};
}

async function templateFor(db, message) {
  const snapshot = await db.collection("CommunicationTemplates").doc(message.templateId).get();
  if (!snapshot.exists || snapshot.get("status") !== "published") return fallbackTemplate(message);
  const fallback = fallbackTemplate(message);
  const values = {firstName: message.payload?.firstName || "there",
    eventTitle: message.payload?.eventTitle || "Event", manageUrl: message.payload?.manageUrl || "",
    supportEmail: SUPPORT_EMAIL};
  const render = (source) => String(source || "").replace(/\{\{(firstName|eventTitle|manageUrl|supportEmail)\}\}/g,
      (_, key) => values[key]);
  return {subject: render(snapshot.get("subject")) || fallback.subject,
    text: render(snapshot.get("text")) || fallback.text,
    html: render(snapshot.get("html")) || fallback.html,
    sms: render(snapshot.get("sms")) || fallback.sms};
}

async function sendEmail(db, message, contact) {
  const template = await templateFor(db, message);
  const token = await graphAccessToken();
  const invite = calendarInvite(message,
      message.templateId === "guest_registration_cancelled" ? "CANCEL" : "PUBLISH");
  const response = await fetch(`https://graph.microsoft.com/v1.0/users/${encodeURIComponent(SUPPORT_EMAIL)}/sendMail`, {
    method: "POST", headers: {authorization: `Bearer ${token}`, "content-type": "application/json"},
    body: JSON.stringify({message: {subject: template.subject,
      body: {contentType: "HTML", content: template.html},
      toRecipients: [{emailAddress: {address: contact.value}}],
      attachments: [{"@odata.type": "#microsoft.graph.fileAttachment",
        name: "attendus-event.ics", contentType: "text/calendar; method=PUBLISH",
        contentBytes: Buffer.from(invite).toString("base64")}]} , saveToSentItems: true}),
  });
  if (response.status !== 202) throw new Error(`Microsoft Graph rejected email (${response.status})`);
  return {provider: "microsoft_graph", providerStatus: "accepted"};
}

async function sendSms(db, message, contact) {
  const suppress = await db.collection("CommunicationSuppressions")
      .doc(contactHash(contact)).get();
  if (suppress.exists && suppress.get("smsSuppressed") === true) {
    throw new Error("SMS contact is suppressed");
  }
  const twilio = require("twilio")(secret(TWILIO_ACCOUNT_SID, "Twilio account"),
      secret(TWILIO_AUTH_TOKEN, "Twilio authentication"));
  const template = await templateFor(db, message);
  const result = await twilio.messages.create({to: contact.value,
    messagingServiceSid: secret(TWILIO_MESSAGING_SERVICE_SID, "Twilio Messaging Service"),
    body: template.sms, statusCallback: `${PUBLIC_ORIGIN}/communications/sms-status`});
  return {provider: "twilio", providerStatus: result.status || "accepted", providerMessageId: result.sid};
}

async function processMessage(admin, ref) {
  const db = admin.firestore();
  let reserved = false;
  await db.runTransaction(async (transaction) => {
    const snapshot = await transaction.get(ref);
    if (!snapshot.exists || !["pending", "retry"].includes(snapshot.get("status"))) return;
    const next = snapshot.get("nextAttemptAt")?.toDate?.();
    if (next && next > new Date()) return;
    reserved = true;
    transaction.update(ref, {status: "sending", attempts: Number(snapshot.get("attempts") || 0) + 1,
      lastAttemptAt: admin.firestore.FieldValue.serverTimestamp()});
  });
  if (!reserved) return;
  const snapshot = await ref.get();
  const message = snapshot.data();
  try {
    const contact = await decryptContact(message.encryptedContact);
    const result = message.channel === "sms" ? await sendSms(db, message, contact) :
      await sendEmail(db, message, contact);
    await ref.update({...result, status: "accepted",
      acceptedAt: admin.firestore.FieldValue.serverTimestamp(), lastError: null});
    if (message.guestId) await db.collection("GuestAttendees").doc(message.guestId).set({
      deliveryStatus: "accepted", deliveryChannel: message.channel,
      deliveryUpdatedAt: admin.firestore.FieldValue.serverTimestamp()}, {merge: true});
  } catch (error) {
    const attempts = Number(message.attempts || 1);
    const terminal = attempts >= 5;
    await ref.update({status: terminal ? "dead_letter" : "retry",
      nextAttemptAt: new Date(Date.now() + Math.min(3600000, 30000 * (2 ** attempts))),
      lastError: String(error.message || error).slice(0, 500)});
    if (message.guestId) await db.collection("GuestAttendees").doc(message.guestId).set({
      deliveryStatus: terminal ? "failed" : "retrying",
      deliveryUpdatedAt: admin.firestore.FieldValue.serverTimestamp()}, {merge: true});
    logger.warn("Guest confirmation delivery failed", {messageId: ref.id, attempts, terminal,
      error: error.message});
  }
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
    const snapshot = await admin.firestore().collection("OutboundMessages")
        .where("status", "in", ["pending", "retry"]).where("nextAttemptAt", "<=", new Date())
        .limit(100).get();
    for (const document of snapshot.docs) await processMessage(admin, document.ref);
  });
}

function createTwilioStatusCallback(admin) {
  return onRequest({region: "us-central1", invoker: "public", secrets: [TWILIO_AUTH_TOKEN],
    maxInstances: 20}, async (req, res) => {
    if (req.method !== "POST") return res.status(405).send("Method not allowed");
    const signature = req.get("x-twilio-signature");
    const valid = require("twilio").validateRequest(secret(TWILIO_AUTH_TOKEN, "Twilio authentication"),
        signature, `${PUBLIC_ORIGIN}/communications/sms-status`, req.body || {});
    if (!valid) return res.status(403).send("Invalid signature");
    const sid = String(req.body.MessageSid || "");
    const status = String(req.body.MessageStatus || "unknown");
    const snapshot = await admin.firestore().collection("OutboundMessages")
        .where("providerMessageId", "==", sid).limit(1).get();
    if (!snapshot.empty) await snapshot.docs[0].ref.update({providerStatus: status,
      status: ["failed", "undelivered"].includes(status) ? "failed" :
        status === "delivered" ? "delivered" : "accepted",
      providerUpdatedAt: admin.firestore.FieldValue.serverTimestamp(),
      providerErrorCode: req.body.ErrorCode || null});
    return res.status(204).send("");
  });
}

function createTwilioInbound(admin) {
  return onRequest({region: "us-central1", invoker: "public",
    secrets: [TWILIO_AUTH_TOKEN, CONTACT_HMAC_KEY], maxInstances: 20}, async (req, res) => {
    if (req.method !== "POST") return res.status(405).send("Method not allowed");
    const signature = req.get("x-twilio-signature");
    const valid = require("twilio").validateRequest(secret(TWILIO_AUTH_TOKEN, "Twilio authentication"),
        signature, `${PUBLIC_ORIGIN}/communications/sms-inbound`, req.body || {});
    if (!valid) return res.status(403).send("Invalid signature");
    let contact;
    try {
      contact = normalizeContact("phone", String(req.body.From || ""));
    } catch (_) {
      return res.status(200).type("text/xml").send("<Response></Response>");
    }
    const command = String(req.body.Body || "").trim().toUpperCase();
    const ref = admin.firestore().collection("CommunicationSuppressions").doc(contactHash(contact));
    if (["STOP", "STOPALL", "UNSUBSCRIBE", "CANCEL", "END", "QUIT"].includes(command)) {
      await ref.set({smsSuppressed: true, source: "twilio_inbound",
        updatedAt: admin.firestore.FieldValue.serverTimestamp()}, {merge: true});
    } else if (["START", "UNSTOP"].includes(command)) {
      await ref.set({smsSuppressed: false, source: "twilio_inbound",
        updatedAt: admin.firestore.FieldValue.serverTimestamp()}, {merge: true});
    }
    return res.status(200).type("text/xml").send("<Response></Response>");
  });
}

module.exports = {calendarInvite, createDeliverOutboundMessage,
  createRetryOutboundMessages, createTwilioInbound, createTwilioStatusCallback,
  fallbackTemplate, graphAssertion, processMessage};
