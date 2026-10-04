"use strict";
const crypto = require("node:crypto");
const {onCall, HttpsError} = require("firebase-functions/v2/https");
const {activePublicEvent, eventDto, enforceDiscoveryRateLimit} = require("./marketplace");
function parseQuerySimple(query) {
  const queryLower = (String(query) || "").toLowerCase();

  // Extract keywords (remove common words)
  const commonWords = new Set(["the", "a", "an", "and", "or", "but", "in", "on", "at", "to", "for", "of", "with", "within", "by", "near", "me", "find", "search", "event", "events", "today", "tomorrow", "weekend", "this", "week", "nearby", "local", "around", "close", "km", "miles", "kilometers"]);
  const keywords = queryLower
      .split(/[^a-z0-9]+/)
      .filter((word) => word.length > 2 && !/^\d+$/.test(word) && !commonWords.has(word))
      .slice(0, 5);

  // Detect categories based on keywords
  const categoryMap = {
    "book": ["book club", "reading"],
    "read": ["book club", "reading"],
    "music": ["music", "concert"],
    "concert": ["music", "concert"],
    "sport": ["sports"],
    "fitness": ["sports", "fitness"],
    "tech": ["tech", "technology"],
    "technology": ["tech", "technology"],
    "network": ["networking"],
    "business": ["networking", "business"],
    "family": ["family"],
    "kid": ["family"],
    "art": ["art"],
    "paint": ["art"],
    "food": ["food"],
    "cook": ["food"],
    "game": ["gaming"],
    "gaming": ["gaming"],
    "education": ["education"],
    "learn": ["education"],
    "workshop": ["education"],
  };

  const categories = [];
  keywords.forEach((keyword) => {
    if (categoryMap[keyword]) {
      categories.push(...categoryMap[keyword]);
    }
  });

  // Remove duplicates
  const uniqueCategories = [...new Set(categories)];

  // Detect location intent
  const nearMe = /near\s+me|around\s+me|close\s+by|nearby|local/i.test(query);

  // Extract radius if mentioned
  let radiusKm = nearMe ? 25 : 0;
  const radiusMatch = query.match(/(\d+)\s*(km|kilometers?|miles?)/i);
  if (radiusMatch) {
    const value = parseInt(radiusMatch[1]);
    radiusKm = radiusMatch[2].toLowerCase().startsWith("m") ? Math.min(160.9344, value * 1.609344) : Math.min(160.9344, value); // Convert miles to km
  }

  // Basic date parsing
  const dateRange = {};
  const now = new Date();

  if (/today/i.test(query)) {
    const today = new Date(now.getFullYear(), now.getMonth(), now.getDate());
    dateRange.start = today.toISOString();
    dateRange.end = new Date(today.getTime() + 24 * 60 * 60 * 1000).toISOString();
  } else if (/tomorrow/i.test(query)) {
    const tomorrow = new Date(now.getFullYear(), now.getMonth(), now.getDate() + 1);
    dateRange.start = tomorrow.toISOString();
    dateRange.end = new Date(tomorrow.getTime() + 24 * 60 * 60 * 1000).toISOString();
  } else if (/this\s+week/i.test(query)) {
    const startOfWeek = new Date(now);
    startOfWeek.setDate(now.getDate() - now.getDay());
    startOfWeek.setHours(0, 0, 0, 0);
    const endOfWeek = new Date(startOfWeek.getTime() + 7 * 24 * 60 * 60 * 1000);
    dateRange.start = startOfWeek.toISOString();
    dateRange.end = endOfWeek.toISOString();
  } else if (/weekend/i.test(query)) {
    const daysUntilSaturday = 6 - now.getDay();
    const saturday = new Date(now.getFullYear(), now.getMonth(), now.getDate() + daysUntilSaturday);
    saturday.setHours(0, 0, 0, 0);
    const sunday = new Date(saturday.getTime() + 2 * 24 * 60 * 60 * 1000);
    dateRange.start = saturday.toISOString();
    dateRange.end = sunday.toISOString();
  }

  return {
    categories: uniqueCategories,
    keywords,
    nearMe,
    radiusKm,
    dateRange,
  };
}

function kmDistance(lat1, lon1, lat2, lon2) {
  const toRad = (v) => v * Math.PI / 180;
  const R = 6371; // km
  const dLat = toRad(lat2 - lat1);
  const dLon = toRad(lon2 - lon1);
  const a = Math.sin(dLat/2) * Math.sin(dLat/2) +
            Math.cos(toRad(lat1)) * Math.cos(toRad(lat2)) *
            Math.sin(dLon/2) * Math.sin(dLon/2);
  const c = 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));
  return R * c;
}

function searchInput(data = {}) {
  if (typeof data.query !== "string" || !data.query.trim() || data.query.length > 200) throw new HttpsError("invalid-argument", "Enter a search of up to 200 characters.");
  const limit = data.limit === undefined ? 50 : data.limit;
  if (!Number.isSafeInteger(limit) || limit < 1 || limit > 100) throw new HttpsError("invalid-argument", "Search limit must be between 1 and 100.");
  const coordinates = data.lat !== undefined || data.lng !== undefined;
  if (coordinates && (typeof data.lat !== "number" || typeof data.lng !== "number" || !Number.isFinite(data.lat) || !Number.isFinite(data.lng) ||
      Math.abs(data.lat) > 90 || Math.abs(data.lng) > 180)) throw new HttpsError("invalid-argument", "Valid latitude and longitude are required.");
  return {query: data.query.trim(), limit, coordinates, lat: data.lat, lng: data.lng};
}
function createNaturalSearchHandler(admin) {
  const db = admin.firestore();
  return async (request) => {
    const input = searchInput(request.data);
    const subject = request.auth?.uid || `guest:${request.rawRequest?.ip || "unknown"}`;
    const rateUid = `ai_${crypto.createHash("sha256").update(subject).digest("hex")}`;
    await enforceDiscoveryRateLimit(db, {auth: {uid: rateUid, token: {firebase: {sign_in_provider: request.auth?.token?.firebase?.sign_in_provider || "anonymous"}}}});
    const intent = parseQuerySimple(input.query), now = new Date();
    const start = intent.dateRange.start ? new Date(intent.dateRange.start) : new Date(now.getTime() - 10800000);
    const end = intent.dateRange.end ? new Date(intent.dateRange.end) : new Date(now.getTime() + 60 * 86400000);
    const snapshot = await db.collection("Events").where("private", "==", false)
        .where("selectedDateTime", ">=", start).where("selectedDateTime", "<=", end).orderBy("selectedDateTime").limit(400).get();
    let events = snapshot.docs.filter((doc) => activePublicEvent(doc.data(), now)).map((doc) => eventDto(doc));
    if (intent.categories.length) events = events.filter((event) => event.categories.some((category) => intent.categories.includes(category.toLowerCase())));
    if (intent.keywords.length) events = events.filter((event) => intent.keywords.some((word) =>
      [event.title, event.description, event.location].some((text) => text.toLowerCase().includes(word))));
    const near = intent.nearMe && input.coordinates;
    if (near) events = events.map((event) => ({...event, distanceMiles: kmDistance(input.lat, input.lng, event.latitude, event.longitude) / 1.609344}))
        .filter((event) => event.locationType !== "online" && event.distanceMiles * 1.609344 <= intent.radiusKm);
    events.sort((left, right) => (near ? left.distanceMiles - right.distanceMiles : 0) ||
      new Date(left.selectedDateTime) - new Date(right.selectedDateTime) || left.id.localeCompare(right.id));
    return {events: events.slice(0, input.limit), intent};
  };
}
function createNaturalSearch(admin) {
  return onCall({region: "us-central1", timeoutSeconds: 20, memory: "512MiB", maxInstances: 20}, createNaturalSearchHandler(admin));
}
module.exports = {createNaturalSearch, createNaturalSearchHandler, searchInput, parseQuerySimple};
