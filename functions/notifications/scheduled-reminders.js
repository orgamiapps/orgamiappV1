"use strict";
const {qualificationDecision, interceptQualification} = require("../communications/qualification-isolation");

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

async function loadReminderSettings(db, userId, tx = null) {
  const read = (ref) => tx ? tx.get(ref) : ref.get();
  const canonical = await read(db.collection("users").doc(userId)
      .collection("settings").doc("notifications"));
  if (canonical.exists) return canonical.data();

  const legacy = await read(db.collection("users").doc(userId)
      .collection("notificationSettings").doc("settings"));
  if (legacy.exists) return legacy.data();

  const customer = await read(db.collection("Customers").doc(userId));
  const preferences = customer.data()?.notificationPreferences;
  if (preferences && typeof preferences === "object") {
    return {
      eventReminders: preferences.eventReminders,
      reminderTime: preferences.reminderTime,
    };
  }
  return {};
}

async function userIsEligible(db, eventId, eventData, userId, tx = null) {
  const read = (ref) => tx ? tx.get(ref) : ref.get();
  const event = normalizedEvent(eventData);
  if ((await read(db.collection("account_deletion_jobs").doc(userId))).exists) return false;
  if (event?.ownerUid === userId) return true;
  const [tickets, registrations] = await Promise.all([
    read(db.collection("Tickets").where("eventId", "==", eventId).where("customerUid", "==", userId)),
    read(db.collection("RegisterAttendance").where("eventId", "==", eventId).where("customerUid", "==", userId)),
  ]);
  const rows = require("../events/roster").buildRoster(registrations.docs.map((doc) => ({id: doc.id, ...doc.data()})), tickets.docs.map((doc) => ({id: doc.id, ...doc.data()})), [], [], eventData);
  return rows.some((row) => row.status === "confirmed");
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
  return db.runTransaction(async (tx) => {
  const [eventSnapshot, settingsData, existing] = await Promise.all([
    tx.get(db.collection("Events").doc(eventId)),
    loadReminderSettings(db, userId, tx),
    tx.get(queueRef),
  ]);
  const eventData = eventSnapshot.exists ? eventSnapshot.data() : null;
  const schedule = scheduleFor(eventData, settingsData, now);
  const eligible = eventData ?
    await userIsEligible(db, eventId, eventData, userId, tx) : false;

  if (!schedule.eligible || !eligible) {
    const reason = !eligible ? "recipient_ineligible" : schedule.reason;
    if (existing.exists && !["sent", "in_app_only", "unknown"].includes(
        existing.data().deliveryState,
    )) {
      tx.set(queueRef, terminalUpdate(
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
  if (["sent", "in_app_only", "unknown"].includes(existingData.deliveryState) &&
      !eventTimeChanged) {
    tx.set(queueRef, {
      eventTitle: schedule.event.title,
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    }, {merge: true});
    return {state: existingData.deliveryState};
  }

  if (!eventTimeChanged && existingData.deliveryState === "processing") return {state: "processing"};
  const nextAttemptAt = schedule.dueAt.getTime() <= now.getTime() ?
    now : schedule.dueAt;
  tx.set(queueRef, {
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
    claimId: null,
    pushDispatching: false,
    lastErrorCategory: null,
    terminalReason: null,
    createdAt: existing.exists ?
      (existingData.createdAt || admin.firestore.FieldValue.serverTimestamp()) :
      admin.firestore.FieldValue.serverTimestamp(),
    updatedAt: admin.firestore.FieldValue.serverTimestamp(),
  }, {merge: true});
  return {state: "pending"};
  });
}

async function eligibleUsersForEvent(db, eventData, eventId) {
  const users = new Set();
  const event = normalizedEvent(eventData);
  if (event?.ownerUid) users.add(event.ownerUid);
  const [tickets, registrations] = await Promise.all([db.collection("Tickets").where("eventId", "==", eventId).get(), db.collection("RegisterAttendance").where("eventId", "==", eventId).get()]);
  const rows = require("../events/roster").buildRoster(registrations.docs.map((doc) => ({id: doc.id, ...doc.data()})), tickets.docs.map((doc) => ({id: doc.id, ...doc.data()})), [], [], eventData);
  for (const row of rows) if (row.uid && row.status === "confirmed") users.add(row.uid);
  return users;
}

async function cancelEventReminders(admin, eventId, reason) {
  const db = admin.firestore();
  const snapshot = await db.collection("scheduledNotifications")
      .where("eventId", "==", eventId).get();
  const writes = [];
  for (const document of snapshot.docs) {
    if (["sent", "in_app_only"].includes(document.data().deliveryState)) continue;
    writes.push(db.runTransaction(async (tx) => {
      const [current, event] = await Promise.all([tx.get(document.ref), tx.get(db.collection("Events").doc(eventId))]);
      const normalized = normalizedEvent(event.data());
      if (!current.exists || ["sent", "in_app_only", "unknown"].includes(current.get("deliveryState")) ||
          (normalized?.startsAt && !CANCELLED_EVENT_STATES.has(normalized.status))) return;
      tx.update(document.ref, terminalUpdate(admin, "cancelled", reason));
    }));
  }
  await Promise.all(writes);
}

async function reconcileEvent(admin, eventId, eventData) {
  // Trigger snapshots may arrive out of order; reconcile the current document.
  eventData = (await admin.firestore().collection("Events").doc(eventId).get()).data();
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
  const [tickets, ownedEvents, registrations] = await Promise.all([
    db.collection("Tickets").where("customerUid", "==", userId).get(),
    db.collection("Events").where("customerUid", "==", userId).get(),
    db.collection("RegisterAttendance").where("customerUid", "==", userId).get(),
  ]);
  for (const ticket of [...tickets.docs, ...registrations.docs]) {
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
    if (attempts > MAX_ATTEMPTS) {
      transaction.update(document.ref, terminalUpdate(admin, "expired", "attempts_exhausted"));
      return null;
    }
    const claimId = crypto.randomUUID();
    transaction.update(document.ref, {
      deliveryState: "processing",
      claimId,
      pushDispatching: false,
      attemptCount: attempts,
      leaseUntil: admin.firestore.Timestamp.fromMillis(now.getTime() + LEASE_MS),
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    });
    return {...data, attemptCount: attempts, claimId};
  });
}

function reminderInboxId(queueId, eventTime) {
  const time = asDate(eventTime);
  if (!time) throw Error("Reminder inbox requires an exact event time.");
  return `${queueId}_${time.getTime()}`;
}

async function saveInAppNotification(admin, reminder, queueId, now) {
  const ref = admin.firestore().collection("users").doc(reminder.userId)
      .collection("notifications").doc(reminderInboxId(queueId, reminder.eventTime));
  await admin.firestore().runTransaction(async (transaction) => {
    const [existing, deleting] = await Promise.all([
      transaction.get(ref), transaction.get(admin.firestore().collection("account_deletion_jobs").doc(reminder.userId)),
    ]);
    const queue = await transaction.get(admin.firestore().collection("scheduledNotifications").doc(queueId));
    const event = await transaction.get(admin.firestore().collection("Events").doc(reminder.eventId));
    const settings = await loadReminderSettings(admin.firestore(), reminder.userId, transaction);
    const schedule = scheduleFor(event.data(), settings, now);
    const eligible = event.exists && await userIsEligible(admin.firestore(), reminder.eventId, event.data(), reminder.userId, transaction);
    const isolation = await qualificationDecision(admin.firestore(), {recipientUid: reminder.userId, eventId: reminder.eventId}, transaction);
    if (isolation.mode !== "normal" || existing.exists || deleting.exists || !eligible || !schedule.eligible ||
        queue.get("claimId") !== reminder.claimId || queue.get("deliveryState") !== "processing" ||
        schedule.event.startsAt.getTime() !== asDate(reminder.eventTime)?.getTime()) return;
    transaction.create(ref, {
    title: reminder.title || "Event Reminder",
    body: reminder.body || "An event is starting soon.",
    type: "event_reminder",
    eventId: reminder.eventId,
    eventTitle: reminder.eventTitle || "Event",
    createdAt: admin.firestore.Timestamp.fromDate(now),
    isRead: false,
    data: {scheduledNotificationId: queueId},
    });
  });
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

async function finishReminder(admin, ref, state, fields = {}, claimId) {
  return admin.firestore().runTransaction(async (tx) => {
    const current = await tx.get(ref);
    if (!current.exists || current.get("deliveryState") !== "processing" || current.get("claimId") !== claimId) return false;
    tx.update(ref, {deliveryState: state, leaseUntil: null,
      updatedAt: admin.firestore.FieldValue.serverTimestamp(), ...fields});
    return true;
  });
}

function normalizedMessagingError(error) {
  return String(error?.code || "messaging/unknown");
}

async function processReminder(admin, document, now = new Date()) {
  const reminder = await claimReminder(admin, document, now);
  if (!reminder) return {result: "not_claimed"};
  const db = admin.firestore();
  const finish = (state, fields) => finishReminder(admin, document.ref, state, fields, reminder.claimId);
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
    await finish(expired ? "expired" : "cancelled", {
      terminalReason: expired ? "delivery_window_expired" :
        (!eligible ? "recipient_ineligible" : schedule.reason),
    });
    return {result: expired ? "expired" : "cancelled"};
  }

  const context = {recipientUid: reminder.userId, eventId: reminder.eventId};
  const isolation = await interceptQualification(db, context, `reminder:${reminderInboxId(document.id, reminder.eventTime)}`, {
    title: reminder.title || "Event Reminder", body: reminder.body || "An event is starting soon.", type: "event_reminder", eventId: reminder.eventId,
  });
  if (isolation.mode !== "normal") {
    const state = isolation.mode === "capture" ? "captured" : "cancelled";
    await finish(state, {terminalReason: `qualification_${isolation.mode}`, completedAt: admin.firestore.Timestamp.fromDate(now)});
    return {result: state};
  }
  const userSnapshot = await db.collection("users").doc(reminder.userId).get();
  const token = userSnapshot.data()?.fcmToken;
  if (!token || !await require("./push-tokens").canDeliverPush(db, reminder.userId, token)) {
    await saveInAppNotification(admin, reminder, document.id, now);
    await finish("in_app_only", {
      terminalReason: "push_token_unavailable",
      completedAt: admin.firestore.Timestamp.fromDate(now),
    });
    return {result: "in_app_only"};
  }

  await saveInAppNotification(admin, reminder, document.id, now);
  const dispatch = await db.runTransaction(async (tx) => {
    const current = await tx.get(document.ref);
    const freshEvent = await tx.get(db.collection("Events").doc(reminder.eventId));
    const freshSettings = await loadReminderSettings(db, reminder.userId, tx);
    const currentSchedule = scheduleFor(freshEvent.data(), freshSettings, now);
    const currentEligible = freshEvent.exists && await userIsEligible(db, reminder.eventId, freshEvent.data(), reminder.userId, tx);
    const tokenEligible = await require("./push-tokens").canDeliverPush(db, reminder.userId, token, tx);
    const freshIsolation = await qualificationDecision(db, context, tx);
    if (freshIsolation.mode !== "normal" || !current.exists || current.get("claimId") !== reminder.claimId || current.get("deliveryState") !== "processing" ||
        !currentSchedule.eligible || !currentEligible || !tokenEligible ||
        currentSchedule.event.startsAt.getTime() !== asDate(reminder.eventTime)?.getTime()) return false;
    tx.update(document.ref, {pushDispatching: true});
    return true;
  });
  if (!dispatch) { await finish("cancelled", {terminalReason: "delivery_context_changed"}); return {result: "cancelled"}; }
  try {
    await admin.messaging().send({
      token,
      notification: {
        title: reminder.title || "Event Reminder",
        body: reminder.body || "An event is starting soon.",
      },
      data: {
        type: "event_reminder",
        recipientUid: String(reminder.userId),
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
    await finish("sent", {
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
      await finish("in_app_only", {
        terminalReason: "invalid_push_token",
        lastErrorCategory: category,
        completedAt: admin.firestore.Timestamp.fromDate(now),
      });
      return {result: "in_app_only"};
    }

    // Provider errors can be lost acknowledgements. Keep the in-app result,
    // preserve the unknown outcome, and never automatically send it again.
    await saveInAppNotification(admin, reminder, document.id, now);
    await finish("unknown", {
      terminalReason: "push_delivery_unknown", lastErrorCategory: category,
      completedAt: admin.firestore.Timestamp.fromDate(now),
    });
    return {result: "unknown"};
  }
}

async function recoverExpiredLeases(admin, now) {
  const db = admin.firestore();
  const snapshot = await db.collection("scheduledNotifications")
      .where("deliveryState", "==", "processing")
      .where("leaseUntil", "<=", admin.firestore.Timestamp.fromDate(now))
      .limit(100).get();
  await Promise.all(snapshot.docs.map((document) => db.runTransaction(async (tx) => {
    const current = await tx.get(document.ref);
    if (!current.exists || current.get("deliveryState") !== "processing" || asDate(current.get("leaseUntil"))?.getTime() > now.getTime()) return;
    const unknown = current.get("pushDispatching") === true;
    tx.update(document.ref, {
      deliveryState: unknown ? "unknown" : "retry",
      nextAttemptAt: admin.firestore.Timestamp.fromDate(now), leaseUntil: null,
      lastErrorCategory: unknown ? "provider_handoff_unknown" : "processing_lease_expired",
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    });
  })));
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

  const reconcileRegistrationRemindersV2 = onDocumentWritten({
    document: "RegisterAttendance/{registrationId}",
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
    reconcileRegistrationRemindersV2,
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
  reminderInboxId,
  runScheduledWorker,
  scheduleFor,
};
