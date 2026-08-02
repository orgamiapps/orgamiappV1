"use strict";

const {createHash} = require("node:crypto");
const {getAuth} = require("firebase-admin/auth");
const {FieldValue, getFirestore} = require("firebase-admin/firestore");
const {getStorage} = require("firebase-admin/storage");
const {logger} = require("firebase-functions");
const {HttpsError, onCall} = require("firebase-functions/v2/https");

const DELETE_QUERIES = Object.freeze([
  ["Tickets", "customerUid", "=="],
  ["Tickets", "userId", "=="],
  ["Tickets", "purchaserUid", "=="],
  ["Attendance", "customerUid", "=="],
  ["Attendance", "userId", "=="],
  ["RegisterAttendance", "customerUid", "=="],
  ["RegisterAttendance", "userId", "=="],
  ["Messages", "senderId", "=="],
  ["Messages", "receiverId", "=="],
  ["Comments", "userId", "=="],
  ["event_feedback", "userId", "=="],
  ["Notifications", "userId", "=="],
  ["Notifications", "recipientId", "=="],
  ["scheduledNotifications", "userId", "=="],
  ["FaceEnrollments", "userId", "=="],
  ["Conversations", "participantIds", "array-contains"],
]);

const COLLECTION_GROUP_QUERIES = Object.freeze([
  ["Members", "userId"],
  ["JoinRequests", "userId"],
]);

const ROOT_DOCUMENTS = Object.freeze([
  "Customers",
  "users",
  "subscriptions",
  "user_analytics",
  "notificationSettings",
]);

const PAYMENT_COLLECTIONS = Object.freeze([
  "TicketPayments",
  "TicketUpgradePayments",
  "EventFeaturePayments",
  "FeaturePayments",
  "Payments",
]);

const PAYMENT_OWNER_FIELDS = Object.freeze([
  "customerUid",
  "userId",
  "purchaserUid",
  "ownerId",
]);

const STORAGE_PREFIXES = Object.freeze([
  "profile_pictures/{uid}/",
  "profilePictures/{uid}/",
  "users/{uid}/",
  "user_uploads/{uid}/",
  "banners/{uid}/",
]);

function accountHash(uid) {
  return createHash("sha256").update(`attendus-deleted-account:${uid}`).digest("hex");
}

async function deleteQuery(db, query, counterKey, counts) {
  let deleted = 0;
  let snapshot = await query.limit(200).get();
  while (!snapshot.empty) {
    const batch = db.batch();
    for (const document of snapshot.docs) batch.delete(document.ref);
    await batch.commit();
    deleted += snapshot.size;
    snapshot = await query.limit(200).get();
  }
  counts[counterKey] = (counts[counterKey] || 0) + deleted;
}

async function deleteDocumentTree(db, document, counterKey, counts) {
  await db.recursiveDelete(document);
  counts[counterKey] = (counts[counterKey] || 0) + 1;
}

async function anonymizePayments(db, uid, hash, counts) {
  for (const collectionName of PAYMENT_COLLECTIONS) {
    for (const ownerField of PAYMENT_OWNER_FIELDS) {
      const query = db.collection(collectionName)
          .where(ownerField, "==", uid)
          .limit(200);
      let snapshot = await query.get();
      while (!snapshot.empty) {
        const batch = db.batch();
        for (const document of snapshot.docs) {
          batch.update(document.ref, {
            [ownerField]: FieldValue.delete(),
            purchaserEmail: FieldValue.delete(),
            customerEmail: FieldValue.delete(),
            deletedAccountHash: hash,
            accountDeletedAt: FieldValue.serverTimestamp(),
          });
        }
        await batch.commit();
        counts.paymentRecordsAnonymized += snapshot.size;
        snapshot = await query.get();
      }
    }
  }
}

async function deleteStorageObjects(bucket, uid, counts) {
  for (const prefixTemplate of STORAGE_PREFIXES) {
    const prefix = prefixTemplate.replace("{uid}", uid);
    const [files] = await bucket.getFiles({prefix});
    if (files.length === 0) continue;
    for (let offset = 0; offset < files.length; offset += 20) {
      const batch = files.slice(offset, offset + 20);
      await Promise.all(batch.map(async (file) =>
        file.delete({ignoreNotFound: true})));
      counts.storageObjectsDeleted += batch.length;
    }
  }
}

async function runAccountDeletion({uid, db, auth, bucket}) {
  const job = db.collection("account_deletion_jobs").doc(uid);
  const existing = await job.get();
  if (existing.exists && existing.data()?.status === "complete") {
    return existing.data().result;
  }

  const hash = accountHash(uid);
  const counts = {
    documentsDeleted: 0,
    documentTreesDeleted: 0,
    paymentRecordsAnonymized: 0,
    storageObjectsDeleted: 0,
  };

  await job.set({
    status: "running",
    accountHash: hash,
    startedAt: FieldValue.serverTimestamp(),
    attempts: FieldValue.increment(1),
  }, {merge: true});

  try {
    for (const [collectionName, field, operator] of DELETE_QUERIES) {
      const query = db.collection(collectionName).where(field, operator, uid);
      await deleteQuery(db, query, "documentsDeleted", counts);
    }

    for (const [groupName, field] of COLLECTION_GROUP_QUERIES) {
      const query = db.collectionGroup(groupName).where(field, "==", uid);
      await deleteQuery(db, query, "documentsDeleted", counts);
    }

    await anonymizePayments(db, uid, hash, counts);

    for (const collectionName of ROOT_DOCUMENTS) {
      await deleteDocumentTree(
          db,
          db.collection(collectionName).doc(uid),
          "documentTreesDeleted",
          counts,
      );
    }

    await deleteStorageObjects(bucket, uid, counts);

    try {
      await auth.deleteUser(uid);
    } catch (error) {
      if (error.code !== "auth/user-not-found") throw error;
    }

    const result = {
      status: "complete",
      ...counts,
    };
    await job.set({
      status: "complete",
      completedAt: FieldValue.serverTimestamp(),
      result,
      lastErrorCode: FieldValue.delete(),
    }, {merge: true});
    logger.info("Account deletion completed", {accountHash: hash, ...counts});
    return result;
  } catch (error) {
    logger.error("Account deletion failed", {
      accountHash: hash,
      code: error.code || "unknown",
    });
    await job.set({
      status: "failed",
      failedAt: FieldValue.serverTimestamp(),
      lastErrorCode: String(error.code || "unknown").slice(0, 120),
      partialCounts: counts,
    }, {merge: true});
    throw error;
  }
}

function createDeleteUserAccount() {
  return onCall({
    region: "us-central1",
    maxInstances: 5,
    timeoutSeconds: 540,
    memory: "1GiB",
  }, async (request) => {
    const uid = request.auth?.uid;
    const provider = request.auth?.token?.firebase?.sign_in_provider;
    if (!uid || provider === "anonymous") {
      throw new HttpsError("unauthenticated", "A signed-in account is required.");
    }

    try {
      return await runAccountDeletion({
        uid,
        db: getFirestore(),
        auth: getAuth(),
        bucket: getStorage().bucket(),
      });
    } catch (error) {
      if (error instanceof HttpsError) throw error;
      throw new HttpsError(
          "internal",
          "Account deletion did not finish. It is safe to retry.",
      );
    }
  });
}

module.exports = {
  COLLECTION_GROUP_QUERIES,
  DELETE_QUERIES,
  PAYMENT_COLLECTIONS,
  ROOT_DOCUMENTS,
  STORAGE_PREFIXES,
  accountHash,
  createDeleteUserAccount,
  runAccountDeletion,
};
