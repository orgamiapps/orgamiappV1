"use strict";

const {HttpsError} = require("firebase-functions/v2/https");
const {
  enforceRateLimit,
  requireAdminCallable,
  requireConfirmedOperation,
  requireDataMap,
  requireString,
  requireStringArray,
  reserveIdempotencyKey,
} = require("../security/callable");

const NOTIFICATION_ROLES = ["super_admin", "support", "moderator"];
const SMS_ROLES = ["super_admin", "support"];

async function audit(db, admin, entry) {
  await db.collection("admin_audit_logs").add({
    ...entry,
    timestamp: admin.firestore.FieldValue.serverTimestamp(),
  });
}

function createAdminDispatchHandlers({admin, twilioClient, twilioFromNumber, logger}) {
  const db = admin.firestore();

  async function sendCustomNotifications(req) {
    const actor = await requireAdminCallable(req, db, NOTIFICATION_ROLES);
    const operation = requireConfirmedOperation(req.data);
    const userIds = requireStringArray(req.data?.userIds, "Recipients", {
      max: 500,
      pattern: /^[A-Za-z0-9_-]{1,128}$/,
    });
    const title = requireString(req.data?.title, "Title", {max: 120});
    const body = requireString(req.data?.body, "Body", {max: 1000});
    const type = requireString(req.data?.type || "custom", "Type", {max: 64});
    const data = requireDataMap(req.data?.data);

    await enforceRateLimit(db, {
      uid: actor.uid,
      operation: "sendCustomNotifications",
      limit: 5,
    });
    const reservation = await reserveIdempotencyKey(db, {
      operation: "sendCustomNotifications",
      uid: actor.uid,
      key: operation.idempotencyKey,
    });
    if (reservation.result) return reservation.result;

    const now = admin.firestore.Timestamp.now();
    const refs = userIds.map((uid) => db.collection("users").doc(uid));
    const recipients = await db.getAll(...refs);
    const tokens = [];
    let batch = db.batch();
    let writes = 0;
    for (const recipient of recipients) {
      const notificationRef = recipient.ref.collection("notifications").doc();
      batch.set(notificationRef, {
        title,
        body,
        type,
        data,
        isRead: false,
        createdAt: now,
        createdBy: actor.uid,
      });
      writes += 1;
      const token = recipient.data()?.fcmToken;
      if (typeof token === "string" && token.length >= 10) tokens.push(token);
      if (writes === 400) {
        await batch.commit();
        batch = db.batch();
        writes = 0;
      }
    }
    if (writes) await batch.commit();

    let pushSuccessCount = 0;
    let pushFailureCount = 0;
    if (tokens.length) {
      const response = await admin.messaging().sendEachForMulticast({
        tokens,
        notification: {title, body},
        data: {type, ...data},
      });
      pushSuccessCount = response.successCount;
      pushFailureCount = response.failureCount;
    }
    const result = {
      status: "ok",
      recipientCount: userIds.length,
      pushSuccessCount,
      pushFailureCount,
    };
    await reservation.ref.set({status: "completed", result, completedAt: now}, {merge: true});
    await audit(db, admin, {
      action: "notifications.send_custom",
      actorUid: actor.uid,
      actorRoles: actor.roles,
      reason: operation.reason,
      idempotencyKey: operation.idempotencyKey,
      recipientCount: userIds.length,
      result,
    });
    return result;
  }

  async function sendBulkSms(req) {
    const actor = await requireAdminCallable(req, db, SMS_ROLES);
    const operation = requireConfirmedOperation(req.data);
    const phoneNumbers = requireStringArray(req.data?.phoneNumbers, "Phone numbers", {
      max: 50,
      pattern: /^\+[1-9][0-9]{7,14}$/,
    });
    const message = requireString(req.data?.message, "Message", {max: 1000});
    if (!twilioClient || !twilioFromNumber) {
      throw new HttpsError("failed-precondition", "SMS delivery is not configured.");
    }

    await enforceRateLimit(db, {
      uid: actor.uid,
      operation: "sendBulkSms",
      limit: 2,
    });
    const reservation = await reserveIdempotencyKey(db, {
      operation: "sendBulkSms",
      uid: actor.uid,
      key: operation.idempotencyKey,
    });
    if (reservation.result) return reservation.result;

    let sent = 0;
    const failures = [];
    for (let offset = 0; offset < phoneNumbers.length; offset += 10) {
      const group = phoneNumbers.slice(offset, offset + 10);
      const results = await Promise.allSettled(group.map((to) =>
        twilioClient.messages.create({to, from: twilioFromNumber, body: message})));
      results.forEach((result, index) => {
        if (result.status === "fulfilled") sent += 1;
        else failures.push({to: group[index], error: String(result.reason?.message || result.reason)});
      });
    }
    const result = {
      status: "ok",
      recipientCount: phoneNumbers.length,
      sent,
      failed: failures.length,
    };
    await reservation.ref.set({
      status: "completed",
      result,
      completedAt: admin.firestore.Timestamp.now(),
    }, {merge: true});
    await audit(db, admin, {
      action: "notifications.send_sms",
      actorUid: actor.uid,
      actorRoles: actor.roles,
      reason: operation.reason,
      idempotencyKey: operation.idempotencyKey,
      recipientCount: phoneNumbers.length,
      failureSample: failures.slice(0, 10),
      result,
    });
    logger.info("Administrative SMS dispatch completed", result);
    return result;
  }

  return {sendBulkSms, sendCustomNotifications};
}

module.exports = {createAdminDispatchHandlers};
