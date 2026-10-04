"use strict";

const {getApps, initializeApp} = require("firebase-admin/app");
const {getFirestore, Timestamp} = require("firebase-admin/firestore");
const {
  RECOMPUTE_COLLECTION,
} = require("../analytics/user-analytics");
const {reminderDocumentId} = require("../notifications/scheduled-reminders");

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

function validateCanaryIdentity(ownerId, eventIds) {
  const match = /^__analytics_canary_owner_(\d{13})$/.exec(ownerId || "");
  if (!match || !Array.isArray(eventIds) || eventIds.length !== 2 ||
      eventIds[0] !== `__analytics_canary_first_${match[1]}` ||
      eventIds[1] !== `__analytics_canary_second_${match[1]}`) {
    throw new Error("Exact analytics canary ownership is required.");
  }
}

function preferencesRef(db, ownerId) {
  return db.collection("users").doc(ownerId).collection("settings").doc("notifications");
}

async function createCanaryReminderPreferences(db, ownerId, eventIds) {
  validateCanaryIdentity(ownerId, eventIds);
  const settings = preferencesRef(db, ownerId);
  await db.runTransaction(async (tx) => {
    const existing = await Promise.all([
      tx.get(settings), ...eventIds.map((id) => tx.get(db.collection("Events").doc(id))),
      tx.get(db.collection("users").doc(ownerId)), tx.get(db.collection("Customers").doc(ownerId)),
    ]);
    if (existing.some((doc) => doc.exists)) throw new Error("Canary fixture identity is already in use.");
    tx.create(settings, {eventReminders: false, syntheticCanary: true, canaryOwnerId: ownerId});
  });
}

async function cleanupCanaryReminderArtifacts(db, ownerId, eventIds, settingsCreated) {
  const queues = eventIds.map((id) => db.collection("scheduledNotifications").doc(reminderDocumentId(id, ownerId)));
  const settings = preferencesRef(db, ownerId);
  await db.runTransaction(async (tx) => {
    const events = await Promise.all(eventIds.map((id) => tx.get(db.collection("Events").doc(id))));
    const reminders = await Promise.all(queues.map((ref) => tx.get(ref)));
    const preference = await tx.get(settings);
    if (events.some((event) => event.exists)) throw new Error("Canary events must be absent before reminder cleanup.");
    for (const [i, reminder] of reminders.entries()) {
      if (!reminder.exists) continue;
      const data = reminder.data();
      const lease = data.leaseUntil?.toMillis?.();
      if (data.eventId !== eventIds[i] || data.userId !== ownerId || data.type !== "event_reminder" ||
          !["pending", "retry", "cancelled", "expired", "in_app_only", "sent"].includes(data.deliveryState) ||
          data.pushDispatching !== undefined && data.pushDispatching !== null && data.pushDispatching !== false || data.claimId ||
          data.leaseUntil !== undefined && data.leaseUntil !== null && (!Number.isFinite(lease) || lease > Date.now())) {
        throw new Error("Canary reminder ownership or delivery state requires review.");
      }
    }
    if (settingsCreated && preference.exists) {
      const data = preference.data();
      if (data.eventReminders !== false || data.syntheticCanary !== true || data.canaryOwnerId !== ownerId ||
          Object.keys(data).some((key) => !["eventReminders", "syntheticCanary", "canaryOwnerId"].includes(key))) {
        throw new Error("Canary reminder preference changed; preserve it for review.");
      }
    }
    for (const reminder of reminders) if (reminder.exists) tx.delete(reminder.ref);
    if (settingsCreated && preference.exists) tx.delete(settings);
  });
}

async function cleanupCanaryFixtures(db, ownerId, eventIds, {settingsCreated = false} = {}) {
  validateCanaryIdentity(ownerId, eventIds);
  for (const eventId of eventIds) {
    const event = db.collection("Events").doc(eventId);
    await db.runTransaction(async (tx) => {
      const current = await tx.get(event);
      if (!current.exists) return;
      if (current.get("customerUid") !== ownerId || current.get("syntheticCanary") !== true) {
        throw new Error("Canary event ownership changed; preserve it for review.");
      }
      tx.delete(event);
    });
    await deleteIfPresent(db.collection("event_analytics").doc(eventId));
  }
  await deleteIfPresent(db.collection("user_analytics").doc(ownerId));
  await deleteIfPresent(db.collection(RECOMPUTE_COLLECTION).doc(ownerId));
  await cleanupCanaryReminderArtifacts(db, ownerId, eventIds, settingsCreated);
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

  let settingsCreated = false;
  try {
    // Create-only, owner-scoped preferences prevent unrelated reminder work.
    // Keep them until both events are gone, including failed canary runs.
    await createCanaryReminderPreferences(db, ownerId, eventIds);
    settingsCreated = true;
    const creation = await Promise.allSettled([
      db.collection("Events").doc(firstId).create(event("Analytics canary one")),
      db.collection("Events").doc(secondId).create(event("Analytics canary two")),
    ]);
    const failed = creation.find((result) => result.status === "rejected");
    if (failed) throw failed.reason;
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
    await waitFor(async () => {
      const [aggregate, recompute, ...analytics] = await Promise.all([
        db.collection("user_analytics").doc(ownerId).get(),
        db.collection(RECOMPUTE_COLLECTION).doc(ownerId).get(),
        ...eventIds.map((id) => db.collection("event_analytics").doc(id).get()),
      ]);
      return !aggregate.exists && analytics.every((document) => !document.exists) && recompute.exists &&
        Number.isSafeInteger(recompute.get("requestedGeneration")) &&
        recompute.get("processedGeneration") === recompute.get("requestedGeneration");
    },
    "aggregate cleanup");
    process.stdout.write(JSON.stringify({projectId, ownerId, status: "passed"}) +
      "\n");
  } finally {
    if (settingsCreated) await cleanupCanaryFixtures(db, ownerId, eventIds, {settingsCreated});
  }
}

if (require.main === module) {
  main().catch((error) => {
    process.stderr.write(`${error.stack || error.message}\n`);
    process.exitCode = 1;
  });
}

module.exports = {cleanupCanaryFixtures, createCanaryReminderPreferences};
