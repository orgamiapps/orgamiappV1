"use strict";
const {publicOrigin} = require("../public-web/origin");

const {FieldValue} = require("firebase-admin/firestore");
const {digest} = require("./service");
const {qualificationDecision, captureQualification} = require("../communications/qualification-isolation");

async function deliverMessageNotifications(db, messaging, event) {
  const message = event.data?.data();
  if (!message?.conversationId) return;
  const conversation = (await db.collection("Conversations").doc(message.conversationId).get()).data();
  if (!conversation?.participantIds?.includes(message.senderId)) return;
  const sender = (await db.collection("Customers").doc(message.senderId).get()).data();
  const recipients = message.notificationRecipients || conversation.participantIds.filter((id) => id !== message.senderId);
  for (const uid of recipients) {
    if (!conversation.participantIds.includes(uid) || uid === message.senderId) continue;
    const userRef = db.collection("users").doc(uid);
    const [user, settings, legacy, person, blockA, blockB] = await db.getAll(userRef,
        userRef.collection("settings").doc("notifications"), userRef.collection("notificationSettings").doc("settings"),
        db.collection("Customers").doc(uid), db.doc(`Customers/${uid}/blocks/${message.senderId}`),
        db.doc(`Customers/${message.senderId}/blocks/${uid}`));
    if (blockA.exists || blockB.exists) continue;
    const customerPreferences = person.data()?.notificationPreferences;
    const customerConfig = customerPreferences && typeof customerPreferences === "object" && !Array.isArray(customerPreferences) ? customerPreferences : {};
    // An existing settings document is authoritative, including its defaults.
    // Customer's older editor named the ordinary-message control "messages".
    const config = settings.exists ? settings.data() : legacy.exists ? legacy.data() : {
      ...customerConfig, ...(Object.hasOwn(customerConfig, "messages") ? {messagesAll: customerConfig.messages} : {}),
    };
    const mention = Boolean(person.data()?.username && message.content?.includes(`@${person.data().username}`));
    const normal = config.messagesAll !== false && config.messageNotifications !== false;
    if (!normal && !(mention && config.messageMentions !== false)) continue;
    const title = conversation.isGroup ? `${conversation.groupName || "Group"} · ${sender?.name || "Someone"}` : sender?.name || "Someone";
    const type = normal ? "new_message" : "message_mention";
    const notificationRef = userRef.collection("notifications").doc(`message_${digest(event.data.id)}`);
    const context = {actorUid: message.senderId, recipientUid: uid, conversationId: message.conversationId};
    // A durable claim prevents duplicate trigger deliveries from sending twice.
    // An interrupted FCM request stays 'dispatching' (unknown delivery), never blindly retried.
    const claimed = await db.runTransaction(async (tx) => {
      const [existing, liveConversation, recipientDeletion, senderDeletion, liveMessage] = await Promise.all([
        tx.get(notificationRef), tx.get(db.collection("Conversations").doc(message.conversationId)),
        tx.get(db.collection("account_deletion_jobs").doc(uid)),
        tx.get(db.collection("account_deletion_jobs").doc(message.senderId)), tx.get(event.data.ref),
      ]);
      if (existing.exists || recipientDeletion.exists || senderDeletion.exists || !liveMessage.exists ||
          !liveConversation.get("participantIds")?.includes(uid) ||
          !liveConversation.get("participantIds")?.includes(message.senderId)) return false;
      const qualification = await qualificationDecision(db, context, tx);
      if (qualification.mode !== "normal") {
        if (qualification.mode === "capture") await captureQualification(db, tx, qualification, context, `message:${event.data.id}`,
            {title, body: message.content, type, conversationId: message.conversationId});
        return false;
      }
      tx.create(notificationRef, {title, body: message.content, type, conversationId: message.conversationId,
        messageId: event.data.id, senderId: message.senderId, data: {conversationId: message.conversationId}, createdAt: FieldValue.serverTimestamp(),
        isRead: false, pushStatus: user.data()?.fcmToken ? "dispatching" : "no-token"});
      return true;
    });
    if (!claimed || !user.data()?.fcmToken) continue;
    try {
      if ((await qualificationDecision(db, context)).mode !== "normal" ||
          !await require("../notifications/push-tokens").canDeliverPush(db, uid, user.get("fcmToken"))) {
        await notificationRef.update({pushStatus: "suppressed", pushErrorCode: "token_owner_changed"});
        continue;
      }
      await messaging.send({token: user.data().fcmToken, notification: {title, body: message.content.slice(0, 100)},
        data: {recipientUid: uid, type, conversationId: message.conversationId, messageId: event.data.id, senderId: message.senderId},
        webpush: {fcmOptions: {link: `${publicOrigin()}/?conversationId=${encodeURIComponent(message.conversationId)}`}},
        android: {notification: {channelId: "attendus_channel"}}, apns: {payload: {aps: {sound: "default"}}}});
      await notificationRef.update({pushStatus: "sent"});
    } catch (error) {
      await notificationRef.update({pushStatus: "unknown", pushErrorCode: String(error.code || "unknown")})
          .catch((updateError) => { if (updateError.code !== 5 && updateError.code !== "not-found") throw updateError; });
    }
  }
}

module.exports = {deliverMessageNotifications};
