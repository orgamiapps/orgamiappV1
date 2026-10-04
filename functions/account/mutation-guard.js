"use strict";
const {HttpsError} = require("firebase-functions/v2/https");

async function requireActiveAccounts(db, transaction, ...uids) {
  for (const uid of new Set(uids.filter((value) => typeof value === "string" && value.length))) {
    if ((await transaction.get(db.collection("account_deletion_jobs").doc(uid))).exists) {
      throw new HttpsError("failed-precondition", "Account deletion is in progress.");
    }
  }
}

async function readGuestRegistration(db, transaction, {registrationId, guestId, eventId, actorUid, requireOwnership = false}) {
  const registration = await transaction.get(db.collection("RegisterAttendance").doc(registrationId));
  if (!registration.exists || registration.get("guestId") !== guestId || (eventId && registration.get("eventId") !== eventId)) throw new HttpsError("not-found", "Registration not found.");
  const guest = await transaction.get(db.collection("GuestAttendees").doc(guestId));
  if (!guest.exists || (requireOwnership && (registration.get("customerUid") !== actorUid || guest.get("ownerUid") !== actorUid))) {
    throw new HttpsError("not-found", "Registration not found.");
  }
  await requireActiveAccounts(db, transaction, actorUid, registration.get("customerUid"), registration.get("userId"),
      guest.get("ownerUid"), guest.get("claimedByUid"));
  return {registration, guest};
}

module.exports = {requireActiveAccounts, readGuestRegistration};
