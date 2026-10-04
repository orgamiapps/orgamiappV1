"use strict";

const DELETE_QUERIES = Object.freeze([
  ["Tickets", "customerUid", "=="],
  ["Tickets", "userId", "=="],
  ["Attendance", "customerUid", "=="],
  ["Attendance", "userId", "=="],
  ["RegisterAttendance", "customerUid", "=="],
  ["RegisterAttendance", "userId", "=="],
  ["Messages", "senderId", "=="],
  ["notifications", "userId", "=="],
  ["EventDrafts", "ownerUid", "=="],
  ["GuestManageSessions", "ownerUid", "=="],
  ["TicketReservations", "customerUid", "=="],
  ["Comments", "userId", "=="],
  ["event_feedback", "userId", "=="],
  ["app_feedback", "userId", "=="],
  ["feedback_submissions", "userId", "=="],
  ["LegacyNotificationDeliveries", "userId", "=="],
  ["QualificationCaptures", "recipientUid", "=="],
  ["QualificationCaptures", "actorUid", "=="],
  ["QuizParticipants", "userId", "=="],
  ["QuizResponses", "userId", "=="],
  ["Notifications", "userId", "=="],
  ["Notifications", "recipientId", "=="],
  ["scheduledNotifications", "userId", "=="],
  ["FaceEnrollments", "userId", "=="],
  ["AttendanceSubjects", "customerUid", "=="],
  ["PublicRegistrationFlows", "ownerUid", "=="],
  ["GuestManageTokens", "ownerUid", "=="],
  ["OutboundMessages", "ownerUid", "=="],
]);

const COLLECTION_GROUP_QUERIES = Object.freeze([
  ["Members", "userId"],
  ["JoinRequests", "userId"],
  ["AccessRequests", "userId"],
  ["Followers", "userId"],
  ["Following", "userId"],
  ["followers", "userId"],
  ["followers", "organizerUid"],
  ["following", "userId"],
  ["following", "followerUid"],
]);

const ROOT_DOCUMENTS = Object.freeze([
  "Customers",
  "users",
  "subscriptions",
  "user_analytics",
  "notificationSettings",
  "ProfileReadLimits",
  "discovery_notification_batches",
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
  "user_banners/{uid}/",
  "event-drafts/{uid}/",
]);

// These relationships require an explicit owner/retention decision. Never infer
// a replacement owner or remove an audit/payment exception by account name.
const REVIEW_QUERIES = Object.freeze([
  ["Events", "customerUid", "=="],
  ["Events", "coHosts", "array-contains"],
  ["Events", "checkInStaff", "array-contains"],
  ["Organizations", "createdBy", "=="],
  ["EventTemplates", "ownerUid", "=="],
  ["LiveQuizzes", "creatorId", "=="],
  ["OutboundDeliveryResolutions", "actorUid", "=="],
  ["QualificationScopes", "actorUids", "array-contains"],
  ["QualificationScopes", "recipientUids", "array-contains"],
  ["admin_audit_logs", "actorUid", "=="],
  ["admin_audit_logs", "targetId", "=="],
]);

function requireClearInventory(inventory) {
  if (inventory.remaining.length) {
    const error = new Error("Account disposition requires review before authentication deletion");
    error.code = "deletion/review-required";
    error.categories = inventory.remaining;
    throw error;
  }
}

async function documentTreeExists(ref) {
  if ((await ref.get()).exists) return true;
  for (const collection of await ref.listCollections()) {
    for (const child of await collection.listDocuments()) {
      if (await documentTreeExists(child)) return true;
    }
  }
  return false;
}

async function inspectDispositions({db, bucket, uid, reviewOnly = false}) {
  const checks = [];
  const queryCheck = async (scope, collection, field, operator = "==") => {
    const query = scope === "group" ? db.collectionGroup(collection) : db.collection(collection);
    const result = await query.where(field, operator, uid).limit(1).get();
    checks.push({category: `${scope}:${collection}:${field}`, clear: result.empty});
  };
  for (const [collection, field, operator] of REVIEW_QUERIES) await queryCheck("review", collection, field, operator);
  await queryCheck("group", "operations", "actorUid");
  if (!reviewOnly) {
    checks.push(...await require("../community/account-deletion").inspectCommunityAccountData(db, bucket, uid));
    // Source redirect IDs and retry namespaces can identify a deleted account.
    // Keep surviving participants' links functional, but do not pretend these
    // references are anonymous or an approved retention exception. A reviewed
    // basis/expiry/access policy and operator resolution are still required.
    await queryCheck("retention-review", "ConversationMigrationState", "subjectDeletionJobIds", "array-contains");
    for (const [collection, field, operator] of DELETE_QUERIES) await queryCheck("delete", collection, field, operator);
    for (const [collection, field] of COLLECTION_GROUP_QUERIES) await queryCheck("group", collection, field);
    for (const collection of PAYMENT_COLLECTIONS) {
      for (const field of PAYMENT_OWNER_FIELDS) await queryCheck("payment", collection, field);
    }
    for (const [collection, field, operator] of [
      ["Tickets", "purchaserUid"], ["AttendancePasses", "ownerUid"],
      ["AttendanceHistoryIdentities", "ownerUid"], ["AttendanceArchiveGroups", "ownerUid"],
      ["GuestAttendees", "ownerUid"], ["GuestAttendees", "claimedByUid"],
      ["Messages", "receiverId"], ["Conversations", "participantIds", "array-contains"],
      ["EventExportJobs", "actorUid"],
      ["PushTokenBindings", "ownerUid"], ["PushInstallations", "ownerUid"],
      ["DiscoverySavedEventStates", "uid"],
    ]) await queryCheck("related", collection, field, operator);
    for (const collection of ROOT_DOCUMENTS) {
      const ref = db.collection(collection).doc(uid);
      const clear = !(await documentTreeExists(ref));
      checks.push({category: `tree:${collection}`, clear});
    }
    for (const template of [...STORAGE_PREFIXES, "profile_pictures/{uid}.jpg"]) {
      const prefix = template.replace("{uid}", uid);
      const [files] = await bucket.getFiles({prefix, maxResults: 1, autoPaginate: false});
      checks.push({category: `storage:${template}`, clear: files.length === 0});
    }
  }
  const fingerprint = require("node:crypto").createHash("sha256").update(JSON.stringify(checks)).digest("hex");
  return {registryVersion: 1, checks, fingerprint, remaining: checks.filter((check) => !check.clear).map((check) => check.category)};
}

module.exports = {DELETE_QUERIES, COLLECTION_GROUP_QUERIES, ROOT_DOCUMENTS, PAYMENT_COLLECTIONS,
  PAYMENT_OWNER_FIELDS, STORAGE_PREFIXES, REVIEW_QUERIES, inspectDispositions, requireClearInventory};
