#!/usr/bin/env node
"use strict";

const {applicationDefault, initializeApp} = require("firebase-admin/app");
const {getAuth} = require("firebase-admin/auth");
const {FieldValue, getFirestore} = require("firebase-admin/firestore");

function arg(name) {
  const index = process.argv.indexOf(`--${name}`); return index >= 0 ? process.argv[index + 1] : null;
}

async function main() {
  const projectId = arg("project");
  const email = arg("email");
  const confirm = arg("confirm");
  if (!projectId || !email || confirm !== `BOOTSTRAP:${email}`) {
    throw new Error("Usage: node admin/bootstrap-super-admin.js --project PROJECT_ID --email EMAIL --confirm \"BOOTSTRAP:EMAIL\"");
  }
  initializeApp({projectId, credential: applicationDefault()});
  const auth = getAuth();
  const user = await auth.getUserByEmail(email);
  const claims = user.customClaims || {};
  await auth.setCustomUserClaims(user.uid, {...claims, admin: true});
  const db = getFirestore();
  await db.collection("admin_roles").doc(user.uid).set({roles: ["super_admin"], active: true, updatedBy: "bootstrap-cli", updatedAt: FieldValue.serverTimestamp()});
  await db.collection("admin_audit_logs").doc().create({actorUid: "bootstrap-cli", actorEmail: null, actorRoles: ["bootstrap"], action: "admin.bootstrap", targetType: "account", targetId: user.uid, reason: "Explicit first-super-admin bootstrap", requestId: `bootstrap-${Date.now()}`, before: null, after: {roles: ["super_admin"], active: true}, metadata: {projectId}, createdAt: FieldValue.serverTimestamp()});
  console.log(`Bootstrapped super_admin for ${email} (${user.uid}) in ${projectId}. Re-authentication is required.`);
}

if (require.main === module) {
  main().catch((error) => {
    console.error(error.message); process.exitCode = 1;
  });
}
module.exports = {main};
