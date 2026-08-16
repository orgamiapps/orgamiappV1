"use strict";

const {getApps, initializeApp} = require("firebase-admin/app");
const {getFirestore} = require("firebase-admin/firestore");
const {activePublicEvent} = require("../discovery/marketplace");

async function main() {
  if (getApps().length === 0) initializeApp();
  const db = getFirestore();
  const events = await db.collection("Events").get();
  const failures = [];
  let discoverable = 0;
  for (const document of events.docs) {
    const data = document.data();
    if (!activePublicEvent(data)) continue;
    discoverable += 1;
    if (data.private === true) failures.push(`${document.id}: private`);
    if (data.locationType !== "online") {
      const latitude = Number(data.latitude);
      const longitude = Number(data.longitude);
      if (!data.discoveryLocationValid || !data.geohash || !data.city ||
          !data.regionCode || !data.countryCode || !Number.isFinite(latitude) ||
          !Number.isFinite(longitude) || (latitude === 0 && longitude === 0)) {
        failures.push(`${document.id}: incomplete geographic metadata`);
      }
    }
  }
  const summary = {scanned: events.size, discoverable, failures: failures.length,
    sampleFailures: failures.slice(0, 50)};
  process.stdout.write(`${JSON.stringify(summary, null, 2)}\n`);
  if (failures.length) process.exitCode = 2;
}

main().catch((error) => {
  process.stderr.write(`${error.stack || error.message}\n`);
  process.exitCode = 1;
});
