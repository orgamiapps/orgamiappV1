"use strict";
const fs = require("node:fs");
const path = require("node:path");

function associations(teamId, fingerprints, applicationId = "com.stormdeve.orgami") {
  if (!/^[A-Za-z][A-Za-z0-9_]*(?:\.[A-Za-z][A-Za-z0-9_]*)+$/.test(applicationId)) throw Error("Verified application identifier required.");
  if (!/^[A-Z0-9]{10}$/.test(teamId || "")) throw Error("A verified Apple Team ID is required.");
  const certificates = String(fingerprints || "").split(",").map((s) => s.trim().toUpperCase()).filter(Boolean);
  if (!certificates.length || certificates.some((s) => !/^(?:[A-F0-9]{2}:){31}[A-F0-9]{2}$/.test(s))) throw Error("Verified Play App Signing SHA-256 fingerprints are required.");
  return {
    "apple-app-site-association": {applinks: {apps: [], details: [{appID: `${teamId}.${applicationId}`, paths: ["/event/*", "/community/*", "/app/event/*", "/app/community/*"]}]}},
    "assetlinks.json": [{relation: ["delegate_permission/common.handle_all_urls"], target: {namespace: "android_app", package_name: applicationId, sha256_cert_fingerprints: certificates}}],
  };
}
if (require.main === module) {
  const values = associations(process.env.ATTENDUS_APPLE_TEAM_ID, process.env.ATTENDUS_PLAY_SIGNING_SHA256, process.env.ATTENDUS_APPLICATION_ID);
  const directory = path.resolve(process.argv[2] || "build/web", ".well-known");
  fs.mkdirSync(directory, {recursive: true});
  for (const [name, value] of Object.entries(values)) fs.writeFileSync(path.join(directory, name), `${JSON.stringify(value)}\n`);
  process.stdout.write("Prepared mobile association assets; deployed identity verification remains required.\n");
}
module.exports = {associations};
