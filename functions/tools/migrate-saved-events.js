"use strict";

const {getApps, initializeApp} = require("firebase-admin/app");
const {FieldValue, getFirestore} = require("firebase-admin/firestore");

async function main() {
  const apply = process.argv.includes("--apply");
  if (getApps().length === 0) initializeApp();
  const db = getFirestore();
  const customers = await db.collection("Customers").get();
  const summary = {mode: apply ? "apply" : "dry-run", customers: customers.size,
    legacyReferences: 0, existing: 0, migrated: 0};
  for (const customer of customers.docs) {
    const favorites = [...new Set((customer.get("favorites") || []).map(String).filter(Boolean))];
    summary.legacyReferences += favorites.length;
    for (const eventId of favorites) {
      const ref = customer.ref.collection("SavedEvents").doc(eventId);
      const existing = await ref.get();
      if (existing.exists) { summary.existing += 1; continue; }
      if (apply) await ref.set({eventId, userId: customer.id,
        createdAt: FieldValue.serverTimestamp(), migratedFromFavorites: true});
      summary.migrated += 1;
    }
  }
  process.stdout.write(`${JSON.stringify(summary, null, 2)}\n`);
  if (!apply) process.stdout.write("Dry run only. This migration intentionally does not delete legacy arrays.\n");
}

main().catch((error) => { process.stderr.write(`${error.stack || error.message}\n`); process.exitCode = 1; });
