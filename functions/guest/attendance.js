"use strict";

const crypto = require("node:crypto");
const {onCall, HttpsError} = require("firebase-functions/v2/https");
const {Timestamp, FieldValue} = require("firebase-admin/firestore");

const METHODS = new Set(["qr_code", "manual_code", "geofence"]);
const NAME_PATTERN = /^[\p{L}\p{M}][\p{L}\p{M}\s.'-]*$/u;
const WINDOW_MS = 60 * 1000;
const ATTEMPT_LIMIT = 8;

function finite(value) {
  return typeof value === "number" && Number.isFinite(value);
}

function distanceMeters(lat1, lon1, lat2, lon2) {
  const radians = (degrees) => degrees * Math.PI / 180;
  const dLat = radians(lat2 - lat1);
  const dLon = radians(lon2 - lon1);
  const a = Math.sin(dLat / 2) ** 2 +
    Math.cos(radians(lat1)) * Math.cos(radians(lat2)) *
    Math.sin(dLon / 2) ** 2;
  return 6371000 * 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));
}

async function enforceRateLimit(db, uid, nowMs = Date.now()) {
  const key = crypto.createHash("sha256").update(uid).digest("hex").slice(0, 32);
  const ref = db.collection("service_rate_limits").doc(`guest_checkin_${key}`);
  let allowed = false;
  await db.runTransaction(async (transaction) => {
    const snapshot = await transaction.get(ref);
    const existing = snapshot.exists ? snapshot.data() : {};
    const startedAt = Number(existing.windowStartedAtMs || 0);
    const inWindow = nowMs - startedAt < WINDOW_MS;
    const count = inWindow ? Number(existing.count || 0) : 0;
    if (count >= ATTEMPT_LIMIT) return;
    allowed = true;
    transaction.set(ref, {
      service: "guest_checkin",
      count: count + 1,
      windowStartedAtMs: inWindow ? startedAt : nowMs,
      expiresAt: Timestamp.fromMillis(nowMs + (2 * WINDOW_MS)),
    }, {merge: true});
  });
  if (!allowed) {
    throw new HttpsError("resource-exhausted", "Too many check-in attempts.");
  }
}

function validateInput(data) {
  const eventId = typeof data?.eventId === "string" ? data.eventId.trim() : "";
  const method = typeof data?.method === "string" ? data.method : "";
  const fullName = typeof data?.fullName === "string" ? data.fullName.trim() : "";
  const answers = Array.isArray(data?.answers) ? data.answers : [];
  if (!eventId || eventId.length > 200) {
    throw new HttpsError("invalid-argument", "A valid event code is required.");
  }
  if (!METHODS.has(method)) {
    throw new HttpsError("invalid-argument", "Unsupported check-in method.");
  }
  if (fullName.length < 2 || fullName.length > 100 || !NAME_PATTERN.test(fullName)) {
    throw new HttpsError("invalid-argument", "Enter a valid full name.");
  }
  if (answers.length > 25 || answers.some((answer) =>
    typeof answer !== "string" || answer.length > 500)) {
    throw new HttpsError("invalid-argument", "Invalid event-question answers.");
  }
  return {eventId, method, fullName, answers};
}

async function validateQuestions(db, eventId, answers) {
  const snapshot = await db.collection("Events").doc(eventId)
      .collection("EventQuestions").get();
  const supplied = new Map(answers.map((value) => {
    const parts = value.split("--ans--");
    return [parts.shift(), parts.join("--ans--").trim()];
  }));
  for (const doc of snapshot.docs) {
    const question = doc.data();
    const title = String(question.questionTitle || "");
    if (question.required === true && !supplied.get(title)) {
      throw new HttpsError(
          "failed-precondition",
          "Answer all required event questions before checking in.",
      );
    }
  }
}

function createSubmitGuestAttendance(adminSdk) {
  const db = adminSdk.firestore();
  return onCall({
    region: "us-central1",
    enforceAppCheck: process.env.FUNCTIONS_EMULATOR !== "true",
    maxInstances: 20,
  }, async (request) => {
    const uid = request.auth?.uid;
    const provider = request.auth?.token?.firebase?.sign_in_provider;
    if (!uid || provider !== "anonymous") {
      throw new HttpsError("unauthenticated", "An anonymous guest session is required.");
    }
    const input = validateInput(request.data);
    await enforceRateLimit(db, uid);

    const eventRef = db.collection("Events").doc(input.eventId);
    const eventSnapshot = await eventRef.get();
    if (!eventSnapshot.exists) throw new HttpsError("not-found", "Event not found.");
    const event = eventSnapshot.data();
    if (event.private === true) {
      throw new HttpsError("permission-denied", "Private events require an account.");
    }
    const enabledMethods = Array.isArray(event.signInMethods) && event.signInMethods.length ?
      event.signInMethods : ["qr_code", "manual_code"];
    if (!enabledMethods.includes(input.method)) {
      throw new HttpsError("permission-denied", "This check-in method is not enabled.");
    }

    if (input.method === "geofence") {
      const {latitude, longitude, accuracyMeters} = request.data;
      if (!finite(latitude) || !finite(longitude) || !finite(accuracyMeters) ||
          latitude < -90 || latitude > 90 || longitude < -180 || longitude > 180 ||
          accuracyMeters < 0 || accuracyMeters > 500) {
        throw new HttpsError("invalid-argument", "Valid location data is required.");
      }
      const eventLat = Number(event.latitude);
      const eventLon = Number(event.longitude);
      const radius = Number(event.radius);
      if (!finite(eventLat) || !finite(eventLon) || !finite(radius) || radius <= 0) {
        throw new HttpsError("failed-precondition", "This event has no valid geofence.");
      }
      const allowance = Math.min(100, accuracyMeters);
      if (distanceMeters(latitude, longitude, eventLat, eventLon) > radius + allowance) {
        throw new HttpsError("failed-precondition", "You are outside the event check-in area.");
      }
    }

    await validateQuestions(db, input.eventId, input.answers);
    const id = crypto.createHash("sha256")
        .update(`${input.eventId}:${uid}`).digest("hex").slice(0, 40);
    const attendanceRef = db.collection("Attendance").doc(`guest_${id}`);
    await db.runTransaction(async (transaction) => {
      const existing = await transaction.get(attendanceRef);
      if (existing.exists) {
        throw new HttpsError("already-exists", "Guest is already checked in.");
      }
      transaction.create(attendanceRef, {
        id: attendanceRef.id,
        eventId: input.eventId,
        userName: input.fullName,
        customerUid: "without_login",
        guestSessionId: uid,
        attendanceDateTime: FieldValue.serverTimestamp(),
        entryTimestamp: FieldValue.serverTimestamp(),
        dwellStatus: "active",
        answers: input.answers,
        isAnonymous: false,
        signInMethod: input.method,
        source: "guest_callable_v1",
      });
    });
    return {attendanceId: attendanceRef.id};
  });
}

module.exports = {
  createSubmitGuestAttendance,
  distanceMeters,
  validateInput,
};
