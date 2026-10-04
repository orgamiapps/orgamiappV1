"use strict";
const crypto = require("node:crypto");
const {demoDeliveryCaptureEnabled} = require("../communications/delivery");
const {canDeliverPush} = require("./push-tokens");
const {qualificationDecision, captureQualification} = require("../communications/qualification-isolation");
const idFor = (uid, key) => crypto.createHash("sha256").update(JSON.stringify([uid, key])).digest("hex");
const canNotifyNearby = (event) => event?.private === false && ["active", "scheduled"].includes(event.status) && Boolean(event.eventLocation);
function createLegacyNotificationSender(admin) {
  return async (userId, data, db, sourceKey, condition = null) => {
    if (!sourceKey || typeof sourceKey !== "string") throw Error("A stable notification source identity is required");
    const id = idFor(userId, sourceKey);
    const markerRef = db.collection("LegacyNotificationDeliveries").doc(id);
    const userRef = db.collection("users").doc(userId);
    const notificationRef = userRef.collection("notifications").doc(id);
    const context = {recipientUid: userId, actorUid: data.actorUid || data.data?.actorUid,
      eventId: data.eventId, organizationId: data.organizationId || data.data?.organizationId,
      conversationId: data.data?.conversationId};
    const preferences = {org_update: ["organizationUpdates"], organizer_feedback: ["organizerFeedback"],
      group_event: ["newEvents", "organizationUpdates"], new_event: ["newEvents"], ticket_update: ["ticketUpdates"], event_feedback: ["eventFeedback"]}[data.type] || [];
    const conditions = Array.isArray(condition) ? condition : condition ? [condition] : [];
    const eligible = async (tx) => {
      const [deleting, current, settings, legacySettings] = await Promise.all([
        tx.get(db.collection("account_deletion_jobs").doc(userId)),
        Promise.all(conditions.map((rule) => tx.get(db.doc(rule.path)))),
        tx.get(userRef.collection("settings").doc("notifications")),
        tx.get(userRef.collection("notificationSettings").doc("settings")),
      ]);
      if (deleting.exists || preferences.some((preference) => settings.get(preference) === false || legacySettings.get(preference) === false)) return false;
      for (let index = 0; index < conditions.length; index++) {
        const rule = conditions[index], document = current[index];
        if (!document.exists) return false;
        if (rule.approvedAdmin && (document.get("status") !== "approved" || !["admin", "owner"].includes(String(document.get("role") || "").toLowerCase()))) return false;
        if (rule.fields && Object.entries(rule.fields).some(([field, value]) => document.get(field) !== value)) return false;
      }
      return true;
    };
    const attempt = await db.runTransaction(async (tx) => {
      const [marker, user, allowed] = await Promise.all([tx.get(markerRef), tx.get(userRef), eligible(tx)]);
      if (marker.exists || !allowed) return null;
      const qualification = await qualificationDecision(db, context, tx);
      if (qualification.mode !== "normal") {
        if (qualification.mode === "capture") await captureQualification(db, tx, qualification, context, `legacy:${sourceKey}`, data);
        return {intercepted: true, mode: qualification.mode};
      }
      const token = user.get("fcmToken");
      const capture = demoDeliveryCaptureEnabled();
      const wantsPush = typeof token === "string" && token.length > 0 && await canDeliverPush(db, userId, token, tx);
      const state = capture ? "emulator_capture" : wantsPush ? "delivery_unknown" : "not_requested";
      const stamp = admin.firestore.FieldValue.serverTimestamp();
      tx.create(notificationRef, {title: data.title, body: data.body, type: data.type,
        eventId: data.eventId || null, eventTitle: data.eventTitle || null,
        data: data.data || {}, createdAt: stamp, isRead: false});
      // Reserve the external attempt before handoff. If acknowledgement is lost,
      // the durable unknown state prevents an unsafe automatic push replay.
      tx.create(markerRef, {userId, sourceHash: idFor("source", sourceKey), state, createdAt: stamp});
      return {token, capture, wantsPush};
    });
    if (attempt?.intercepted) return {notificationId: id, status: `qualification_${attempt.mode}`};
    if (!attempt || attempt.capture || !attempt.wantsPush) return {notificationId: id, status: "recorded_or_replayed"};
    const allowed = await db.runTransaction(async (tx) => {
      const [marker, valid, currentUser, ownership] = await Promise.all([tx.get(markerRef), eligible(tx), tx.get(userRef), canDeliverPush(db, userId, attempt.token, tx)]);
      if (!marker.exists || marker.get("state") !== "delivery_unknown") return false;
      const qualification = await qualificationDecision(db, context, tx);
      const currentRecipient = valid && ownership && currentUser.get("fcmToken") === attempt.token && qualification.mode === "normal";
      if (!currentRecipient) tx.update(markerRef, {state: "suppressed", updatedAt: admin.firestore.FieldValue.serverTimestamp()});
      return currentRecipient;
    });
    if (!allowed) return {notificationId: id, status: "suppressed"};
    try {
      const result = await admin.messaging().send({token: attempt.token,
        notification: {title: data.title, body: data.body},
        data: {type: data.type, recipientUid: userId, eventId: data.eventId || "", eventTitle: data.eventTitle || "",
          conversationId: data.data?.conversationId || "", organizationId: data.data?.organizationId || "",
          notificationId: id, click_action: "FLUTTER_NOTIFICATION_CLICK"},
        android: {notification: {channelId: "orgami_channel", priority: "high", defaultSound: true, defaultVibrateTimings: true}},
        apns: {payload: {aps: {sound: "default", badge: 1}}}});
      await db.runTransaction(async (tx) => {
        const marker = await tx.get(markerRef);
        if (marker.exists && marker.get("state") === "delivery_unknown") tx.update(markerRef, {state: "accepted", providerMessageId: result, updatedAt: admin.firestore.FieldValue.serverTimestamp()});
      });
      return {notificationId: id, status: "accepted"};
    } catch (_error) {
      // Preserve the original durable unknown record on either provider or
      // completion-store failure. A retried trigger never replays this send.
      return {notificationId: id, status: "delivery_unknown"};
    }
  };
}
module.exports = {createLegacyNotificationSender, canNotifyNearby};
