"use strict";

const {getApps, initializeApp} = require("firebase-admin/app");
const {FieldValue, getFirestore} = require("firebase-admin/firestore");
const admin = require("../firebase-admin-compat");
const {
  reconcileEvent,
  reconcileReminder,
  reminderDocumentId,
} = require("../notifications/scheduled-reminders");

async function migratePreferences(db, apply, summary) {
  const users = await db.collection("users").get();
  for (const user of users.docs) {
    const canonicalRef = user.ref.collection("settings").doc("notifications");
    const canonical = await canonicalRef.get();
    if (canonical.exists) {
      summary.preferencesCanonical += 1;
      continue;
    }
    const legacy = await user.ref.collection("notificationSettings")
        .doc("settings").get();
    const customer = legacy.exists ? null :
      await db.collection("Customers").doc(user.id).get();
    const customerPreferences = customer?.data()?.notificationPreferences;
    const source = legacy.exists ? legacy.data() :
      (customerPreferences && typeof customerPreferences === "object" ? {
        eventReminders: customerPreferences.eventReminders,
        reminderTime: customerPreferences.reminderTime,
        messagesAll: customerPreferences.messages,
        generalNotifications: customerPreferences.announcements,
      } : null);
    if (!source) {
      summary.preferencesDefaulted += 1;
      if (apply) await canonicalRef.set({
        eventReminders: true,
        reminderTime: 60,
        migratedAt: FieldValue.serverTimestamp(),
      }, {merge: true});
    } else {
      summary.preferencesMigrated += 1;
      const definedSource = Object.fromEntries(
          Object.entries(source).filter(([, value]) => value !== undefined),
      );
      if (apply) await canonicalRef.set({
        ...definedSource,
        migratedAt: FieldValue.serverTimestamp(),
      }, {merge: true});
    }
  }
}

async function migrateLegacyQueue(db, apply, summary) {
  const queue = await db.collection("scheduledNotifications").get();
  for (const document of queue.docs) {
    const data = document.data();
    if (data.deliveryState) {
      summary.queueCurrent += 1;
      continue;
    }
    summary.queueLegacy += 1;
    const eventId = String(data.eventId || "");
    const userId = String(data.userId || "");
    if (!eventId || !userId) {
      summary.queueInvalid += 1;
      if (apply) await document.ref.set({
        deliveryState: "failed",
        terminalReason: "invalid_legacy_record",
        migratedAt: FieldValue.serverTimestamp(),
      }, {merge: true});
      continue;
    }
    if (!apply) continue;
    await reconcileReminder(admin, eventId, userId);
    const targetId = reminderDocumentId(eventId, userId);
    if (document.id !== targetId) {
      await document.ref.set({
        deliveryState: "migrated",
        terminalReason: "replaced_by_deterministic_record",
        migrationTargetId: targetId,
        migratedAt: FieldValue.serverTimestamp(),
      }, {merge: true});
    }
  }
}

async function reconcileFutureEvents(db, apply, summary) {
  const events = await db.collection("Events").get();
  const now = Date.now();
  for (const event of events.docs) {
    const data = event.data();
    const value = data.selectedDateTime || data.eventDateTime;
    const startsAt = value?.toDate ? value.toDate() : new Date(value);
    if (!Number.isFinite(startsAt?.getTime()) || startsAt.getTime() <= now) {
      continue;
    }
    summary.futureEvents += 1;
    if (apply) await reconcileEvent(admin, event.id, data);
  }
}

async function main() {
  const apply = process.argv.includes("--apply");
  if (getApps().length === 0) initializeApp();
  const db = getFirestore();
  const summary = {
    mode: apply ? "apply" : "dry-run",
    preferencesCanonical: 0,
    preferencesMigrated: 0,
    preferencesDefaulted: 0,
    queueCurrent: 0,
    queueLegacy: 0,
    queueInvalid: 0,
    futureEvents: 0,
  };
  await migratePreferences(db, apply, summary);
  await migrateLegacyQueue(db, apply, summary);
  await reconcileFutureEvents(db, apply, summary);
  process.stdout.write(`${JSON.stringify(summary, null, 2)}\n`);
  if (!apply) {
    process.stdout.write("Dry run only. Re-run with --apply after review.\n");
  }
}

main().catch((error) => {
  process.stderr.write(`${error.stack || error.message}\n`);
  process.exitCode = 1;
});
