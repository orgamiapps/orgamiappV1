"use strict";

const crypto = require("node:crypto");
const {HttpsError} = require("firebase-functions/v2/https");

function requireString(value, label, {min = 1, max = 500} = {}) {
  const normalized = typeof value === "string" ? value.trim() : "";
  if (normalized.length < min || normalized.length > max) {
    throw new HttpsError(
        "invalid-argument",
        `${label} must be between ${min} and ${max} characters.`,
    );
  }
  return normalized;
}

function requireConfirmedOperation(data) {
  if (data?.confirmation !== true) {
    throw new HttpsError(
        "failed-precondition",
        "Explicit confirmation is required for this operation.",
    );
  }
  return {
    reason: requireString(data.reason, "Reason", {min: 10, max: 500}),
    idempotencyKey: requireString(
        data.idempotencyKey,
        "Idempotency key",
        {min: 8, max: 128},
    ),
  };
}

function requireStringArray(value, label, {max, pattern} = {}) {
  if (!Array.isArray(value) || value.length === 0 || value.length > max) {
    throw new HttpsError(
        "invalid-argument",
        `${label} must contain between 1 and ${max} entries.`,
    );
  }
  const normalized = [...new Set(value.map((entry) =>
    typeof entry === "string" ? entry.trim() : ""))];
  if (normalized.some((entry) => !entry || (pattern && !pattern.test(entry)))) {
    throw new HttpsError("invalid-argument", `${label} contains an invalid entry.`);
  }
  return normalized;
}

function requireDataMap(value) {
  if (value === undefined) return {};
  if (!value || Array.isArray(value) || typeof value !== "object") {
    throw new HttpsError("invalid-argument", "Notification data must be an object.");
  }
  const entries = Object.entries(value);
  if (entries.length > 20) {
    throw new HttpsError("invalid-argument", "Notification data has too many fields.");
  }
  return Object.fromEntries(entries.map(([key, entry]) => {
    if (!/^[A-Za-z0-9_.-]{1,64}$/.test(key) ||
        !["string", "number", "boolean"].includes(typeof entry)) {
      throw new HttpsError(
          "invalid-argument",
          "Notification data contains an unsupported field.",
      );
    }
    return [key, String(entry).slice(0, 500)];
  }));
}

async function requireAdminCallable(req, db, allowedRoles) {
  const uid = req.auth?.uid;
  const provider = req.auth?.token?.firebase?.sign_in_provider;
  if (!uid || provider === "anonymous") {
    throw new HttpsError("unauthenticated", "A signed-in account is required.");
  }
  if (!req.app) {
    throw new HttpsError("failed-precondition", "App Check verification is required.");
  }
  if (req.auth?.token?.admin !== true) {
    throw new HttpsError("permission-denied", "Administrator access is required.");
  }
  const roleSnap = await db.collection("admin_roles").doc(uid).get();
  const roleData = roleSnap.data() || {};
  const roles = Array.isArray(roleData.roles) ? roleData.roles : [];
  if (!roleSnap.exists || roleData.active !== true ||
      !roles.some((role) => allowedRoles.includes(role))) {
    throw new HttpsError("permission-denied", "An authorized administrator role is required.");
  }
  return {uid, roles};
}

async function enforceRateLimit(db, {uid, operation, limit, windowSeconds = 60}) {
  const window = Math.floor(Date.now() / (windowSeconds * 1000));
  const ref = db.collection("admin_rate_limits").doc(`${uid}_${operation}_${window}`);
  await db.runTransaction(async (transaction) => {
    const snap = await transaction.get(ref);
    const count = Number(snap.data()?.count || 0);
    if (count >= limit) {
      throw new HttpsError(
          "resource-exhausted",
          "This administrative action has reached its rate limit.",
      );
    }
    transaction.set(ref, {
      uid,
      operation,
      window,
      count: count + 1,
      expiresAt: new Date((window + 2) * windowSeconds * 1000),
    }, {merge: true});
  });
}

function idempotencyDocumentId(operation, uid, key) {
  return crypto.createHash("sha256").update(`${operation}:${uid}:${key}`).digest("hex");
}

async function reserveIdempotencyKey(db, {operation, uid, key}) {
  const ref = db.collection("admin_idempotency")
      .doc(idempotencyDocumentId(operation, uid, key));
  return db.runTransaction(async (transaction) => {
    const snap = await transaction.get(ref);
    if (snap.exists) {
      const data = snap.data() || {};
      if (data.status === "completed") return {ref, result: data.result || {}};
      throw new HttpsError("aborted", "This operation is already in progress.");
    }
    transaction.create(ref, {
      operation,
      actorUid: uid,
      status: "in_progress",
      createdAt: new Date(),
    });
    return {ref, result: null};
  });
}

module.exports = {
  enforceRateLimit,
  requireAdminCallable,
  requireConfirmedOperation,
  requireDataMap,
  requireString,
  requireStringArray,
  reserveIdempotencyKey,
};
