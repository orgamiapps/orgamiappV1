"use strict";

const {onCall, HttpsError} = require("firebase-functions/v2/https");
const {requireEvent, capabilities} = require("../events/access");
const {requireProfileCaller, limitProfileReads, publicProfile, validProfileUid} = require("./access");

function normalizedStaffEmail(value) {
  if (typeof value !== "string" || value.length > 254) throw new HttpsError("invalid-argument", "Enter a valid email address.");
  const email = value.trim().toLowerCase();
  const parts = email.split("@");
  if (parts.length !== 2 || parts[0].length > 64 ||
      !/^[a-z0-9!#$%&'*+/=?^_`{|}~-]+(?:\.[a-z0-9!#$%&'*+/=?^_`{|}~-]+)*$/.test(parts[0]) ||
      !parts[1].includes(".") || parts[1].split(".").some((label) => !/^[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?$/.test(label))) {
    throw new HttpsError("invalid-argument", "Enter a valid email address.");
  }
  return email;
}

function staffProfile(snapshot) {
  const {uid, name, username, profilePictureUrl} = publicProfile(snapshot);
  return {uid, name, username, profilePictureUrl};
}

function createEventStaffLookupHandler(db, auth, {rateLimit = limitProfileReads} = {}) {
  return async (request) => {
    const uid = requireProfileCaller(request);
    const email = normalizedStaffEmail(request.data?.email);
    const access = await requireEvent(db, request, "manageEvent");
    await rateLimit(db, uid, "staff", 10);
    let account;
    try {
      // The Auth index is unique and authoritative. Editable Customers.email
      // values must never select the account that receives an event role.
      account = await auth.getUserByEmail(email);
    } catch (error) {
      if (error?.code !== "auth/user-not-found") throw new HttpsError("unavailable", "Account lookup is temporarily unavailable.");
    }
    const validAccount = account && validProfileUid(account.uid) &&
      typeof account.email === "string" && account.email.toLowerCase() === email && account.emailVerified === true && account.disabled !== true &&
      account.providerData?.some((provider) => provider.providerId && provider.providerId !== "anonymous");
    // All target availability states use the same response, including deletion.
    return db.runTransaction(async (transaction) => {
      const event = await transaction.get(access.document.ref);
      if (!event.exists || !(await capabilities(db, uid, event.data(), transaction)).manageEvent) {
        throw new HttpsError("permission-denied", "Event access changed.");
      }
      if (!validAccount) return {profile: null};
      const profile = await transaction.get(db.collection("Customers").doc(account.uid));
      const deleting = await transaction.get(db.collection("account_deletion_jobs").doc(account.uid));
      return {profile: profile.exists && profile.get("isDeleted") !== true && !deleting.exists ? staffProfile(profile) : null};
    });
  };
}

function createLookupEventStaffAccountV1(admin) {
  return onCall({region: "us-central1", enforceAppCheck: process.env.FUNCTIONS_EMULATOR !== "true",
    timeoutSeconds: 30, maxInstances: 20}, createEventStaffLookupHandler(admin.firestore(), admin.auth()));
}

module.exports = {createLookupEventStaffAccountV1, createEventStaffLookupHandler, normalizedStaffEmail};
