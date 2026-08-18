"use strict";

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

async function audit(db, admin, entry) {
  await db.collection("admin_audit_logs").add({
    ...entry,
    timestamp: admin.firestore.FieldValue.serverTimestamp(),
  });
}

function createAdminDispatchHandlers({admin}) {
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

  return {sendCustomNotifications};
}

module.exports = {createAdminDispatchHandlers};
