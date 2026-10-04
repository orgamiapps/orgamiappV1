"use strict";
const {HttpsError} = require("firebase-functions/v2/https");

function validProfileUid(value) {
  return typeof value === "string" && value.length > 0 && value.length <= 128 &&
    [...value].every((character) => character !== "/" && character.charCodeAt(0) >= 32 && character.charCodeAt(0) !== 127);
}

function requireProfileCaller(request) {
  const uid = request.auth?.uid;
  if (!uid || request.auth.token?.firebase?.sign_in_provider === "anonymous") {
    throw new HttpsError("unauthenticated", "Sign in to view profiles.");
  }
  if (!request.app && !(process.env.FUNCTIONS_EMULATOR === "true" && process.env.GCLOUD_PROJECT === "demo-attendus-admin")) {
    throw new HttpsError("failed-precondition", "App Check verification is required.");
  }
  return uid;
}

async function limitProfileReads(db, uid, operation, limit = 120, now = Date.now()) {
  if (!["read", "search", "username", "staff"].includes(operation)) throw Error("Unknown profile operation");
  const ref = db.collection("ProfileReadLimits").doc(uid);
  const window = Math.floor(now / 60000);
  await db.runTransaction(async (tx) => {
    const [guard, snapshot] = await Promise.all([
      tx.get(db.collection("account_deletion_jobs").doc(uid)), tx.get(ref),
    ]);
    if (guard.exists) throw new HttpsError("failed-precondition", "Account deletion is in progress.");
    const buckets = snapshot.get("buckets") || {};
    const current = buckets[operation];
    const count = current?.window === window && Number.isSafeInteger(current.count) ? current.count : 0;
    if (count >= limit) throw new HttpsError("resource-exhausted", "Profile requests are temporarily limited. Try again shortly.");
    tx.set(ref, {buckets: {...buckets, [operation]: {window, count: count + 1}},
      updatedAt: new Date(now), expiresAt: new Date((window + 2) * 60000)});
  });
}

function bounded(value, max) {
  return typeof value === "string" ? value.trim().slice(0, max) : "";
}
function imageUrl(value) {
  const result = bounded(value, 2048);
  try {
    const parsed = new URL(result);
    return parsed.protocol === "https:" && !parsed.username && !parsed.password ? result : null;
  } catch (_) { return null; }
}
function publicProfile(snapshot) {
  const data = snapshot.data() || {};
  return {uid: snapshot.id, name: bounded(data.name, 160) || "Attendus member",
    username: bounded(data.username, 50) || null,
    profilePictureUrl: imageUrl(data.profilePictureUrl), bannerUrl: imageUrl(data.bannerUrl),
    bio: bounded(data.bio, 1000) || null, isDiscoverable: data.isDiscoverable === true};
}

module.exports = {requireProfileCaller, limitProfileReads, publicProfile, validProfileUid};
