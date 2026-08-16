"use strict";

const {onDocumentWritten} = require("firebase-functions/v2/firestore");
const {onSchedule} = require("firebase-functions/v2/scheduler");
const {FieldValue, Timestamp} = require("firebase-admin/firestore");
const {distanceBetween} = require("geofire-common");
const {activePublicEvent} = require("./marketplace");

function eligible(data) {
  return activePublicEvent(data) && data.private !== true;
}

function createQueueDiscoveryNotifications(admin) {
  const db = admin.firestore();
  return onDocumentWritten({document: "Events/{eventId}", region: "us-central1"}, async (event) => {
    const before = event.data?.before?.exists ? event.data.before.data() : null;
    const after = event.data?.after?.exists ? event.data.after.data() : null;
    if (!after || !eligible(after) || (before && eligible(before))) return;
    const recipients = new Set();
    if (after.customerUid) {
      const followers = await db.collection("Customers").doc(String(after.customerUid))
          .collection("followers").limit(1000).get();
      followers.docs.forEach((doc) => recipients.add(doc.id));
    }
    if (after.organizationId) {
      const followers = await db.collection("Organizations").doc(String(after.organizationId))
          .collection("Followers").limit(1000).get();
      followers.docs.forEach((doc) => recipients.add(doc.id));
    }
    const latitude = Number(after.latitude);
    const longitude = Number(after.longitude);
    if (after.locationType !== "online" && Number.isFinite(latitude) && Number.isFinite(longitude)) {
      const preferences = await db.collectionGroup("Discovery")
          .where("nearbyInterestNotifications", "==", true).limit(1000).get();
      for (const preference of preferences.docs) {
        if (preference.id !== "preferences") continue;
        const data = preference.data();
        const userLatitude = Number(data.latitude);
        const userLongitude = Number(data.longitude);
        if (!Number.isFinite(userLatitude) || !Number.isFinite(userLongitude)) continue;
        const radiusMiles = Math.min(100, Math.max(1, Number(data.notificationRadius || 25)));
        const distanceMiles = distanceBetween(
            [latitude, longitude], [userLatitude, userLongitude],
        ) / 1.609344;
        const categories = new Set((data.preferredCategories || []).map((value) => String(value).toLowerCase()));
        const matchesInterest = !categories.size || (after.categories || [])
            .some((value) => categories.has(String(value).toLowerCase()));
        if (distanceMiles <= radiusMiles && matchesInterest) {
          const uid = preference.ref.parent.parent?.id;
          if (uid) recipients.add(uid);
        }
      }
    }
    recipients.delete(String(after.customerUid || ""));
    const deliverAfter = Timestamp.fromMillis(Date.now() + 45 * 60 * 1000);
    await Promise.all([...recipients].map((uid) => db.collection("discovery_notification_batches")
        .doc(uid).set({
          uid,
          eventIds: FieldValue.arrayUnion(event.params.eventId),
          eventTitles: FieldValue.arrayUnion(String(after.title || "New event")),
          status: "pending",
          deliverAfter,
          updatedAt: FieldValue.serverTimestamp(),
        }, {merge: true})));
  });
}

function createDeliverDiscoveryNotifications(admin) {
  const db = admin.firestore();
  return onSchedule({region: "us-central1", schedule: "every 1 hours", timeZone: "UTC"}, async () => {
    const snapshot = await db.collection("discovery_notification_batches")
        .where("deliverAfter", "<=", Timestamp.now()).limit(250).get();
    for (const document of snapshot.docs) {
      const batch = document.data();
      if (batch.status !== "pending") continue;
      const claimed = await db.runTransaction(async (transaction) => {
        const current = await transaction.get(document.ref);
        if (!current.exists || current.get("status") !== "pending") return false;
        transaction.update(document.ref, {status: "sending", sendingAt: FieldValue.serverTimestamp()});
        return true;
      });
      if (!claimed) continue;
      const settings = await db.collection("users").doc(batch.uid)
          .collection("settings").doc("notifications").get();
      if (settings.exists && settings.get("newEvents") === false) {
        await document.ref.delete();
        continue;
      }
      const eventIds = (batch.eventIds || []).map(String).slice(0, 10);
      const titles = (batch.eventTitles || []).map(String).slice(0, 3);
      const count = eventIds.length;
      const notification = await db.collection("users").doc(batch.uid)
          .collection("notifications").add({
            type: "discovery_new_events",
            title: count === 1 ? "A new event for you" : `${count} new events for you`,
            body: titles.join(" · "),
            eventId: count === 1 ? eventIds[0] : null,
            eventIds,
            createdAt: FieldValue.serverTimestamp(),
            isRead: false,
          });
      const user = await db.collection("users").doc(batch.uid).get();
      const token = user.get("fcmToken");
      if (token) {
        await admin.messaging().send({
          token,
          notification: {
            title: count === 1 ? "A new event for you" : `${count} new events for you`,
            body: titles.join(" · "),
          },
          data: {
            type: "discovery_new_events",
            eventId: count === 1 ? eventIds[0] : "",
            notificationId: notification.id,
            click_action: "FLUTTER_NOTIFICATION_CLICK",
          },
        }).catch(() => null);
      }
      await document.ref.delete();
    }
  });
}

module.exports = {createDeliverDiscoveryNotifications, createQueueDiscoveryNotifications};
