"use strict";

const {getApps, initializeApp} = require("firebase-admin/app");
const {getFirestore} = require("firebase-admin/firestore");
const {
  deleteFaceEnrollments,
  inventoryFaceEnrollments,
} = require("../biometrics/retention");

function argumentsByName(values) {
  const result = {};
  for (const value of values) {
    const match = /^--([^=]+)=(.*)$/.exec(value);
    if (match) result[match[1]] = match[2];
    else if (value.startsWith("--")) result[value.slice(2)] = true;
  }
  return result;
}

async function main() {
  const args = argumentsByName(process.argv.slice(2));
  if (getApps().length === 0) initializeApp();
  const db = getFirestore();

  if (!args.delete) {
    const inventory = await inventoryFaceEnrollments(db);
    process.stdout.write(`${JSON.stringify(inventory, null, 2)}\n`);
    return;
  }

  const result = await deleteFaceEnrollments(db, {
    confirmation: args.confirm,
    backupReference: args["backup-reference"],
    notBefore: args["not-before"],
    requestedBy: args["requested-by"],
  });
  process.stdout.write(`${JSON.stringify(result, null, 2)}\n`);
}

main().catch((error) => {
  process.stderr.write(`${error.message}\n`);
  process.exitCode = 1;
});
