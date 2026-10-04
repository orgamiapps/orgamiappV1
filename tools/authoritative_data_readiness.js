"use strict";
const {createHash} = require("node:crypto");
const {tierFromSubscription} = require("../functions/events/wizard");
const {inspectEvent} = require("../functions/events/migration");
const hash = (value) => createHash("sha256").update(value).digest("hex");
const validCounter = (value) => Number.isSafeInteger(value) && value >= 0;
function quotaReadiness(customers, subscriptions, entitlements) {
  const subs = new Map(subscriptions.map((row) => [row.id, row]));
  const grants = new Map(entitlements.map((row) => [row.id, row.data()]));
  const result = {customers: customers.length, subscriptions: subscriptions.length,
    customerCounterMissing: 0, customerCounterInvalid: 0, subscriptionCounterMissing: 0, subscriptionCounterInvalid: 0,
    effectiveCounterBlocked: 0, explicitUnlimited: 0, activePremium: 0, free: 0, basic: 0, blockedAccountHashes: []};
  for (const row of subscriptions) {
    const count = row.data().eventsCreatedThisMonth;
    if (count === undefined) result.subscriptionCounterMissing++;
    else if (!validCounter(count)) result.subscriptionCounterInvalid++;
  }
  for (const row of customers) {
    const count = row.data().eventsCreated;
    if (count === undefined) result.customerCounterMissing++;
    else if (!validCounter(count)) result.customerCounterInvalid++;
    const subscription = subs.get(row.id) || {data: () => undefined};
    const tier = tierFromSubscription(subscription);
    if (grants.get(row.id)?.unlimitedEventCreation === true) { result.explicitUnlimited++; continue; }
    if (tier === "premium") { result.activePremium++; continue; }
    result[tier]++;
    if (!validCounter(tier === "basic" ? subscription.data()?.eventsCreatedThisMonth : count)) {
      result.effectiveCounterBlocked++; result.blockedAccountHashes.push(hash(row.id));
    }
  }
  result.blockedAccountHashes.sort();
  return result;
}
async function readAuthoritativeReadiness(db, projectId) {
  if (!["orgami-66nxok", "attendus-staging"].includes(projectId)) throw Error("Explicit supported readiness source project required");
  const fields = {
    Customers: ["eventsCreated"], subscriptions: ["eventsCreatedThisMonth", "tier", "subscriptionTier", "status", "isActive"],
    account_entitlements: ["unlimitedEventCreation"],
    Events: ["eventRevision", "selectedDateTime", "eventDurationMinutes", "eventDuration", "eventEnd", "eventTimeZone", "ticketsEnabled", "status", "registrationPolicy"],
    RegisterAttendance: ["eventId", "customerUid", "userId", "ticketId", "status", "cancelled", "checkedIn", "createdAt"],
    Tickets: ["eventId", "customerUid", "userId", "registrationId", "status", "cancelled", "checkedIn", "createdAt"],
    Attendance: ["eventId", "customerUid", "userId", "ticketId", "registrationId", "admissionKey", "checkedInAt", "attendanceDateTime", "checkedOutAt", "isSignedIn", "checkedIn", "status", "voided", "verificationSource", "signInMethod", "method", "checkInMethod"],
  };
  return db.runTransaction(async (tx) => {
    const rows = {};
    for (const [name, projection] of Object.entries(fields)) {
      const snapshot = await tx.get(db.collection(name).select(...projection).limit(10001));
      if (snapshot.size > 10000) throw Error("Readiness inventory exceeds the reviewed per-collection bound");
      rows[name] = snapshot.docs;
    }
    const issues = [];
    for (const event of rows.Events) {
      const sources = ["RegisterAttendance", "Tickets", "Attendance"].map((name) => rows[name].filter((row) => row.get("eventId") === event.id).map((row) => ({...row.data(), id: row.id})));
      for (const issue of inspectEvent(event.id, event.data(), sources).issues) issues.push({eventHash: hash(event.id), recordHash: hash(issue.recordId), type: issue.type});
    }
    return {schemaVersion: 1, readOnly: true, projectId, observedAt: new Date().toISOString(),
      liveEvents: rows.Events.length, liveMigrationIssueCount: issues.length, liveMigrationIssues: issues,
      quota: quotaReadiness(rows.Customers, rows.subscriptions, rows.account_entitlements),
      counterFields: {free: "Customers.eventsCreated", basic: "subscriptions.eventsCreatedThisMonth"}};
  }, {readOnly: true});
}
module.exports = {quotaReadiness, readAuthoritativeReadiness, validCounter};
