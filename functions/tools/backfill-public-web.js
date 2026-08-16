"use strict";

const {getApps, initializeApp} = require("firebase-admin/app");
const {FieldValue, getFirestore} = require("firebase-admin/firestore");
const {
  communityEligibility,
  eventEligibility,
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
  const eligibleEvents = events.docs.filter((entry) => eventEligibility(entry.data()));
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
      const changed = ["eventTimeZone", "streetAddress", "postalCode"]
          .some((field) => String(data[field] || "") !== String(metadata[field] || ""));
      if (changed) {
        summary.metadataChanges += 1;
        await event.ref.set({...metadata,
          publicWebMetadataUpdatedAt: FieldValue.serverTimestamp()}, {merge: true});
      }
      await db.collection("PublicWebEvents").doc(event.id)
          .set(projectionForEvent(event.id, {...data, ...metadata}));
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

main().catch((error) => {
  process.stderr.write(`${error.stack || error.message}\n`);
  process.exitCode = 1;
});
