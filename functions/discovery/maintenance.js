"use strict";
const crypto = require("node:crypto");
const {onDocumentWritten} = require("firebase-functions/v2/firestore");
const {geohashForLocation} = require("geofire-common");
const {inferDiscoveryCategories} = require("./category-catalog");
const stateId = (uid, eventId) => crypto.createHash("sha256").update(JSON.stringify([uid, eventId])).digest("hex");
const count = (value) => Number.isSafeInteger(value) && value > 0 ? value : 0;
function desiredMetadata(data) {
  const latitude = Number(data.latitude || 0), longitude = Number(data.longitude || 0);
  const city = String(data.city || "").trim(), regionCode = String(data.regionCode || "").trim().toUpperCase();
  const countryCode = String(data.countryCode || "").trim().toUpperCase();
  const valid = data.locationType !== "online" && Number.isFinite(latitude) && Number.isFinite(longitude) &&
    Math.abs(latitude) <= 90 && Math.abs(longitude) <= 180 && !(latitude === 0 && longitude === 0) && city.length > 0 && regionCode.length > 0 && countryCode === "US";
  return {geohash: valid ? geohashForLocation([latitude, longitude]) : null, city: valid ? city : "",
    regionCode: valid ? regionCode : "", countryCode: valid ? countryCode : null,
    discoveryLocationValid: valid, ...inferDiscoveryCategories(data)};
}
function createDiscoveryMaintenanceHandlers(admin) {
  const db = admin.firestore();
  const stamp = () => admin.firestore.FieldValue.serverTimestamp();
  async function metadata(event) {
    const ref = db.collection("Events").doc(event.params.eventId);
    return db.runTransaction(async (tx) => {
      const current = await tx.get(ref);
      if (!current.exists) return;
      const data = current.data(), desired = desiredMetadata(data);
      if (Object.entries(desired).every(([key, value]) => JSON.stringify(data[key] ?? null) === JSON.stringify(value))) return;
      tx.update(ref, {...desired, discoveryMetadataUpdatedAt: stamp()});
    });
  }
  async function saved(event) {
    const {uid, eventId} = event.params;
    const ref = db.collection("Events").doc(eventId);
    const source = db.collection("Customers").doc(uid).collection("SavedEvents").doc(eventId);
    const marker = db.collection("DiscoverySavedEventStates").doc(stateId(uid, eventId));
    return db.runTransaction(async (tx) => {
      const [current, live, state, deleting] = await Promise.all([tx.get(ref), tx.get(source), tx.get(marker), tx.get(db.collection("account_deletion_jobs").doc(uid))]);
      const desired = current.exists && live.exists && !deleting.exists;
      const previous = state.get("counted") === true;
      // Existing saved records need an explicit historical marker baseline.
      // A metadata-only update must not count that legacy save for a second time.
      if (!state.exists && event.data?.before?.exists && event.data?.after?.exists) return;
      if (desired === previous) return;
      if (current.exists) tx.update(ref, {saveCount: Math.max(0, count(current.get("saveCount")) + (desired ? 1 : -1))});
      if (desired) tx.set(marker, {uid, eventId, counted: true, updatedAt: stamp()});
      else if (state.exists) tx.delete(marker);
    });
  }
  return {metadata, saved};
}
function createMaintainDiscoveryMetadata(admin) {
  return onDocumentWritten({document: "Events/{eventId}", region: "us-central1", retry: true}, createDiscoveryMaintenanceHandlers(admin).metadata);
}
function createSavedEventCounter(admin) {
  return onDocumentWritten({document: "Customers/{uid}/SavedEvents/{eventId}", region: "us-central1", retry: true}, createDiscoveryMaintenanceHandlers(admin).saved);
}
async function cleanupDiscoveryAccountData(db, uid, counts) {
  const query = db.collection("DiscoverySavedEventStates").where("uid", "==", uid).limit(100);
  let page = await query.get();
  while (!page.empty) {
    for (const selected of page.docs) await counts.lease.transaction(async (tx) => {
      const marker = await tx.get(selected.ref);
      if (!marker.exists || marker.get("uid") !== uid) return;
      const event = await tx.get(db.collection("Events").doc(marker.get("eventId")));
      if (event.exists && marker.get("counted") === true) tx.update(event.ref, {saveCount: Math.max(0, count(event.get("saveCount")) - 1)});
      tx.delete(marker.ref);
      tx.set(counts.job, {lastCompletedItem: marker.ref.path}, {merge: true});
    });
    page = await query.get();
  }
}
module.exports = {createDiscoveryMaintenanceHandlers, createMaintainDiscoveryMetadata, createSavedEventCounter, cleanupDiscoveryAccountData, desiredMetadata};
