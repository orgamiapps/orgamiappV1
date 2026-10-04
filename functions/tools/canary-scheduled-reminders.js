"use strict";

const {getApps, initializeApp} = require("firebase-admin/app");
const {getFirestore, Timestamp} = require("firebase-admin/firestore");
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

async function main() {
  const projectId = argumentValue("--project");
  if (!process.argv.includes("--apply")) {
    throw new Error("Production canary requires --apply.");
  }
  if (!allowedProjects.has(projectId)) {
    throw new Error("Canary requires an explicit approved --project.");
  }
  if (getApps().length === 0) initializeApp({projectId});
  const db = getFirestore();
  const suffix = Date.now();
  const eventId = `__reminder_canary_event_${suffix}`;
  const userId = `__reminder_canary_user_${suffix}`;
  const queueId = reminderDocumentId(eventId, userId);
  const eventRef = db.collection("Events").doc(eventId);
  const userRef = db.collection("users").doc(userId);
  const settingsRef = userRef.collection("settings").doc("notifications");
  const queueRef = db.collection("scheduledNotifications").doc(queueId);
  const notificationRef = userRef.collection("notifications").doc(queueId);
  const startsAt = new Date(Date.now() + 30 * 60 * 1000);
  const result = {projectId, eventId, userId, queueId, state: "starting"};

  try {
    await userRef.set({
      syntheticCanary: true,
      createdAt: Timestamp.now(),
    });
    await settingsRef.set({eventReminders: true, reminderTime: 30});
    await eventRef.set({
      id: eventId,
      title: "Scheduled reminder production canary",
      selectedDateTime: Timestamp.fromDate(startsAt),
      customerUid: userId,
      status: "active",
      private: true,
      syntheticCanary: true,
    });

    await waitFor(async () => {
      const snapshot = await queueRef.get();
      return snapshot.exists && snapshot.get("deliveryState") === "pending";
    }, "V2 reminder reconciliation");
    result.state = "queued";

    const delivered = await waitFor(async () => {
      const snapshot = await queueRef.get();
      return snapshot.exists && snapshot.get("deliveryState") ===
        "in_app_only" ? snapshot : null;
    }, "scheduled worker in-app fallback");
    const notification = await notificationRef.get();
    if (!notification.exists) {
      throw new Error("Worker completed without deterministic in-app record.");
    }
    result.state = delivered.get("deliveryState");
    result.terminalReason = delivered.get("terminalReason");
    result.inAppCreated = notification.exists;
    process.stdout.write(`${JSON.stringify(result, null, 2)}\n`);
  } finally {
    await deleteIfPresent(eventRef);
    await deleteIfPresent(notificationRef);
    await deleteIfPresent(settingsRef);
    await deleteIfPresent(queueRef);
    await deleteIfPresent(userRef);
    await deleteIfPresent(db.collection("event_analytics").doc(eventId));
    await deleteIfPresent(db.collection("user_analytics").doc(userId));
    await deleteIfPresent(
        db.collection("_user_analytics_recompute").doc(userId),
    );
  }
}

main().catch((error) => {
  process.stderr.write(`${error.stack || error.message}\n`);
  process.exitCode = 1;
});
