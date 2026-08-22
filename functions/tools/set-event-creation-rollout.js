"use strict";

const {getApps, initializeApp} = require("firebase-admin/app");
const {FieldValue, getFirestore} = require("firebase-admin/firestore");

const allowedProjects = new Set(["attendus-staging", "orgami-66nxok"]);

function value(name) {
  const index = process.argv.indexOf(name);
  return index === -1 ? "" : String(process.argv[index + 1] || "").trim();
}

async function main() {
  const projectId = value("--project");
  const version = Number(value("--experience-version"));
  if (!allowedProjects.has(projectId) || ![1, 2].includes(version)) {
    throw new Error("Usage: node set-event-creation-rollout.js --project <approved-project> " +
      "--experience-version 1|2");
  }
  if (getApps().length === 0) initializeApp({projectId});
  const ref = getFirestore().collection("AppConfig").doc("eventCreation");
  await ref.set({experienceVersion: version,
    rolloutUpdatedAt: FieldValue.serverTimestamp()}, {merge: true});
  process.stdout.write(`${JSON.stringify({projectId, experienceVersion: version})}\n`);
}

main().catch((error) => {
  process.stderr.write(`${error.stack || error.message}\n`);
  process.exitCode = 1;
});
