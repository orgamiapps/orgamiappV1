"use strict";

const {initializeApp} = require("firebase-admin/app");
const {getFirestore, FieldValue} = require("firebase-admin/firestore");
const core = require("../attendance/arrival-core");
const value = (name) => {
  const index = process.argv.indexOf(name);
  return index >= 0 ? process.argv[index + 1] : "";
};

async function main() {
  const projectId = value("--project");
  const feature = value("--feature");
  const enabled = value("--enabled");
  const eventIds = [...new Set((value("--events") || "").split(",").filter(Boolean))];
  const userIds = [...new Set((value("--accounts") || "").split(",").filter(Boolean))];
  const identityEnabled = process.argv.includes("--identity");
  if (!["attendus-staging", "orgami-66nxok"].includes(projectId) ||
      !["smartArrival", "corePasses", "appleDelivery", "googleDelivery"].includes(feature) || !["true", "false"].includes(enabled) ||
      [...eventIds, ...userIds].some((id) => id.includes("/") || id.length > 500) ||
      (enabled === "true" && !userIds.length) ||
      (enabled === "true" && !eventIds.length && !(feature !== "smartArrival" && identityEnabled))) {
    throw Error("Usage: --project <project> --feature smartArrival|corePasses|appleDelivery|googleDelivery --enabled true|false --events <ids> --accounts <uids> [--identity] [--apply]. Enabling requires a scoped pilot.");
  }
  initializeApp({projectId});
  const db = getFirestore();
  for (const eventId of eventIds) {
    const event = await db.collection("Events").doc(eventId).get();
    if (!event.exists || !core.activeEvent(event.data())) throw Error(`Unavailable pilot event: ${eventId}`);
    if (feature === "smartArrival" && enabled === "true") core.validateBoundary(event.data());
  }
  const ref = db.collection("AppConfig").doc("attendance");
  const before = (await ref.get()).data()?.[feature] || {};
  const after = {...before, enabled: enabled === "true", allEvents: false,
    ...(enabled === "true" ? {eventIds, userIds, ...(feature !== "smartArrival" ? {identityEnabled} : {})} : {})};
  process.stdout.write(JSON.stringify({projectId, feature, before, after, apply: process.argv.includes("--apply")}, null, 2) + "\n");
  if (process.argv.includes("--apply")) {
    await ref.set({[feature]: after, updatedAt: FieldValue.serverTimestamp()}, {merge: true});
    // Later issuer activation synchronizes existing identities, including revoked
    // passes, instead of creating replacement credentials or provider objects.
    if (enabled === "true" && ["appleDelivery", "googleDelivery"].includes(feature)) {
      for (const uid of userIds) {
        const passes = await db.collection("AttendancePasses").where("ownerUid", "==", uid).get();
        for (const pass of passes.docs) {
          if (!(eventIds.includes(pass.data().eventId) || (!pass.data().eventId && identityEnabled))) continue;
          await db.collection("AttendanceWalletDeliveryJobs").doc(pass.id).set({passId: pass.id,
            nextAttemptAtMs: 0, attempts: 0, updatedAt: FieldValue.serverTimestamp()});
        }
      }
    }
  }
}

main().catch((error) => {process.stderr.write(`${error.message}\n`); process.exitCode = 1;});
