"use strict";

const {HttpsError} = require("firebase-functions/v2/https");

async function capabilities(db, uid, event, transaction = null) {
  const read = (ref) => transaction ? transaction.get(ref) : ref.get();
  if (!uid || !event || (await read(db.collection("account_deletion_jobs").doc(uid))).exists) {
    return {manageEvent: false, operateDoor: false};
  }
  let manageEvent = Boolean(uid && (event.customerUid === uid ||
    (event.coHosts || []).includes(uid)));
  if (!manageEvent && uid && event.organizationId) {
    const organization = db.collection("Organizations").doc(event.organizationId);
    const [root, member] = await Promise.all([read(organization),
      read(organization.collection("Members").doc(uid))]);
    manageEvent = root.get("createdBy") === uid ||
      (member.exists && member.get("status") === "approved" &&
      ["owner", "admin"].includes(String(member.get("role") || "").toLowerCase()));
  }
  return {manageEvent, operateDoor: manageEvent || Boolean(uid &&
    (event.checkInStaff || []).includes(uid))};
}

function actor(request) {
  if (!request.auth?.uid || request.auth.token?.firebase?.sign_in_provider === "anonymous") {
    throw new HttpsError("unauthenticated", "Sign in to manage an event.");
  }
  return request.auth.uid;
}

async function requireEvent(db, request, capability = "manageEvent") {
  const uid = actor(request);
  if ((await db.collection("account_deletion_jobs").doc(uid).get()).exists) {
    throw new HttpsError("failed-precondition", "Account deletion is in progress.");
  }
  const eventId = String(request.data?.eventId || "");
  if (!/^[A-Za-z0-9._:-]{1,500}$/.test(eventId)) {
    throw new HttpsError("invalid-argument", "A valid event is required.");
  }
  const document = await db.collection("Events").doc(eventId).get();
  if (!document.exists) throw new HttpsError("not-found", "Event not found.");
  const permissions = await capabilities(db, uid, document.data());
  if (!permissions[capability]) throw new HttpsError("permission-denied", "Event access is required.");
  return {uid, eventId, document, event: document.data(), permissions};
}

module.exports = {capabilities, actor, requireEvent};
