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
  const mode = value("--mode");
  if (!allowedProjects.has(projectId)) throw new Error("Use an explicitly approved project.");
  if (!["disabled", "pages", "registration", "paid"].includes(mode)) {
    throw new Error("Use --mode disabled|pages|registration|paid.");
  }
  if (getApps().length === 0) initializeApp({projectId});
  const ref = getFirestore().collection("AppConfig").doc("publicWeb");
  const current = (await ref.get()).data() || {};
  const appCheckSiteKey = value("--app-check-site-key") ||
    String(current.appCheckSiteKey || "");
  const stripePublishableKey = value("--stripe-publishable-key") ||
    String(current.stripePublishableKey || "");
  const pages = mode !== "disabled";
  const registration = ["registration", "paid"].includes(mode);
  const paid = mode === "paid";
  if (registration && !appCheckSiteKey) {
    throw new Error("Registration requires --app-check-site-key or an existing value.");
  }
  if (paid && !/^pk_live_[A-Za-z0-9]+$/.test(stripePublishableKey)) {
    throw new Error("Paid mode requires a live Stripe publishable key.");
  }
  await ref.set({
    publicPagesEnabled: pages,
    inlineRegistrationEnabled: registration,
    paidTicketCheckoutEnabled: paid,
    appCheckSiteKey,
    stripePublishableKey,
    updatedAt: FieldValue.serverTimestamp(),
    rolloutMode: mode,
  }, {merge: true});
  process.stdout.write(`${JSON.stringify({projectId, mode, pages, registration,
    paid, appCheckConfigured: Boolean(appCheckSiteKey),
    stripePublishableConfigured: Boolean(stripePublishableKey)})}\n`);
}

main().catch((error) => {
  process.stderr.write(`${error.stack || error.message}\n`);
  process.exitCode = 1;
});
