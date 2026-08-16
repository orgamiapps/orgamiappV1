"use strict";

const crypto = require("node:crypto");
const {onCall, HttpsError} = require("firebase-functions/v2/https");
const {onSchedule} = require("firebase-functions/v2/scheduler");
const {Timestamp, FieldValue} = require("firebase-admin/firestore");

const EVENTS = new Set([
  "guest_discover_view",
  "guest_auth_cta_selected",
  "guest_locked_feature_prompt",
  "guest_auth_started",
  "guest_auth_completed",
  "guest_auth_failed",
  "guest_intent_resumed",
  "guest_checkin_started",
  "guest_checkin_completed",
  "guest_checkin_failed",
  "discovery_view",
  "discovery_location_prompt",
  "discovery_location_result",
  "discovery_section_impression",
  "discovery_card_open",
  "discovery_search_results",
  "discovery_search_no_result",
  "discovery_radius_expansion",
  "discovery_save",
  "discovery_follow",
  "discovery_registration_start",
  "discovery_registration_complete",
  "discovery_organizer_create_cta",
  "discovery_category_module_impression",
  "discovery_category_selected",
  "discovery_category_cleared",
  "discovery_category_view_all",
  "discovery_quick_choice_selected",
  "discovery_section_view_all",
  "discovery_search_page_loaded",
  "discovery_category_no_result",
]);
const DIMENSIONS = new Set([
  "entryPoint", "feature", "authChoice", "checkInMethod", "platform",
  "result", "errorCategory", "section", "position", "radiusBand",
  "locationSource", "category", "accessMode", "resultCount", "source",
  "targetType", "metro", "categoryId", "choice", "experienceVersion",
]);
const RETENTION_MS = 90 * 24 * 60 * 60 * 1000;

async function rateLimit(db, uid, nowMs = Date.now()) {
  const id = crypto.createHash("sha256").update(uid).digest("hex").slice(0, 32);
  const ref = db.collection("service_rate_limits").doc(`funnel_${id}`);
  let allowed = false;
  await db.runTransaction(async (transaction) => {
    const snapshot = await transaction.get(ref);
    const data = snapshot.exists ? snapshot.data() : {};
    const start = Number(data.windowStartedAtMs || 0);
    const active = nowMs - start < 60000;
    const count = active ? Number(data.count || 0) : 0;
    if (count >= 120) return;
    allowed = true;
    transaction.set(ref, {
      service: "product_funnel",
      windowStartedAtMs: active ? start : nowMs,
      count: count + 1,
      expiresAt: Timestamp.fromMillis(nowMs + 120000),
    }, {merge: true});
  });
  if (!allowed) throw new HttpsError("resource-exhausted", "Analytics rate limit reached.");
}

function validate(data) {
  const event = typeof data?.event === "string" ? data.event : "";
  const sessionId = typeof data?.sessionId === "string" ? data.sessionId : "";
  if (!EVENTS.has(event) || !/^[a-f0-9]{32}$/.test(sessionId)) {
    throw new HttpsError("invalid-argument", "Invalid funnel event.");
  }
  if (data.dimensions === null || data.dimensions === undefined ||
      typeof data.dimensions !== "object" ||
      Array.isArray(data.dimensions)) {
    throw new HttpsError("invalid-argument", "Invalid funnel dimensions.");
  }
  const dimensions = {};
  for (const [key, raw] of Object.entries(data.dimensions)) {
    if (!DIMENSIONS.has(key) || typeof raw !== "string" || raw.length > 64 ||
        !/^[a-zA-Z0-9_.:-]*$/.test(raw)) {
      throw new HttpsError("invalid-argument", "Unsupported funnel dimension.");
    }
    dimensions[key] = raw;
  }
  return {event, sessionId, dimensions};
}

function createRecordProductFunnelEvent(adminSdk) {
  const db = adminSdk.firestore();
  return onCall({
    region: "us-central1",
    enforceAppCheck: process.env.FUNCTIONS_EMULATOR !== "true",
    maxInstances: 20,
  }, async (request) => {
    if (!request.auth?.uid) throw new HttpsError("unauthenticated", "Authentication required.");
    const input = validate(request.data);
    await rateLimit(db, request.auth.uid);
    const provider = request.auth.token?.firebase?.sign_in_provider || "unknown";
    await db.collection("product_funnel_events").add({
      event: input.event,
      sessionId: input.sessionId,
      dimensions: input.dimensions,
      accessMode: provider === "anonymous" ? "guest" : "authenticated",
      occurredAt: FieldValue.serverTimestamp(),
      expireAt: Timestamp.fromMillis(Date.now() + RETENTION_MS),
      schemaVersion: 1,
    });
    return {accepted: true};
  });
}

function increment(target, key) {
  target[key] = Number(target[key] || 0) + 1;
}

function createAggregateProductFunnelDaily(adminSdk) {
  const db = adminSdk.firestore();
  return onSchedule({
    region: "us-central1",
    schedule: "30 2 * * *",
    timeZone: "UTC",
    timeoutSeconds: 540,
  }, async () => {
    const end = new Date();
    end.setUTCHours(0, 0, 0, 0);
    const start = new Date(end.getTime() - 24 * 60 * 60 * 1000);
    const snapshot = await db.collection("product_funnel_events")
        .where("occurredAt", ">=", Timestamp.fromDate(start))
        .where("occurredAt", "<", Timestamp.fromDate(end)).get();
    const counts = {};
    const byEntryPoint = {};
    const byCheckInMethod = {};
    const byFeature = {};
    const discoveryCounts = {};
    const sessions = new Set();
    for (const doc of snapshot.docs) {
      const data = doc.data();
      increment(counts, data.event);
      sessions.add(data.sessionId);
      const dimensions = data.dimensions || {};
      if (dimensions.entryPoint) increment(byEntryPoint, dimensions.entryPoint);
      if (dimensions.checkInMethod) increment(byCheckInMethod, dimensions.checkInMethod);
      if (dimensions.feature) increment(byFeature, dimensions.feature);
      if (String(data.event || "").startsWith("discovery_")) {
        increment(discoveryCounts, data.event);
      }
    }
    const day = start.toISOString().slice(0, 10);
    await db.collection("admin_funnel_daily").doc(day).set({
      date: day,
      counts,
      byEntryPoint,
      byCheckInMethod,
      byFeature,
      discovery: {
        counts: discoveryCounts,
        eventDetailCtr: (discoveryCounts.discovery_view || 0) > 0 ?
          (discoveryCounts.discovery_card_open || 0) / discoveryCounts.discovery_view : 0,
        zeroResultRate: ((discoveryCounts.discovery_search_results || 0) +
          (discoveryCounts.discovery_search_no_result || 0)) > 0 ?
          (discoveryCounts.discovery_search_no_result || 0) /
            ((discoveryCounts.discovery_search_results || 0) +
             (discoveryCounts.discovery_search_no_result || 0)) : 0,
        saveRate: (discoveryCounts.discovery_card_open || 0) > 0 ?
          (discoveryCounts.discovery_save || 0) / discoveryCounts.discovery_card_open : 0,
        followRate: (discoveryCounts.discovery_card_open || 0) > 0 ?
          (discoveryCounts.discovery_follow || 0) / discoveryCounts.discovery_card_open : 0,
        registrationConversion: (discoveryCounts.discovery_registration_start || 0) > 0 ?
          (discoveryCounts.discovery_registration_complete || 0) /
            discoveryCounts.discovery_registration_start : 0,
        categorySelectionRate: (discoveryCounts.discovery_category_module_impression || 0) > 0 ?
          (discoveryCounts.discovery_category_selected || 0) /
            discoveryCounts.discovery_category_module_impression : 0,
      },
      sessions: sessions.size,
      updatedAt: FieldValue.serverTimestamp(),
      schemaVersion: 1,
    });
  });
}

module.exports = {
  EVENTS,
  createAggregateProductFunnelDaily,
  createRecordProductFunnelEvent,
  validate,
};
