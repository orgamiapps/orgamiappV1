"use strict";

const {getApps, initializeApp} = require("firebase-admin/app");
const {getFirestore, FieldValue} = require("firebase-admin/firestore");
const {inferDiscoveryCategories} = require("../discovery/category-catalog");
const {activePublicEvent} = require("../discovery/marketplace");

const allowedProjects = new Set(["attendus-staging", "orgami-66nxok"]);

function argumentValue(name) {
  const index = process.argv.indexOf(name);
  return index === -1 ? undefined : process.argv[index + 1];
}

async function main() {
  const projectId = argumentValue("--project");
  const apply = process.argv.includes("--apply");
  if (!allowedProjects.has(projectId)) throw new Error("Use an explicitly approved project.");
  if (getApps().length === 0) initializeApp({projectId});
  const db = getFirestore();
  const snapshot = await db.collection("Events").get();
  const eligible = snapshot.docs.filter((doc) => activePublicEvent(doc.data()));
  const changes = eligible.filter((doc) => {
    const data = doc.data();
    const desired = inferDiscoveryCategories(data);
    return data.primaryDiscoveryCategoryId !== desired.primaryDiscoveryCategoryId ||
      JSON.stringify(data.discoveryCategoryIds || []) !== JSON.stringify(desired.discoveryCategoryIds) ||
      data.discoveryCategorySource !== desired.discoveryCategorySource ||
      data.discoveryCategoryVersion !== desired.discoveryCategoryVersion;
  });
  if (apply) {
    for (let offset = 0; offset < changes.length; offset += 400) {
      const batch = db.batch();
      for (const doc of changes.slice(offset, offset + 400)) {
        batch.set(doc.ref, {...inferDiscoveryCategories(doc.data()),
          discoveryMetadataUpdatedAt: FieldValue.serverTimestamp()}, {merge: true});
      }
      await batch.commit();
    }
  }
  process.stdout.write(`${JSON.stringify({projectId, scanned: snapshot.size,
    eligible: eligible.length, changed: changes.length, applied: apply})}\n`);
}

main().catch((error) => {
  process.stderr.write(`${error.stack || error.message}\n`);
  process.exitCode = 1;
});
