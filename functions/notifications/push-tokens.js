"use strict";
const crypto = require("node:crypto");
const {onCall, HttpsError} = require("firebase-functions/v2/https");
const tokenHash = (value) => crypto.createHash("sha256").update(String(value)).digest("hex");
const fail = (code, message, details) => { throw new HttpsError(code, message, details); };
function validated(request) {
  const uid = request.auth?.uid, data = request.data || {};
  if (!uid || request.auth.token?.firebase?.sign_in_provider === "anonymous") fail("unauthenticated", "Sign in to register notifications.");
  if (data.expectedUid !== uid) fail("permission-denied", "The account changed before notification registration.");
  if (typeof data.token !== "string" || !/^[A-Za-z0-9:_-]{10,4096}$/.test(data.token) ||
      typeof data.installationId !== "string" || !/^[A-Za-z0-9_-]{24,128}$/.test(data.installationId) ||
      !Number.isSafeInteger(data.generation) || data.generation < 1) fail("invalid-argument", "A valid token, installation and generation are required.");
  return {uid, token: data.token, hash: tokenHash(data.token), installation: tokenHash(data.installationId), generation: data.generation};
}
async function canDeliverPush(db, uid, token, transaction = null) {
  if (!uid || typeof token !== "string" || !token) return false;
  const read = (ref) => transaction ? transaction.get(ref) : ref.get();
  const hash = tokenHash(token);
  const [user, binding, deleting] = await Promise.all([
    read(db.collection("users").doc(uid)), read(db.collection("PushTokenBindings").doc(hash)),
    read(db.collection("account_deletion_jobs").doc(uid)),
  ]);
  if (deleting.exists || user.get("fcmToken") !== token || !binding.exists || binding.get("ownerUid") !== uid || binding.get("status") !== "active") return false;
  const installation = binding.get("installationHash");
  if (!/^[a-f0-9]{64}$/.test(installation || "")) return false;
  const state = await read(db.collection("PushInstallations").doc(installation));
  return state.exists && state.get("invalidated") !== true && state.get("ownerUid") === uid &&
    state.get("tokenHash") === hash && state.get("operation") === "register" && state.get("generation") === binding.get("generation");
}
function createPushTokenOperations(admin) {
  const db = admin.firestore();
  const stamp = () => admin.firestore.FieldValue.serverTimestamp();
  async function mutate(request, operation) {
    const input = validated(request);
    const {uid, token, hash, installation, generation} = input;
    const installationRef = db.collection("PushInstallations").doc(installation);
    const bindingRef = db.collection("PushTokenBindings").doc(hash);
    const userRef = db.collection("users").doc(uid);
    return db.runTransaction(async (tx) => {
      const [state, binding, user, deleting] = await Promise.all([
        tx.get(installationRef), tx.get(bindingRef), tx.get(userRef), tx.get(db.collection("account_deletion_jobs").doc(uid)),
      ]);
      if (deleting.exists) fail("failed-precondition", "Account deletion is in progress.");
      const previousGeneration = Number(state.get("generation") || 0);
      const identical = state.get("ownerUid") === uid && state.get("tokenHash") === hash && state.get("operation") === operation;
      if (operation === "revoke") {
        // A late revoke can only remove this exact account/install binding.
        // It never advances another account's generation or clears its token.
        if (!binding.exists || binding.get("ownerUid") !== uid || binding.get("installationHash") !== installation ||
            (state.exists && state.get("ownerUid") !== uid) || generation < previousGeneration ||
            (generation === previousGeneration && !identical)) return {revoked: false, stale: true, generation};
        tx.delete(bindingRef);
        tx.set(installationRef, {ownerUid: uid, tokenHash: hash, generation, operation: "revoke", invalidated: false, updatedAt: stamp()});
        if (user.get("fcmToken") === token) { const data = user.data(); delete data.fcmToken; tx.set(userRef, data); }
        return {revoked: true, generation};
      }
      if (state.get("invalidated") === true) fail("failed-precondition", "This installation must rotate its notification token.", {code: "installation-reset-required"});
      if (generation < previousGeneration || (generation === previousGeneration && !identical)) fail("failed-precondition", "A newer notification intent has already been applied.", {code: "stale-installation-generation"});
      if (generation === previousGeneration && identical) {
        if (binding.get("ownerUid") === uid && binding.get("installationHash") === installation && binding.get("generation") === generation && user.get("fcmToken") === token) return {registered: true, generation};
        fail("failed-precondition", "This token binding is no longer current.", {code: "installation-reset-required"});
      }
      const previousInstallationHash = binding.get("installationHash");
      const previousInstallationRef = previousInstallationHash && previousInstallationHash !== installation ? db.collection("PushInstallations").doc(previousInstallationHash) : null;
      const previousHashes = new Set([state.get("tokenHash"), user.get("fcmToken") ? tokenHash(user.get("fcmToken")) : null].filter((value) => value && value !== hash));
      const previousBindings = await Promise.all([...previousHashes].map((value) => tx.get(db.collection("PushTokenBindings").doc(value))));
      const previousOwners = new Set([state.get("ownerUid"), binding.get("ownerUid")].filter((value) => value && value !== uid));
      const previousUsers = await Promise.all([...previousOwners].map((owner) => tx.get(db.collection("users").doc(owner))));
      const previousInstallation = previousInstallationRef ? await tx.get(previousInstallationRef) : null;
      // Every read is complete before atomically transferring both owner fields.
      for (const previous of previousUsers) {
        const oldToken = previous.get("fcmToken");
        if (typeof oldToken === "string" && [hash, state.get("tokenHash")].includes(tokenHash(oldToken))) {
          const data = previous.data(); delete data.fcmToken; tx.set(previous.ref, data);
        }
      }
      for (const previous of previousBindings) if (previous.exists &&
          (previous.get("installationHash") === installation || previous.get("ownerUid") === uid)) tx.delete(previous.ref);
      if (previousInstallation?.exists && previousInstallation.get("tokenHash") === hash) tx.update(previousInstallationRef, {invalidated: true, updatedAt: stamp()});
      tx.set(bindingRef, {ownerUid: uid, installationHash: installation, generation, status: "active", updatedAt: stamp()});
      tx.set(installationRef, {ownerUid: uid, tokenHash: hash, generation, operation: "register", invalidated: false, updatedAt: stamp()});
      tx.set(userRef, {...user.data(), fcmToken: token});
      return {registered: true, generation};
    });
  }
  const options = {region: "us-central1", enforceAppCheck: process.env.FUNCTIONS_EMULATOR !== "true", maxInstances: 20};
  return {registerPushTokenV1: onCall(options, (request) => mutate(request, "register")),
    revokePushTokenV1: onCall(options, (request) => mutate(request, "revoke"))};
}
async function cleanupPushTokenAccountData(db, uid, counts) {
  for (const collection of ["PushTokenBindings", "PushInstallations"]) {
    let page = await db.collection(collection).where("ownerUid", "==", uid).limit(100).get();
    while (!page.empty) {
      await counts.lease.transaction(async (tx) => {
        const current = await Promise.all(page.docs.map((doc) => tx.get(doc.ref)));
        for (const doc of current) if (doc.exists && doc.get("ownerUid") === uid) tx.delete(doc.ref);
        tx.set(counts.job, {lastCompletedItem: `${collection}:owned-bindings`}, {merge: true});
      });
      page = await db.collection(collection).where("ownerUid", "==", uid).limit(100).get();
    }
  }
}
module.exports = {createPushTokenOperations, canDeliverPush, cleanupPushTokenAccountData, tokenHash};
