"use strict";

const {getApps, initializeApp} = require("firebase-admin/app");
const {FieldValue, getFirestore} = require("firebase-admin/firestore");
const {
  communityEligibility,
  eventProjectionEligibility,
  projectionForCommunity,
  projectionForEvent,
} = require("../public-web/renderer");

const allowedProjects = new Set(["attendus-staging", "orgami-66nxok"]);

function argumentValue(name) {
  const index = process.argv.indexOf(name);
  return index === -1 ? undefined : process.argv[index + 1];
}

async function geographicMetadata(data, key) {
  const latitude = Number(data.latitude);
  const longitude = Number(data.longitude);
  if (!key || data.locationType === "online" || !Number.isFinite(latitude) ||
      !Number.isFinite(longitude) || (latitude === 0 && longitude === 0)) {
    return {
      eventTimeZone: String(data.eventTimeZone || "UTC"),
      streetAddress: String(data.streetAddress || data.location || ""),
      postalCode: String(data.postalCode || ""),
    };
  }
  const timestamp = Math.floor(Date.now() / 1000);
  const [timeZoneResponse, geocodeResponse] = await Promise.all([
    fetch("https://maps.googleapis.com/maps/api/timezone/json?" +
      new URLSearchParams({location: `${latitude},${longitude}`,
        timestamp: String(timestamp), key})),
    fetch("https://maps.googleapis.com/maps/api/geocode/json?" +
      new URLSearchParams({latlng: `${latitude},${longitude}`, key})),
  ]);
  const [timeZone, geocode] = await Promise.all([
    timeZoneResponse.json(), geocodeResponse.json(),
  ]);
  let streetNumber = "";
  let route = "";
  let postalCode = String(data.postalCode || "");
  if (geocode.status === "OK") {
    for (const component of geocode.results?.[0]?.address_components || []) {
      const types = component.types || [];
      if (types.includes("street_number")) streetNumber = component.long_name || "";
      if (types.includes("route")) route = component.long_name || "";
      if (types.includes("postal_code")) postalCode = component.long_name || "";
    }
  }
  return {
    eventTimeZone: timeZone.status === "OK" ?
      String(timeZone.timeZoneId || "UTC") : String(data.eventTimeZone || "UTC"),
    streetAddress: [streetNumber, route].filter(Boolean).join(" ") ||
      String(data.streetAddress || data.location || ""),
    postalCode,
  };
}

async function applyEventBackfill(db, scanned, metadata) {
  const projection = db.collection("PublicWebEvents").doc(scanned.id);
  return db.runTransaction(async (tx) => {
    const current = await tx.get(scanned.ref);
    if (!current.exists || !eventProjectionEligibility(current.data())) {
      tx.delete(projection);
      return {metadataChanged: false, projectionWritten: false};
    }
    // Geocoding used the scanned address. Leave concurrently edited sources
    // for a new scan rather than applying metadata for their former location.
    if (!current.updateTime?.isEqual(scanned.updateTime)) {
      return {metadataChanged: false, projectionWritten: false};
    }
    const data = current.data();
    const metadataChanged = ["eventTimeZone", "streetAddress", "postalCode"]
        .some((field) => String(data[field] || "") !== String(metadata[field] || ""));
    if (metadataChanged) {
      tx.update(current.ref, {...metadata, publicWebMetadataUpdatedAt: FieldValue.serverTimestamp()});
    }
    tx.set(projection, projectionForEvent(current.id, {...data, ...metadata}));
    return {metadataChanged, projectionWritten: true};
  });
}

async function main() {
  const projectId = argumentValue("--project");
  const apply = process.argv.includes("--apply");
  if (!allowedProjects.has(projectId)) throw new Error("Use an explicitly approved project.");
  if (getApps().length === 0) initializeApp({projectId});
  const db = getFirestore();
  const [events, organizations, projectedEvents, projectedCommunities] =
    await Promise.all([
      db.collection("Events").get(),
      db.collection("Organizations").get(),
      db.collection("PublicWebEvents").get(),
      db.collection("PublicWebCommunities").get(),
    ]);
  const eligibleEvents = events.docs.filter((entry) => eventProjectionEligibility(entry.data()));
  const eligibleCommunities = organizations.docs.filter((entry) =>
    communityEligibility(entry.data()));
  const desiredEventIds = new Set(eligibleEvents.map((entry) => entry.id));
  const desiredCommunityIds = new Set(eligibleCommunities.map((entry) => entry.id));
  const summary = {
    projectId,
    mode: apply ? "apply" : "dry-run",
    eventsScanned: events.size,
    eventsEligible: eligibleEvents.length,
    communitiesScanned: organizations.size,
    communitiesEligible: eligibleCommunities.length,
    metadataChanges: 0,
    projectionWrites: eligibleEvents.length + eligibleCommunities.length,
    staleProjectionDeletes: projectedEvents.docs.filter((entry) =>
      !desiredEventIds.has(entry.id)).length + projectedCommunities.docs.filter((entry) =>
      !desiredCommunityIds.has(entry.id)).length,
  };
  const placesKey = String(process.env.GOOGLE_PLACES_API_KEY || "").trim();
  if (apply) {
    for (const event of eligibleEvents) {
      const data = event.data();
      const metadata = await geographicMetadata(data, placesKey);
      const result = await applyEventBackfill(db, event, metadata);
      if (result.metadataChanged) summary.metadataChanges += 1;
      if (!result.projectionWritten) summary.projectionWrites -= 1;
    }
    for (const organization of eligibleCommunities) {
      await db.collection("PublicWebCommunities").doc(organization.id)
          .set(projectionForCommunity(organization.id, organization.data()));
    }
    for (const entry of projectedEvents.docs) {
      if (!desiredEventIds.has(entry.id)) await entry.ref.delete();
    }
    for (const entry of projectedCommunities.docs) {
      if (!desiredCommunityIds.has(entry.id)) await entry.ref.delete();
    }
  } else {
    summary.metadataChanges = eligibleEvents.filter((entry) => {
      const data = entry.data();
      return !data.eventTimeZone || !data.streetAddress ||
        data.postalCode === undefined;
    }).length;
  }
  process.stdout.write(`${JSON.stringify(summary, null, 2)}\n`);
}

if (require.main === module) {
  main().catch((error) => {
    process.stderr.write(`${error.stack || error.message}\n`);
    process.exitCode = 1;
  });
}

module.exports = {applyEventBackfill};
