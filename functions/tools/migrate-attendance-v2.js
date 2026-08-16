"use strict";

const {getApps, initializeApp} = require("firebase-admin/app");
const {getFirestore} = require("firebase-admin/firestore");
const {normalizePolicy} = require("../attendance/v2");

async function main() {
  const apply = process.argv.includes("--apply");
  if (getApps().length === 0) initializeApp();
  const db = getFirestore();
  const snapshot = await db.collection("Events").get();
  const summary = {
    mode: apply ? "apply" : "dry-run",
    scanned: snapshot.size,
    alreadyMigrated: 0,
    selfCheckIn: 0,
    hybrid: 0,
    organizerReview: 0,
    updated: 0,
  };
  let batch = db.batch();
  let batchSize = 0;

  for (const document of snapshot.docs) {
    const event = document.data();
    if (event.checkInPolicy?.version === 2) {
      summary.alreadyMigrated += 1;
      continue;
    }
    const policy = normalizePolicy(event);
    if (policy.profile === "self_check_in") summary.selfCheckIn += 1;
    else summary.hybrid += 1;
    if (policy.needsOrganizerReview) summary.organizerReview += 1;

    if (!apply) continue;
    const signInMethods = policy.profile === "self_check_in" ?
      ["qr_code", "manual_code"] :
      ["qr_code", "manual_code", "personal_pass", "staff_roster"];
    const legacyRadius = Number(event.radius);
    batch.update(document.ref, {
      checkInPolicy: policy,
      signInMethods,
      signInSecurityTier: policy.profile === "hybrid" ? "all" : "regular",
      attendanceV2MigratedAt: new Date(),
      radius: event.radiusUnit === "meters" || !Number.isFinite(legacyRadius) ?
        event.radius : legacyRadius * 0.3048,
      radiusUnit: "meters",
    });
    summary.updated += 1;
    batchSize += 1;
    if (batchSize === 400) {
      await batch.commit();
      batch = db.batch();
      batchSize = 0;
    }
  }
  if (apply && batchSize > 0) await batch.commit();
  process.stdout.write(`${JSON.stringify(summary, null, 2)}\n`);
  if (!apply) {
    process.stdout.write("Dry run only. Re-run with --apply after review.\n");
  }
}

main().catch((error) => {
  process.stderr.write(`${error.stack || error.message}\n`);
  process.exitCode = 1;
});
