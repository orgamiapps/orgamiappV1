"use strict";
const {createHash} = require("node:crypto");
const {schedule, instant} = require("./schedule");
const {validTicket, confirmedRegistration} = require("../attendance/arrival-core");

function normalized(value) { return String(value || "").normalize("NFKD").replace(/\p{M}/gu, "").toLowerCase().trim(); }
function prefixes(value) {
  const result = new Set();
  for (const word of [normalized(value), ...normalized(value).split(/\s+/).slice(0, 6)]) {
    for (let index = 1; index <= Math.min(word.length, 80); index++) result.add(word.slice(0, index));
  }
  return [...result];
}
function key(value) { return createHash("sha256").update(value).digest("hex"); }

function buildRoster(registrations, tickets, attendance, history = [], event = {}) {
  const rows = new Map();
  const transitions = new Map();
  const byRegistration = new Map(); const byTicket = new Map();
  for (const registration of registrations) {
    const id = `r:${registration.id}`;
    rows.set(id, {id: key(id), registrationId: registration.id, ticketId: registration.ticketId || null,
      uid: registration.customerUid || registration.userId || null, guestId: registration.guestId || null,
      name: registration.realName || registration.userName || "Attendee",
      status: confirmedRegistration(registration) ? "confirmed" : registration.cancelled || registration.revoked ? "cancelled" : registration.status === "confirmed" || !registration.status ? "pending" : registration.status, identityType: registration.identityType || "account",
      emailHash: registration.emailHash || null, emailRef: registration.emailRef || null,
      registrationAnswers: registration.answers || [],
      attendanceStatus: "not_arrived", attendanceIds: [], checkedInAt: null, checkedOutAt: null});
    byRegistration.set(registration.id, id);
    if (registration.ticketId) byTicket.set(registration.ticketId, id);
  }
  for (const ticket of tickets) {
    let id = byTicket.get(ticket.id) || byRegistration.get(ticket.registrationId);
    if (id && rows.get(id).ticketId && rows.get(id).ticketId !== ticket.id) id = null;
    if (!id && ticket.guestId) {
      const matches = registrations.filter((r) => r.guestId === ticket.guestId && !r.ticketId);
      if (matches.length === 1 && !rows.get(byRegistration.get(matches[0].id)).ticketId) id = byRegistration.get(matches[0].id);
    }
    if (!id) {
      id = `t:${ticket.id}`;
      rows.set(id, {id: key(id), registrationId: ticket.registrationId || null,
        uid: ticket.customerUid || ticket.userId || null, guestId: ticket.guestId || null,
        name: ticket.customerName || "Attendee", status: validTicket(ticket, event) ? "confirmed" : ticket.revoked || ticket.cancelled || ["cancelled", "canceled", "revoked", "refunded"].includes(ticket.status) || ticket.paymentStatus === "refunded" ? "cancelled" : "pending",
        identityType: ticket.identityType || "account", emailRef: ticket.guestId ? `GuestAttendees/${ticket.guestId}` : null,
        emailHash: null, attendanceStatus: "not_arrived", attendanceIds: [], checkedInAt: null, checkedOutAt: null});
    }
    const row = rows.get(id);
    row.ticketId = ticket.id; row.ticketCode = ticket.ticketCode || null;
    if (!validTicket(ticket, event) && row.status === "confirmed") row.status = ticket.revoked || ticket.cancelled || ["cancelled", "canceled", "revoked", "refunded"].includes(ticket.status) || ticket.paymentStatus === "refunded" ? "cancelled" : "pending";
    byTicket.set(ticket.id, id);
  }
  const sourceIds = new Set(attendance.map((entry) => key(entry.id)));
  const entries = [...attendance, ...history.filter((item) => !sourceIds.has(item.sourceAttendanceHash || key(item.sourceAttendanceId || item.id)))];
  entries.sort((a, b) => (instant(a.checkedInAt || a.attendanceDateTime)?.getTime() || 0) - (instant(b.checkedInAt || b.attendanceDateTime)?.getTime() || 0) || String(a.id).localeCompare(String(b.id)));
  for (const entry of entries) {
    const checkedIn = instant(entry.checkedInAt || entry.attendanceDateTime);
    if ((!checkedIn && entry.timestampQuality !== "unknown") || entry.voided === true || ["voided", "rejected"].includes(entry.status)) continue;
    let id = byTicket.get(entry.ticketId) || byRegistration.get(entry.registrationId);
    if (!id && entry.customerUid) {
      const matches = [...rows.entries()].filter(([, row]) => row.uid === entry.customerUid && !row.ticketId);
      if (matches.length === 1) id = matches[0][0];
    }
    if (!id) {
      id = `a:${entry.admissionGroupId || entry.admissionKey || entry.sourceAttendanceId || entry.id}`;
      if (!rows.has(id)) rows.set(id, {id: key(id), registrationId: null, ticketId: entry.ticketId || null,
        uid: entry.customerUid || null, guestId: entry.guestId || null,
        name: entry.realName || entry.userName || "Former attendee", status: "attended",
        identityType: entry.identityType || "account", emailHash: null, emailRef: null,
        attendanceIds: [], checkedInAt: null, checkedOutAt: null});
    }
    const row = rows.get(id);
    row.attendanceIds.push(entry.sourceAttendanceId || entry.id);
    row.attendanceAnswers = entry.answers || [];
    if (checkedIn && (!row.checkedInAt || checkedIn < new Date(row.checkedInAt))) row.checkedInAt = checkedIn.toISOString();
    const checkout = instant(entry.checkedOutAt);
    const candidates = transitions.get(id) || [];
    if (checkedIn) candidates.push({at: checkedIn.getTime(), kind: "checked_in", id: String(entry.id)});
    if (checkout && (!checkedIn || checkout >= checkedIn)) {
      candidates.push({at: checkout.getTime(), kind: "checked_out", id: String(entry.id)});
    }
    transitions.set(id, candidates);
    candidates.sort((a, b) => a.at - b.at || a.id.localeCompare(b.id) || a.kind.localeCompare(b.kind));
    const latest = candidates[candidates.length - 1];
    row.attendanceStatus = latest?.kind || "attended_unknown";
    row.checkedOutAt = latest?.kind === "checked_out" ? new Date(latest.at).toISOString() : null;
  }
  return [...rows.values()].map((row) => ({...row, searchPrefixes: prefixes(row.name),
    ticketCode: row.ticketCode || null, registrationAnswers: row.registrationAnswers || [], attendanceAnswers: row.attendanceAnswers || []}));
}

function metrics(rows, event, now = new Date()) {
  const confirmed = rows.filter((row) => row.status === "confirmed");
  const arrived = rows.filter((row) => row.attendanceIds.length > 0);
  const remaining = confirmed.filter((row) => !row.attendanceIds.length).length;
  const ended = schedule(event).end;
  return {confirmed: confirmed.length, pending: rows.filter((r) => r.status === "pending").length,
    waitlisted: rows.filter((r) => r.status === "waitlisted").length, arrived: arrived.length,
    inside: event.checkInPolicy?.checkoutEnabled ? arrived.filter((r) => r.attendanceStatus === "checked_in").length : null, remaining,
    noShow: ended && ended <= now && !event.cancelled && !["cancelled", "canceled"].includes(event.status) ? remaining : null};
}

async function allDocuments(query) {
  const result = []; let cursor;
  for (;;) {
    let page = query.orderBy("__name__").limit(400);
    if (cursor) page = page.startAfter(cursor);
    const snapshot = await page.get();
    result.push(...snapshot.docs);
    if (snapshot.size < 400) return result;
    cursor = snapshot.docs[snapshot.docs.length - 1];
  }
}

module.exports = {normalized, prefixes, key, buildRoster, metrics, allDocuments};
