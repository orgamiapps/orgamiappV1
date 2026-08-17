"use strict";

const crypto = require("node:crypto");
const {onRequest} = require("firebase-functions/v2/https");
const {onDocumentWritten} = require("firebase-functions/v2/firestore");
const logger = require("firebase-functions/logger");
const QRCode = require("qrcode");
const {CONTACT_HMAC_KEY, CONTACT_KMS_KEY_NAME, contactHash, digest,
  encryptContact, maskedContact, normalizeContact} = require("./accountless");

const PUBLIC_ORIGIN = "https://attendus.app";
const PAGE_SIZE = 10000;
const INDEXABLE_EVENT_STATUSES = new Set([
  "active", "scheduled", "completed", "cancelled", "canceled",
]);
const FALLBACK_IMAGE = `${PUBLIC_ORIGIN}/public-web/v1/event-fallback.png`;

function text(value) {
  return String(value ?? "").trim();
}

function escapeHtml(value) {
  return text(value)
      .replaceAll("&", "&amp;")
      .replaceAll("<", "&lt;")
      .replaceAll(">", "&gt;")
      .replaceAll("\"", "&quot;")
      .replaceAll("'", "&#39;");
}

function escapeXml(value) {
  return escapeHtml(value);
}

function safeJson(value) {
  return JSON.stringify(value)
      .replaceAll("<", "\\u003c")
      .replaceAll(">", "\\u003e")
      .replaceAll("&", "\\u0026");
}

function safeUrl(value, fallback = "") {
  try {
    const parsed = new URL(text(value));
    return parsed.protocol === "https:" ? parsed.toString() : fallback;
  } catch (_) {
    return fallback;
  }
}

function asDate(value) {
  if (!value) return null;
  if (typeof value.toDate === "function") return value.toDate();
  const parsed = new Date(value);
  return Number.isNaN(parsed.getTime()) ? null : parsed;
}

function validTimeZone(value) {
  const candidate = text(value) || "UTC";
  try {
    new Intl.DateTimeFormat("en-US", {timeZone: candidate}).format(new Date());
    return candidate;
  } catch (_) {
    return "UTC";
  }
}

function isoInTimeZone(date, timeZone) {
  const zone = validTimeZone(timeZone);
  const parts = new Intl.DateTimeFormat("en-US", {
    timeZone: zone,
    year: "numeric",
    month: "2-digit",
    day: "2-digit",
    hour: "2-digit",
    minute: "2-digit",
    second: "2-digit",
    hourCycle: "h23",
    timeZoneName: "longOffset",
  }).formatToParts(date);
  const part = (type) => parts.find((entry) => entry.type === type)?.value || "";
  const offsetName = part("timeZoneName");
  const offset = offsetName === "GMT" ? "Z" : offsetName.replace("GMT", "");
  return `${part("year")}-${part("month")}-${part("day")}T` +
    `${part("hour")}:${part("minute")}:${part("second")}${offset}`;
}

function eventEligibility(data) {
  if (!data || data.private === true) return false;
  return Boolean(text(data.title) && asDate(data.selectedDateTime) &&
    INDEXABLE_EVENT_STATUSES.has(text(data.status).toLowerCase()));
}

function communityEligibility(data) {
  return Boolean(data && data.publicPageEnabled === true && text(data.name));
}

function eventEnd(data) {
  const start = asDate(data.selectedDateTime);
  if (!start) return null;
  const duration = Math.max(1, Number(data.eventDuration || 2));
  return new Date(start.getTime() + duration * 3600000);
}

function eventState(data, now = new Date()) {
  const status = text(data.status).toLowerCase();
  if (status === "cancelled" || status === "canceled") return "cancelled";
  const end = eventEnd(data);
  return end && end <= now ? "ended" : "scheduled";
}

function ticketState(data, now = new Date()) {
  const state = eventState(data, now);
  if (state !== "scheduled") return {state, label: state === "ended" ? "Event ended" : "Cancelled"};
  if (data.ticketsEnabled === true) {
    const maximum = Number(data.maxTickets || 0);
    const committed = Number(data.issuedTickets || 0);
    const reserved = Number(data.reservedTickets || 0);
    if (maximum > 0 && committed + reserved >= maximum) {
      return {state: "sold_out", label: "Sold out"};
    }
    const price = Math.max(0, Number(data.ticketPrice || 0));
    return price > 0 ? {
      state: "paid_ticket",
      action: "ticket",
      label: `Buy ticket · $${price.toFixed(2)}`,
      price,
    } : {state: "free_ticket", action: "ticket", label: "Get free ticket", price: 0};
  }
  return {state: "rsvp", action: "rsvp", label: "RSVP"};
}

function formatDate(date, timeZone) {
  return new Intl.DateTimeFormat("en-US", {
    timeZone: validTimeZone(timeZone),
    weekday: "long",
    month: "long",
    day: "numeric",
    year: "numeric",
    hour: "numeric",
    minute: "2-digit",
    timeZoneName: "short",
  }).format(date);
}

function description(value, maximum = 200) {
  const compact = text(value).replace(/\s+/g, " ");
  return compact.length <= maximum ? compact : `${compact.slice(0, maximum - 1)}…`;
}

function pageHeaders(res, nonce) {
  const sources = [
    "default-src 'self'",
    `script-src 'self' 'nonce-${nonce}' https://www.gstatic.com https://js.stripe.com`,
    "style-src 'self' 'unsafe-inline'",
    "img-src 'self' https: data:",
    "connect-src 'self' https://*.googleapis.com https://*.firebaseio.com " +
      "https://identitytoolkit.googleapis.com https://securetoken.googleapis.com " +
      "https://www.googleapis.com https://api.stripe.com",
    "frame-src https://accounts.google.com https://*.firebaseapp.com " +
      "https://js.stripe.com https://hooks.stripe.com https://www.google.com",
    "font-src 'self' data:",
    "base-uri 'self'",
    "form-action 'self'",
    "frame-ancestors 'none'",
    "object-src 'none'",
    "upgrade-insecure-requests",
  ];
  res.set("Content-Security-Policy", sources.join("; "));
  res.set("Referrer-Policy", "strict-origin-when-cross-origin");
  res.set("X-Content-Type-Options", "nosniff");
  res.set("Permissions-Policy", "camera=(), microphone=(), geolocation=()");
  res.set("Cache-Control", "private, no-cache, no-store, must-revalidate");
  res.set("Content-Type", "text/html; charset=utf-8");
}

function shell({title, summary, canonical, image, body, jsonLd, config, nonce}) {
  const safeTitle = escapeHtml(`${title} | Attendus`);
  const safeSummary = escapeHtml(description(summary));
  const safeCanonical = escapeHtml(canonical);
  const safeImage = escapeHtml(safeUrl(image, FALLBACK_IMAGE));
  return `<!doctype html>
<html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>${safeTitle}</title><meta name="description" content="${safeSummary}">
<link rel="canonical" href="${safeCanonical}"><meta name="robots" content="index,follow,max-image-preview:large">
<meta property="og:type" content="website"><meta property="og:site_name" content="Attendus"><meta property="og:locale" content="en_US">
<meta property="og:title" content="${safeTitle}"><meta property="og:description" content="${safeSummary}">
<meta property="og:url" content="${safeCanonical}"><meta property="og:image" content="${safeImage}">
<meta name="twitter:card" content="summary_large_image"><meta name="twitter:title" content="${safeTitle}">
<meta name="twitter:description" content="${safeSummary}"><meta name="twitter:image" content="${safeImage}">
<link rel="icon" href="/favicon.png"><link rel="stylesheet" href="/public-web/v1/public.css"><link rel="stylesheet" href="/public-web/v1/registration.css">
<script type="application/ld+json" nonce="${nonce}">${safeJson(jsonLd)}</script></head>
<body><a class="skip-link" href="#main">Skip to event details</a>
<header class="site-header"><a class="brand" href="/" aria-label="Attendus home"><img src="/icons/Icon-192.png" alt="" width="36" height="36"><span>Attendus</span></a></header>
${body}<footer class="site-footer"><span>Attendus</span><a href="/privacy">Privacy</a><a href="/terms">Terms</a></footer>
<script id="attendus-public-config" type="application/json" nonce="${nonce}">${safeJson(config)}</script>
<script src="/public-web/v1/actions.js" defer></script></body></html>`;
}

function organizerFor(event, organization) {
  if (organization && communityEligibility(organization)) {
    return {
      name: text(organization.name),
      url: `${PUBLIC_ORIGIN}/community/${encodeURIComponent(text(event.organizationId))}`,
    };
  }
  return {name: text(event.groupName || event.authorName || "Attendus organizer")};
}

function eventDescription(data, organization) {
  const supplied = description(data.description, 5000);
  if (supplied) return supplied;
  const organizer = organizerFor(data, organization);
  return `View date, location, and attendance details for ${text(data.title)}, ` +
    `organized by ${organizer.name} on Attendus.`;
}

function categoryLabel(value) {
  return text(value).split(/[-_]/).filter(Boolean)
      .map((part) => part.charAt(0).toUpperCase() + part.slice(1)).join(" & ");
}

function eventJsonLd(id, data, organization, now = new Date()) {
  const start = asDate(data.selectedDateTime);
  const end = eventEnd(data);
  const zone = validTimeZone(data.eventTimeZone);
  const canonical = `${PUBLIC_ORIGIN}/event/${encodeURIComponent(id)}`;
  const state = eventState(data, now);
  const ticket = ticketState(data, now);
  const organizer = organizerFor(data, organization);
  const location = data.locationType === "online" ? {
    "@type": "VirtualLocation",
    "url": canonical,
  } : {
    "@type": "Place",
    "name": text(data.locationName || data.location),
    "address": {
      "@type": "PostalAddress",
      "streetAddress": text(data.streetAddress || data.location),
      "addressLocality": text(data.city),
      "addressRegion": text(data.regionCode),
      "postalCode": text(data.postalCode),
      "addressCountry": text(data.countryCode || "US"),
    },
  };
  const result = {
    "@context": "https://schema.org",
    "@type": "Event",
    "name": text(data.title),
    "description": eventDescription(data, organization),
    "url": canonical,
    "image": [safeUrl(data.imageUrl, FALLBACK_IMAGE)],
    "startDate": isoInTimeZone(start, zone),
    "endDate": isoInTimeZone(end, zone),
    "eventStatus": state === "cancelled" ?
      "https://schema.org/EventCancelled" : "https://schema.org/EventScheduled",
    "eventAttendanceMode": data.locationType === "online" ?
      "https://schema.org/OnlineEventAttendanceMode" :
      "https://schema.org/OfflineEventAttendanceMode",
    location,
    "organizer": {"@type": "Organization", ...organizer},
  };
  if (state === "scheduled") {
    result.offers = {
      "@type": "Offer",
      "url": canonical,
      "price": ticket.price ?? 0,
      "priceCurrency": "USD",
      "availability": ticket.state === "sold_out" ?
        "https://schema.org/SoldOut" : "https://schema.org/InStock",
    };
  }
  return result;
}

function eventBody(id, data, organization, config, now = new Date()) {
  const start = asDate(data.selectedDateTime);
  const zone = validTimeZone(data.eventTimeZone);
  const ticket = ticketState(data, now);
  const organizer = organizerFor(data, organization);
  const appUrl = `/app/event/${encodeURIComponent(id)}?action=${ticket.action || "view"}`;
  const location = data.locationType === "online" ? "Online event" :
    text(data.locationName || data.location || [data.city, data.regionCode]
        .filter(Boolean).join(", "));
  const category = categoryLabel(data.primaryDiscoveryCategoryId ||
    (Array.isArray(data.categories) ? data.categories[0] : ""));
  const disabled = !ticket.action;
  const actionAttrs = disabled ? "aria-disabled=\"true\"" :
    `href="${escapeHtml(appUrl)}" data-public-action="${ticket.action}" ` +
    `data-event-id="${escapeHtml(id)}"`;
  const organizerMarkup = organizer.url ?
    `<a href="${escapeHtml(organizer.url)}">${escapeHtml(organizer.name)}</a>` :
    escapeHtml(organizer.name);
  const action = `<a class="cta ${disabled ? "disabled" : ""}" ${actionAttrs}>` +
    `${escapeHtml(ticket.label)}</a>`;
  return `<main id="main" class="page"><article class="event-layout">
<section class="event-content"><div class="hero"><img src="${escapeHtml(safeUrl(data.imageUrl, FALLBACK_IMAGE))}" alt="${escapeHtml(text(data.title))}" width="1200" height="800" fetchpriority="high"></div>
<div class="eyebrow">${escapeHtml(category || "Event")}</div><h1>${escapeHtml(data.title)}</h1>
<p class="lead">${escapeHtml(eventDescription(data, organization))}</p><section aria-labelledby="details-heading"><h2 id="details-heading">Event details</h2>
<dl class="details"><div><dt>Date and time</dt><dd><time datetime="${escapeHtml(isoInTimeZone(start, zone))}">${escapeHtml(formatDate(start, zone))}</time></dd></div>
<div><dt>Location</dt><dd>${data.locationType === "online" ? escapeHtml(location) : `<address>${escapeHtml(location)}</address>`}</dd></div>
<div><dt>Organizer</dt><dd>${organizerMarkup}</dd></div></dl></section></section>
<aside class="registration" aria-labelledby="registration-heading"><div class="registration-card"><h2 id="registration-heading">Attend this event</h2>
<p>${escapeHtml(ticket.label)}</p>${action}<p class="fine-print">Secure registration through Attendus.</p></div></aside></article></main>
<div class="mobile-cta">${action}</div><p id="public-action-status" class="sr-only" aria-live="polite"></p>`;
}

function notFound(res, nonce) {
  pageHeaders(res, nonce);
  res.set("X-Robots-Tag", "noindex, nofollow");
  res.status(404).send(`<!doctype html><html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><meta name="robots" content="noindex,nofollow"><title>Page not found | Attendus</title><link rel="stylesheet" href="/public-web/v1/public.css"></head><body><main class="not-found"><h1>Page not found</h1><p>This page is unavailable.</p><a class="cta" href="/">Discover events</a></main></body></html>`);
}

function cookies(req) {
  return Object.fromEntries(String(req.get("cookie") || "").split(";")
      .map((part) => part.trim().split("="))
      .filter((parts) => parts.length === 2)
      .map(([key, value]) => [key, decodeURIComponent(value)]));
}

async function manageSession(db, req) {
  const raw = cookies(req).attendus_guest_manage;
  if (!raw || !/^[A-Za-z0-9_-]{32,200}$/.test(raw)) return null;
  const snapshot = await db.collection("GuestManageSessions")
      .doc(crypto.createHash("sha256").update(raw).digest("hex")).get();
  if (!snapshot.exists || snapshot.get("status") !== "active") return null;
  const expires = asDate(snapshot.get("expiresAt"));
  return !expires || expires <= new Date() ? null : {ref: snapshot.ref, ...snapshot.data()};
}

async function exchangeManageToken(db, req, res, raw, nonce) {
  if (!/^[A-Za-z0-9_-]{32,200}$/.test(raw)) return notFound(res, nonce);
  const tokenRef = db.collection("GuestManageTokens")
      .doc(crypto.createHash("sha256").update(raw).digest("hex"));
  const sessionRaw = crypto.randomBytes(32).toString("base64url");
  const sessionRef = db.collection("GuestManageSessions")
      .doc(crypto.createHash("sha256").update(sessionRaw).digest("hex"));
  let accepted = false;
  await db.runTransaction(async (transaction) => {
    const token = await transaction.get(tokenRef);
    const expires = token.exists ? asDate(token.get("expiresAt")) : null;
    if (!token.exists || token.get("status") !== "active" || !expires || expires <= new Date()) return;
    accepted = true;
    const csrfToken = crypto.randomBytes(24).toString("base64url");
    transaction.update(tokenRef, {status: "exchanged", exchangedAt: new Date()});
    transaction.create(sessionRef, {status: "active", registrationId: token.get("registrationId"),
      guestId: token.get("guestId"), csrfToken, createdAt: new Date(),
      expiresAt: new Date(Date.now() + 2 * 3600000)});
    transaction.set(db.collection("GuestAttendees").doc(token.get("guestId")), {
      verificationStatus: "verified", verifiedAt: new Date(),
    }, {merge: true});
  });
  if (!accepted) return notFound(res, nonce);
  res.set("Set-Cookie", `attendus_guest_manage=${encodeURIComponent(sessionRaw)}; Path=/manage; Max-Age=7200; HttpOnly; Secure; SameSite=Strict`);
  res.set("Cache-Control", "no-store");
  return res.redirect(303, "/manage");
}

async function manageData(db, session) {
  const registration = await db.collection("RegisterAttendance")
      .doc(session.registrationId).get();
  if (!registration.exists || registration.get("guestId") !== session.guestId) return null;
  const event = await db.collection("Events").doc(registration.get("eventId")).get();
  if (!event.exists) return null;
  const tickets = await db.collection("Tickets").where("eventId", "==", event.id)
      .where("guestId", "==", session.guestId).limit(1).get();
  const guest = await db.collection("GuestAttendees").doc(session.guestId).get();
  return {registration, event, ticket: tickets.empty ? null : tickets.docs[0], guest};
}

function managePage(res, nonce, data, session, notice = "") {
  pageHeaders(res, nonce);
  res.set("X-Robots-Tag", "noindex, nofollow");
  const event = data.event.data();
  const registration = data.registration.data();
  const ticket = data.ticket?.data();
  const guest = data.guest.data() || {};
  const cancelled = registration.status === "cancelled" || ticket?.revoked === true;
  const paid = ticket?.isPaid === true;
  const cancel = !cancelled && !paid && eventStartForManage(event) > new Date() ?
    `<form method="post" action="/manage/action"><input type="hidden" name="csrf" value="${escapeHtml(session.csrfToken)}"><input type="hidden" name="action" value="cancel"><button class="secondary-button danger" type="submit">Cancel registration</button></form>` : "";
  const ticketMarkup = ticket ? `<section class="manage-ticket" aria-labelledby="ticket-heading"><h2 id="ticket-heading">Your ticket</h2><div class="ticket-code"><span>Ticket code</span><strong>${escapeHtml(ticket.ticketCode)}</strong><img src="/manage/ticket.svg" width="220" height="220" alt="QR ticket code ${escapeHtml(ticket.ticketCode)}"></div><button class="secondary-button print-ticket" type="button">Print ticket</button></section>` : "";
  const contactForm = `<details class="contact-update"><summary>Update confirmation contact</summary><form method="post" action="/manage/action"><input type="hidden" name="csrf" value="${escapeHtml(session.csrfToken)}"><input type="hidden" name="action" value="update_contact"><label>Contact method <select name="contactType"><option value="email">Email</option><option value="phone">U.S. mobile</option></select></label><label>Email or phone <input name="contactValue" required maxlength="254"></label><p class="sms-consent">If you choose mobile, you agree to transactional Attendus texts for this registration. Message and data rates may apply. Reply STOP to opt out or HELP for help.</p><button class="secondary-button" type="submit">Update and resend</button></form></details>`;
  const body = `<main id="main" class="page manage-page"><article><div class="eyebrow">Guest registration</div><h1>${escapeHtml(event.title)}</h1>${notice ? `<p class="notice" role="status">${escapeHtml(notice)}</p>` : ""}<dl class="details"><div><dt>Status</dt><dd>${cancelled ? "Cancelled" : "Confirmed"}</dd></div><div><dt>Attendee</dt><dd>${escapeHtml(registration.realName || registration.userName)}</dd></div><div><dt>Contact</dt><dd>${escapeHtml(guest.maskedContact || "Protected")}</dd></div><div><dt>Date</dt><dd>${escapeHtml(formatDate(eventStartForManage(event), validTimeZone(event.eventTimeZone)))}</dd></div></dl>${ticketMarkup}<div class="manage-actions"><a class="secondary-button" href="/manage/calendar.ics">Download calendar invite</a><a class="secondary-button" href="/event/${encodeURIComponent(data.event.id)}">View event</a>${cancel}</div>${contactForm}${paid ? `<p>Paid ticket refunds are handled by the organizer or <a href="mailto:support@attendus.app">support@attendus.app</a>.</p>` : ""}</article></main>`;
  res.status(200).send(`<!doctype html><html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><meta name="robots" content="noindex,nofollow"><title>Manage registration | Attendus</title><link rel="stylesheet" href="/public-web/v1/public.css"><link rel="stylesheet" href="/public-web/v1/registration.css"></head><body><a class="skip-link" href="#main">Skip to registration</a><header class="site-header"><a class="brand" href="/"><img src="/icons/Icon-192.png" alt="" width="36" height="36"><span>Attendus</span></a></header>${body}<script nonce="${nonce}">document.querySelector('.print-ticket')?.addEventListener('click',()=>window.print());</script></body></html>`);
}

function eventStartForManage(event) {
  return asDate(event.selectedDateTime) || new Date(0);
}

async function renderManage(db, req, res, nonce) {
  const session = await manageSession(db, req);
  if (!session) return notFound(res, nonce);
  const data = await manageData(db, session);
  if (!data) return notFound(res, nonce);
  return managePage(res, nonce, data, session);
}

async function manageCalendar(db, req, res, nonce) {
  const session = await manageSession(db, req);
  if (!session) return notFound(res, nonce);
  const data = await manageData(db, session);
  if (!data) return notFound(res, nonce);
  const event = data.event.data();
  const start = eventStartForManage(event);
  const end = eventEnd(event);
  const format = (date) => date.toISOString().replace(/[-:]/g, "").replace(/\.\d{3}Z$/, "Z");
  const clean = (value) => String(value || "").replaceAll("\\", "\\\\")
      .replaceAll("\n", "\\n").replaceAll(",", "\\,").replaceAll(";", "\\;");
  const method = data.registration.get("status") === "cancelled" ? "CANCEL" : "PUBLISH";
  const content = ["BEGIN:VCALENDAR", "VERSION:2.0", "PRODID:-//Attendus//Registration//EN",
    `METHOD:${method}`, "BEGIN:VEVENT", `UID:${data.registration.id}@attendus.app`,
    `DTSTAMP:${format(new Date())}`, `DTSTART:${format(start)}`, `DTEND:${format(end)}`,
    `SUMMARY:${clean(event.title)}`, `LOCATION:${clean(event.location)}`,
    `URL:${PUBLIC_ORIGIN}/event/${data.event.id}`, "END:VEVENT", "END:VCALENDAR", ""].join("\r\n");
  res.set("Cache-Control", "no-store"); res.set("X-Robots-Tag", "noindex, nofollow");
  res.set("Content-Disposition", "attachment; filename=attendus-event.ics");
  return res.type("text/calendar").send(content);
}

async function manageTicketQr(db, req, res, nonce) {
  const session = await manageSession(db, req);
  if (!session) return notFound(res, nonce);
  const data = await manageData(db, session);
  const code = data?.ticket?.get("ticketCode");
  if (!code) return notFound(res, nonce);
  const svg = await QRCode.toString(code, {type: "svg", margin: 1, width: 220,
    errorCorrectionLevel: "M"});
  res.set("Cache-Control", "private, no-store");
  res.set("X-Robots-Tag", "noindex, nofollow");
  return res.type("image/svg+xml").send(svg);
}

async function manageAction(db, req, res, nonce) {
  const session = await manageSession(db, req);
  if (!session || req.body?.csrf !== session.csrfToken ||
      !["cancel", "update_contact"].includes(req.body?.action)) {
    return notFound(res, nonce);
  }
  const data = await manageData(db, session);
  if (!data) return notFound(res, nonce);
  if (req.body.action === "update_contact") {
    try {
      const contact = normalizeContact(req.body.contactType, req.body.contactValue);
      const hash = contactHash(contact);
      const encrypted = await encryptContact(contact);
      const guest = data.guest.data();
      const oldClaim = db.collection("GuestEventContactClaims")
          .doc(digest(data.event.id, guest.contactHash));
      const newClaim = db.collection("GuestEventContactClaims").doc(digest(data.event.id, hash));
      await db.runTransaction(async (transaction) => {
        const collision = await transaction.get(newClaim);
        if (collision.exists && collision.get("guestId") !== data.guest.id) {
          throw new Error("That contact already has a registration.");
        }
        transaction.set(newClaim, {eventId: data.event.id, guestId: data.guest.id,
          registrationId: data.registration.id, contactHash: hash,
          status: data.registration.get("status"), updatedAt: new Date()});
        if (oldClaim.id !== newClaim.id) transaction.delete(oldClaim);
        transaction.update(data.guest.ref, {contactType: contact.type, contactHash: hash,
          encryptedContact: encrypted, maskedContact: maskedContact(contact),
          transactionalSmsConsent: contact.type === "phone",
          smsConsentAt: contact.type === "phone" ? new Date() : null,
          verificationStatus: "pending", verifiedAt: null, updatedAt: new Date()});
      });
      const rawToken = crypto.randomBytes(32).toString("base64url");
      const tokenId = crypto.createHash("sha256").update(rawToken).digest("hex");
      const messageId = `resend_${crypto.randomUUID()}`;
      await Promise.all([
        db.collection("GuestManageTokens").doc(tokenId).set({guestId: data.guest.id,
          registrationId: data.registration.id, ownerUid: "contact_proof_only", status: "active",
          createdAt: new Date(), expiresAt: new Date(Date.now() + 72 * 3600000)}),
        db.collection("OutboundMessages").doc(messageId).set({id: messageId,
          templateId: "guest_registration_confirmation",
          channel: contact.type === "phone" ? "sms" : "email", status: "pending", attempts: 0,
          registrationId: data.registration.id, guestId: data.guest.id, eventId: data.event.id,
          encryptedContact: encrypted, maskedContact: maskedContact(contact), payload: {
            firstName: data.guest.get("firstName"), eventTitle: data.event.get("title"),
            eventStart: data.event.get("selectedDateTime"), eventLocation: data.event.get("location"),
            kind: data.ticket ? "ticket" : "rsvp",
            manageUrl: `${PUBLIC_ORIGIN}/manage/${rawToken}`}, createdAt: new Date(),
          nextAttemptAt: new Date()}),
      ]);
      return managePage(res, nonce, await manageData(db, session), session,
          "Contact updated. A new confirmation is being sent.");
    } catch (error) {
      return managePage(res, nonce, data, session,
          error.message || "Contact could not be updated.");
    }
  }
  if (eventStartForManage(data.event.data()) <= new Date() || data.ticket?.get("isPaid") === true) {
    return managePage(res, nonce, data, session, "This registration cannot be cancelled online.");
  }
  await db.runTransaction(async (transaction) => {
    const current = await transaction.get(data.registration.ref);
    if (!current.exists || current.get("status") === "cancelled") return;
    transaction.update(data.registration.ref, {status: "cancelled", cancelledAt: new Date(),
      cancellationSource: "guest_manage_page"});
    if (data.ticket && data.ticket.get("revoked") !== true) {
      transaction.update(data.ticket.ref, {revoked: true, revokedReason: "guest_cancelled",
        revokedAt: new Date()});
      transaction.update(data.event.ref, {issuedTickets:
        require("firebase-admin/firestore").FieldValue.increment(-1)});
    }
  });
  const guest = data.guest.data();
  if (guest.encryptedContact) {
    const messageId = `cancellation_${data.registration.id}`;
    await db.collection("OutboundMessages").doc(messageId).set({id: messageId,
      templateId: "guest_registration_cancelled",
      channel: guest.contactType === "phone" ? "sms" : "email", status: "pending", attempts: 0,
      registrationId: data.registration.id, guestId: data.guest.id, eventId: data.event.id,
      encryptedContact: guest.encryptedContact, maskedContact: guest.maskedContact,
      payload: {firstName: guest.firstName, eventTitle: data.event.get("title"),
        eventStart: data.event.get("selectedDateTime"), eventLocation: data.event.get("location")},
      createdAt: new Date(), nextAttemptAt: new Date()});
  }
  const refreshed = await manageData(db, session);
  return managePage(res, nonce, refreshed, session, "Your registration has been cancelled.");
}

async function configFor(db) {
  const snapshot = await db.collection("AppConfig").doc("publicWeb").get();
  const data = snapshot.data() || {};
  return {
    publicPagesEnabled: data.publicPagesEnabled === true,
    inlineRegistrationEnabled: data.inlineRegistrationEnabled === true,
    accountlessRegistrationEnabled: data.accountlessRegistrationEnabled === true,
    paidTicketCheckoutEnabled: data.paidTicketCheckoutEnabled === true,
    appCheckSiteKey: text(data.appCheckSiteKey),
    stripePublishableKey: text(data.stripePublishableKey),
  };
}

function browserConfig(flags, action, event = null) {
  const actionName = typeof action === "string" ? action : action?.action;
  return {
    inlineRegistrationEnabled: flags.inlineRegistrationEnabled,
    accountlessRegistrationEnabled: flags.accountlessRegistrationEnabled,
    paidTicketCheckoutEnabled: flags.paidTicketCheckoutEnabled,
    action: actionName || "view",
    ticketState: typeof action === "object" ? action.state : "view",
    event: event ? {
      title: text(event.title),
      date: asDate(event.selectedDateTime)?.toISOString() || null,
      location: event.locationType === "online" ? "Online event" :
        text(event.locationName || event.location),
      price: Math.max(0, Number(event.ticketPrice || 0)),
    } : null,
    firebase: {
      apiKey: "AIzaSyA-PFyqhP5aEVE6XwGku3jMe91G3efMaVw",
      authDomain: "attendus.app",
      projectId: process.env.GCLOUD_PROJECT || "orgami-66nxok",
      appId: "1:951311475019:web:65b1de24d2f3a8d289c8ce",
      messagingSenderId: "951311475019",
    },
    appCheckSiteKey: flags.appCheckSiteKey,
    stripePublishableKey: flags.stripePublishableKey,
  };
}

async function renderEvent(db, req, res, id, flags, nonce) {
  const snapshot = await db.collection("Events").doc(id).get();
  const data = snapshot.data();
  if (!snapshot.exists || !eventEligibility(data)) return notFound(res, nonce);
  let organization = null;
  if (text(data.organizationId)) {
    organization = (await db.collection("Organizations")
        .doc(text(data.organizationId)).get()).data() || null;
  }
  const canonical = `${PUBLIC_ORIGIN}/event/${encodeURIComponent(id)}`;
  const action = ticketState(data);
  const html = shell({
    title: text(data.title) || "Event",
    summary: eventDescription(data, organization),
    canonical,
    image: data.imageUrl,
    body: eventBody(id, data, organization, flags),
    jsonLd: eventJsonLd(id, data, organization),
    config: browserConfig(flags, action, data),
    nonce,
  });
  pageHeaders(res, nonce);
  res.status(200);
  if (req.method === "HEAD") return res.end();
  return res.send(html);
}

async function renderCommunity(db, req, res, id, flags, nonce) {
  const snapshot = await db.collection("Organizations").doc(id).get();
  const data = snapshot.data();
  if (!snapshot.exists || !communityEligibility(data)) return notFound(res, nonce);
  const events = await db.collection("PublicWebEvents")
      .where("organizationId", "==", id).limit(12).get();
  const links = events.docs.map((event) => `<li><a href="${escapeHtml(event.data().canonicalUrl)}">${escapeHtml(event.data().title)}</a></li>`).join("");
  const canonical = `${PUBLIC_ORIGIN}/community/${encodeURIComponent(id)}`;
  const body = `<main id="main" class="page"><article class="community"><div class="community-hero"><img src="${escapeHtml(safeUrl(data.bannerUrl || data.logoUrl, FALLBACK_IMAGE))}" alt="" width="1200" height="480"></div><div class="eyebrow">${escapeHtml(data.category || "Community")}</div><h1>${escapeHtml(data.name)}</h1><p class="lead">${escapeHtml(data.description)}</p>${data.locationAddress ? `<address>${escapeHtml(data.locationAddress)}</address>` : ""}<section><h2>Events from this community</h2>${links ? `<ul class="event-links">${links}</ul>` : "<p>No public events are listed yet.</p>"}</section><a class="cta" href="/app/community/${encodeURIComponent(id)}">Open community in Attendus</a></article></main>`;
  const jsonLd = {
    "@context": "https://schema.org",
    "@type": "Organization",
    "name": text(data.name),
    "description": description(data.description, 5000),
    "url": canonical,
    "logo": safeUrl(data.logoUrl, FALLBACK_IMAGE),
  };
  pageHeaders(res, nonce);
  res.status(200);
  if (req.method === "HEAD") return res.end();
  return res.send(shell({
    title: data.name,
    summary: data.description || `Discover events from ${data.name}.`,
    canonical,
    image: data.bannerUrl || data.logoUrl,
    body,
    jsonLd,
    config: browserConfig(flags, "view"),
    nonce,
  }));
}

async function sitemapIndex(db, res) {
  const [events, communities] = await Promise.all([
    db.collection("PublicWebEvents").count().get(),
    db.collection("PublicWebCommunities").count().get(),
  ]);
  const groups = [
    ["events", events.data().count],
    ["communities", communities.data().count],
  ];
  const entries = groups.flatMap(([kind, count]) => Array.from({
    length: Math.max(1, Math.ceil(count / PAGE_SIZE)),
  }, (_, index) => `<sitemap><loc>${PUBLIC_ORIGIN}/sitemaps/${kind}-${index + 1}.xml</loc></sitemap>`)).join("");
  res.set("Cache-Control", "public, max-age=300, s-maxage=3600");
  res.type("application/xml").send(`<?xml version="1.0" encoding="UTF-8"?><sitemapindex xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">${entries}</sitemapindex>`);
}

async function sitemapShard(db, res, kind, page) {
  const collection = kind === "events" ? "PublicWebEvents" : "PublicWebCommunities";
  const snapshot = await db.collection(collection).orderBy("canonicalUrl")
      .offset((page - 1) * PAGE_SIZE).limit(PAGE_SIZE).get();
  const urls = snapshot.docs.map((entry) => {
    const data = entry.data();
    const modified = asDate(data.lastModified)?.toISOString();
    return `<url><loc>${escapeXml(data.canonicalUrl)}</loc>${modified ? `<lastmod>${modified}</lastmod>` : ""}</url>`;
  }).join("");
  res.set("Cache-Control", "public, max-age=300, s-maxage=3600");
  res.type("application/xml").send(`<?xml version="1.0" encoding="UTF-8"?><urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">${urls}</urlset>`);
}

function projectionForEvent(id, data) {
  return {
    canonicalUrl: `${PUBLIC_ORIGIN}/event/${encodeURIComponent(id)}`,
    title: text(data.title),
    organizationId: text(data.organizationId) || null,
    eventEndTime: eventEnd(data),
    lastModified: data.updatedAt || data.createdAt || new Date(),
  };
}

function projectionForCommunity(id, data) {
  return {
    canonicalUrl: `${PUBLIC_ORIGIN}/community/${encodeURIComponent(id)}`,
    name: text(data.name),
    lastModified: data.publicPageUpdatedAt || data.updatedAt || data.createdAt || new Date(),
  };
}

function createPublicWeb(admin) {
  const db = admin.firestore();
  return onRequest({
    region: "us-central1",
    invoker: "public",
    minInstances: 1,
    maxInstances: 30,
    memory: "256MiB",
    timeoutSeconds: 20,
    secrets: [CONTACT_HMAC_KEY, CONTACT_KMS_KEY_NAME],
  }, async (req, res) => {
    const nonce = crypto.randomBytes(18).toString("base64");
    if (!["GET", "HEAD", "POST"].includes(req.method)) {
      res.set("Allow", "GET, HEAD");
      return res.status(405).send("Method not allowed");
    }
    try {
      const flags = await configFor(db);
      if (!flags.publicPagesEnabled) {
        res.set("Cache-Control", "no-store");
        res.set("X-Robots-Tag", "noindex, nofollow");
        return res.status(503).send("Public pages are not enabled.");
      }
      const path = req.path.replace(/\/+$/, "") || "/";
      let match = path.match(/^\/manage\/([A-Za-z0-9_-]+)$/);
      if (match && req.method !== "POST") {
        return exchangeManageToken(db, req, res, match[1], nonce);
      }
      if (path === "/manage" && req.method !== "POST") return renderManage(db, req, res, nonce);
      if (path === "/manage/calendar.ics" && req.method !== "POST") {
        return manageCalendar(db, req, res, nonce);
      }
      if (path === "/manage/ticket.svg" && req.method !== "POST") {
        return manageTicketQr(db, req, res, nonce);
      }
      if (path === "/manage/action" && req.method === "POST") {
        return manageAction(db, req, res, nonce);
      }
      match = path.match(/^\/event\/([A-Za-z0-9_-]+)$/);
      if (match) return renderEvent(db, req, res, match[1], flags, nonce);
      match = path.match(/^\/community\/([A-Za-z0-9_-]+)$/);
      if (match) return renderCommunity(db, req, res, match[1], flags, nonce);
      if (path === "/sitemap.xml") return sitemapIndex(db, res);
      match = path.match(/^\/sitemaps\/(events|communities)-(\d+)\.xml$/);
      if (match) return sitemapShard(db, res, match[1], Number(match[2]));
      return notFound(res, nonce);
    } catch (error) {
      logger.error("Public web request failed", {path: req.path, error});
      res.set("Cache-Control", "no-store");
      res.set("X-Robots-Tag", "noindex, nofollow");
      return res.status(500).send("Public page temporarily unavailable.");
    }
  });
}

function createMaintainPublicEventPage(admin) {
  return onDocumentWritten({
    document: "Events/{eventId}",
    region: "us-central1",
  }, async (event) => {
    const after = event.data?.after;
    const ref = admin.firestore().collection("PublicWebEvents")
        .doc(event.params.eventId);
    if (!after?.exists || !eventEligibility(after.data())) return ref.delete();
    return ref.set(projectionForEvent(event.params.eventId, after.data()));
  });
}

function createMaintainPublicCommunityPage(admin) {
  return onDocumentWritten({
    document: "Organizations/{organizationId}",
    region: "us-central1",
  }, async (event) => {
    const after = event.data?.after;
    const ref = admin.firestore().collection("PublicWebCommunities")
        .doc(event.params.organizationId);
    if (!after?.exists || !communityEligibility(after.data())) return ref.delete();
    return ref.set(projectionForCommunity(event.params.organizationId, after.data()));
  });
}

module.exports = {
  communityEligibility,
  createMaintainPublicCommunityPage,
  createMaintainPublicEventPage,
  createPublicWeb,
  escapeHtml,
  eventEligibility,
  eventDescription,
  eventJsonLd,
  eventState,
  isoInTimeZone,
  projectionForCommunity,
  projectionForEvent,
  safeJson,
  ticketState,
};
