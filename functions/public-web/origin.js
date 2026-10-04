"use strict";

function publicOrigin(env = process.env) {
  const project = env.GCLOUD_PROJECT || env.GOOGLE_CLOUD_PROJECT;
  if (env.GCLOUD_PROJECT && env.GOOGLE_CLOUD_PROJECT && env.GCLOUD_PROJECT !== env.GOOGLE_CLOUD_PROJECT) {
    throw new Error("Public links require matching Firebase project configuration.");
  }
  if (project === "orgami-66nxok") return "https://attendus.app";
  if (project === "attendus-staging") return "https://attendus-staging.web.app";
  if (project === "demo-attendus-admin" && env.FUNCTIONS_EMULATOR === "true") {
    const url = new URL(env.ATTENDUS_EMULATOR_PUBLIC_ORIGIN || "http://127.0.0.1:4173");
    if (url.protocol !== "http:" || !["127.0.0.1", "localhost", "[::1]"].includes(url.hostname) ||
        url.username || url.password || url.pathname !== "/" || url.search || url.hash) {
      throw new Error("Emulator public links require a loopback HTTP origin.");
    }
    return url.origin;
  }
  throw new Error("Public links require an explicit supported Firebase project.");
}

module.exports = {publicOrigin};
