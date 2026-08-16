"use strict";

const {getApps, initializeApp} = require("firebase-admin/app");
const {FieldValue, getFirestore} = require("firebase-admin/firestore");

const allowedProjects = new Set(["attendus-staging", "orgami-66nxok"]);

async function main() {
  const projectIndex = process.argv.indexOf("--project");
  const projectId = projectIndex >= 0 ? process.argv[projectIndex + 1] : "";
  const useLegacyFeed = process.argv.includes("--legacy");
  const useMarketplace = process.argv.includes("--marketplace");
  const versionIndex = process.argv.indexOf("--experience-version");
  const experienceVersion = versionIndex >= 0 ? Number(process.argv[versionIndex + 1]) : null;
  if (!allowedProjects.has(projectId) || useLegacyFeed === useMarketplace) {
    throw new Error(
        "Usage: node set-discovery-rollout.js --project <project> " +
        "(--legacy|--marketplace) [--experience-version 1|2]",
    );
  }
  if (experienceVersion !== null && ![1, 2].includes(experienceVersion)) {
    throw new Error("Experience version must be 1 or 2.");
  }
  if (getApps().length === 0) initializeApp({projectId});
  await getFirestore().collection("AppConfig").doc("discovery").set({
    useLegacyFeed,
    ...(experienceVersion === null ? {} : {marketplaceExperienceVersion: experienceVersion}),
    rolloutUpdatedAt: FieldValue.serverTimestamp(),
  }, {merge: true});
  process.stdout.write(
      `Discovery ${useLegacyFeed ? "legacy rollback" : "marketplace"} ` +
      `enabled in ${projectId}${experienceVersion === null ? "" : ` at V${experienceVersion}`}.\n`,
  );
}

main().catch((error) => {
  process.stderr.write(`${error.stack || error.message}\n`);
  process.exitCode = 1;
});
