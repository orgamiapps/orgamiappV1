"use strict";

const crypto = require("node:crypto");
const {onDocumentWritten} = require("firebase-functions/v2/firestore");
const {onSchedule} = require("firebase-functions/v2/scheduler");
const {distanceBetween} = require("geofire-common");
const {activePublicEvent} = require("./marketplace");
const {canDeliverPush} = require("../notifications/push-tokens");
const {demoDeliveryCaptureEnabled} = require("../communications/delivery");
const {qualificationDecision, captureQualification} = require("../communications/qualification-isolation");

const DELAY_MS = 45 * 60 * 1000;
const DELIVERY_SIZE = 10;
const hash = (value) => crypto.createHash("sha256").update(JSON.stringify(value)).digest("hex");
const validId = (value) => typeof value === "string" && value.length > 0 && value.length <= 1500 && !value.includes("/");
const millis = (value) => value?.toMillis ? value.toMillis() : new Date(value || 0).getTime();
function eligible(data, now = new Date()) {
  return data?.private === false && ["active", "scheduled"].includes(String(data.status || "").toLowerCase()) &&
    data.deleted !== true && data.isHidden !== true && activePublicEvent(data, now);
}
function nearbyInterest(data, preference) {
  if (preference?.nearbyInterestNotifications !== true || data.locationType === "online") return false;
  const coordinates = [data.latitude, data.longitude, preference.latitude, preference.longitude];
  if (coordinates.some((value) => value === null || value === undefined || value === "" || !Number.isFinite(Number(value)))) return false;
  const [latitude, longitude, userLatitude, userLongitude] = coordinates.map(Number);
  if (Math.abs(latitude) > 90 || Math.abs(userLatitude) > 90 || Math.abs(longitude) > 180 || Math.abs(userLongitude) > 180) return false;
  const requestedRadius = Number(preference.notificationRadius || 25);
  const radius = Number.isFinite(requestedRadius) ? Math.min(100, Math.max(1, requestedRadius)) : 25;
  const categories = new Set((Array.isArray(preference.preferredCategories) ? preference.preferredCategories : []).map((value) => String(value).toLowerCase()));
  return distanceBetween([latitude, longitude], [userLatitude, userLongitude]) / 1.609344 <= radius &&
    (!categories.size || (Array.isArray(data.categories) ? data.categories : []).some((value) => categories.has(String(value).toLowerCase())));
}

function createDiscoveryNotificationHandlers(admin) {
  const db = admin.firestore();
  const stamp = () => admin.firestore.FieldValue.serverTimestamp();
  const timestamp = (value) => admin.firestore.Timestamp.fromMillis(value);
  const rootFor = (uid) => db.collection("discovery_notification_batches").doc(uid);
  const eventsFor = (root) => root.collection("events");
  async function recipient(tx, uid) {
    const user = db.collection("users").doc(uid);
    const [profile, deleting, settings, legacySettings, preference] = await Promise.all([
      tx.get(user), tx.get(db.collection("account_deletion_jobs").doc(uid)),
      tx.get(user.collection("settings").doc("notifications")),
      tx.get(user.collection("notificationSettings").doc("settings")),
      tx.get(db.collection("Customers").doc(uid).collection("Discovery").doc("preferences")),
    ]);
    return {allowed: profile.exists && !deleting.exists && settings.get("newEvents") !== false && legacySettings.get("newEvents") !== false,
      token: profile.get("fcmToken"), preference: preference.data() || {}};
  }
  async function interested(tx, uid, event, preference) {
    if (event.customerUid === uid) return false;
    const references = [];
    if (validId(event.customerUid)) references.push(db.collection("Customers").doc(event.customerUid).collection("followers").doc(uid));
    if (validId(event.organizationId)) references.push(db.collection("Organizations").doc(event.organizationId).collection("Followers").doc(uid));
    const followers = await Promise.all(references.map((ref) => tx.get(ref)));
    return followers.some((snapshot) => snapshot.exists) || nearbyInterest(event, preference);
  }
  async function enqueue(uid, eventId, now = Date.now()) {
    if (!validId(uid) || !validId(eventId)) return false;
    const root = rootFor(uid), item = eventsFor(root).doc(hash(eventId));
    return db.runTransaction(async (tx) => {
      const [batch, previous, event, target] = await Promise.all([
        tx.get(root), tx.get(item), tx.get(db.collection("Events").doc(eventId)), recipient(tx, uid),
      ]);
      if (previous.exists || !target.allowed || !event.exists || !eligible(event.data(), new Date(now)) ||
          !await interested(tx, uid, event.data(), target.preference)) return false;
      if ((await qualificationDecision(db, {recipientUid: uid, eventId}, tx)).mode === "suppress") return false;
      const readyAt = now + DELAY_MS;
      // Preserve the active delivery and the earliest pending deadline.
      const priorDue = millis(batch.get("deliverAfter"));
      tx.create(item, {eventId, status: "pending", readyAt: timestamp(readyAt), queuedAt: stamp()});
      tx.set(root, {uid, deliverAfter: timestamp(priorDue > 0 && Number.isFinite(priorDue) ? Math.min(priorDue, readyAt) : readyAt),
        updatedAt: stamp(), ...(!batch.exists ? {schemaVersion: 2} : {})}, {merge: true});
      return true;
    });
  }
  async function scan(query, visit) {
    let cursor = null;
    do {
      const page = await (cursor ? query.orderBy("__name__").startAfter(cursor) : query.orderBy("__name__")).limit(100).get();
      for (let offset = 0; offset < page.docs.length; offset += 10) await Promise.all(page.docs.slice(offset, offset + 10).map(visit));
      cursor = page.size === 100 ? page.docs[page.docs.length - 1] : null;
    } while (cursor);
  }
  async function queue(event) {
    const before = event.data?.before?.exists ? event.data.before.data() : null;
    const after = event.data?.after?.exists ? event.data.after.data() : null;
    if (!after || !eligible(after) || (before && eligible(before))) return;
    const id = event.params.eventId;
    if (validId(after.customerUid)) await scan(db.collection("Customers").doc(after.customerUid).collection("followers"), (doc) => enqueue(doc.id, id));
    if (validId(after.organizationId)) await scan(db.collection("Organizations").doc(after.organizationId).collection("Followers"), (doc) => enqueue(doc.id, id));
    if (after.locationType !== "online") await scan(db.collectionGroup("Discovery").where("nearbyInterestNotifications", "==", true), async (doc) => {
      if (doc.id !== "preferences" || !nearbyInterest(after, doc.data())) return;
      const path = doc.ref.path.split("/");
      if (path.length === 4 && path[0] === "Customers") await enqueue(path[1], id);
    });
  }
  async function migrateLegacy(root, now) {
    return db.runTransaction(async (tx) => {
      const [batch, deleting] = await Promise.all([tx.get(root), tx.get(db.collection("account_deletion_jobs").doc(root.id))]);
      if (!batch.exists || deleting.exists || batch.get("schemaVersion") === 2) return false;
      const data = batch.data();
      const ids = [...new Set((Array.isArray(data.eventIds) ? data.eventIds : []).filter(validId))];
      const selected = ids.slice(0, 100), remaining = ids.slice(100);
      const documents = await Promise.all(selected.map((id) => tx.get(eventsFor(root).doc(hash(id)))));
      const readyAt = millis(data.deliverAfter) || now;
      for (let index = 0; index < selected.length; index++) {
        if (documents[index].exists) continue;
        const safeToPrepare = data.status === "pending";
        tx.create(documents[index].ref, {eventId: selected[index],
          status: safeToPrepare ? "pending" : "legacy_delivery_unknown",
          ...(safeToPrepare ? {readyAt: timestamp(readyAt)} : {}), migratedAt: stamp()});
      }
      // Old sending records lack provider acknowledgement and a stable inbox
      // identity. Preserve that uncertainty instead of replaying their pushes.
      tx.set(root, {uid: root.id, schemaVersion: remaining.length ? 1 : 2,
        ...(remaining.length ? {eventIds: remaining, status: data.status || "unknown"} : {}),
        deliverAfter: timestamp(now), updatedAt: stamp()});
      return remaining.length > 0;
    });
  }
  async function prepare(root, now) {
    return db.runTransaction(async (tx) => {
      const [batch, deleting] = await Promise.all([tx.get(root), tx.get(db.collection("account_deletion_jobs").doc(root.id))]);
      if (!batch.exists || deleting.exists) return null;
      if (batch.get("activeDeliveryId")) return root.collection("deliveries").doc(batch.get("activeDeliveryId"));
      const pending = await tx.get(eventsFor(root).orderBy("readyAt").limit(DELIVERY_SIZE));
      const due = pending.docs.filter((item) => millis(item.get("readyAt")) <= now);
      if (!due.length) {
        tx.set(root, {uid: root.id, schemaVersion: 2, updatedAt: stamp(),
          ...(pending.docs.length ? {deliverAfter: pending.docs[0].get("readyAt")} : {})});
        return null;
      }
      const id = hash([root.id, due.map((item) => item.id).sort()]);
      const delivery = root.collection("deliveries").doc(id);
      const previous = await tx.get(delivery);
      if (previous.exists) throw Error("Discovery delivery identity already exists for unclaimed events");
      tx.create(delivery, {uid: root.id, eventIds: due.map((item) => item.get("eventId")), state: "prepared", createdAt: stamp()});
      for (const item of due) tx.set(item.ref, {eventId: item.get("eventId"), deliveryId: id, status: "claimed", claimedAt: stamp()});
      tx.set(root, {uid: root.id, schemaVersion: 2, activeDeliveryId: id, deliverAfter: timestamp(now), updatedAt: stamp()});
      return delivery;
    });
  }
  async function reserveHandoff(root, delivery, now) {
    return db.runTransaction(async (tx) => {
      const [current, batch, target] = await Promise.all([tx.get(delivery), tx.get(root), recipient(tx, root.id)]);
      if (!current.exists || current.get("state") !== "prepared" || batch.get("activeDeliveryId") !== delivery.id) return null;
      const ids = (current.get("eventIds") || []).filter(validId).slice(0, DELIVERY_SIZE);
      const events = await Promise.all(ids.map((id) => tx.get(db.collection("Events").doc(id))));
      const currentEvents = [];
      for (const event of events) if (target.allowed && event.exists && eligible(event.data(), new Date(now)) &&
          await interested(tx, root.id, event.data(), target.preference)) currentEvents.push(event);
      const wantsPush = currentEvents.length > 0 && typeof target.token === "string" &&
        await canDeliverPush(db, root.id, target.token, tx);
      const capture = demoDeliveryCaptureEnabled();
      let state = !currentEvents.length ? "suppressed" : capture ? "emulator_capture" : wantsPush ? "delivery_unknown" : "not_requested";
      const eventIds = currentEvents.map((event) => event.id);
      const title = eventIds.length === 1 ? "A new event for you" : `${eventIds.length} new events for you`;
      const body = currentEvents.slice(0, 3).map((event) => String(event.get("title") || "New event").slice(0, 200)).join(" · ");
      const context = {recipientUid: root.id, eventIds};
      const isolation = await qualificationDecision(db, context, tx);
      if (eventIds.length && isolation.mode !== "normal") {
        if (isolation.mode === "capture") await captureQualification(db, tx, isolation, context, `discovery:${delivery.id}`, {title, body, eventIds, type: "discovery_new_events"});
        state = `qualification_${isolation.mode}`;
      }
      if (eventIds.length && isolation.mode === "normal") tx.create(db.collection("users").doc(root.id).collection("notifications").doc(delivery.id), {
        type: "discovery_new_events", title, body, eventId: eventIds.length === 1 ? eventIds[0] : null,
        eventIds, createdAt: stamp(), isRead: false,
      });
      // Only the invocation winning this durable transition may send. A lost
      // response after commit remains unknown and is never automatically replayed.
      tx.update(delivery, {state, visibleEventIds: eventIds, updatedAt: stamp()});
      return {state, token: target.token, title, body, eventIds};
    });
  }
  async function finish(root, delivery) {
    return db.runTransaction(async (tx) => {
      const [batch, current, pending, deleting] = await Promise.all([tx.get(root), tx.get(delivery),
        tx.get(eventsFor(root).orderBy("readyAt").limit(1)), tx.get(db.collection("account_deletion_jobs").doc(root.id))]);
      if (!batch.exists || deleting.exists || batch.get("activeDeliveryId") !== delivery.id || !current.exists || current.get("state") === "prepared") return;
      tx.set(root, {uid: root.id, schemaVersion: 2, updatedAt: stamp(),
        ...(pending.docs.length ? {deliverAfter: pending.docs[0].get("readyAt")} : {})});
    });
  }
  async function deliverUser(uid, now = Date.now()) {
    const root = rootFor(uid);
    if (await migrateLegacy(root, now)) return;
    const delivery = await prepare(root, now);
    if (!delivery) return;
    const attempt = await reserveHandoff(root, delivery, now);
    if (attempt?.state === "delivery_unknown") {
      try {
        if ((await qualificationDecision(db, {recipientUid: uid, eventIds: attempt.eventIds})).mode !== "normal" ||
            !await canDeliverPush(db, uid, attempt.token)) throw Error("Delivery context changed before provider handoff");
        const providerMessageId = await admin.messaging().send({token: attempt.token,
          notification: {title: attempt.title, body: attempt.body}, data: {
            type: "discovery_new_events", recipientUid: uid, eventId: attempt.eventIds.length === 1 ? attempt.eventIds[0] : "",
            notificationId: delivery.id, click_action: "FLUTTER_NOTIFICATION_CLICK",
          }});
        await db.runTransaction(async (tx) => {
          const [current, deleting] = await Promise.all([tx.get(delivery), tx.get(db.collection("account_deletion_jobs").doc(uid))]);
          if (current.exists && current.get("state") === "delivery_unknown" && !deleting.exists) {
            tx.update(delivery, {state: "accepted", providerMessageId, updatedAt: stamp()});
          }
        });
      } catch (_error) { /* Keep the durable unknown result; never blindly replay. */ }
    }
    await finish(root, delivery);
  }
  async function deliver(now = Date.now()) {
    const pending = await db.collection("discovery_notification_batches").where("deliverAfter", "<=", timestamp(now)).limit(250).get();
    for (const document of pending.docs) {
      try { await deliverUser(document.id, now); } catch (error) {
        require("firebase-functions/logger").error("Discovery delivery remains resumable", {code: error.code || "internal"});
      }
    }
  }
  return {queue, enqueue, deliver, deliverUser, prepare, reserveHandoff, finish};
}

function createQueueDiscoveryNotifications(admin) {
  return onDocumentWritten({document: "Events/{eventId}", region: "us-central1", retry: true, timeoutSeconds: 540}, createDiscoveryNotificationHandlers(admin).queue);
}
function createDeliverDiscoveryNotifications(admin) {
  const handlers = createDiscoveryNotificationHandlers(admin);
  return onSchedule({region: "us-central1", schedule: "every 1 hours", timeZone: "UTC"}, () => handlers.deliver());
}
module.exports = {createDeliverDiscoveryNotifications, createQueueDiscoveryNotifications, createDiscoveryNotificationHandlers, eligible, nearbyInterest};
