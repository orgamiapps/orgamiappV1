"use strict";

const {getApps, initializeApp} = require("firebase-admin/app");
const {FieldValue, getFirestore} = require("firebase-admin/firestore");

const allowedProjects = new Set(["attendus-staging", "orgami-66nxok"]);

async function main() {
  const projectIndex = process.argv.indexOf("--project");
  const projectId = projectIndex >= 0 ? process.argv[projectIndex + 1] : "";
  const useLegacyFeed = process.argv.includes("--legacy");
  const useMarketplace = process.argv.includes("--marketplace");
  if (!allowedProjects.has(projectId) || useLegacyFeed === useMarketplace) {
    throw new Error(
        "Usage: node set-discovery-rollout.js --project <project> " +
        "(--legacy|--marketplace)",
    );
  }
  if (getApps().length === 0) initializeApp({projectId});
  await getFirestore().collection("AppConfig").doc("discovery").set({
    useLegacyFeed,
    rolloutUpdatedAt: FieldValue.serverTimestamp(),
  }, {merge: true});
  process.stdout.write(
      `Discovery ${useLegacyFeed ? "legacy rollback" : "marketplace"} ` +
      `enabled in ${projectId}.\n`,
  );
}

main().catch((error) => {
  process.stderr.write(`${error.stack || error.message}\n`);
  process.exitCode = 1;
});
