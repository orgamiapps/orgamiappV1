"use strict";

const {createHash} = require("node:crypto");
const {FieldPath, Timestamp} = require("firebase-admin/firestore");
const {HttpsError} = require("firebase-functions/v2/https");
const {distanceBetween} = require("geofire-common");
const BANDS = [25, 50, 100, 250, 500, 1000];
const encode = (value) => Buffer.from(JSON.stringify(value)).toString("base64url");

function exactDistance(data, center) {
  if (!center || data.locationType === "online" ||
      (data.locationInputMode === "text" && data.locationCoordinatesEnabled !== true)) return null;
  if ((data.latitude === null || data.latitude === undefined) || (data.longitude === null || data.longitude === undefined)) return null;
  const lat = Number(data.latitude); const lng = Number(data.longitude);
  if (!Number.isFinite(lat) || !Number.isFinite(lng) || Math.abs(lat) > 90 ||
      Math.abs(lng) > 180 || (lat === 0 && lng === 0)) return null;
  return distanceBetween([center.latitude, center.longitude], [lat, lng]) / 1.609344;
}

// Each call scans a bounded batch; continuation cursors never impose a candidate cap.
async function discoveryFeed(db, data, helpers) {
  const pageSize = Math.max(1, Math.min(20, Number(data.limit) || 20));
  const fixed = data.distanceMode === "fixed";
  const radius = Number(data.radiusMiles || 25);
  if (fixed && ![5, 10, 25, 50, 100].includes(radius)) {
    throw new HttpsError("invalid-argument", "Choose a supported distance.");
  }
  const center = data.nationwide === true ? null : helpers.validateCenter(data);
  if (fixed && !center) throw new HttpsError("invalid-argument", "Choose a location first.");
  const identity = createHash("sha256").update(JSON.stringify([
    center, fixed, radius, data.query || "", data.categoryId || "", data.datePreset || "",
    data.onlineOnly === true, data.freeOnly === true,
  ])).digest("hex");
  let state;
  if (data.cursor) {
    try {
      if (String(data.cursor).length > 4096) throw Error();
      state = JSON.parse(Buffer.from(String(data.cursor), "base64url").toString());
      if (state.identity !== identity || (fixed && (state.scope !== radius || state.phase !== "feed")) || !Number.isFinite(state.anchor) ||
          !["resolve", "feed"].includes(state.phase) ||
          (state.scope !== null && ![5, 10, ...BANDS].includes(state.scope)) ||
          !Array.isArray(state.nearest) || state.nearest.length > 6 ||
          state.nearest.some((n) => !Number.isFinite(n) || n < 0) ||
          (state.after && (!Number.isInteger(state.after[0]) || !Number.isInteger(state.after[1]) || typeof state.after[2] !== "string"))) throw Error();
    } catch (_) {
      throw new HttpsError("invalid-argument", "This discovery cursor does not match the filters.");
    }
  } else {
    state = {identity, anchor: Date.now(), after: null, nearest: [],
      phase: !fixed && center && !data.onlineOnly ? "resolve" : "feed",
      scope: fixed ? radius : null};
  }
  const now = new Date(state.anchor);
  const events = [];
  let exhausted = false;
  for (let batch = 0; batch < 5 && events.length < pageSize; batch++) {
    let query = db.collection("Events").where("private", "==", false)
        .where("selectedDateTime", ">", Timestamp.fromMillis(state.anchor - 3 * 3600000))
        .orderBy("selectedDateTime").orderBy(FieldPath.documentId()).limit(200);
    if (state.after) query = query.startAfter(new Timestamp(state.after[0], state.after[1]), state.after[2]);
    const snapshot = await query.get();
    exhausted = snapshot.docs.length < 200;
    for (const doc of snapshot.docs) {
      const raw = doc.data();
      state.after = [raw.selectedDateTime.seconds, raw.selectedDateTime.nanoseconds, doc.id];
      if (!helpers.activePublicEvent(raw, now)) continue;
      if (raw.locationType !== "online" && raw.countryCode && String(raw.countryCode).toUpperCase() !== "US") continue;
      const event = helpers.eventDto(doc, center);
      if (!helpers.applyV2Filters([event], data, now, {onlineOnly: data.onlineOnly === true}).length ||
          (data.query && !helpers.includesQuery(event, String(data.query).trim().toLowerCase().slice(0, 120)))) continue;
      const distance = exactDistance(raw, center);
      if (state.phase === "resolve") {
        if (event.locationType !== "online" && distance !== null) {
          state.nearest = [...state.nearest, distance].sort((a, b) => a - b).slice(0, 6);
        }
        if (state.nearest.length === 6 && state.nearest[5] <= 25) break;
      } else if (event.locationType === "online" || state.scope === null ||
          (distance !== null && distance <= state.scope)) {
        events.push(event);
        if (events.length === pageSize) {
          exhausted = exhausted && doc === snapshot.docs[snapshot.docs.length - 1];
          break;
        }
      }
    }
    if (state.phase === "resolve" && (exhausted ||
        (state.nearest.length === 6 && state.nearest[5] <= 25))) {
      state.scope = state.nearest.length < 6 ? null : BANDS.find((n) => n >= state.nearest[5]) || null;
      state.phase = "feed"; state.after = null; exhausted = false;
    } else if (exhausted) break;
  }
  return {feedVersion: 1, events, nextCursor: exhausted ? null : encode(state),
    resolving: state.phase === "resolve", radiusMiles: state.scope,
    geographicScope: state.scope === null ? "nationwide" : "radius",
    distanceMode: fixed ? "fixed" : "auto", schemaVersion: 2};
}

module.exports = {discoveryFeed, exactDistance, BANDS};
