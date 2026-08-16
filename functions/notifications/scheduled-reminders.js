"use strict";

const crypto = require("node:crypto");
const {
  onDocumentWritten,
} = require("firebase-functions/v2/firestore");
const {onSchedule} = require("firebase-functions/v2/scheduler");
const logger = require("firebase-functions/logger");

const REGION = "us-central1";
const DEFAULT_REMINDER_MINUTES = 60;
const DELIVERY_GRACE_MS = 15 * 60 * 1000;
const LEASE_MS = 55 * 1000;
const MAX_ATTEMPTS = 3;
const RETRY_DELAYS_MS = [60 * 1000, 3 * 60 * 1000, 7 * 60 * 1000];
const ACTIVE_STATES = new Set(["pending", "retry"]);
const CANCELLED_EVENT_STATES = new Set(["cancelled", "canceled"]);
const PERMANENT_TOKEN_ERRORS = new Set([
  "messaging/registration-token-not-registered",
  "messaging/invalid-registration-token",
]);

function asDate(value) {
  if (!value) return null;
  if (typeof value.toDate === "function") return value.toDate();
  const parsed = value instanceof Date ? value : new Date(value);
  return Number.isFinite(parsed.getTime()) ? parsed : null;
}

function normalizedEvent(data) {
  if (!data) return null;
  const startsAt = asDate(data.selectedDateTime || data.eventDateTime);
  return {
    startsAt,
    title: String(data.title || data.eventTitle || "Event"),
    ownerUid: String(data.customerUid || data.createdBy || ""),
    status: String(data.status || "active").toLowerCase(),
  };
}

function normalizedSettings(data) {
  const minutes = Number(data?.reminderTime);
  const allowedMinutes = [15, 30, 60, 120, 1440];
  return {
    enabled: data?.eventReminders !== false,
    reminderMinutes: allowedMinutes.includes(minutes) ?
      minutes : DEFAULT_REMINDER_MINUTES,
  };
}

function reminderDocumentId(eventId, userId) {
  return crypto.createHash("sha256")
      .update(`event_reminder:${eventId}:${userId}`)
      .digest("hex");
}

function scheduleFor(eventData, settingsData, now = new Date()) {
  const event = normalizedEvent(eventData);
  const settings = normalizedSettings(settingsData);
  if (!event?.startsAt || CANCELLED_EVENT_STATES.has(event.status)) {
    return {eligible: false, reason: "event_unavailable", event, settings};
  }
  if (!settings.enabled) {
    return {eligible: false, reason: "preference_disabled", event, settings};
  }
  const dueAt = new Date(
      event.startsAt.getTime() - settings.reminderMinutes * 60 * 1000,
  );
  const deadlineAt = new Date(Math.min(
      event.startsAt.getTime(),
      dueAt.getTime() + DELIVERY_GRACE_MS,
  ));
  if (now.getTime() > deadlineAt.getTime()) {
    return {
      eligible: false,
      reason: "delivery_window_expired",
      event,
      settings,
      dueAt,
      deadlineAt,
    };
  }
  return {eligible: true, event, settings, dueAt, deadlineAt};
}

function eventChanged(beforeData, afterData) {
  const before = normalizedEvent(beforeData);
  const after = normalizedEvent(afterData);
  if (!before || !after) return true;
  return before.startsAt?.getTime() !== after.startsAt?.getTime() ||
    before.title !== after.title ||
    before.ownerUid !== after.ownerUid ||
    before.status !== after.status;
}

async function loadReminderSettings(db, userId) {
  const canonical = await db.collection("users").doc(userId)
      .collection("settings").doc("notifications").get();
  if (canonical.exists) return canonical.data();

  const legacy = await db.collection("users").doc(userId)
      .collection("notificationSettings").doc("settings").get();
  if (legacy.exists) return legacy.data();

  const customer = await db.collection("Customers").doc(userId).get();
  const preferences = customer.data()?.notificationPreferences;
  if (preferences && typeof preferences === "object") {
    return {
      eventReminders: preferences.eventReminders,
      reminderTime: preferences.reminderTime,
    };
  }
  return {};
}

async function userIsEligible(db, eventId, eventData, userId) {
  const event = normalizedEvent(eventData);
  if (event?.ownerUid === userId) return true;
  const ticket = await db.collection("Tickets")
      .where("eventId", "==", eventId)
      .where("customerUid", "==", userId)
      .limit(1)
      .get();
  return !ticket.empty;
}

function terminalUpdate(admin, state, reason) {
  return {
    deliveryState: state,
    terminalReason: reason,
    leaseUntil: null,
    updatedAt: admin.firestore.FieldValue.serverTimestamp(),
  };
}

async function reconcileReminder(admin, eventId, userId, now = new Date()) {
  if (!eventId || !userId) return {state: "ignored"};
  const db = admin.firestore();
  const queueRef = db.collection("scheduledNotifications")
      .doc(reminderDocumentId(eventId, userId));
  const [eventSnapshot, settingsData, existing] = await Promise.all([
    db.collection("Events").doc(eventId).get(),
    loadReminderSettings(db, userId),
    queueRef.get(),
  ]);
  const eventData = eventSnapshot.exists ? eventSnapshot.data() : null;
  const schedule = scheduleFor(eventData, settingsData, now);
  const eligible = eventData ?
    await userIsEligible(db, eventId, eventData, userId) : false;

  if (!schedule.eligible || !eligible) {
    const reason = !eligible ? "recipient_ineligible" : schedule.reason;
    if (existing.exists && !["sent", "in_app_only"].includes(
        existing.data().deliveryState,
    )) {
      await queueRef.set(terminalUpdate(
          admin,
          reason === "delivery_window_expired" ? "expired" : "cancelled",
          reason,
      ), {merge: true});
    }
    return {state: reason === "delivery_window_expired" ? "expired" : "cancelled"};
  }

  const existingData = existing.data() || {};
  const existingEventTime = asDate(existingData.eventTime);
  const eventTimeChanged = existingEventTime &&
    existingEventTime.getTime() !== schedule.event.startsAt.getTime();
  if (["sent", "in_app_only"].includes(existingData.deliveryState) &&
      !eventTimeChanged) {
    await queueRef.set({
      eventTitle: schedule.event.title,
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    }, {merge: true});
    return {state: existingData.deliveryState};
  }

  const nextAttemptAt = schedule.dueAt.getTime() <= now.getTime() ?
    now : schedule.dueAt;
  await queueRef.set({
    type: "event_reminder",
    eventId,
    userId,
    eventTitle: schedule.event.title,
    eventTime: admin.firestore.Timestamp.fromDate(schedule.event.startsAt),
    originalDueAt: admin.firestore.Timestamp.fromDate(schedule.dueAt),
    nextAttemptAt: admin.firestore.Timestamp.fromDate(nextAttemptAt),
    deliveryDeadline: admin.firestore.Timestamp.fromDate(schedule.deadlineAt),
    reminderMinutes: schedule.settings.reminderMinutes,
    title: "Event Reminder",
    body: `Your event "${schedule.event.title}" starts in ` +
      `${schedule.settings.reminderMinutes} minutes`,
    deliveryState: "pending",
    sent: false,
    attemptCount: 0,
    leaseUntil: null,
    lastErrorCategory: null,
    terminalReason: null,
    createdAt: existing.exists ?
      (existingData.createdAt || admin.firestore.FieldValue.serverTimestamp()) :
      admin.firestore.FieldValue.serverTimestamp(),
    updatedAt: admin.firestore.FieldValue.serverTimestamp(),
  }, {merge: true});
  return {state: "pending"};
}

async function eligibleUsersForEvent(db, eventData, eventId) {
  const users = new Set();
  const event = normalizedEvent(eventData);
  if (event?.ownerUid) users.add(event.ownerUid);
  const tickets = await db.collection("Tickets")
      .where("eventId", "==", eventId).get();
  for (const ticket of tickets.docs) {
    const uid = ticket.data().customerUid;
    if (uid) users.add(String(uid));
  }
  return users;
}

async function cancelEventReminders(admin, eventId, reason) {
  const db = admin.firestore();
  const snapshot = await db.collection("scheduledNotifications")
      .where("eventId", "==", eventId).get();
  const writes = [];
  for (const document of snapshot.docs) {
    if (["sent", "in_app_only"].includes(document.data().deliveryState)) continue;
    writes.push(document.ref.set(
        terminalUpdate(admin, "cancelled", reason),
        {merge: true},
    ));
  }
  await Promise.all(writes);
}

async function reconcileEvent(admin, eventId, eventData) {
  if (!eventData) {
    await cancelEventReminders(admin, eventId, "event_deleted");
    return;
  }
  const event = normalizedEvent(eventData);
  if (!event?.startsAt || CANCELLED_EVENT_STATES.has(event.status)) {
    await cancelEventReminders(admin, eventId, "event_unavailable");
    return;
  }
  const users = await eligibleUsersForEvent(admin.firestore(), eventData, eventId);
  await Promise.all([...users].map((uid) =>
    reconcileReminder(admin, eventId, uid),
  ));
}

async function eventIdsForUser(db, userId) {
  const ids = new Set();
  const [tickets, ownedEvents] = await Promise.all([
    db.collection("Tickets").where("customerUid", "==", userId).get(),
    db.collection("Events").where("customerUid", "==", userId).get(),
  ]);
  for (const ticket of tickets.docs) {
    const eventId = ticket.data().eventId;
    if (eventId) ids.add(String(eventId));
  }
  for (const event of ownedEvents.docs) ids.add(event.id);
  return ids;
}

async function claimReminder(admin, document, now) {
  const db = admin.firestore();
  return db.runTransaction(async (transaction) => {
    const current = await transaction.get(document.ref);
    if (!current.exists) return null;
    const data = current.data();
    if (!ACTIVE_STATES.has(data.deliveryState)) return null;
    const nextAttempt = asDate(data.nextAttemptAt);
    if (!nextAttempt || nextAttempt.getTime() > now.getTime()) return null;
    const attempts = Number(data.attemptCount || 0) + 1;
    transaction.update(document.ref, {
      deliveryState: "processing",
      attemptCount: attempts,
      leaseUntil: admin.firestore.Timestamp.fromMillis(now.getTime() + LEASE_MS),
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    });
    return {...data, attemptCount: attempts};
  });
}

async function saveInAppNotification(admin, reminder, queueId, now) {
  const ref = admin.firestore().collection("users").doc(reminder.userId)
      .collection("notifications").doc(queueId);
  await ref.set({
    title: reminder.title || "Event Reminder",
    body: reminder.body || "An event is starting soon.",
    type: "event_reminder",
    eventId: reminder.eventId,
    eventTitle: reminder.eventTitle || "Event",
    createdAt: admin.firestore.Timestamp.fromDate(now),
    isRead: false,
    data: {scheduledNotificationId: queueId},
  }, {merge: true});
}

async function clearInvalidToken(admin, userId, token) {
  const userRef = admin.firestore().collection("users").doc(userId);
  await admin.firestore().runTransaction(async (transaction) => {
    const snapshot = await transaction.get(userRef);
    if (snapshot.data()?.fcmToken === token) {
      transaction.update(userRef, {
        fcmToken: admin.firestore.FieldValue.delete(),
      });
    }
  });
}

async function finishReminder(admin, ref, state, fields = {}) {
  await ref.set({
    deliveryState: state,
    leaseUntil: null,
    updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    ...fields,
  }, {merge: true});
}

function normalizedMessagingError(error) {
  return String(error?.code || "messaging/unknown");
}

async function processReminder(admin, document, now = new Date()) {
  const reminder = await claimReminder(admin, document, now);
  if (!reminder) return {result: "not_claimed"};
  const db = admin.firestore();
  const eventSnapshot = await db.collection("Events").doc(reminder.eventId).get();
  const settings = await loadReminderSettings(db, reminder.userId);
  const eventData = eventSnapshot.exists ? eventSnapshot.data() : null;
  const schedule = scheduleFor(eventData, settings, now);
  const eligible = eventData ? await userIsEligible(
      db, reminder.eventId, eventData, reminder.userId,
  ) : false;
  const deadline = asDate(reminder.deliveryDeadline) || schedule.deadlineAt;

  if (!schedule.eligible || !eligible ||
      !deadline || now.getTime() > deadline.getTime()) {
    const expired = deadline && now.getTime() > deadline.getTime();
    await finishReminder(admin, document.ref, expired ? "expired" : "cancelled", {
      terminalReason: expired ? "delivery_window_expired" :
        (!eligible ? "recipient_ineligible" : schedule.reason),
    });
    return {result: expired ? "expired" : "cancelled"};
  }

  const userSnapshot = await db.collection("users").doc(reminder.userId).get();
  const token = userSnapshot.data()?.fcmToken;
  if (!token) {
    await saveInAppNotification(admin, reminder, document.id, now);
    await finishReminder(admin, document.ref, "in_app_only", {
      terminalReason: "push_token_unavailable",
      completedAt: admin.firestore.Timestamp.fromDate(now),
    });
    return {result: "in_app_only"};
  }

  try {
    await admin.messaging().send({
      token,
      notification: {
        title: reminder.title || "Event Reminder",
        body: reminder.body || "An event is starting soon.",
      },
      data: {
        type: "event_reminder",
        eventId: String(reminder.eventId || ""),
        eventTitle: String(reminder.eventTitle || ""),
        click_action: "FLUTTER_NOTIFICATION_CLICK",
      },
      android: {
        notification: {
          channelId: "attendus_channel",
          priority: "high",
          defaultSound: true,
          defaultVibrateTimings: true,
        },
      },
      apns: {payload: {aps: {sound: "default", badge: 1}}},
    });
    await saveInAppNotification(admin, reminder, document.id, now);
    await finishReminder(admin, document.ref, "sent", {
      sent: true,
      sentAt: admin.firestore.Timestamp.fromDate(now),
      completedAt: admin.firestore.Timestamp.fromDate(now),
      terminalReason: null,
      lastErrorCategory: null,
    });
    return {result: "sent"};
  } catch (error) {
    const category = normalizedMessagingError(error);
    if (PERMANENT_TOKEN_ERRORS.has(category)) {
      await clearInvalidToken(admin, reminder.userId, token);
      await saveInAppNotification(admin, reminder, document.id, now);
      await finishReminder(admin, document.ref, "in_app_only", {
        terminalReason: "invalid_push_token",
        lastErrorCategory: category,
        completedAt: admin.firestore.Timestamp.fromDate(now),
      });
      return {result: "in_app_only"};
    }

    const attempt = Number(reminder.attemptCount || 1);
    const delay = RETRY_DELAYS_MS[Math.min(attempt - 1, RETRY_DELAYS_MS.length - 1)];
    const retryAt = new Date(now.getTime() + delay);
    if (attempt < MAX_ATTEMPTS && retryAt.getTime() <= deadline.getTime()) {
      await finishReminder(admin, document.ref, "retry", {
        nextAttemptAt: admin.firestore.Timestamp.fromDate(retryAt),
        lastErrorCategory: category,
      });
      return {result: "retry"};
    }
    await saveInAppNotification(admin, reminder, document.id, now);
    await finishReminder(admin, document.ref, "in_app_only", {
      terminalReason: "push_delivery_failed",
      lastErrorCategory: category,
      completedAt: admin.firestore.Timestamp.fromDate(now),
    });
    return {result: "in_app_only"};
  }
}

async function recoverExpiredLeases(admin, now) {
  const db = admin.firestore();
  const snapshot = await db.collection("scheduledNotifications")
      .where("deliveryState", "==", "processing")
      .where("leaseUntil", "<=", admin.firestore.Timestamp.fromDate(now))
      .limit(100).get();
  await Promise.all(snapshot.docs.map((document) => document.ref.set({
    deliveryState: "retry",
    nextAttemptAt: admin.firestore.Timestamp.fromDate(now),
    leaseUntil: null,
    lastErrorCategory: "processing_lease_expired",
    updatedAt: admin.firestore.FieldValue.serverTimestamp(),
  }, {merge: true})));
  return snapshot.size;
}

async function runScheduledWorker(admin, now = new Date()) {
  const db = admin.firestore();
  const recovered = await recoverExpiredLeases(admin, now);
  const snapshot = await db.collection("scheduledNotifications")
      .where("deliveryState", "in", ["pending", "retry"])
      .where("nextAttemptAt", "<=", admin.firestore.Timestamp.fromDate(now))
      .orderBy("nextAttemptAt")
      .limit(100).get();
  const results = {};
  for (const document of snapshot.docs) {
    const outcome = await processReminder(admin, document, now);
    results[outcome.result] = (results[outcome.result] || 0) + 1;
  }
  logger.info("Scheduled reminder worker completed", {
    recovered,
    selected: snapshot.size,
    results,
  });
  return {recovered, selected: snapshot.size, results};
}

function createScheduledReminderFunctions(admin) {
  const sendScheduledNotifications = onSchedule({
    schedule: "every 1 minutes",
    region: REGION,
    maxInstances: 1,
    timeoutSeconds: 120,
  }, async () => runScheduledWorker(admin));

  const reconcileEventRemindersV2 = onDocumentWritten({
    document: "Events/{eventId}",
    region: REGION,
    maxInstances: 10,
  }, async (event) => {
    const before = event.data?.before?.data();
    const after = event.data?.after?.data();
    if (before && after && !eventChanged(before, after)) return;
    await reconcileEvent(admin, event.params.eventId, after);
  });

  const reconcileTicketRemindersV2 = onDocumentWritten({
    document: "Tickets/{ticketId}",
    region: REGION,
    maxInstances: 20,
  }, async (event) => {
    const before = event.data?.before?.data();
    const after = event.data?.after?.data();
    const pairs = new Set();
    for (const ticket of [before, after]) {
      if (ticket?.eventId && ticket?.customerUid) {
        pairs.add(`${ticket.eventId}\u0000${ticket.customerUid}`);
      }
    }
    await Promise.all([...pairs].map((pair) => {
      const [eventId, userId] = pair.split("\u0000");
      return reconcileReminder(admin, eventId, userId);
    }));
  });

  const reconcileReminderSettingsV2 = onDocumentWritten({
    document: "users/{userId}/settings/notifications",
    region: REGION,
    maxInstances: 10,
  }, async (event) => {
    const userId = event.params.userId;
    const eventIds = await eventIdsForUser(admin.firestore(), userId);
    await Promise.all([...eventIds].map((eventId) =>
      reconcileReminder(admin, eventId, userId),
    ));
  });

  return {
    sendScheduledNotifications,
    reconcileEventRemindersV2,
    reconcileTicketRemindersV2,
    reconcileReminderSettingsV2,
  };
}

module.exports = {
  DEFAULT_REMINDER_MINUTES,
  DELIVERY_GRACE_MS,
  MAX_ATTEMPTS,
  asDate,
  createScheduledReminderFunctions,
  eventChanged,
  normalizedEvent,
  normalizedSettings,
  reconcileEvent,
  reconcileReminder,
  reminderDocumentId,
  runScheduledWorker,
  scheduleFor,
};
