"use strict";

const COLLECTION = "FaceEnrollments";
const DELETE_CONFIRMATION = "DELETE_FACE_ENROLLMENTS";
const MAX_BATCH_SIZE = 400;

function parseNotBefore(value) {
  const parsed = new Date(`${value}T00:00:00.000Z`);
  if (!/^\d{4}-\d{2}-\d{2}$/.test(value) || Number.isNaN(parsed.getTime())) {
    throw new Error("A valid --not-before=YYYY-MM-DD date is required.");
  }
  return parsed;
}

function assertDeletionAuthorized({
  confirmation,
  backupReference,
  notBefore,
  now = new Date(),
}) {
  if (confirmation !== DELETE_CONFIRMATION) {
    throw new Error(`Deletion requires --confirm=${DELETE_CONFIRMATION}.`);
  }
  if (typeof backupReference !== "string" || backupReference.trim().length < 8) {
    throw new Error("A verified --backup-reference is required.");
  }
  const earliest = parseNotBefore(notBefore);
  if (now.getTime() < earliest.getTime()) {
    throw new Error(`Deletion is blocked until ${notBefore} UTC.`);
  }
  return {
    backupReference: backupReference.trim(),
    notBefore,
  };
}

async function inventoryFaceEnrollments(db) {
  const snapshot = await db.collection(COLLECTION)
      .select("userId", "eventId", "enrolledAt")
      .get();
  const owners = new Set();
  const events = new Set();
  let missingOwnerCount = 0;
  let missingEventCount = 0;
  let missingEnrollmentDateCount = 0;
  let earliestEnrollment = null;
  let latestEnrollment = null;

  for (const document of snapshot.docs) {
    const data = document.data();
    if (typeof data.userId === "string" && data.userId) owners.add(data.userId);
    else missingOwnerCount += 1;
    if (typeof data.eventId === "string" && data.eventId) events.add(data.eventId);
    else missingEventCount += 1;

    const date = data.enrolledAt?.toDate?.();
    if (!(date instanceof Date) || Number.isNaN(date.getTime())) {
      missingEnrollmentDateCount += 1;
      continue;
    }
    if (earliestEnrollment === null || date < earliestEnrollment) {
      earliestEnrollment = date;
    }
    if (latestEnrollment === null || date > latestEnrollment) {
      latestEnrollment = date;
    }
  }

  return {
    collection: COLLECTION,
    documentCount: snapshot.size,
    distinctOwnerCount: owners.size,
    distinctEventCount: events.size,
    missingOwnerCount,
    missingEventCount,
    missingEnrollmentDateCount,
    earliestEnrollment: earliestEnrollment?.toISOString() || null,
    latestEnrollment: latestEnrollment?.toISOString() || null,
  };
}

async function deleteFaceEnrollments(db, options) {
  const authorization = assertDeletionAuthorized(options);
  const before = await inventoryFaceEnrollments(db);
  let deletedCount = 0;
  let hasMore = true;

  while (hasMore) {
    const snapshot = await db.collection(COLLECTION)
        .orderBy("__name__")
        .limit(MAX_BATCH_SIZE)
        .get();
    if (snapshot.empty) {
      hasMore = false;
      continue;
    }

    const batch = db.batch();
    for (const document of snapshot.docs) batch.delete(document.ref);
    await batch.commit();
    deletedCount += snapshot.size;
  }

  const after = await inventoryFaceEnrollments(db);
  if (after.documentCount !== 0) {
    throw new Error(
        `Biometric deletion incomplete: ${after.documentCount} documents remain.`,
    );
  }

  const result = {
    collection: COLLECTION,
    deletedCount,
    beforeCount: before.documentCount,
    afterCount: after.documentCount,
    backupReference: authorization.backupReference,
    notBefore: authorization.notBefore,
  };
  await db.collection("admin_audit_logs").add({
    action: "biometrics.retention.delete",
    targetType: "collection",
    targetId: COLLECTION,
    ...result,
    requestedBy: options.requestedBy || "retention-cli",
    createdAt: options.createdAt || new Date(),
  });
  return result;
}

module.exports = {
  COLLECTION,
  DELETE_CONFIRMATION,
  MAX_BATCH_SIZE,
  assertDeletionAuthorized,
  deleteFaceEnrollments,
  inventoryFaceEnrollments,
};
