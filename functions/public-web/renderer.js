"use strict";
const {readGuestRegistration, requireActiveAccounts} = require("../account/mutation-guard");

const crypto = require("node:crypto");
const PUBLIC_ASSETS = require("./asset-manifest.json").assets;
const {browserEnvironment} = require("./browser-environment");
const {onRequest} = require("firebase-functions/v2/https");
const {onDocumentWritten} = require("firebase-functions/v2/firestore");
const logger = require("firebase-functions/logger");
const QRCode = require("qrcode");
const {CONTACT_HMAC_KEY, CONTACT_KMS_KEY_NAME, digest, emailHash,
  encryptEmail, maskedEmail, normalizeEmail} = require("./accountless");

const {publicOrigin} = require("./origin");
const PAGE_SIZE = 10000;
const INDEXABLE_EVENT_STATUSES = new Set([
  "active", "scheduled", "completed", "cancelled", "canceled",
]);
const fallbackImage = () => `${publicOrigin()}/public-web/v1/event-fallback.png`;

function publicAssetUrl(name) {
  const version = PUBLIC_ASSETS[name];
  if (!/^[a-f0-9]{64}$/.test(version || "")) throw new Error("Public asset version is missing");
  return `/public-web/v1/assets/${version}/${name}`;
}

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
  const offset = ["GMT", "GMT+00:00", "GMT-00:00"].includes(offsetName) ?
    "Z" : offsetName.replace("GMT", "");
  return `${part("year")}-${part("month")}-${part("day")}T` +
    `${part("hour")}:${part("minute")}:${part("second")}${offset}`;
}

function eventEligibility(data) {
  if (!data || data.private !== false || data.isHidden === true || data.deleted === true) return false;
  return Boolean(text(data.title) && asDate(data.selectedDateTime) &&
    INDEXABLE_EVENT_STATUSES.has(text(data.status).toLowerCase()));
}

function communityEligibility(data) {
  return Boolean(data && data.publicPageEnabled === true && text(data.name));
}

function eventEnd(data) {
  return require("../events/schedule").schedule(data).end;
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
  const policy = data.registrationPolicy || {};
  const opens = asDate(policy.opensAt); const closes = asDate(policy.closesAt);
  if (opens && now < opens) return {state: "closed", label: "Registration opens soon"};
  if (closes && now > closes) return {state: "closed", label: "Registration closed"};
  let full;
  try {
    const capacity = require("../events/capacity");
    // Public free registration uses V3 and requires reconciled totals. Paid
    // checkout retains its existing V2 ticket-only legacy capacity contract.
    const paidCheckout = data.ticketsEnabled === true && Number(data.ticketPrice || 0) > 0;
    full = (paidCheckout ? capacity.ticketCapacityState(data) : capacity.capacityState(data)).full;
  } catch (error) {
    if (error.code !== "failed-precondition") throw error;
    return {state: "unavailable", label: "Availability unavailable"};
  }
  if (data.ticketsEnabled === true) {
    if (full) {
      if (Number(data.ticketPrice || 0) <= 0 && policy.waitlistEnabled !== false) return {state: "waitlist", action: "ticket", label: "Join waitlist"};
      return {state: "sold_out", label: "Sold out"};
    }
    const price = Math.max(0, Number(data.ticketPrice || 0));
    return price > 0 ? {
      state: "paid_ticket",
      action: "ticket",
      label: `Buy ticket · $${price.toFixed(2)}`,
      price,
    } : {state: "free_ticket", action: "ticket", label: policy.approvalMode === "manual" ? "Request a place" : "Get free ticket", price: 0};
  }
  if (full) {
    return policy.waitlistEnabled !== false ? {state: "waitlist", action: "rsvp", label: "Join waitlist"} : {state: "full", label: "Event full"};
  }
  return {state: "rsvp", action: "rsvp", label: policy.approvalMode === "manual" ? "Request a place" : "RSVP"};
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
  const environment = browserEnvironment();
  const sources = [
    "default-src 'self'",
    `script-src 'self' 'nonce-${nonce}' https://www.gstatic.com https://www.google.com/recaptcha/ https://js.stripe.com`,
    "style-src 'self' 'unsafe-inline'",
    "img-src 'self' https: data:",
    "connect-src 'self' https://*.googleapis.com https://*.firebaseio.com " +
      "https://identitytoolkit.googleapis.com https://securetoken.googleapis.com " +
      "https://www.googleapis.com https://www.google.com/recaptcha/ https://api.stripe.com " + environment.connectSources.join(" "),
    "frame-src https://accounts.google.com https://*.firebaseapp.com " +
      "https://js.stripe.com https://hooks.stripe.com https://www.google.com",
    "font-src 'self' data:",
    "base-uri 'self'",
    "form-action 'self'",
    "frame-ancestors 'none'",
    "object-src 'none'",
    ...(environment.emulators ? [] : ["upgrade-insecure-requests"]),
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
  const safeImage = escapeHtml(safeUrl(image, fallbackImage()));
  return `<!doctype html>
<html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>${safeTitle}</title><meta name="description" content="${safeSummary}">
<link rel="canonical" href="${safeCanonical}"><meta name="robots" content="index,follow,max-image-preview:large">
<meta property="og:type" content="website"><meta property="og:site_name" content="Attendus"><meta property="og:locale" content="en_US">
<meta property="og:title" content="${safeTitle}"><meta property="og:description" content="${safeSummary}">
<meta property="og:url" content="${safeCanonical}"><meta property="og:image" content="${safeImage}">
<meta name="twitter:card" content="summary_large_image"><meta name="twitter:title" content="${safeTitle}">
<meta name="twitter:description" content="${safeSummary}"><meta name="twitter:image" content="${safeImage}">
<link rel="icon" href="/favicon.png"><link rel="stylesheet" href="${publicAssetUrl("public.css")}"><link rel="stylesheet" href="${publicAssetUrl("registration-email-v2.css")}">
<script type="application/ld+json" nonce="${nonce}">${safeJson(jsonLd)}</script></head>
<body><a class="skip-link" href="#main">Skip to event details</a>
<header class="site-header"><a class="brand" href="/" aria-label="Attendus home"><img src="/icons/Icon-192.png" alt="" width="36" height="36"><span>Attendus</span></a></header>
${body}<footer class="site-footer"><span>Attendus</span><a href="/privacy">Privacy</a><a href="/terms">Terms</a></footer>
<script id="attendus-public-config" type="application/json" nonce="${nonce}">${safeJson(config)}</script>
<script src="${publicAssetUrl("actions-email-v2.js")}" defer></script></body></html>`;
}

function organizerFor(event, organization) {
  if (organization && communityEligibility(organization)) {
    return {
      name: text(organization.name),
      url: `${publicOrigin()}/community/${encodeURIComponent(text(event.organizationId))}`,
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
  const canonical = `${publicOrigin()}/event/${encodeURIComponent(id)}`;
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
    "image": [safeUrl(data.imageUrl, fallbackImage())],
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

function practicalDetails(data) {
  const experience = data.experience || {};
  const sections = [];
  const section = (title, value) => { if (value) sections.push(`<section><h2>${escapeHtml(title)}</h2><p>${escapeHtml(value).replaceAll("\n", "<br>")}</p></section>`); };
  section("Agenda", (experience.agenda || []).map((item) => `${item.title || ""}${item.details ? `\n${item.details}` : ""}`).join("\n\n"));
  section("Accessibility", [...(experience.accessibilityOptions || []), experience.accessibilityDetails].filter(Boolean).join("\n"));
  section("Things to bring", (experience.thingsToBring || []).join("\n"));
  if (experience.publicContact?.visible) section("Contact the organizer", [experience.publicContact.name, experience.publicContact.email].filter(Boolean).join("\n"));
  section("Refund terms", data.registrationPolicy?.refundTerms);
  return sections.join("");
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
<section class="event-content"><div class="hero"><img src="${escapeHtml(safeUrl(data.imageUrl, fallbackImage()))}" alt="${escapeHtml(text(data.title))}" width="1200" height="800" fetchpriority="high"></div>
<div class="eyebrow">${escapeHtml(category || "Event")}</div><h1>${escapeHtml(data.title)}</h1>
<p class="lead">${escapeHtml(eventDescription(data, organization).slice(0, 230))}</p><section aria-labelledby="details-heading"><h2 id="details-heading">Event details</h2>
<dl class="details"><div><dt>Date and time</dt><dd><time datetime="${escapeHtml(isoInTimeZone(start, zone))}">${escapeHtml(formatDate(start, zone))}</time></dd></div>
<div><dt>Location</dt><dd>${data.locationType === "online" ? escapeHtml(location) : `<address>${escapeHtml(location)}</address>`}</dd></div>
<div><dt>Organizer</dt><dd>${organizerMarkup}</dd></div></dl></section><section><h2>About this event</h2><p>${escapeHtml(eventDescription(data, organization)).replaceAll("\n", "<br>")}</p></section>${practicalDetails(data)}</section>
<aside class="registration" aria-labelledby="registration-heading"><div class="registration-card"><h2 id="registration-heading">Attend this event</h2>
<p>${escapeHtml(ticket.label)}</p>${action}<p class="fine-print">Secure registration through Attendus.</p></div></aside></article></main>
<div class="mobile-cta">${action}</div><p id="public-action-status" class="sr-only" aria-live="polite"></p>`;
}

function notFound(res, nonce) {
  pageHeaders(res, nonce);
  res.set("X-Robots-Tag", "noindex, nofollow");
  res.status(404).send(`<!doctype html><html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><meta name="robots" content="noindex,nofollow"><title>Page not found | Attendus</title><link rel="stylesheet" href="${publicAssetUrl("public.css")}"></head><body><main class="not-found"><h1>Page not found</h1><p>This page is unavailable.</p><a class="cta" href="/">Discover events</a></main></body></html>`);
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
  const accepted = await db.runTransaction(async (transaction) => {
    const token = await transaction.get(tokenRef);
    const expires = token.exists ? asDate(token.get("expiresAt")) : null;
    if (!token.exists || token.get("status") !== "active" || !expires || expires <= new Date()) return;
    const fresh = await readGuestRegistration(db, transaction, {registrationId: token.get("registrationId"), guestId: token.get("guestId")});
    await requireActiveAccounts(db, transaction, token.get("ownerUid"), token.get("claimedByUid"));
    const csrfToken = crypto.randomBytes(24).toString("base64url");
    transaction.update(tokenRef, {status: "exchanged", exchangedAt: new Date()});
    transaction.create(sessionRef, {status: "active", registrationId: token.get("registrationId"),
      guestId: token.get("guestId"), csrfToken, createdAt: new Date(),
      expiresAt: new Date(Date.now() + 2 * 3600000)});
    transaction.update(fresh.guest.ref, {verificationStatus: "verified", verifiedAt: new Date()});
    return true;
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

function manageAdmission(data) {
  const event = data.event.data(), registration = data.registration.data();
  const ticket = data.ticket?.data();
  const {activeEvent, confirmedRegistration, validTicket} = require("../attendance/arrival-core");
  // Missing legacy status is supported by the admission contract. Other
  // malformed values must not gain eligibility merely because they are falsy.
  const status = registration.status === undefined || registration.status === null || registration.status === "" ? "confirmed" : registration.status;
  const linkedTicket = Boolean(ticket && (!registration.ticketId || registration.ticketId === data.ticket.id) &&
    (!ticket.registrationId || ticket.registrationId === data.registration.id));
  const cancelled = registration.cancelled === true || registration.revoked === true ||
    ["cancelled", "canceled", "revoked", "refunded"].includes(status) ||
    event.cancelled === true || ["cancelled", "canceled"].includes(event.status) ||
    (linkedTicket && (ticket.revoked === true || ticket.cancelled === true ||
      ["cancelled", "canceled", "revoked", "refunded"].includes(ticket.status) || ticket.paymentStatus === "refunded"));
  const confirmed = !cancelled && status === "confirmed" && confirmedRegistration(registration) && activeEvent(event) &&
    (!(event.ticketsEnabled || registration.ticketId || ticket) || (linkedTicket && validTicket(ticket, event)));
  const label = cancelled ? "Cancelled" : confirmed ? "Confirmed" :
    status === "pending" ? "Pending approval" : status === "waitlisted" ? "Waitlisted" :
      status === "declined" ? "Declined" : "Unavailable";
  return {label, confirmed, cancelled, calendarMethod: cancelled ? "CANCEL" : confirmed ? "PUBLISH" : null,
    showTicket: confirmed && linkedTicket && typeof ticket.ticketCode === "string" && ticket.ticketCode.length > 0,
    canCancel: !cancelled && activeEvent(event) && ["pending", "waitlisted", "confirmed"].includes(status) &&
      ticket?.isPaid !== true && eventStartForManage(event) > new Date()};
}

function managePage(res, nonce, data, session, notice = "") {
  pageHeaders(res, nonce);
  res.set("X-Robots-Tag", "noindex, nofollow");
  const event = data.event.data();
  const registration = data.registration.data();
  const ticket = data.ticket?.data();
  const guest = data.guest.data() || {};
  const admission = manageAdmission(data);
  const paid = ticket?.isPaid === true;
  const cancel = admission.canCancel ?
    `<form method="post" action="/manage/action"><input type="hidden" name="csrf" value="${escapeHtml(session.csrfToken)}"><input type="hidden" name="action" value="cancel"><button class="secondary-button danger" type="submit">Cancel registration</button></form>` : "";
  const ticketMarkup = admission.showTicket ? `<section class="manage-ticket" aria-labelledby="ticket-heading"><h2 id="ticket-heading">Your ticket</h2><div class="ticket-code"><span>Ticket code</span><strong>${escapeHtml(ticket.ticketCode)}</strong><img src="/manage/ticket.svg" width="220" height="220" alt="QR ticket code ${escapeHtml(ticket.ticketCode)}"></div><button class="secondary-button print-ticket" type="button">Print ticket</button></section>` : "";
  const admissionActions = `${admission.confirmed ? `<a class="secondary-button" href="/manage/attendance">Check in or get my event pass</a>` : ""}${admission.calendarMethod ? `<a class="secondary-button" href="/manage/calendar.ics">Download calendar invite</a>` : ""}`;
  const emailForm = `<details class="contact-update"><summary>Update confirmation email</summary><form method="post" action="/manage/action"><input type="hidden" name="csrf" value="${escapeHtml(session.csrfToken)}"><input type="hidden" name="action" value="update_email"><label>Email address <input name="email" type="email" autocomplete="email" required maxlength="254"></label><button class="secondary-button" type="submit">Update and resend</button></form></details>`;
  const body = `<main id="main" class="page manage-page"><article><div class="eyebrow">Guest registration</div><h1>${escapeHtml(event.title)}</h1>${notice ? `<p class="notice" role="status">${escapeHtml(notice)}</p>` : ""}<dl class="details"><div><dt>Status</dt><dd>${admission.label}</dd></div><div><dt>Attendee</dt><dd>${escapeHtml(registration.realName || registration.userName)}</dd></div><div><dt>Email</dt><dd>${escapeHtml(guest.maskedEmail || "Protected")}</dd></div><div><dt>Date</dt><dd>${escapeHtml(formatDate(eventStartForManage(event), validTimeZone(event.eventTimeZone)))}</dd></div></dl>${ticketMarkup}<div class="manage-actions">${admissionActions}<a class="secondary-button" href="/event/${encodeURIComponent(data.event.id)}">View event</a>${cancel}</div>${emailForm}${paid ? `<p>Paid ticket refunds are handled by the organizer or <a href="mailto:support@attendus.app">support@attendus.app</a>.</p>` : ""}</article></main>`;
  res.status(200).send(`<!doctype html><html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><meta name="robots" content="noindex,nofollow"><title>Manage registration | Attendus</title><link rel="stylesheet" href="${publicAssetUrl("public.css")}"><link rel="stylesheet" href="${publicAssetUrl("registration-email-v2.css")}"></head><body><a class="skip-link" href="#main">Skip to registration</a><header class="site-header"><a class="brand" href="/"><img src="/icons/Icon-192.png" alt="" width="36" height="36"><span>Attendus</span></a></header>${body}<script nonce="${nonce}">document.querySelector('.print-ticket')?.addEventListener('click',()=>window.print());</script></body></html>`);
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
  const {calendarMethod: method} = manageAdmission(data);
  if (!method) {
    res.set("Cache-Control", "no-store"); res.set("X-Robots-Tag", "noindex, nofollow");
    return res.status(409).send("A confirmed registration is required for a calendar invite.");
  }
  if (!eventEnd(event)) return res.status(409).send("The organizer needs to confirm the event end time.");
  const content = require("../events/schedule").calendar(event, {
    uid: `${data.registration.id}@attendus.app`, method,
    url: `${publicOrigin()}/event/${data.event.id}`,
  });
  res.set("Cache-Control", "no-store"); res.set("X-Robots-Tag", "noindex, nofollow");
  res.set("Content-Disposition", "attachment; filename=attendus-event.ics");
  return res.type("text/calendar").send(content);
}

async function manageTicketQr(db, req, res, nonce) {
  const session = await manageSession(db, req);
  if (!session) return notFound(res, nonce);
  const data = await manageData(db, session);
  const code = data?.ticket?.get("ticketCode");
  if (!data || !manageAdmission(data).showTicket) return notFound(res, nonce);
  const svg = await QRCode.toString(code, {type: "svg", margin: 1, width: 220,
    errorCorrectionLevel: "M"});
  res.set("Cache-Control", "private, no-store");
  res.set("X-Robots-Tag", "noindex, nofollow");
  return res.type("image/svg+xml").send(svg);
}

async function manageAction(db, req, res, nonce) {
  const session = await manageSession(db, req);
  if (!session || req.body?.csrf !== session.csrfToken ||
      !["cancel", "update_email"].includes(req.body?.action)) {
    return notFound(res, nonce);
  }
  const data = await manageData(db, session);
  if (!data) return notFound(res, nonce);
  if (req.body.action === "update_email") {
    try {
      const email = normalizeEmail(req.body.email);
      const hash = emailHash(email);
      const encrypted = await encryptEmail(email);
      const newClaim = db.collection("GuestEventEmailClaims").doc(digest(data.event.id, hash));
      const rawToken = crypto.randomBytes(32).toString("base64url");
      const tokenId = crypto.createHash("sha256").update(rawToken).digest("hex");
      const messageId = `resend_${crypto.randomUUID()}`;
      await db.runTransaction(async (transaction) => {
        const currentSession = await transaction.get(session.ref);
        if (!currentSession.exists || currentSession.get("status") !== "active" ||
            !asDate(currentSession.get("expiresAt")) || asDate(currentSession.get("expiresAt")) <= new Date() ||
            currentSession.get("csrfToken") !== req.body.csrf || currentSession.get("registrationId") !== data.registration.id ||
            currentSession.get("guestId") !== data.guest.id) throw new Error("This session is no longer available.");
        const fresh = await readGuestRegistration(db, transaction, {registrationId: data.registration.id, guestId: data.guest.id, eventId: data.event.id});
        const oldClaim = db.collection("GuestEventEmailClaims").doc(digest(data.event.id, fresh.guest.get("emailHash")));
        const collision = await transaction.get(newClaim);
        if (collision.exists && collision.get("guestId") !== fresh.guest.id) throw new Error("That email already has a registration.");
        transaction.set(newClaim, {eventId: data.event.id, guestId: fresh.guest.id,
          registrationId: fresh.registration.id, emailHash: hash,
          status: fresh.registration.get("status"), updatedAt: new Date()});
        if (oldClaim.id !== newClaim.id) transaction.delete(oldClaim);
        transaction.update(fresh.guest.ref, {emailHash: hash, encryptedEmail: encrypted, maskedEmail: maskedEmail(email),
          verificationStatus: "pending", verifiedAt: null, updatedAt: new Date()});
        transaction.set(db.collection("GuestManageTokens").doc(tokenId), {guestId: fresh.guest.id,
          registrationId: fresh.registration.id, ownerUid: "email_proof_only", status: "active",
          createdAt: new Date(), expiresAt: new Date(Date.now() + 72 * 3600000)});
        transaction.set(db.collection("OutboundMessages").doc(messageId), {id: messageId,
          templateId: "guest_registration_confirmation",
          channel: "email", status: "pending", attempts: 0,
          registrationId: data.registration.id, guestId: data.guest.id, eventId: data.event.id,
          encryptedEmail: encrypted, maskedEmail: maskedEmail(email), payload: {
            firstName: fresh.guest.get("greetingName"), eventTitle: data.event.get("title"),
            eventStart: data.event.get("selectedDateTime"), eventLocation: data.event.get("location"),
            kind: data.ticket ? "ticket" : "rsvp",
            manageUrl: `${publicOrigin()}/manage/${rawToken}`}, createdAt: new Date(),
          nextAttemptAt: new Date()});
      });
      return managePage(res, nonce, await manageData(db, session), session,
          "Email updated. A new confirmation is being sent.");
    } catch (error) {
      return managePage(res, nonce, data, session,
          error.message || "Email could not be updated.");
    }
  }
  if (eventStartForManage(data.event.data()) <= new Date() || data.ticket?.get("isPaid") === true) {
    return managePage(res, nonce, data, session, "This registration cannot be cancelled online.");
  }
  try {
    await db.runTransaction(async (transaction) => {
      const [current, currentSession, event, guest] = await Promise.all([
        transaction.get(data.registration.ref), transaction.get(session.ref),
        transaction.get(data.event.ref), transaction.get(data.guest.ref),
      ]);
      if (!currentSession.exists || currentSession.get("status") !== "active" ||
          !asDate(currentSession.get("expiresAt")) || asDate(currentSession.get("expiresAt")) <= new Date() ||
          currentSession.get("csrfToken") !== req.body.csrf || currentSession.get("registrationId") !== current.id ||
          currentSession.get("guestId") !== current.get("guestId") || !guest.exists || !event.exists) {
        throw new Error("This management session is no longer available.");
      }
      const uids = [...new Set([current.get("customerUid"), current.get("userId"), guest.get("ownerUid"), guest.get("claimedByUid")].filter(Boolean))];
      for (const uid of uids) if ((await transaction.get(db.collection("account_deletion_jobs").doc(uid))).exists) throw new Error("Account deletion is in progress.");
      if (!current.exists || current.get("status") === "cancelled") return;
      if (eventStartForManage(event.data()) <= new Date()) throw new Error("This registration cannot be cancelled online.");
      const {activeTickets, eventUpdate, previouslyConfirmed} = await require("../events/admission-cancellation").cancellationAdmissions(db, transaction, current, event);
      transaction.update(current.ref, {status: "cancelled", cancelledAt: new Date(), cancellationSource: "guest_manage_page"});
      for (const ticket of activeTickets) transaction.update(ticket.ref, {revoked: true, revokedReason: "guest_cancelled", revokedAt: new Date()});
      transaction.update(event.ref, eventUpdate);
      if (guest.get("encryptedEmail")) {
        const messageId = `cancellation_${current.id}`;
        transaction.set(db.collection("OutboundMessages").doc(messageId), {id: messageId,
          templateId: "guest_registration_cancelled", channel: "email", status: "pending", attempts: 0,
          registrationId: current.id, guestId: guest.id, eventId: event.id,
          encryptedEmail: guest.get("encryptedEmail"), maskedEmail: guest.get("maskedEmail"),
          payload: {firstName: guest.get("greetingName") || "there", eventTitle: event.get("title"), calendarPreviouslyConfirmed: previouslyConfirmed,
            eventStart: event.get("selectedDateTime"), eventLocation: event.get("location") || "",
            eventDurationMinutes: event.get("eventDurationMinutes") || null, eventDuration: event.get("eventDuration") || null,
            eventTimeZone: event.get("eventTimeZone") || "UTC", eventRevision: event.get("eventRevision") || 0},
          createdAt: new Date(), nextAttemptAt: new Date()});
      }
    });
  } catch (error) {
    return managePage(res, nonce, data, session, error.message || "Cancellation could not be completed.");
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

function browserConfig(flags, action, event = null, questions = []) {
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
      end: eventEnd(event)?.toISOString() || null,
      timeZone: validTimeZone(event.eventTimeZone),
      locationType: event.locationType || "in_person",
      location: event.locationType === "online" ? "Online event" :
        text(event.locationName || event.location),
      price: Math.max(0, Number(event.ticketPrice || 0)),
      approvalMode: event.registrationPolicy?.approvalMode === "manual" ? "manual" : "automatic",
      questions: questions.map((question) => ({
        id: text(question.id),
        prompt: text(question.prompt || question.questionTitle),
        type: ["short_text", "long_text", "single_choice", "multiple_choice", "acknowledgement"]
            .includes(question.type) ? question.type : "long_text",
        options: Array.isArray(question.options) ? question.options.map(text).filter(Boolean).slice(0, 20) : [],
        required: question.required === true,
      })),
    } : null,
    firebase: browserEnvironment().firebase,
    ...(browserEnvironment().emulators ? {emulators: browserEnvironment().emulators} : {}),
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
  const canonical = `${publicOrigin()}/event/${encodeURIComponent(id)}`;
  const action = ticketState(data);
  const questionSnapshot = await snapshot.ref.collection("EventQuestions")
      .where("timing", "==", "registration").get();
  const registrationQuestions = questionSnapshot.docs
      .map((document) => ({id: document.id, ...document.data()}))
      .sort((a, b) => Number(a.order || 0) - Number(b.order || 0));
  const html = shell({
    title: text(data.title) || "Event",
    summary: eventDescription(data, organization),
    canonical,
    image: data.imageUrl,
    body: eventBody(id, data, organization, flags),
    jsonLd: eventJsonLd(id, data, organization),
    config: browserConfig(flags, action, data, registrationQuestions),
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
  const canonical = `${publicOrigin()}/community/${encodeURIComponent(id)}`;
  const body = `<main id="main" class="page"><article class="community"><div class="community-hero"><img src="${escapeHtml(safeUrl(data.bannerUrl || data.logoUrl, fallbackImage()))}" alt="" width="1200" height="480"></div><div class="eyebrow">${escapeHtml(data.category || "Community")}</div><h1>${escapeHtml(data.name)}</h1><p class="lead">${escapeHtml(data.description)}</p>${data.locationAddress ? `<address>${escapeHtml(data.locationAddress)}</address>` : ""}<section><h2>Events from this community</h2>${links ? `<ul class="event-links">${links}</ul>` : "<p>No public events are listed yet.</p>"}</section><a class="cta" href="/app/community/${encodeURIComponent(id)}">Open community in Attendus</a></article></main>`;
  const jsonLd = {
    "@context": "https://schema.org",
    "@type": "Organization",
    "name": text(data.name),
    "description": description(data.description, 5000),
    "url": canonical,
    "logo": safeUrl(data.logoUrl, fallbackImage()),
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
  }, (_, index) => `<sitemap><loc>${publicOrigin()}/sitemaps/${kind}-${index + 1}.xml</loc></sitemap>`)).join("");
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
    canonicalUrl: `${publicOrigin()}/event/${encodeURIComponent(id)}`,
    title: text(data.title),
    organizationId: text(data.organizationId) || null,
    eventEndTime: eventEnd(data),
    lastModified: data.updatedAt || data.createdAt || new Date(),
  };
}

function projectionForCommunity(id, data) {
  return {
    canonicalUrl: `${publicOrigin()}/community/${encodeURIComponent(id)}`,
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
    const db = admin.firestore(), id = event.params.eventId;
    const source = db.collection("Events").doc(id);
    const ref = db.collection("PublicWebEvents").doc(id);
    // Deliveries can arrive after deletion, privacy changes or recreation.
    // Couple the current source read and mirror write so a concurrent source
    // change retries the transaction instead of publishing a stale projection.
    return db.runTransaction(async (tx) => {
      const current = await tx.get(source);
      if (!current.exists || !eventEligibility(current.data())) return tx.delete(ref);
      return tx.set(ref, projectionForEvent(id, current.data()));
    });
  });
}

function createMaintainPublicCommunityPage(admin) {
  return onDocumentWritten({
    document: "Organizations/{organizationId}",
    region: "us-central1",
  }, async (event) => {
    const db = admin.firestore(), id = event.params.organizationId;
    const source = db.collection("Organizations").doc(id);
    const ref = db.collection("PublicWebCommunities").doc(id);
    return db.runTransaction(async (tx) => {
      const current = await tx.get(source);
      if (!current.exists || !communityEligibility(current.data())) return tx.delete(ref);
      return tx.set(ref, projectionForCommunity(id, current.data()));
    });
  });
}

module.exports = {
  exchangeManageToken,
  manageAction,
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
  pageHeaders,
  safeJson,
  ticketState,
};
