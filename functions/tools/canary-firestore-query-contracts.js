"use strict";

const {getApps, initializeApp} = require("firebase-admin/app");
const {getFirestore} = require("firebase-admin/firestore");
const contracts = require("../../tools/firestore_query_contracts");

const allowedProjects = new Set(["attendus-staging", "orgami-66nxok"]);

function valueFor(filter) {
  if (filter.value === "boolean") return true;
  if (filter.value === "approved") return "approved";
  if (filter.value === "string-list") return ["__attendus_index_canary__"];
  return "__attendus_index_canary__";
}

async function main() {
  const projectIndex = process.argv.indexOf("--project");
  const projectId = projectIndex >= 0 ? process.argv[projectIndex + 1] : "";
  if (!allowedProjects.has(projectId)) {
    throw new Error("Use --project attendus-staging or --project orgami-66nxok.");
  }
  if (getApps().length === 0) initializeApp({projectId});
  const db = getFirestore();
  for (const contract of contracts) {
    let query = db.collectionGroup(contract.collectionGroup);
    for (const filter of contract.filters) {
      query = query.where(filter.fieldPath, filter.operator, valueFor(filter));
    }
    await query.limit(1).get();
  }
  process.stdout.write(
      `Firestore query canary passed ${contracts.length} contracts in ${projectId}.\n`,
  );
}

main().catch((error) => {
  process.stderr.write(`${error.stack || error.message}\n`);
  process.exitCode = 1;
});
