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

const {createHash} = require("node:crypto");
const {canDeliverPush} = require("./push-tokens");
const {qualificationDecision, captureQualification} = require("../communications/qualification-isolation");

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
      fingerprint: createHash("sha256").update(JSON.stringify({
        userIds: [...userIds].sort(), title, body, type,
        data: Object.fromEntries(Object.entries(data).sort(([a], [b]) => a.localeCompare(b))), reason: operation.reason,
      })).digest("hex"),
    });
    if (reservation.result) return reservation.result;

    const now = admin.firestore.Timestamp.now();
    const refs = userIds.map((uid) => db.collection("users").doc(uid));
    const recipients = await db.getAll(...refs);
    const messages = [];
    let recipientCount = 0;
    for (const recipient of recipients) {
      const context = {actorUid: actor.uid, recipientUid: recipient.id, eventId: data.eventId, organizationId: data.organizationId, conversationId: data.conversationId};
      const notificationRef = recipient.ref.collection("notifications").doc(`admin_${reservation.ref.id}`);
      const accepted = await db.runTransaction(async (transaction) => {
        const [current, deleting, existing] = await Promise.all([
          transaction.get(recipient.ref), transaction.get(db.collection("account_deletion_jobs").doc(recipient.id)),
          transaction.get(notificationRef),
        ]);
        if (!current.exists || deleting.exists) return false;
        const isolation = await qualificationDecision(db, context, transaction);
        if (isolation.mode !== "normal") {
          if (isolation.mode === "capture") await captureQualification(db, transaction, isolation, context, `admin:${reservation.ref.id}`, {title, body, type, data});
          return false;
        }
        if (!existing.exists) transaction.create(notificationRef, {
          title, body, type, data, isRead: false, createdAt: now, createdBy: actor.uid,
        });
        return true;
      });
      if (!accepted) continue;
      recipientCount += 1;
      const token = recipient.data()?.fcmToken;
      if (await canDeliverPush(db, recipient.id, token)) messages.push({
        token, notification: {title, body}, data: {...data, type, recipientUid: recipient.id},
      });
    }
    // Recheck ownership at the provider boundary after the bounded inbox fanout.
    const deliverable = [];
    for (const message of messages) {
      const context = {actorUid: actor.uid, recipientUid: message.data.recipientUid, eventId: data.eventId, organizationId: data.organizationId, conversationId: data.conversationId};
      if ((await qualificationDecision(db, context)).mode === "normal" && await canDeliverPush(db, message.data.recipientUid, message.token)) deliverable.push(message);
    }
    let pushSuccessCount = 0;
    let pushFailureCount = 0;
    if (deliverable.length) {
      const response = await admin.messaging().sendEach(deliverable);
      pushSuccessCount = response.successCount;
      pushFailureCount = response.failureCount;
    }
    const result = {
      status: "ok",
      recipientCount,
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
      recipientCount,
      result,
    });
    return result;
  }

  return {sendCustomNotifications};
}

module.exports = {createAdminDispatchHandlers};
