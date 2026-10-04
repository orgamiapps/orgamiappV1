"use strict";
const {buildRoster, metrics, key} = require("./roster");
const {schedule} = require("./schedule");
const {evidence, verifyArchivedEvidence} = require("../account/attendance-history");

function canonical(value) {
  if (value instanceof Date) return value.toISOString();
  if (Array.isArray(value)) return value.map(canonical);
  if (value && typeof value === "object") return Object.fromEntries(Object.keys(value).sort().map((field) => [field, canonical(value[field])]));
  return value;
}

function fingerprint(value) { return key(JSON.stringify(canonical(value)) ?? "undefined"); }

function sourceFingerprint(event, sources) {
  return fingerprint([event, ...sources.map((records) => [...records].sort((a, b) => a.id.localeCompare(b.id)))]);
}

function verifyArchiveRecord(source, archive, corrections) {
  const stamp = evidence(source.id, source);
  if (!stamp || !archive?.admissionGroupId) throw Error("Attendance archival evidence is absent or unproven");
  stamp.admissionGroupId = archive.admissionGroupId;
  verifyArchivedEvidence(archive, corrections, stamp);
  const matches = (candidate) => Object.entries(stamp).every(([field, value]) => fingerprint(candidate?.[field]) === fingerprint(value));
  if (!matches(archive) && !corrections.some((correction) => correction.data.source === "attendance_record_update" && matches(correction.data.evidence))) {
    throw Error("Archived attendance does not match its current source");
  }
  return fingerprint({archive, corrections: [...corrections].sort((a, b) => a.id.localeCompare(b.id))});
}

async function readArchiveState(db, attendance, transaction = null, {verify = false} = {}) {
  const read = (ref) => transaction ? transaction.get(ref) : ref.get();
  const entries = [];
  for (const source of [...attendance].sort((a, b) => a.id.localeCompare(b.id))) {
    const ref = db.collection("HistoricalAttendance").doc(key(source.id));
    const grouping = source.admissionKey || (source.ticketId ? `ticket:${source.ticketId}` : source.registrationId ? `registration:${source.registrationId}` : `attendance:${source.id}`);
    const [history, changes, identity, group] = await Promise.all([read(ref), read(ref.collection("corrections")),
      read(db.collection("AttendanceHistoryIdentities").doc(ref.id)),
      read(db.collection("AttendanceArchiveGroups").doc(key(`${source.eventId}:${grouping}`)))]);
    const corrections = changes.docs.map((doc) => ({id: doc.id, data: doc.data()})).sort((a, b) => a.id.localeCompare(b.id));
    const archiveFingerprint = verify ? verifyArchiveRecord(source, history.data(), corrections) : null;
    entries.push({sourceId: source.id, sourceFingerprint: fingerprint(source), archiveFingerprint,
      stateFingerprint: fingerprint({history: history.data() || null, corrections, identity: identity.data() || null, group: group.data() || null})});
  }
  return {entries, fingerprint: fingerprint(entries)};
}

function migrationUpdate(inspected) {
  return {confirmedRegistrationCount: inspected.confirmedCount, launchScheduleNeedsReview: inspected.scheduleQuality !== "exact"};
}

function completedCheckpointMatches(checkpoint, inspected, archives) {
  return checkpoint?.status === "complete" && checkpoint.fingerprintVersion === 2 &&
    checkpoint.resultingFingerprint === inspected.fingerprint && checkpoint.archiveFingerprint === archives.fingerprint &&
    checkpoint.attendanceSourceCount === inspected.attendanceSourceCount && checkpoint.confirmedCount === inspected.confirmedCount &&
    fingerprint(checkpoint.totals) === fingerprint(inspected.totals);
}

function inspectEvent(eventId, event, sources) {
  const [registrations, tickets, attendance] = sources;
  const issues = [];
  for (const ticket of tickets) {
    if (!ticket.registrationId && !registrations.some((r) => r.ticketId === ticket.id) && registrations.some((r) => (r.customerUid || r.userId) && (r.customerUid || r.userId) === (ticket.customerUid || ticket.userId))) issues.push({type: "ambiguous_admission_link", recordId: ticket.id});
  }
  for (const item of attendance) if (!evidence(item.id, item)) issues.push({type: "insufficient_attendance_evidence", recordId: item.id});
  const rows = buildRoster(registrations, tickets, attendance, [], event);
  return {eventId, revision: Number(event.eventRevision || 0), scheduleQuality: schedule(event).quality,
    confirmedCount: metrics(rows, event).confirmed, attendanceSourceCount: attendance.length,
    totals: metrics(rows, event), issues,
    fingerprintVersion: 2, fingerprint: sourceFingerprint(event, sources)};
}
module.exports = {inspectEvent, canonical, fingerprint, sourceFingerprint, verifyArchiveRecord, readArchiveState, migrationUpdate, completedCheckpointMatches};
