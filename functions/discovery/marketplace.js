"use strict";

const {onCall, HttpsError} = require("firebase-functions/v2/https");
const {onDocumentWritten} = require("firebase-functions/v2/firestore");
const {logger} = require("firebase-functions");
const {FieldValue, Timestamp} = require("firebase-admin/firestore");
const {
  distanceBetween,
  geohashForLocation,
  geohashQueryBounds,
} = require("geofire-common");
const {
  CATEGORY_BY_ID,
  categoryFacets,
  inferDiscoveryCategories,
} = require("./category-catalog");

const DISCOVERY_RADII_MILES = Object.freeze([25, 50, 100]);
const MILES_TO_KM = 1.609344;
const MIN_SECTION_SIZE = 3;
const TARGET_LOCAL_RESULTS = 6;
const MAX_BOUND_RESULTS = 80;
const MAX_SEARCH_RESULTS = 50;
const BLOCKED_STATUSES = new Set([
  "cancelled", "canceled", "declined", "draft", "pending",
  "pending_approval", "unpublished",
]);

function finiteNumber(value, label) {
  const parsed = Number(value);
  if (!Number.isFinite(parsed)) {
    throw new HttpsError("invalid-argument", `${label} must be a number.`);
  }
  return parsed;
}

function validateCenter(data) {
  const latitude = finiteNumber(data?.latitude, "latitude");
  const longitude = finiteNumber(data?.longitude, "longitude");
  if (latitude < -90 || latitude > 90 || longitude < -180 || longitude > 180) {
    throw new HttpsError("invalid-argument", "Invalid discovery location.");
  }
  return {latitude, longitude};
}

function isFullUser(request) {
  return request.auth?.token?.firebase?.sign_in_provider !== "anonymous";
}

function requireCaller(request) {
  if (!request.auth?.uid) {
    throw new HttpsError("unauthenticated", "Authentication is required.");
  }
  return request.auth.uid;
}

async function enforceDiscoveryRateLimit(db, request) {
  const uid = requireCaller(request);
  const now = Date.now();
  const windowMs = 60 * 1000;
  const limit = isFullUser(request) ? 90 : 30;
  const ref = db.collection("_service_rate_limits").doc(`discovery_${uid}`);
  await db.runTransaction(async (transaction) => {
    const snapshot = await transaction.get(ref);
    const data = snapshot.exists ? snapshot.data() : {};
    const windowStartedAt = Number(data.windowStartedAt || 0);
    const inWindow = now - windowStartedAt < windowMs;
    const count = inWindow ? Number(data.count || 0) : 0;
    if (count >= limit) {
      throw new HttpsError("resource-exhausted", "Too many discovery requests. Please try again shortly.");
    }
    transaction.set(ref, {
      windowStartedAt: inWindow ? windowStartedAt : now,
      count: count + 1,
      expiresAt: Timestamp.fromMillis(now + 5 * windowMs),
    });
  });
}

function normalizeDate(value) {
  if (!value) return null;
  if (typeof value.toDate === "function") return value.toDate();
  if (value instanceof Date) return value;
  if (typeof value === "string") {
    const parsed = new Date(value);
    return Number.isNaN(parsed.getTime()) ? null : parsed;
  }
  if (Number.isFinite(value._seconds)) return new Date(value._seconds * 1000);
  return null;
}

function activePublicEvent(data, now = new Date()) {
  if (!data || data.private === true) return false;
  if (BLOCKED_STATUSES.has(String(data.status || "").toLowerCase())) return false;
  const startsAt = normalizeDate(data.selectedDateTime);
  if (!startsAt) return false;
  const durationHours = Math.max(1, Number(data.eventDuration || 2));
  const endsAt = new Date(startsAt.getTime() + durationHours * 3600000);
  return endsAt.getTime() > now.getTime() - 3 * 3600000;
}

function normalizeTimestamp(value) {
  const date = normalizeDate(value);
  return date ? date.toISOString() : null;
}

function eventDto(document, center = null) {
  const data = document.data ? document.data() : document;
  const id = document.id || data.id;
  const latitude = Number(data.latitude || 0);
  const longitude = Number(data.longitude || 0);
  let distanceMiles = null;
  if (center && Number.isFinite(latitude) && Number.isFinite(longitude) &&
      !(latitude === 0 && longitude === 0)) {
    distanceMiles = distanceBetween(
        [center.latitude, center.longitude], [latitude, longitude],
    ) / MILES_TO_KM;
  }
  const discovery = inferDiscoveryCategories(data);
  return {
    id,
    title: String(data.title || ""),
    description: String(data.description || ""),
    groupName: String(data.groupName || ""),
    customerUid: String(data.customerUid || ""),
    organizationId: data.organizationId || null,
    imageUrl: String(data.imageUrl || ""),
    location: String(data.location || ""),
    locationName: data.locationName || null,
    locationType: data.locationType === "online" ? "online" : "in_person",
    placeId: data.placeId || null,
    city: String(data.city || ""),
    regionCode: String(data.regionCode || ""),
    countryCode: String(data.countryCode || "US"),
    latitude,
    longitude,
    geohash: String(data.geohash || ""),
    selectedDateTime: normalizeTimestamp(data.selectedDateTime),
    eventGenerateTime: normalizeTimestamp(data.eventGenerateTime || data.createdAt),
    status: String(data.status || "scheduled"),
    private: false,
    getLocation: Boolean(data.getLocation),
    radius: Number(data.radius || 0),
    radiusUnit: String(data.radiusUnit || "meters"),
    categories: Array.isArray(data.categories) ? data.categories.map(String) : [],
    primaryDiscoveryCategoryId: discovery.primaryDiscoveryCategoryId,
    discoveryCategoryIds: discovery.discoveryCategoryIds,
    discoveryCategorySource: discovery.discoveryCategorySource,
    discoveryCategoryVersion: discovery.discoveryCategoryVersion,
    isFeatured: Boolean(data.isFeatured),
    featureEndDate: normalizeTimestamp(data.featureEndDate),
    ticketsEnabled: Boolean(data.ticketsEnabled),
    maxTickets: Number(data.maxTickets || 0),
    issuedTickets: Number(data.issuedTickets || 0),
    ticketPrice: data.ticketPrice === null || data.ticketPrice === undefined ?
      null : Number(data.ticketPrice),
    eventDuration: Math.max(1, Number(data.eventDuration || 2)),
    saveCount: Math.max(0, Number(data.saveCount || 0)),
    attendanceCount: Math.max(0, Number(data.attendanceCount || 0)),
    commentCount: Math.max(0, Number(data.commentCount || 0)),
    distanceMiles: distanceMiles === null ? null : Number(distanceMiles.toFixed(1)),
  };
}

function listingQuality(event) {
  let score = 0;
  if (event.imageUrl) score += 0.25;
  if (String(event.description || "").length >= 80) score += 0.25;
  if ((event.discoveryCategoryIds || []).length || (event.categories || []).length) score += 0.2;
  if (event.locationName || event.locationType === "online") score += 0.15;
  if (event.groupName || event.organizationId) score += 0.15;
  return score;
}

function preferenceScore(event, preferences) {
  const preferred = new Set((preferences.preferredCategories || []).map((v) => String(v).toLowerCase()));
  const categories = (event.categories || []).map((v) => String(v).toLowerCase());
  const categoryMatch = preferred.size ? categories.filter((v) => preferred.has(v)).length / preferred.size : 0;
  const preferredDiscovery = new Set((preferences.preferredDiscoveryCategoryIds || []).map(String));
  const discoveryMatch = (event.discoveryCategoryIds || []).some((id) => preferredDiscovery.has(id)) ? 1 : 0;
  const savedOrganizer = preferences.savedOrganizerIds?.has(event.customerUid) ? 1 : 0;
  const followedOrganizer = preferences.followedUserIds?.has(event.customerUid) ? 1 : 0;
  const followedOrganization = event.organizationId && preferences.followedOrganizationIds?.has(event.organizationId) ? 1 : 0;
  return Math.min(1, categoryMatch * 0.35 + discoveryMatch * 0.25 + savedOrganizer * 0.15 +
    followedOrganizer * 0.15 + followedOrganization * 0.2);
}

function scoreEvent(event, preferences = {}, now = new Date()) {
  const distance = event.distanceMiles === null || event.distanceMiles === undefined ?
    100 : event.distanceMiles;
  const distanceScore = Math.max(0, 1 - distance / 100);
  const startsAt = new Date(event.selectedDateTime);
  const hoursAway = Math.max(0, (startsAt.getTime() - now.getTime()) / 3600000);
  const recencyScore = Math.max(0.1, 1 - Math.min(hoursAway, 720) / 720);
  const engagement = Math.min(1,
      Math.log1p(event.saveCount + event.issuedTickets + event.attendanceCount + event.commentCount) / Math.log(51),
  );
  const personal = preferenceScore(event, preferences);
  return personal * 0.35 + distanceScore * 0.25 + recencyScore * 0.15 +
    engagement * 0.15 + listingQuality(event) * 0.10;
}

function sortByScore(events, preferences, now = new Date()) {
  return [...events].sort((left, right) => {
    const scoreDifference = scoreEvent(right, preferences, now) - scoreEvent(left, preferences, now);
    if (Math.abs(scoreDifference) > 0.000001) return scoreDifference;
    const distanceDifference = (left.distanceMiles ?? Infinity) - (right.distanceMiles ?? Infinity);
    if (distanceDifference !== 0) return distanceDifference;
    const timeDifference = new Date(left.selectedDateTime) - new Date(right.selectedDateTime);
    if (timeDifference !== 0) return timeDifference;
    return left.id.localeCompare(right.id);
  });
}

function chooseFallbackRadius(events, requestedRadius = 25) {
  const startingRadius = DISCOVERY_RADII_MILES.find((radius) => radius >= requestedRadius) || 100;
  const candidates = DISCOVERY_RADII_MILES.filter((radius) => radius >= startingRadius);
  for (const radius of candidates) {
    if (events.filter((event) => event.distanceMiles !== null &&
      event.distanceMiles !== undefined && event.distanceMiles <= radius).length >= TARGET_LOCAL_RESULTS) {
      return radius;
    }
  }
  return 100;
}

function takeUnique(source, seen, limit = 12) {
  const output = [];
  for (const event of source) {
    if (seen.has(event.id)) continue;
    seen.add(event.id);
    output.push(event);
    if (output.length >= limit) break;
  }
  return output;
}

function buildSections(localEvents, onlineEvents, preferences, radiusMiles, now = new Date()) {
  const eligible = localEvents.filter((event) => event.distanceMiles !== null &&
    event.distanceMiles !== undefined && event.distanceMiles <= radiusMiles);
  const ranked = sortByScore(eligible, preferences, now);
  const seen = new Set();
  const sections = [];
  const add = (id, title, subtitle, source, options = {}) => {
    const events = takeUnique(source, seen, options.limit || 12);
    if (events.length < (options.minimum || MIN_SECTION_SIZE)) return;
    sections.push({id, title, subtitle, featured: Boolean(options.featured), events});
  };

  const hasSignals = (preferences.preferredCategories || []).length > 0 ||
    (preferences.savedOrganizerIds?.size || 0) > 0 ||
    (preferences.followedUserIds?.size || 0) > 0 ||
    (preferences.followedOrganizationIds?.size || 0) > 0;
  add("recommended", hasSignals ? "For you" : "Near you",
      `Events within ${radiusMiles} miles`, ranked, {minimum: 1});

  const sevenDays = now.getTime() + 7 * 86400000;
  add("soon", "Happening soon", "Upcoming in the next seven days",
      eligible.filter((event) => new Date(event.selectedDateTime).getTime() <= sevenDays)
          .sort((a, b) => new Date(a.selectedDateTime) - new Date(b.selectedDateTime)));

  add("featured", "Featured near you", "Promoted events relevant to your area",
      eligible.filter((event) => event.isFeatured &&
        (!event.featureEndDate || new Date(event.featureEndDate) > now)),
      {featured: true});

  add("popular", "Popular nearby", "Events people are saving and joining",
      [...eligible].sort((a, b) =>
        (b.saveCount + b.issuedTickets + b.attendanceCount + b.commentCount) -
        (a.saveCount + a.issuedTickets + a.attendanceCount + a.commentCount),
      ));

  add("online", "Online across the U.S.", "Join from anywhere",
      sortByScore(onlineEvents, preferences, now));
  return sections;
}

async function loadPreferences(db, request) {
  if (!isFullUser(request)) return {
    preferredCategories: Array.isArray(request.data?.preferredCategories) ?
      request.data.preferredCategories.map(String).slice(0, 20) : [],
    preferredDiscoveryCategoryIds: Array.isArray(request.data?.preferredDiscoveryCategoryIds) ?
      request.data.preferredDiscoveryCategoryIds.map(String).filter((id) => CATEGORY_BY_ID.has(id)).slice(0, 15) : [],
  };
  const uid = request.auth.uid;
  const [preferenceDoc, behaviorDoc, savedSnapshot, followedUsersSnapshot,
    ticketSnapshot, attendanceSnapshot] = await Promise.all([
    db.collection("Customers").doc(uid).collection("Discovery").doc("preferences").get(),
    db.collection("Customers").doc(uid).collection("Discovery").doc("behavior").get(),
    db.collection("Customers").doc(uid).collection("SavedEvents").orderBy("createdAt", "desc").limit(100).get(),
    db.collection("Customers").doc(uid).collection("following").limit(100).get(),
    db.collection("Tickets").where("customerUid", "==", uid).limit(50).get(),
    db.collection("Attendance").where("customerUid", "==", uid).limit(50).get(),
  ]);
  const preferenceData = preferenceDoc.exists ? preferenceDoc.data() : {};
  const behaviorData = behaviorDoc.exists ? behaviorDoc.data() : {};
  const savedOrganizerIds = new Set();
  const savedIds = savedSnapshot.docs.map((doc) => doc.id);
  const behavioralEventIds = [...new Set([
    ...savedIds,
    ...ticketSnapshot.docs.map((doc) => doc.get("eventId")),
    ...attendanceSnapshot.docs.map((doc) => doc.get("eventId")),
  ].filter(Boolean).map(String))];
  const behavioralCategories = new Set((behaviorData.recentCategories || []).map(String));
  if (behavioralEventIds.length) {
    const savedEventDocs = await Promise.all(behavioralEventIds.slice(0, 50)
        .map((id) => db.collection("Events").doc(id).get()));
    for (const doc of savedEventDocs) {
      if (doc.exists && doc.get("customerUid")) savedOrganizerIds.add(String(doc.get("customerUid")));
      for (const category of doc.get("categories") || []) behavioralCategories.add(String(category));
    }
  }
  const followedOrganizationsSnapshot = await db.collectionGroup("Followers")
      .where("userId", "==", uid).limit(100).get();
  return {
    ...preferenceData,
    preferredCategories: [...new Set([
      ...(Array.isArray(preferenceData.preferredCategories) ? preferenceData.preferredCategories : []),
      ...behavioralCategories,
    ])].slice(0, 30),
    preferredDiscoveryCategoryIds: Array.isArray(preferenceData.preferredDiscoveryCategoryIds) ?
      preferenceData.preferredDiscoveryCategoryIds.map(String).filter((id) => CATEGORY_BY_ID.has(id)).slice(0, 15) : [],
    savedOrganizerIds,
    followedUserIds: new Set([
      ...followedUsersSnapshot.docs.map((doc) => doc.id),
      ...(behaviorData.viewedOrganizerIds || []).map(String),
    ]),
    followedOrganizationIds: new Set(followedOrganizationsSnapshot.docs.map((doc) => doc.ref.parent.parent?.id).filter(Boolean)),
  };
}

function coldStartPreferences(request) {
  return {
    preferredCategories: Array.isArray(request?.data?.preferredCategories) ?
      request.data.preferredCategories.map(String).slice(0, 20) : [],
    preferredDiscoveryCategoryIds: Array.isArray(request?.data?.preferredDiscoveryCategoryIds) ?
      request.data.preferredDiscoveryCategoryIds.map(String).filter((id) => CATEGORY_BY_ID.has(id)).slice(0, 15) : [],
    savedOrganizerIds: new Set(),
    followedUserIds: new Set(),
    followedOrganizationIds: new Set(),
  };
}

async function loadPreferencesSafely(
    db, request, loader = loadPreferences, log = logger,
) {
  try {
    return await loader(db, request);
  } catch (error) {
    log.warn("Discovery personalization unavailable; using cold-start ranking.", {
      code: error?.code || "unknown",
      message: String(error?.message || error).slice(0, 300),
    });
    return coldStartPreferences(request);
  }
}

async function queryNearby(db, center, radiusMiles, now = new Date()) {
  const radiusMeters = radiusMiles * MILES_TO_KM * 1000;
  const bounds = geohashQueryBounds([center.latitude, center.longitude], radiusMeters);
  const snapshots = await Promise.all(bounds.map(([start, end]) => db.collection("Events")
      .where("private", "==", false)
      .orderBy("geohash")
      .startAt(start)
      .endAt(end)
      .limit(MAX_BOUND_RESULTS)
      .get()));
  const byId = new Map();
  for (const snapshot of snapshots) {
    for (const doc of snapshot.docs) {
      if (!activePublicEvent(doc.data(), now) || doc.get("locationType") === "online") continue;
      const dto = eventDto(doc, center);
      if (dto.distanceMiles !== null && dto.distanceMiles <= radiusMiles) byId.set(dto.id, dto);
    }
  }
  return [...byId.values()];
}

async function queryOnline(db, now = new Date(), limit = 40) {
  const snapshot = await db.collection("Events")
      .where("private", "==", false)
      .where("locationType", "==", "online")
      .where("selectedDateTime", ">", Timestamp.fromDate(new Date(now.getTime() - 3 * 3600000)))
      .orderBy("selectedDateTime")
      .limit(limit)
      .get();
  return snapshot.docs.filter((doc) => activePublicEvent(doc.data(), now)).map((doc) => eventDto(doc));
}

async function queryNationwide(db, now = new Date(), limit = 100) {
  const snapshot = await db.collection("Events")
      .where("private", "==", false)
      .where("selectedDateTime", ">", Timestamp.fromDate(new Date(now.getTime() - 3 * 3600000)))
      .orderBy("selectedDateTime").limit(limit).get();
  return snapshot.docs.filter((doc) => activePublicEvent(doc.data(), now) &&
    String(doc.get("countryCode") || "US").toUpperCase() === "US")
      .map((doc) => eventDto(doc));
}

async function queryStatewide(db, regionCode, center, now = new Date(), limit = 50) {
  if (!/^[A-Z]{2}$/.test(regionCode)) return [];
  const snapshot = await db.collection("Events")
      .where("private", "==", false)
      .where("regionCode", "==", regionCode)
      .where("selectedDateTime", ">", Timestamp.fromDate(new Date(now.getTime() - 3 * 3600000)))
      .orderBy("selectedDateTime").limit(limit).get();
  return snapshot.docs.filter((doc) => activePublicEvent(doc.data(), now) &&
    doc.get("locationType") !== "online").map((doc) => eventDto(doc, center));
}

function buildNationwideSections(events, preferences, now = new Date()) {
  const physical = events.filter((item) => item.locationType !== "online");
  const online = events.filter((item) => item.locationType === "online");
  const ranked = sortByScore(physical, preferences, now);
  const seen = new Set();
  const sections = [];
  const add = (id, title, subtitle, source, minimum = MIN_SECTION_SIZE) => {
    const selected = takeUnique(source, seen, 12);
    if (selected.length >= minimum) sections.push({id, title, subtitle, featured: id === "featured", events: selected});
  };
  add("recommended", "Across the U.S.", "Upcoming events from Attendus organizers", ranked, 1);
  const sevenDays = now.getTime() + 7 * 86400000;
  add("soon", "Happening soon", "Upcoming in the next seven days",
      physical.filter((item) => new Date(item.selectedDateTime).getTime() <= sevenDays));
  add("featured", "Featured across the U.S.", "Clearly labeled promoted events",
      physical.filter((item) => item.isFeatured && (!item.featureEndDate || new Date(item.featureEndDate) > now)));
  add("popular", "Popular across the U.S.", "Events people are saving and joining",
      [...physical].sort((a, b) => (b.saveCount + b.issuedTickets) - (a.saveCount + a.issuedTickets)));
  add("online", "Online across the U.S.", "Join from anywhere", sortByScore(online, preferences, now));
  return sections;
}

function createGetDiscoveryHome(admin) {
  const db = admin.firestore();
  return onCall({
    region: "us-central1",
    enforceAppCheck: process.env.FUNCTIONS_EMULATOR !== "true",
    timeoutSeconds: 30,
    memory: "512MiB",
    maxInstances: 30,
  }, async (request) => {
    requireCaller(request);
    await enforceDiscoveryRateLimit(db, request);
    const center = validateCenter(request.data);
    const requestedRadius = Math.min(100, Math.max(25, Number(request.data?.radiusMiles || 25)));
    const now = new Date();
    if (request.data?.nationwide === true) {
      const [events, preferences] = await Promise.all([
        queryNationwide(db, now), loadPreferencesSafely(db, request),
      ]);
      return {
        sections: buildNationwideSections(events, preferences, now),
        radiusMiles: 100,
        expandedRadius: false,
        localResultCount: events.filter((item) => item.locationType !== "online").length,
        generatedAt: now.toISOString(), schemaVersion: 1,
      };
    }
    const regionCode = String(request.data?.regionCode || "").trim().toUpperCase();
    const [allLocal, online, preferences] = await Promise.all([
      queryNearby(db, center, 100, now), queryOnline(db, now),
      loadPreferencesSafely(db, request),
    ]);
    const radiusMiles = chooseFallbackRadius(allLocal, requestedRadius);
    let sections = buildSections(allLocal, online, preferences, radiusMiles, now);
    if (allLocal.length === 0 && regionCode) {
      const statewide = sortByScore(
          await queryStatewide(db, regionCode, center, now), preferences, now,
      );
      if (statewide.length) {
        sections = [{
          id: "recommended", title: `Across ${regionCode}`,
          subtitle: "No events within 100 miles, so we expanded statewide",
          featured: false, events: statewide.slice(0, 12),
        }, ...sections.filter((section) => section.id !== "recommended")];
      }
    }
    return {
      sections,
      radiusMiles,
      expandedRadius: radiusMiles > requestedRadius,
      localResultCount: allLocal.filter((event) => event.distanceMiles <= radiusMiles).length,
      generatedAt: now.toISOString(),
      schemaVersion: 1,
    };
  });
}

function includesQuery(event, query) {
  const haystack = [event.title, event.description, event.groupName, event.locationName,
    event.city, event.regionCode, ...event.categories].filter(Boolean).join(" ").toLowerCase();
  return query.split(/\s+/).filter(Boolean).every((term) => haystack.includes(term));
}

function encodeCursor(offset) {
  return Buffer.from(JSON.stringify({offset}), "utf8").toString("base64url");
}

function decodeCursor(value) {
  if (!value) return 0;
  try {
    const parsed = JSON.parse(Buffer.from(String(value), "base64url").toString("utf8"));
    return Math.max(0, Number(parsed.offset || 0));
  } catch (_) {
    throw new HttpsError("invalid-argument", "Invalid search cursor.");
  }
}

function selectedDiscoveryCategory(data) {
  const value = String(data?.selectedCategoryId || data?.categoryId || "").trim();
  if (value && !CATEGORY_BY_ID.has(value)) {
    throw new HttpsError("invalid-argument", "Unknown discovery category.");
  }
  return value || null;
}

function dateWindow(datePreset, now) {
  const start = new Date(now);
  const end = new Date(now);
  if (datePreset === "today") {
    start.setHours(0, 0, 0, 0);
    end.setHours(24, 0, 0, 0);
    return {start, end};
  }
  if (datePreset === "weekend") {
    const days = (6 - now.getDay() + 7) % 7;
    start.setDate(now.getDate() + days);
    start.setHours(0, 0, 0, 0);
    end.setTime(start.getTime() + 2 * 86400000);
    return {start, end};
  }
  return null;
}

function applyV2Filters(events, data, now, {onlineOnly = false} = {}) {
  const selected = selectedDiscoveryCategory(data);
  const window = dateWindow(String(data?.datePreset || ""), now);
  return events.filter((event) => {
    if (onlineOnly && event.locationType !== "online") return false;
    if (selected && !(event.discoveryCategoryIds || []).includes(selected)) return false;
    if (data?.freeOnly === true && event.ticketsEnabled && Number(event.ticketPrice || 0) > 0) return false;
    if (window) {
      const startsAt = new Date(event.selectedDateTime);
      if (startsAt < window.start || startsAt >= window.end) return false;
    }
    return true;
  });
}

function addSectionTotals(sections, localEvents, onlineEvents, now = new Date()) {
  const sevenDays = now.getTime() + 7 * 86400000;
  return sections.map((section) => {
    let totalAvailable = localEvents.length;
    if (section.id === "soon") {
      totalAvailable = localEvents.filter((event) =>
        new Date(event.selectedDateTime).getTime() <= sevenDays).length;
    } else if (section.id === "featured") {
      totalAvailable = localEvents.filter((event) => event.isFeatured &&
        (!event.featureEndDate || new Date(event.featureEndDate) > now)).length;
    } else if (section.id === "online") {
      totalAvailable = onlineEvents.length;
    }
    return {...section, totalAvailable};
  });
}

function createGetDiscoveryHomeV2(admin) {
  const db = admin.firestore();
  return onCall({region: "us-central1", enforceAppCheck: process.env.FUNCTIONS_EMULATOR !== "true",
    timeoutSeconds: 30, memory: "512MiB", maxInstances: 30}, async (request) => {
    requireCaller(request);
    await enforceDiscoveryRateLimit(db, request);
    const center = validateCenter(request.data);
    const requestedRadius = Math.min(100, Math.max(25, Number(request.data?.radiusMiles || 25)));
    const now = new Date();
    const preferences = await loadPreferencesSafely(db, request);
    const selectedCategoryId = selectedDiscoveryCategory(request.data);
    const nationwide = request.data?.nationwide === true;
    let allLocal;
    let allOnline;
    if (nationwide) {
      const events = await queryNationwide(db, now, 150);
      allLocal = events.filter((item) => item.locationType !== "online");
      allOnline = events.filter((item) => item.locationType === "online");
    } else {
      [allLocal, allOnline] = await Promise.all([queryNearby(db, center, 100, now), queryOnline(db, now, 100)]);
    }
    const eligibleLocalAtAnyRadius = applyV2Filters(allLocal, request.data, now);
    const radiusMiles = nationwide ? 100 : chooseFallbackRadius(eligibleLocalAtAnyRadius, requestedRadius);
    const facetEvents = [...allLocal.filter((event) => nationwide || event.distanceMiles <= radiusMiles), ...allOnline];
    let local = eligibleLocalAtAnyRadius
        .filter((event) => nationwide || event.distanceMiles <= radiusMiles);
    let online = applyV2Filters(allOnline, request.data, now, {onlineOnly: true});
    if (request.data?.onlineOnly === true) local = [];
    let sections = nationwide ? buildNationwideSections([...local, ...online], preferences, now) :
      buildSections(local, online, preferences, radiusMiles, now);
    const regionCode = String(request.data?.regionCode || "").trim().toUpperCase();
    if (!nationwide && local.length === 0 && regionCode && request.data?.onlineOnly !== true) {
      const statewide = applyV2Filters(
          await queryStatewide(db, regionCode, center, now), request.data, now,
      );
      if (statewide.length) {
        sections = [{id: "recommended", title: `Across ${regionCode}`,
          subtitle: "No events within 100 miles, so we expanded statewide", featured: false,
          events: sortByScore(statewide, preferences, now).slice(0, 12)},
        ...sections.filter((section) => section.id !== "recommended")];
        local = statewide;
      }
    }
    sections = addSectionTotals(sections, local, online, now);
    return {sections, categoryFacets: categoryFacets(facetEvents, preferences), selectedCategoryId,
      radiusMiles, expandedRadius: !nationwide && radiusMiles > requestedRadius,
      localResultCount: local.length, generatedAt: now.toISOString(), schemaVersion: 2};
  });
}

function createSearchDiscoveryEventsV2(admin) {
  const db = admin.firestore();
  return onCall({region: "us-central1", enforceAppCheck: process.env.FUNCTIONS_EMULATOR !== "true",
    timeoutSeconds: 30, memory: "512MiB", maxInstances: 30}, async (request) => {
    requireCaller(request);
    await enforceDiscoveryRateLimit(db, request);
    const center = validateCenter(request.data);
    const radiusMiles = Math.min(100, Math.max(1, Number(request.data?.radiusMiles || 25)));
    const limit = Math.min(MAX_SEARCH_RESULTS, Math.max(1, Number(request.data?.limit || 24)));
    const query = String(request.data?.query || "").trim().toLowerCase().slice(0, 120);
    const now = new Date();
    const preferences = await loadPreferencesSafely(db, request);
    let events = request.data?.nationwide === true ? await queryNationwide(db, now, 150) :
      request.data?.onlineOnly === true ? await queryOnline(db, now, 100) : await queryNearby(db, center, radiusMiles, now);
    events = applyV2Filters(events, request.data, now, {onlineOnly: request.data?.onlineOnly === true});
    if (query) events = events.filter((event) => includesQuery(event, query));
    events = sortByScore(events, preferences, now);
    const offset = decodeCursor(request.data?.cursor);
    const page = events.slice(offset, offset + limit);
    return {events: page, nextCursor: offset + limit < events.length ? encodeCursor(offset + limit) : null,
      total: events.length, radiusMiles, selectedCategoryId: selectedDiscoveryCategory(request.data),
      generatedAt: now.toISOString(), schemaVersion: 2};
  });
}

function createSearchDiscoveryEvents(admin) {
  const db = admin.firestore();
  return onCall({
    region: "us-central1",
    enforceAppCheck: process.env.FUNCTIONS_EMULATOR !== "true",
    timeoutSeconds: 30,
    memory: "512MiB",
    maxInstances: 30,
  }, async (request) => {
    requireCaller(request);
    await enforceDiscoveryRateLimit(db, request);
    const center = validateCenter(request.data);
    const radiusMiles = Math.min(100, Math.max(1, Number(request.data?.radiusMiles || 25)));
    const limit = Math.min(MAX_SEARCH_RESULTS, Math.max(1, Number(request.data?.limit || 20)));
    const query = String(request.data?.query || "").trim().toLowerCase().slice(0, 120);
    const category = String(request.data?.category || "").trim().toLowerCase();
    const onlineOnly = request.data?.onlineOnly === true;
    const datePreset = String(request.data?.datePreset || "");
    const now = new Date();
    const preferences = await loadPreferencesSafely(db, request);
    let events = request.data?.nationwide === true ? await queryNationwide(db, now, 150) :
      onlineOnly ? await queryOnline(db, now, 100) : await queryNearby(db, center, radiusMiles, now);
    if (query) events = events.filter((event) => includesQuery(event, query));
    if (category) events = events.filter((event) => event.categories.some((value) => String(value).toLowerCase() === category));
    if (datePreset) {
      const start = new Date(now);
      const end = new Date(now);
      if (datePreset === "today") {
        start.setHours(0, 0, 0, 0); end.setHours(24, 0, 0, 0);
      } else if (datePreset === "weekend") {
        const days = (6 - now.getDay() + 7) % 7;
        start.setDate(now.getDate() + days); start.setHours(0, 0, 0, 0);
        end.setTime(start.getTime() + 2 * 86400000);
      }
      events = events.filter((event) => {
        const date = new Date(event.selectedDateTime);
        return date >= start && date < end;
      });
    }
    if (request.data?.freeOnly === true) {
      events = events.filter((event) => !event.ticketsEnabled || !event.ticketPrice || event.ticketPrice <= 0);
    }
    events = sortByScore(events, preferences, now);
    const offset = decodeCursor(request.data?.cursor);
    const page = events.slice(offset, offset + limit);
    return {
      events: page,
      nextCursor: offset + limit < events.length ? encodeCursor(offset + limit) : null,
      total: events.length,
      radiusMiles,
      generatedAt: now.toISOString(),
      schemaVersion: 1,
    };
  });
}

function createMaintainDiscoveryMetadata(_admin) {
  return onDocumentWritten({document: "Events/{eventId}", region: "us-central1"}, async (event) => {
    const after = event.data?.after;
    if (!after?.exists) return;
    const data = after.data();
    const physical = data.locationType !== "online";
    const latitude = Number(data.latitude || 0);
    const longitude = Number(data.longitude || 0);
    const city = String(data.city || "").trim();
    const regionCode = String(data.regionCode || "").trim().toUpperCase();
    const countryCode = String(data.countryCode || "").trim().toUpperCase();
    const valid = physical && Number.isFinite(latitude) && Number.isFinite(longitude) &&
      latitude >= -90 && latitude <= 90 && longitude >= -180 && longitude <= 180 &&
      !(latitude === 0 && longitude === 0) && city.length > 0 &&
      regionCode.length > 0 && countryCode === "US";
    const discoveryCategories = inferDiscoveryCategories(data);
    const desired = {
      geohash: valid ? geohashForLocation([latitude, longitude]) : null,
      city: valid ? city : "",
      regionCode: valid ? regionCode : "",
      countryCode: valid ? countryCode : null,
      discoveryLocationValid: valid,
      ...discoveryCategories,
    };
    if (data.geohash === desired.geohash && data.city === desired.city &&
        data.regionCode === desired.regionCode && data.countryCode === desired.countryCode &&
        data.discoveryLocationValid === desired.discoveryLocationValid &&
        data.primaryDiscoveryCategoryId === desired.primaryDiscoveryCategoryId &&
        JSON.stringify(data.discoveryCategoryIds || []) === JSON.stringify(desired.discoveryCategoryIds) &&
        data.discoveryCategorySource === desired.discoveryCategorySource &&
        data.discoveryCategoryVersion === desired.discoveryCategoryVersion) return;
    await after.ref.set({...desired, discoveryMetadataUpdatedAt: FieldValue.serverTimestamp()}, {merge: true});
  });
}

function createSavedEventCounter(admin) {
  return onDocumentWritten({
    document: "Customers/{uid}/SavedEvents/{eventId}", region: "us-central1",
  }, async (event) => {
    const before = event.data?.before?.exists === true;
    const after = event.data?.after?.exists === true;
    if (before === after) return;
    await admin.firestore().collection("Events").doc(event.params.eventId).set({
      saveCount: FieldValue.increment(after ? 1 : -1),
    }, {merge: true});
  });
}

module.exports = {
  DISCOVERY_RADII_MILES,
  activePublicEvent,
  applyV2Filters,
  buildSections,
  chooseFallbackRadius,
  createGetDiscoveryHome,
  createGetDiscoveryHomeV2,
  createMaintainDiscoveryMetadata,
  createSavedEventCounter,
  createSearchDiscoveryEvents,
  createSearchDiscoveryEventsV2,
  eventDto,
  loadPreferencesSafely,
  scoreEvent,
};
