"use strict";
const {HttpsError, onCall} = require("firebase-functions/v2/https");
const {requireProfileCaller, limitProfileReads, publicProfile, validProfileUid} = require("./access");
const OPTIONS = {region: "us-central1", maxInstances: 20, timeoutSeconds: 20,
  enforceAppCheck: process.env.FUNCTIONS_EMULATOR !== "true"};

function profileIds(value) {
  if (!Array.isArray(value) || !value.length || value.length > 50 ||
      value.some((uid) => !validProfileUid(uid))) {
    throw new HttpsError("invalid-argument", "Choose between one and 50 valid profiles.");
  }
  return [...new Set(value)];
}
function searchInput(data = {}) {
  if (typeof data.query !== "string" || data.query.length > 80) {
    throw new HttpsError("invalid-argument", "Enter a name or username of up to 80 characters.");
  }
  const query = data.query.trim().replace(/^@/, "");
  if (query.includes("@")) throw new HttpsError("invalid-argument", "Search by name or username.");
  const limit = data.limit === undefined ? 20 : data.limit;
  if (!Number.isSafeInteger(limit) || limit < 1 || limit > 50) throw new HttpsError("invalid-argument", "Choose a limit between one and 50.");
  return {query, limit};
}
function normalizedUsername(value) {
  const username = typeof value === "string" ? value.trim().toLowerCase() : "";
  if (!/^[a-z0-9_]{3,50}$/.test(username)) throw new HttpsError("invalid-argument", "Use 3 to 50 letters, numbers or underscores for a username.");
  return username;
}

async function readProfiles(db, actorUid, ids, discoverableOnly = false) {
  return db.runTransaction(async (tx) => {
    const actorGuard = await tx.get(db.collection("account_deletion_jobs").doc(actorUid));
    if (actorGuard.exists) throw new HttpsError("failed-precondition", "Account deletion is in progress.");
    const profiles = [];
    for (const uid of ids) {
      const [profile, guard] = await Promise.all([
        tx.get(db.collection("Customers").doc(uid)), tx.get(db.collection("account_deletion_jobs").doc(uid)),
      ]);
      if (profile.exists && !guard.exists && profile.get("isDeleted") !== true &&
          (!discoverableOnly || profile.get("isDiscoverable") === true)) profiles.push(publicProfile(profile));
    }
    return profiles;
  });
}

function createPublicProfileHandlers(admin) {
  const db = admin.firestore();
  async function get(request) {
    const uid = requireProfileCaller(request), ids = profileIds(request.data?.userIds);
    await limitProfileReads(db, uid, "read");
    return {profiles: await readProfiles(db, uid, ids)};
  }
  async function search(request) {
    const uid = requireProfileCaller(request), input = searchInput(request.data);
    await limitProfileReads(db, uid, "search", 60);
    const root = db.collection("Customers");
    let queries;
    if (!input.query) queries = [root.where("isDiscoverable", "==", true).limit(input.limit)];
    else {
      const lower = input.query.toLowerCase();
      const namePrefixes = [...new Set([input.query, lower, input.query.split(/\s+/).map((word) => word[0]?.toUpperCase() + word.slice(1).toLowerCase()).join(" ")])];
      queries = namePrefixes.map((prefix) => root.where("isDiscoverable", "==", true)
          .where("name", ">=", prefix).where("name", "<=", `${prefix}\uf8ff`).limit(input.limit));
      queries.push(root.where("isDiscoverable", "==", true)
          .where("username", ">=", lower).where("username", "<=", `${lower}\uf8ff`).limit(input.limit));
    }
    const candidates = [...new Set((await Promise.all(queries.map((query) => query.get()))).flatMap((result) => result.docs.map((doc) => doc.id)))];
    // At most four bounded queries. Re-read current privacy/deletion state rather
    // than returning the earlier search snapshots or an unbounded fallback.
    const profiles = await readProfiles(db, uid, candidates, true);
    profiles.sort((a, b) => a.name.localeCompare(b.name) || a.uid.localeCompare(b.uid));
    return {profiles: profiles.slice(0, input.limit)};
  }
  async function username(request) {
    const uid = requireProfileCaller(request), username = normalizedUsername(request.data?.username);
    await limitProfileReads(db, uid, "username", 90);
    const result = await db.collection("Customers").where("username", "==", username).limit(2).get();
    // Availability is advisory; it does not disclose a private user's UID or
    // promise an atomic reservation between this check and profile creation.
    return {username, available: !result.docs.some((doc) => doc.id !== uid)};
  }
  return {get, search, username};
}
function createPublicProfileOperations(admin) {
  const handlers = createPublicProfileHandlers(admin);
  return {getPublicProfilesV1: onCall(OPTIONS, handlers.get), searchPublicProfilesV1: onCall(OPTIONS, handlers.search),
    checkUsernameAvailabilityV1: onCall(OPTIONS, handlers.username)};
}
module.exports = {createPublicProfileHandlers, createPublicProfileOperations, profileIds, searchInput, normalizedUsername, readProfiles};
