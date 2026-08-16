"use strict";

const {getApps, initializeApp} = require("firebase-admin/app");
const {getFirestore} = require("firebase-admin/firestore");
const {
  communityEligibility,
  eventEligibility,
} = require("../public-web/renderer");

async function main() {
  if (getApps().length === 0) initializeApp();
  const db = getFirestore();
  const [events, organizations, projectedEvents, projectedCommunities] =
    await Promise.all([
      db.collection("Events").get(),
      db.collection("Organizations").get(),
      db.collection("PublicWebEvents").get(),
      db.collection("PublicWebCommunities").get(),
    ]);
  const eventMap = new Map(events.docs.map((entry) => [entry.id, entry.data()]));
  const organizationMap = new Map(organizations.docs.map((entry) =>
    [entry.id, entry.data()]));
  const projectedEventIds = new Set(projectedEvents.docs.map((entry) => entry.id));
  const projectedCommunityIds = new Set(projectedCommunities.docs.map((entry) => entry.id));
  const failures = [];
  for (const [id, data] of eventMap) {
    if (eventEligibility(data)) {
      if (!projectedEventIds.has(id)) failures.push(`${id}: missing event projection`);
      if (!data.eventTimeZone || data.postalCode === undefined ||
          (data.locationType !== "online" && !data.streetAddress)) {
        failures.push(`${id}: incomplete public metadata`);
      }
    } else if (projectedEventIds.has(id)) {
      failures.push(`${id}: ineligible event projected`);
    }
  }
  for (const [id, data] of organizationMap) {
    if (communityEligibility(data) && !projectedCommunityIds.has(id)) {
      failures.push(`${id}: missing community projection`);
    } else if (!communityEligibility(data) && projectedCommunityIds.has(id)) {
      failures.push(`${id}: ineligible community projected`);
    }
  }
  const summary = {
    events: events.size,
    projectedEvents: projectedEvents.size,
    communities: organizations.size,
    projectedCommunities: projectedCommunities.size,
    failures: failures.length,
    sampleFailures: failures.slice(0, 50),
  };
  process.stdout.write(`${JSON.stringify(summary, null, 2)}\n`);
  if (failures.length) process.exitCode = 2;
}

main().catch((error) => {
  process.stderr.write(`${error.stack || error.message}\n`);
  process.exitCode = 1;
});
