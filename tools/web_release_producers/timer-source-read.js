"use strict";

// Evidence only. Every Firestore access is inside one read-only transaction.
const {isDeepStrictEqual} = require("node:util");
const {digest} = require("../web_release_contract");
const {validateCommunications} = require("./browser-communications");
const {bindingId, validScope} = require("../../functions/communications/qualification-isolation");
const {reminderDocumentId} = require("../../functions/notifications/scheduled-reminders");
const crypto = require("node:crypto");
const itemId = (eventId) => crypto.createHash("sha256").update(JSON.stringify(eventId)).digest("hex");
const millis = (value) => value?.toMillis?.() ?? (value instanceof Date ? value.getTime() : NaN);
function fullTimestamp(value) {
  if (value == null) return null;
  if (Number.isInteger(value.seconds) && Number.isInteger(value.nanoseconds) && value.nanoseconds >= 0 && value.nanoseconds < 1e9) {
    return {seconds: value.seconds, nanoseconds: value.nanoseconds};
  }
  if (value instanceof Date && Number.isFinite(value.getTime())) return {seconds: Math.floor(value.getTime() / 1000), nanoseconds: (value.getTime() % 1000) * 1000000};
  throw Error("original-timer-invalid-timestamp");
}
function originalEventIds(fixture) {
  return [fixture.event.id, fixture.privateEventId, fixture.secondEventId, fixture.canaryEventId, fixture.largeRoster?.eventId,
    fixture.communications.reminderEventId, fixture.communications.discoveryEventId];
}
function sourceIdentity(candidate, fixture) {
  const identity = validateCommunications(fixture, candidate);
  if (candidate.environment !== "staging" || !Number.isFinite(Date.parse(fixture.runStartsAt)) ||
      originalEventIds(fixture).some((id) => typeof id !== "string" || !/^[A-Za-z0-9_-]{1,150}$/.test(id) || !fixture.ownedFixtureIds.includes(id)) ||
      new Set(originalEventIds(fixture)).size !== 7) throw Error("original-timer-fixture-source-invalid");
  return {...identity, candidateSha256: digest(candidate), reminderEventId: fixture.communications.reminderEventId,
    discoveryEventId: fixture.communications.discoveryEventId, discoveryRecipientUid: fixture.attendee.uid,
    reminderRecipientUids: [fixture.owner.uid, fixture.attendee.uid]};
}
function rowEvidence(row, times, fields) {
  return {id: row.id, path: row.ref.path, exists: row.exists, updateTime: fullTimestamp(row.updateTime), readTime: fullTimestamp(row.readTime),
    ...Object.fromEntries(fields.map((name) => [name, row.get(name) ?? null])),
    ...Object.fromEntries(times.map((name) => [name, fullTimestamp(row.get(name))]))};
}
async function readOriginalTimerSource({db, candidate, fixture, now = Date.now}) {
  const identity = sourceIdentity(candidate, fixture), ids = originalEventIds(fixture);
  if (db.projectId !== "attendus-staging" || Object.keys(process.env).some((key) => /EMULATOR/.test(key) && process.env[key])) throw Error("original-timer-live-staging-required");
  const result = await db.runTransaction(async (tx) => {
    const get = (name) => tx.get(db.doc(name));
    const eventIds = [identity.reminderEventId, identity.discoveryEventId], uids = identity.reminderRecipientUids;
    const [scope, setup, organizer, follower, ...rows] = await Promise.all([
      get(`QualificationScopes/${identity.runId}`), get(`QualificationSetup/${identity.runId}`),
      get(`QualificationSetup/${identity.runId}/supplemental/organizer`), get(`Customers/${fixture.owner.uid}/followers/${fixture.attendee.uid}`),
      ...eventIds.map((id) => get(`Events/${id}`)),
      ...[...eventIds.map((id) => ["event", id]), ...uids.map((id) => ["account", id])].map(([kind, id]) => get(`QualificationBindings/${bindingId(kind, id)}`)),
      ...uids.map((id) => get(`account_deletion_jobs/${id}`)),
      get(`discovery_notification_batches/${fixture.attendee.uid}/events/${itemId(identity.discoveryEventId)}`),
      ...uids.map((uid) => get(`scheduledNotifications/${reminderDocumentId(identity.reminderEventId, uid)}`)),
    ]);
    const events = rows.slice(0, 2), bindings = rows.slice(2, 6), deleting = rows.slice(6, 8), discovery = rows[8], reminders = rows.slice(9);
    const bound = (row) => row.get("schemaVersion") === 1 && row.get("state") === "bound" && row.get("projectId") === identity.projectId && row.get("runId") === identity.runId;
    const started = Date.parse(fixture.runStartsAt);
    if (!validScope(scope.data(), identity.runId, identity.projectId, now()) ||
        !isDeepStrictEqual([...scope.get("eventIds")].sort(), [...ids].sort()) ||
        !uids.every((uid) => scope.get("recipientUids").includes(uid) && scope.get("actorUids").includes(uid)) ||
        organizer.exists || setup.get("state") !== "seeded" || setup.get("projectId") !== identity.projectId ||
        setup.get("sourceSha") !== identity.sourceSha || setup.get("candidateRunId") !== identity.candidateRunId ||
        !isDeepStrictEqual(setup.get("ownedFixtureIds"), fixture.ownedFixtureIds) || bindings.some((row) => !bound(row)) || deleting.some((row) => row.exists) ||
        !follower.exists || follower.get("userId") !== fixture.attendee.uid ||
        events.some((row) => !row.exists || row.get("customerUid") !== fixture.owner.uid || row.get("eventRevision") !== 1 ||
          row.get("status") !== "active" || row.get("private") !== false || row.get("isHidden") !== false || row.get("deleted") === true || row.get("isDeleted") === true ||
          millis(row.get("createdAt")) !== started || millis(row.get("selectedDateTime")) !== started + 4 * 3600000 || row.get("eventDurationMinutes") !== 120)) {
      throw Error("original-timer-live-source-binding-changed");
    }
    if (discovery.exists && discovery.get("eventId") !== identity.discoveryEventId) throw Error("original-timer-discovery-item-collision");
    if (reminders.some((row, i) => row.exists && (row.get("eventId") !== identity.reminderEventId || row.get("userId") !== uids[i]))) throw Error("original-timer-reminder-item-collision");
    return {
      discoveryItem: rowEvidence(discovery, ["queuedAt", "readyAt", "claimedAt"], ["eventId", "status", "deliveryId"]),
      reminderQueues: reminders.map((row) => rowEvidence(row, ["createdAt", "eventTime", "originalDueAt", "deliveryDeadline", "completedAt"], ["eventId", "userId", "deliveryState", "reminderMinutes", "attemptCount"])),
      events: events.map((row) => rowEvidence(row, ["createdAt", "selectedDateTime"], ["customerUid", "eventRevision", "eventDurationMinutes", "status"])),
      scopeUpdateTime: fullTimestamp(scope.updateTime), setupUpdateTime: fullTimestamp(setup.updateTime),
    };
  }, {readOnly: true});
  return {schemaVersion: 1, evidenceKind: "original-timer-source-snapshot", identity, observedAt: new Date(now()).toISOString(),
    originalTimersVerified: false, qualifiesCandidate: false,
    discoveryPhase: !result.discoveryItem.exists ? "absent" : result.discoveryItem.status === "pending" ? "pending-observed" : "not-pending", ...result};
}

module.exports = {readOriginalTimerSource, sourceIdentity, fullTimestamp, originalEventIds};
