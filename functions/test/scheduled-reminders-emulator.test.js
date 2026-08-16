"use strict";

const assert = require("node:assert/strict");
const test = require("node:test");
const admin = require("../firebase-admin-compat");
const {
  reconcileReminder,
  reminderDocumentId,
  runScheduledWorker,
} = require("../notifications/scheduled-reminders");
const {uniqueId, waitFor} = require("./emulator-test-helpers");

const cleanupReferences = [];
test.after(async () => {
  for (const reference of cleanupReferences.reverse()) {
    await reference.delete().catch(() => undefined);
  }
});

test("reminder triggers reconcile event, ticket, and reschedule lifecycle", async () => {
  const db = admin.firestore();
  const eventId = uniqueId("reminder-event");
  const ownerUid = uniqueId("reminder-owner");
  const buyerUid = uniqueId("reminder-buyer");
  const ticketId = uniqueId("reminder-ticket");
  const ownerQueueId = reminderDocumentId(eventId, ownerUid);
  const buyerQueueId = reminderDocumentId(eventId, buyerUid);
  const startsAt = new Date(Date.now() + 2 * 60 * 60 * 1000);
  cleanupReferences.push(
      db.collection("users").doc(ownerUid),
      db.collection("users").doc(buyerUid),
      db.collection("Events").doc(eventId),
      db.collection("Tickets").doc(ticketId),
      db.collection("scheduledNotifications").doc(ownerQueueId),
      db.collection("scheduledNotifications").doc(buyerQueueId),
      db.collection("event_analytics").doc(eventId),
      db.collection("user_analytics").doc(ownerUid),
      db.collection("_user_analytics_recompute").doc(ownerUid),
  );

  await Promise.all([
    db.collection("users").doc(ownerUid).set({email: "owner@example.test"}),
    db.collection("users").doc(buyerUid).set({email: "buyer@example.test"}),
    db.collection("users").doc(ownerUid).collection("settings")
        .doc("notifications").set({eventReminders: true, reminderTime: 60}),
    db.collection("users").doc(buyerUid).collection("settings")
        .doc("notifications").set({eventReminders: true, reminderTime: 30}),
  ]);

  await db.collection("Events").doc(eventId).set({
    id: eventId,
    title: "Reminder integration test",
    selectedDateTime: admin.firestore.Timestamp.fromDate(startsAt),
    customerUid: ownerUid,
    status: "active",
    private: false,
  });

  const ownerReminder = await waitFor(async () => {
    const snapshot = await db.collection("scheduledNotifications")
        .doc(ownerQueueId).get();
    return snapshot.exists && snapshot.get("deliveryState") === "pending" ?
      snapshot : null;
  }, "owner reminder creation");
  assert.equal(ownerReminder.get("eventTitle"), "Reminder integration test");
  assert.equal(ownerReminder.get("reminderMinutes"), 60);

  await db.collection("Tickets").doc(ticketId).set({
    eventId,
    customerUid: buyerUid,
    eventTitle: "Reminder integration test",
    eventDateTime: admin.firestore.Timestamp.fromDate(startsAt),
  });
  const buyerReminder = await waitFor(async () => {
    const snapshot = await db.collection("scheduledNotifications")
        .doc(buyerQueueId).get();
    return snapshot.exists && snapshot.get("deliveryState") === "pending" ?
      snapshot : null;
  }, "ticket-holder reminder creation");
  assert.equal(buyerReminder.get("reminderMinutes"), 30);

  const rescheduled = new Date(startsAt.getTime() + 30 * 60 * 1000);
  await db.collection("Events").doc(eventId).update({
    selectedDateTime: admin.firestore.Timestamp.fromDate(rescheduled),
  });
  await waitFor(async () => {
    const snapshot = await db.collection("scheduledNotifications")
        .doc(ownerQueueId).get();
    return snapshot.get("eventTime")?.toMillis() === rescheduled.getTime();
  }, "event reminder reschedule");

  await db.collection("Tickets").doc(ticketId).delete();
  await waitFor(async () => {
    const snapshot = await db.collection("scheduledNotifications")
        .doc(buyerQueueId).get();
    return snapshot.get("deliveryState") === "cancelled";
  }, "ticket-holder reminder cancellation");
});

test("worker records in-app-only delivery when no push token exists", async () => {
  const db = admin.firestore();
  const eventId = uniqueId("worker-event");
  const userId = uniqueId("worker-owner");
  const queueId = reminderDocumentId(eventId, userId);
  const now = new Date();
  const startsAt = new Date(now.getTime() + 30 * 60 * 1000);
  cleanupReferences.push(
      db.collection("users").doc(userId),
      db.collection("Events").doc(eventId),
      db.collection("scheduledNotifications").doc(queueId),
      db.collection("users").doc(userId).collection("notifications")
          .doc(queueId),
      db.collection("event_analytics").doc(eventId),
      db.collection("user_analytics").doc(userId),
      db.collection("_user_analytics_recompute").doc(userId),
  );
  await db.collection("users").doc(userId).set({email: "worker@example.test"});
  await db.collection("users").doc(userId).collection("settings")
      .doc("notifications").set({eventReminders: true, reminderTime: 30});
  await db.collection("Events").doc(eventId).set({
    id: eventId,
    title: "Worker integration test",
    selectedDateTime: admin.firestore.Timestamp.fromDate(startsAt),
    customerUid: userId,
    status: "active",
    private: false,
  });
  await reconcileReminder(admin, eventId, userId, now);
  const outcome = await runScheduledWorker(admin, new Date(now.getTime() + 1000));
  assert.equal(outcome.results.in_app_only, 1);
  const queue = await db.collection("scheduledNotifications").doc(queueId).get();
  assert.equal(queue.get("deliveryState"), "in_app_only");
  const inApp = await db.collection("users").doc(userId)
      .collection("notifications").doc(queueId).get();
  assert.equal(inApp.exists, true);
  assert.equal(inApp.get("type"), "event_reminder");
});
