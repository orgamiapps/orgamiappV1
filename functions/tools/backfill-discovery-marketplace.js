"use strict";

const {getApps, initializeApp} = require("firebase-admin/app");
const {FieldValue, getFirestore} = require("firebase-admin/firestore");
const {geohashForLocation} = require("geofire-common");

async function reverseGeocode(latitude, longitude, key) {
  const query = new URLSearchParams({latlng: `${latitude},${longitude}`, key});
  const response = await fetch(`https://maps.googleapis.com/maps/api/geocode/json?${query}`);
  const body = await response.json();
  if (body.status === "ZERO_RESULTS") {
    return {eligible: false, city: "", regionCode: "", countryCode: ""};
  }
  if (!response.ok || body.status !== "OK" || !body.results?.length) {
    throw new Error(`Reverse geocoding failed: ${body.status || response.status}`);
  }
  let city = "";
  let regionCode = "";
  let countryCode = "";
  for (const component of body.results[0].address_components || []) {
    const types = component.types || [];
    if (!city && ["locality", "postal_town", "administrative_area_level_2"]
        .some((type) => types.includes(type))) city = component.long_name;
    if (types.includes("administrative_area_level_1")) regionCode = component.short_name;
    if (types.includes("country")) countryCode = component.short_name;
  }
  return {
    eligible: Boolean(city && regionCode && countryCode === "US"),
    city,
    regionCode,
    countryCode,
  };
}

async function main() {
  const apply = process.argv.includes("--apply");
  if (getApps().length === 0) initializeApp();
  const db = getFirestore();
  const snapshot = await db.collection("Events").get();
  const placesKey = String(process.env.GOOGLE_PLACES_API_KEY || "").trim();
  const requiresGeocoding = snapshot.docs.some((document) => {
    const data = document.data();
    const latitude = Number(data.latitude);
    const longitude = Number(data.longitude);
    return data.locationType !== "online" && Number.isFinite(latitude) &&
      Number.isFinite(longitude) && !(latitude === 0 && longitude === 0) &&
      (!data.city || !data.regionCode);
  });
  if (apply && requiresGeocoding && !placesKey) {
    throw new Error("GOOGLE_PLACES_API_KEY is required to backfill missing city metadata.");
  }
  const summary = {mode: apply ? "apply" : "dry-run", scanned: snapshot.size,
    online: 0, valid: 0, quarantined: 0, nonUsOrUnresolved: 0,
    updated: 0, missingCity: 0};
  let batch = db.batch();
  let pending = 0;
  for (const document of snapshot.docs) {
    const data = document.data();
    if (data.locationType === "online") {
      summary.online += 1;
      if (apply) batch.set(document.ref, {
        geohash: null, discoveryLocationValid: false,
        discoveryMetadataUpdatedAt: FieldValue.serverTimestamp(),
      }, {merge: true});
    } else {
      const latitude = Number(data.latitude);
      const longitude = Number(data.longitude);
      let valid = Number.isFinite(latitude) && Number.isFinite(longitude) &&
        latitude >= -90 && latitude <= 90 && longitude >= -180 && longitude <= 180 &&
        !(latitude === 0 && longitude === 0);
      if (!valid) summary.quarantined += 1;
      else summary.valid += 1;
      let city = String(data.city || "").trim();
      let regionCode = String(data.regionCode || "").trim().toUpperCase();
      let countryCode = String(data.countryCode || "US").toUpperCase();
      if (valid && (!city || !regionCode)) {
        summary.missingCity += 1;
        if (apply) {
          const resolved = await reverseGeocode(latitude, longitude, placesKey);
          if (resolved.eligible) {
            city = resolved.city;
            regionCode = resolved.regionCode;
            countryCode = resolved.countryCode;
          } else {
            valid = false;
            city = "";
            regionCode = "";
            countryCode = resolved.countryCode || "";
            summary.valid -= 1;
            summary.quarantined += 1;
            summary.nonUsOrUnresolved += 1;
          }
        }
      }
      if (apply) batch.set(document.ref, {
        geohash: valid ? geohashForLocation([latitude, longitude]) : null,
        city,
        regionCode,
        countryCode: valid ? countryCode : null,
        discoveryLocationValid: valid,
        discoveryMetadataUpdatedAt: FieldValue.serverTimestamp(),
      }, {merge: true});
    }
    if (!apply) continue;
    summary.updated += 1;
    pending += 1;
    if (pending === 400) { await batch.commit(); batch = db.batch(); pending = 0; }
  }
  if (apply && pending > 0) await batch.commit();
  process.stdout.write(`${JSON.stringify(summary, null, 2)}\n`);
  if (!apply) process.stdout.write("Dry run only. Re-run with --apply after reviewing invalid and missing-city counts.\n");
}

main().catch((error) => { process.stderr.write(`${error.stack || error.message}\n`); process.exitCode = 1; });
