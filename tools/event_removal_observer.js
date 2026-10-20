"use strict";

// Exact supplemental scope only. Does not write documents or enumerate users.
const c = require("./event_removal_contract");
const {bindingId} = require("./seed_event_removal_qualification");
function normalized(value) {
  if (value?.toDate) return {$date: value.toDate().toISOString()};
  if (value instanceof Date) return {$date: value.toISOString()};
  if (Array.isArray(value)) return value.map(normalized);
  if (value && typeof value === "object") return Object.fromEntries(Object.entries(value).map(([key, v]) => [key, normalized(v)]));
  return value;
}
function documentHash(document) {
  return c.digest({exists: document.exists, data: normalized(document.data()),
    createTime: document.createTime?.toDate?.().toISOString() || null,
    updateTime: document.updateTime?.toDate?.().toISOString() || null});
}
function timestampIdentity(value) {
  if (typeof value === "string") {
    const match = /^(.*T\d{2}:\d{2}:\d{2})(?:\.(\d{1,9}))?Z$/.exec(value);
    c.need(match && Number.isFinite(Date.parse(value)), "TIMESTAMP_INVALID");
    return `${Math.floor(Date.parse(match[1] + "Z") / 1000)}:${(match[2] || "").padEnd(9, "0")}`;
  }
  c.need(Number.isInteger(value?.seconds) && Number.isInteger(value?.nanoseconds), "TIMESTAMP_INVALID");
  return `${value.seconds}:${String(value.nanoseconds).padStart(9, "0")}`;
}
function scopeValid(data, fixture, now = Date.now()) {
  const millis = value => value?.toMillis?.() ?? (value instanceof Date ? value.getTime() : NaN);
  const created = millis(data?.createdAt), expires = millis(data?.expiresAt);
  const equal = (actual, expected) => Array.isArray(actual) && c.digest(actual) === c.digest(expected);
  return data?.schemaVersion === 1 && data.projectId === c.PROJECT && data.status === "active" &&
    data.mode === "capture" && Number.isFinite(created) && created <= now && expires > now &&
    expires - created <= 72 * 3600000 &&
    equal(data.actorUids, c.ROLE_KEYS.map(key => fixture.roles[key].uid)) &&
    equal(data.recipientUids, c.ROLE_KEYS.map(key => fixture.roles[key].uid)) &&
    equal(data.recipientEmailHashes, c.ROLE_KEYS.map(key => c.sha(fixture.roles[key].email.toLowerCase()))) &&
    equal(data.eventIds, c.EVENT_KEYS.map(key => fixture.events[key].id)) &&
    equal(data.organizationIds, [fixture.organizationId]) && equal(data.conversationIds, []);
}
function createObserver({db, fixture, candidate, receipt, environment = process.env}) {
  c.validateContext({fixture, candidate, receipt});
  c.assertLiveEnvironment(environment);
  c.need(db?.projectId === c.PROJECT && (!db._settings?.host || db._settings.host === "firestore.googleapis.com") &&
    db._settings?.ssl !== false, "OBSERVER_DATABASE_SCOPE_INVALID");
  c.need(fixture.state === "seeded", "SEEDED_FIXTURE_REQUIRED");
  c.need(fixture.canonicalEventIds.every(id => fixture.canonicalEventVersions?.[id]?.updateTime &&
    fixture.canonicalEventVersions[id].createTime), "CANONICAL_BASELINE_REQUIRED");
  return async function observe() {
    const canonical = await Promise.all(fixture.canonicalEventIds.map(id => db.doc(`Events/${id}`).get()));
    c.need(canonical.every(doc => doc.exists), "CANONICAL_EVENT_MISSING");
    const changedCount = canonical.filter((doc, index) => {
      const pin = fixture.canonicalEventVersions[fixture.canonicalEventIds[index]];
      return timestampIdentity(doc.createTime) !== timestampIdentity(pin.createTime) ||
        timestampIdentity(doc.updateTime) !== timestampIdentity(pin.updateTime);
    }).length;
    const events = {};
    for (const key of c.EVENT_KEYS) {
      const id = fixture.events[key].id;
      const [source, projection, ...history] = await Promise.all([
        db.doc(`Events/${id}`).get(), db.doc(`PublicWebEvents/${id}`).get(),
        ...["RegisterAttendance", "Tickets", "Attendance"].map(collection =>
          db.collection(collection).where("eventId", "==", id).limit(101).get()),
      ]);
      c.need(history.every(result => result.docs.length < 101), "HISTORY_SCOPE_TOO_LARGE");
      const expected = fixture.history[key], lists = history.map(result => result.docs.map(doc => doc.id).sort());
      events[key] = {exists: source.exists, status: source.exists ? source.get("status") || "active" : "deleted",
        eventRevision: source.exists ? source.get("eventRevision") || 0 : null, projectionExists: projection.exists,
        registrations: lists[0].length, tickets: lists[1].length, attendance: lists[2].length,
        historyPreserved: !expected || [expected.registrationId, expected.ticketId, expected.attendanceId]
          .every((historyId, index) => history[index].docs.some(doc => doc.id === historyId &&
            doc.get("eventId") === id && doc.get("customerUid") === fixture.roles.viewer.uid)),
        historyIdsSha256: c.digest(lists)};
    }
    const [scope, setup] = await Promise.all([
      db.doc(`QualificationScopes/${fixture.runId}`).get(), db.doc(`QualificationSetup/${fixture.runId}`).get(),
    ]);
    c.need(setup.exists && setup.get("purpose") === fixture.purpose && setup.get("state") === "provisioning" &&
      setup.get("candidateSha256") === fixture.candidateSha256 &&
      setup.get("deploymentReceiptSha256") === fixture.deploymentReceiptSha256 &&
      setup.get("sourceSha") === fixture.sourceSha, "SUPPLEMENTAL_SETUP_DIFFERS");
    const bindingTargets = [
      ...c.ROLE_KEYS.map(key => ["account", fixture.roles[key].uid]),
      ...c.EVENT_KEYS.map(key => ["event", fixture.events[key].id]),
      ["organization", fixture.organizationId],
    ];
    const bindings = await Promise.all(bindingTargets.map(([kind, id]) =>
      db.doc(`QualificationBindings/${bindingId(kind, id)}`).get()));
    const boundCount = bindings.filter((doc, index) => doc.exists && doc.get("runId") === fixture.runId &&
      doc.get("state") === "bound" && doc.get("projectId") === c.PROJECT && doc.get("schemaVersion") === 1 &&
      doc.id === bindingId(...bindingTargets[index])).length;
    return {schemaVersion: 1, purpose: fixture.purpose, runId: fixture.runId, sourceSha: fixture.sourceSha,
      candidateRunId: fixture.candidateRunId, candidateSha256: fixture.candidateSha256,
      deploymentReceiptSha256: fixture.deploymentReceiptSha256, observedAt: new Date().toISOString(), events,
      canonical: {unchanged: changedCount === 0, changedCount},
      scope: {active: scope.exists && scopeValid(scope.data(), fixture) && boundCount === 10,
        boundCount}, readOnly: true};
  };
}
module.exports = {createObserver, normalized, documentHash, timestampIdentity, scopeValid};
