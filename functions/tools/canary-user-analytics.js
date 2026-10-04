"use strict";

const {getApps, initializeApp} = require("firebase-admin/app");
const {getFirestore, Timestamp} = require("firebase-admin/firestore");
const {
  RECOMPUTE_COLLECTION,
} = require("../analytics/user-analytics");

const allowedProjects = new Set(["attendus-staging", "orgami-66nxok"]);

function argumentValue(name) {
  const index = process.argv.indexOf(name);
  return index === -1 ? undefined : process.argv[index + 1];
}

async function waitFor(check, description, timeoutMs = 180000) {
  const deadline = Date.now() + timeoutMs;
  while (Date.now() < deadline) {
    const result = await check();
    if (result) return result;
    await new Promise((resolve) => setTimeout(resolve, 2000));
  }
  throw new Error(`Timed out waiting for ${description}`);
}

async function deleteIfPresent(reference) {
  const snapshot = await reference.get();
  if (snapshot.exists) await reference.delete();
}

async function main() {
  const projectId = argumentValue("--project");
  if (!process.argv.includes("--apply")) {
    throw new Error("Analytics canary requires --apply.");
  }
  if (!allowedProjects.has(projectId)) {
    throw new Error("Analytics canary requires an explicit approved --project.");
  }
  if (getApps().length === 0) initializeApp({projectId});
  const db = getFirestore();
  const suffix = Date.now();
  const ownerId = `__analytics_canary_owner_${suffix}`;
  const firstId = `__analytics_canary_first_${suffix}`;
  const secondId = `__analytics_canary_second_${suffix}`;
  const eventIds = [firstId, secondId];
  const event = (title) => ({
    title,
    customerUid: ownerId,
    categories: ["Synthetic Canary"],
    selectedDateTime: Timestamp.fromDate(new Date(Date.now() + 86400000)),
    private: true,
    syntheticCanary: true,
  });

  try {
    await Promise.all([
      db.collection("Events").doc(firstId).set(event("Analytics canary one")),
      db.collection("Events").doc(secondId).set(event("Analytics canary two")),
    ]);
    await waitFor(async () => {
      const aggregate = await db.collection("user_analytics").doc(ownerId).get();
      const recompute = await db.collection(RECOMPUTE_COLLECTION)
          .doc(ownerId).get();
      const eventAnalytics = aggregate.get("eventAnalytics") || {};
      return aggregate.exists && aggregate.get("totalEvents") === 2 &&
        eventAnalytics[firstId] && eventAnalytics[secondId] &&
        recompute.exists && recompute.get("processedGeneration") ===
          recompute.get("requestedGeneration") &&
        aggregate.get("sourceGeneration") ===
          recompute.get("processedGeneration");
    }, "two-event aggregate");

    await db.collection("event_analytics").doc(firstId).set({
      totalAttendees: 7,
      repeatAttendees: 2,
      lastUpdated: Timestamp.now(),
    }, {merge: true});
    await waitFor(async () => {
      const aggregate = await db.collection("user_analytics").doc(ownerId).get();
      return aggregate.get("totalAttendees") === 7;
    }, "aggregate update");

    await db.collection("Events").doc(firstId).delete();
    await waitFor(async () => {
      const aggregate = await db.collection("user_analytics").doc(ownerId).get();
      return aggregate.exists && aggregate.get("totalEvents") === 1;
    }, "aggregate after deletion");

    await db.collection("Events").doc(secondId).delete();
    await waitFor(async () =>
      !(await db.collection("user_analytics").doc(ownerId).get()).exists,
    "aggregate cleanup");
    process.stdout.write(JSON.stringify({projectId, ownerId, status: "passed"}) +
      "\n");
  } finally {
    for (const eventId of eventIds) {
      await deleteIfPresent(db.collection("Events").doc(eventId));
      await deleteIfPresent(db.collection("event_analytics").doc(eventId));
    }
    await deleteIfPresent(db.collection("user_analytics").doc(ownerId));
    await deleteIfPresent(db.collection(RECOMPUTE_COLLECTION).doc(ownerId));
  }
}

main().catch((error) => {
  process.stderr.write(`${error.stack || error.message}\n`);
  process.exitCode = 1;
});
