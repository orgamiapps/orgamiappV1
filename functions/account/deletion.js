"use strict";

const {createHash} = require("node:crypto");
const {getAuth} = require("firebase-admin/auth");
const {FieldValue, getFirestore} = require("firebase-admin/firestore");
const {getStorage} = require("firebase-admin/storage");
const {logger} = require("firebase-functions");
const {HttpsError, onCall} = require("firebase-functions/v2/https");
const {onSchedule} = require("firebase-functions/v2/scheduler");

const {DELETE_QUERIES, COLLECTION_GROUP_QUERIES, ROOT_DOCUMENTS, PAYMENT_COLLECTIONS,
  PAYMENT_OWNER_FIELDS, STORAGE_PREFIXES, inspectDispositions, requireClearInventory} = require("./dispositions");

function accountHash(uid) {
  return createHash("sha256").update(`attendus-deleted-account:${uid}`).digest("hex");
}

async function mutate(counts, ref, operation, data) {
  return counts.lease.transaction(async (tx) => {
    if (operation === "delete") tx.delete(ref);
    else tx[operation](ref, data);
    tx.set(counts.job, {lastCompletedItem: ref.path}, {merge: true});
  });
}

async function deleteQuery(db, query, counterKey, counts) {
  let snapshot = await query.limit(200).get();
  while (!snapshot.empty) {
    const nextCounts = {...counts, [counterKey]: (counts[counterKey] || 0) + snapshot.size};
    await counts.lease.transaction(async (tx) => {
      for (const document of snapshot.docs) tx.delete(document.ref);
      tx.set(counts.job, {partialCounts: nextCounts,
        lastCompletedItem: snapshot.docs[snapshot.docs.length - 1].ref.path}, {merge: true});
    });
    counts[counterKey] = nextCounts[counterKey];
    snapshot = await query.limit(200).get();
  }
}

async function deleteDocumentTree(db, document, counterKey, counts) {
  // Include missing-parent descendants, and fence every leaf commit. A blind
  // recursiveDelete cannot be cancelled when this worker loses its lease.
  for (const collection of await document.listCollections()) {
    // listDocuments includes nonexistent ancestors with surviving descendants.
    for (const child of await collection.listDocuments()) await deleteDocumentTree(db, child, counterKey, counts);
  }
  const deleted = await counts.lease.transaction(async (tx) => {
    const current = await tx.get(document);
    if (!current.exists) return false;
    tx.delete(document);
    tx.set(counts.job, {lastCompletedItem: document.path,
      partialCounts: {...counts, [counterKey]: (counts[counterKey] || 0) + 1}}, {merge: true});
    return true;
  });
  if (deleted) counts[counterKey] = (counts[counterKey] || 0) + 1;
}

async function anonymizePayments(db, uid, hash, counts) {
  for (const collectionName of PAYMENT_COLLECTIONS) {
    for (const ownerField of PAYMENT_OWNER_FIELDS) {
      const query = db.collection(collectionName)
          .where(ownerField, "==", uid)
          .limit(200);
      let snapshot = await query.get();
      while (!snapshot.empty) {
        await counts.lease.transaction(async (tx) => {
          for (const document of snapshot.docs) tx.update(document.ref, {
            [ownerField]: FieldValue.delete(),
            purchaserEmail: FieldValue.delete(),
            customerEmail: FieldValue.delete(),
            deletedAccountHash: hash,
            accountDeletedAt: FieldValue.serverTimestamp(),
          });
          tx.set(counts.job, {partialCounts: {...counts,
            paymentRecordsAnonymized: counts.paymentRecordsAnonymized + snapshot.size},
          lastCompletedItem: snapshot.docs[snapshot.docs.length - 1].ref.path}, {merge: true});
        });
        counts.paymentRecordsAnonymized += snapshot.size;
        snapshot = await query.get();
      }
    }
  }
}

async function deleteStorageObjects(bucket, uid, counts) {
  await counts.lease.checkpoint({partialCounts: {...counts}});
  await bucket.file(`profile_pictures/${uid}.jpg`).delete({ignoreNotFound: true});
  for (const prefixTemplate of STORAGE_PREFIXES) {
    const prefix = prefixTemplate.replace("{uid}", uid);
    const [files] = await bucket.getFiles({prefix});
    if (files.length === 0) continue;
    for (let offset = 0; offset < files.length; offset += 20) {
      const batch = files.slice(offset, offset + 20);
      await counts.lease.checkpoint({partialCounts: {...counts}, storagePrefix: prefixTemplate});
      await Promise.all(batch.map(async (file) =>
        file.delete({ignoreNotFound: true})));
      counts.storageObjectsDeleted += batch.length;
    }
  }
}

function messagingReview(message) {
  const error = new Error(message);
  error.code = "deletion/review-required";
  error.categories = ["messaging:migration_evidence"];
  return error;
}

async function migrateSharedConversation(db, uid, sourceId, counts) {
  const {key} = require("../events/roster");
  const source = db.collection("Conversations").doc(sourceId);
  const destination = db.collection("Conversations").doc(`retained_${key(sourceId)}`);
  const checkpoint = counts.job.collection("conversations").doc(key(sourceId));
  const tombstone = `former_${key(`${sourceId}:${uid}`).slice(0, 24)}`;
  const migrationId = key(`${counts.job.id}:${sourceId}`);
  await counts.lease.transaction(async (tx) => {
    const [original, previous, target, lineage] = await Promise.all([tx.get(source), tx.get(checkpoint), tx.get(destination),
      tx.get(db.collection("ConversationMigrationState").doc(sourceId))]);
    if (previous.get("status") === "complete" || previous.get("status") === "moving") return;
    if (!original.exists || !(original.get("participantIds") || []).includes(uid)) return;
    const data = original.data();
    if (data.migrationState === "moving") throw new HttpsError("aborted", "Conversation must finish its existing migration first.");
    if (data.redirectConversationId) {
      tx.update(source, {participantIds: data.participantIds.map((id) => id === uid ? tombstone : id)});
      return;
    }
    if (data.messagingVersion !== 2) throw messagingReview("Conversation needs a verified messaging-version migration first");
    if (target.exists) throw messagingReview("Conversation migration destination already exists without a checkpoint");
    const legacyIds = [...new Set([...(lineage.get("legacyIds") || []), sourceId])];
    if (legacyIds.length > 30) throw messagingReview("Conversation redirect lineage requires review");
    const clean = {...data, participantIds: data.participantIds.map((id) => id === uid ? tombstone : id), formerParticipant: true,
      formerParticipantIds: [...new Set([...(data.formerParticipantIds || []), tombstone])], migrationState: "moving", migrationId};
    for (const field of ["participant1Id", "participant2Id"]) if (clean[field] === uid) clean[field] = tombstone;
    for (const field of ["createdBy", "ownerUid"]) if (clean[field] === uid) { delete clean[field]; clean.ownerUnavailable = true; }
    if (clean.lastMessageSenderId === uid) { clean.lastMessage = ""; delete clean.lastMessageSenderId; }
    for (const field of ["participantInfo", "receivedTotals", "readTotals", "readSequences", "unreadCounts"]) {
      if (clean[field]) { clean[field] = {...clean[field]}; delete clean[field][uid]; }
    }
    const survivors = clean.participantIds.filter((id) => !clean.formerParticipantIds.includes(id));
    const zeroes = Object.fromEntries(survivors.map((id) => [id, 0]));
    tx.create(destination, clean);
    tx.set(source, {participantIds: clean.participantIds, redirectConversationId: destination.id, migrationState: "moving",
      migrationId, messagingVersion: 2, isGroup: data.isGroup === true, formerParticipant: true});
    tx.set(db.collection("ConversationMigrationState").doc(destination.id), {legacyIds, migrationId,
      subjectDeletionJobIds: [...new Set([...(lineage.get("subjectDeletionJobIds") || []), uid])],
      retentionReviewStatus: "pending"});
    tx.set(checkpoint, {status: "moving", sourceConversationId: sourceId, destinationConversationId: destination.id, migrationId,
      processed: 0, removed: 0, preserved: 0, lastSequence: -1, receivedTotals: zeroes, readTotals: zeroes,
      originalReadSequences: clean.readSequences || {}, originalReadTotals: clean.readTotals || {}, createdAt: new Date()});
  });
  let finished = false;
  while (!finished) {
    const completed = await counts.lease.transaction(async (tx) => {
      const [state, original, target] = await Promise.all([tx.get(checkpoint), tx.get(source), tx.get(destination)]);
      if (!state.exists || state.get("status") === "complete") return true;
      if (state.get("migrationId") !== migrationId || original.get("migrationId") !== migrationId || target.get("migrationId") !== migrationId ||
          original.get("migrationState") !== "moving" || target.get("migrationState") !== "moving") throw messagingReview("Conversation migration lock changed");
      const page = await tx.get(db.collection("Messages").where("conversationId", "==", sourceId).orderBy("sequence").orderBy("__name__").limit(100));
      const data = state.data();
      if (page.empty) {
        const leftovers = await tx.get(db.collection("Messages").where("conversationId", "==", sourceId).limit(1));
        if (!leftovers.empty) throw messagingReview("Legacy messages without an ordered sequence require review");
        const last = data.lastRetainedMessageId ? await tx.get(db.collection("Messages").doc(data.lastRetainedMessageId)) : null;
        if (last && last.get("conversationId") !== destination.id) throw messagingReview("Last preserved message changed during migration");
        const unreadCounts = Object.fromEntries(Object.entries(data.receivedTotals).map(([id, total]) => [id, Math.max(0, total - (data.readTotals[id] || 0))]));
        tx.update(destination, {migrationState: "complete", receivedTotals: data.receivedTotals, readTotals: data.readTotals, unreadCounts,
          lastMessage: last?.get("content") || "", lastMessageSenderId: last?.get("senderId") || FieldValue.delete(),
          ...(last?.get("timestamp") ? {lastMessageTime: last.get("timestamp")} : {})});
        tx.update(source, {migrationState: "complete"});
        tx.update(checkpoint, {status: "complete", completedAt: new Date()});
        return true;
      }
      const totals = {...data.receivedTotals}, readTotals = {...data.readTotals};
      let lastSequence = data.lastSequence, removed = 0, preserved = 0, lastRetainedMessageId = data.lastRetainedMessageId || null;
      const changes = [];
      for (const message of page.docs) {
        const record = message.data();
        if (!Number.isSafeInteger(record.sequence) || record.sequence <= lastSequence || !record.recipientTotals || typeof record.content !== "string") {
          throw messagingReview("Message sequence or read-boundary evidence requires review");
        }
        lastSequence = record.sequence;
        if (record.senderId === uid) { removed++; changes.push({message, action: "delete"}); continue; }
        const recipients = Array.isArray(record.notificationRecipients) ? record.notificationRecipients :
          target.get("isGroup") !== true && record.receiverId ? [record.receiverId] : null;
        if (!recipients) throw messagingReview("Group message recipient evidence requires review");
        for (const id of new Set(recipients)) {
          if (!Object.hasOwn(totals, id)) continue;
          if (!Number.isSafeInteger(record.recipientTotals[id]) || record.recipientTotals[id] < 0) throw messagingReview("Recipient read-boundary evidence requires review");
          totals[id]++;
          if (record.sequence <= (data.originalReadSequences[id] || 0) || record.recipientTotals[id] <= (data.originalReadTotals[id] || 0)) readTotals[id]++;
        }
        const updates = {conversationId: destination.id, recipientTotals: {...totals},
          notificationRecipients: recipients.filter((id) => id !== uid),
          readByUserIds: (record.readByUserIds || []).filter((id) => id !== uid)};
        if (record.receiverId === uid) updates.receiverId = tombstone;
        preserved++; lastRetainedMessageId = message.id;
        changes.push({message, action: "update", updates});
      }
      for (const {message, action, updates} of changes) {
        if (action === "delete") tx.delete(message.ref); else tx.update(message.ref, updates);
        tx.set(checkpoint.collection("messages").doc(message.id), {status: action === "delete" ? "removed_sender" : "preserved",
          sequence: message.get("sequence"), migrationId, completedAt: new Date()});
      }
      tx.update(checkpoint, {receivedTotals: totals, readTotals, lastSequence, lastRetainedMessageId,
        processed: data.processed + page.size, removed: data.removed + removed, preserved: data.preserved + preserved,
        lastCompletedMessageId: page.docs[page.size - 1].id, updatedAt: new Date()});
      tx.set(counts.job, {lastCompletedItem: checkpoint.path}, {merge: true});
      return false;
    });
    finished = completed;
    if (!completed) await counts.lease.checkpoint({phase: "migrate_shared_conversations"});
  }
}

async function removeSharedMessagingIdentity(db, uid, counts) {
  const {allDocuments} = require("../events/roster");
  // A prepared alias no longer contains uid; recover it from its durable job.
  const pending = await allDocuments(counts.job.collection("conversations").where("status", "==", "moving"));
  const sources = new Set(pending.map((doc) => doc.get("sourceConversationId")));
  for (const conversation of await allDocuments(db.collection("Conversations").where("participantIds", "array-contains", uid))) sources.add(conversation.id);
  for (const sourceId of sources) await migrateSharedConversation(db, uid, sourceId, counts);
  for (const message of await allDocuments(db.collection("Messages").where("receiverId", "==", uid))) {
    await mutate(counts, message.ref, "update", {receiverId: "deleted_account"});
  }
}

async function runAccountDeletion({uid, db, auth, bucket}) {
  const job = db.collection("account_deletion_jobs").doc(uid);
  const existing = await job.get();
  if (existing.exists && existing.data()?.status === "complete") {
    return existing.data().result;
  }

  const hash = accountHash(uid);
  const lease = await require("./deletion-lease").claimDeletion(db, job, hash);
  if (lease.result) return lease.result;
  const counts = {
    documentsDeleted: 0,
    documentTreesDeleted: 0,
    paymentRecordsAnonymized: 0,
    storageObjectsDeleted: 0,
    ...lease.counts,
  };
  Object.defineProperties(counts, {lease: {value: lease}, job: {value: job}});


  try {
    const review = await inspectDispositions({db, bucket, uid, reviewOnly: true});
    await lease.checkpoint({partialCounts: counts, phase: "ownership_and_retention_review", review});
    requireClearInventory(review);
    const {allDocuments} = require("../events/roster");
    const affectedEvents = new Set(existing.get("eventIds") || []);
    for (const name of ["Attendance", "RegisterAttendance", "Tickets"]) {
      for (const field of ["customerUid", "userId"]) {
        for (const doc of await allDocuments(db.collection(name).where(field, "==", uid))) {
          if (doc.get("eventId")) affectedEvents.add(doc.get("eventId"));
        }
      }
    }
    await lease.checkpoint({partialCounts: counts, phase: "inventory", eventIds: [...affectedEvents]});
    await lease.checkpoint({partialCounts: counts, phase: "archive_and_verify"});
    counts.attendanceArchived = Math.max(counts.attendanceArchived || 0,
        await require("./attendance-history").archiveBeforeDeletion(db, uid, {lease}));
    await lease.checkpoint({partialCounts: counts, phase: "revoke_credentials", attendanceArchived: counts.attendanceArchived});
    await require("../notifications/push-tokens").cleanupPushTokenAccountData(db, uid, counts);
    const passes = await allDocuments(db.collection("AttendancePasses").where("ownerUid", "==", uid));
    for (const pass of passes) {
      await mutate(counts, pass.ref, "update", {status: "revoked", revokedAt: FieldValue.serverTimestamp()});
      for (const name of ["AttendanceWalletDownloads", "AttendanceWalletDevices"]) {
        await deleteQuery(db, db.collection(name).where("passId", "==", pass.id), "documentsDeleted", counts);
      }
      for (const name of ["AttendanceWalletJobs", "AttendanceWalletDeliveryJobs", "AttendanceWalletDelivery"]) {
        await mutate(counts, db.collection(name).doc(pass.id), "delete");
      }
      await mutate(counts, pass.ref, "delete");
    }
    await lease.checkpoint({partialCounts: counts, phase: "remove_personal_data"});
    for (const field of ["customerUid", "userId"]) {
      for (const attendance of await allDocuments(db.collection("Attendance").where(field, "==", uid))) {
        await deleteQuery(db, db.collection("AttendanceSubjects").where("attendanceId", "==", attendance.id), "documentsDeleted", counts);
      }
    }
    await deleteQuery(db, db.collection("AttendanceArchiveGroups").where("ownerUid", "==", uid), "documentsDeleted", counts);
    await removeSharedMessagingIdentity(db, uid, counts);
    await require("../community/account-deletion").cleanupCommunityAccountData(db, bucket, uid, counts);
    await require("../discovery/maintenance").cleanupDiscoveryAccountData(db, uid, counts);
    await require("../quiz/account-deletion").cleanupQuizAccountData(db, uid, counts);
    const guests = [...new Map((await Promise.all(["ownerUid", "claimedByUid"].map((field) => allDocuments(db.collection("GuestAttendees").where(field, "==", uid))))).flat().map((doc) => [doc.id, doc])).values()];
    for (const guest of guests) {
      for (const name of ["GuestManageTokens", "GuestManageSessions", "OutboundMessages", "GuestEventEmailClaims"]) {
        await deleteQuery(db, db.collection(name).where("guestId", "==", guest.id), "documentsDeleted", counts);
      }
      await mutate(counts, guest.ref, "delete");
    }
    // Purchasing an admission does not make its attendee's record disposable.
    for (const ticket of await allDocuments(db.collection("Tickets").where("purchaserUid", "==", uid))) {
      if (ticket.get("eventId")) affectedEvents.add(ticket.get("eventId"));
      const attendeeUid = ticket.get("customerUid") || ticket.get("userId");
      if (!attendeeUid) {
        const error = new Error("Unlinked purchased admission requires ownership review");
        error.code = "deletion/review-required";
        error.categories = ["ticket:unresolved_attendee_identity"];
        throw error;
      } else if (attendeeUid === uid) {
        await mutate(counts, ticket.ref, "delete");
      } else {
        await mutate(counts, ticket.ref, "update", {purchaserUid: FieldValue.delete(), purchaserEmail: FieldValue.delete(), purchaserName: FieldValue.delete()});
      }
    }
    await lease.checkpoint({eventIds: [...affectedEvents]});
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
    for (const eventId of affectedEvents) {
      await deleteDocumentTree(db, db.collection("EventRosters").doc(eventId), "documentTreesDeleted", counts);
      const exports = await allDocuments(db.collection("EventExportJobs").where("eventId", "==", eventId));
      for (const record of exports) {
        if (record.get("path")) await bucket.file(record.get("path")).delete({ignoreNotFound: true});
        await mutate(counts, record.ref, "delete");
      }
    }

    await lease.checkpoint({partialCounts: counts, phase: "verify_cleanup"});
    const verification = await inspectDispositions({db, bucket, uid});
    await lease.checkpoint({verification, partialCounts: counts});
    requireClearInventory(verification);
    await lease.checkpoint({partialCounts: counts, phase: "delete_authentication"});
    try {
      await auth.deleteUser(uid);
    } catch (error) {
      if (error.code !== "auth/user-not-found") throw error;
    }

    const result = {
      status: "complete",
      ...counts,
    };
    await lease.finish({
      status: "complete",
      completedAt: FieldValue.serverTimestamp(),
      leaseUntil: FieldValue.delete(),
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
    try { await lease.finish({
      status: error.code === "deletion/review-required" ? "review_required" : lease.attempts >= 5 ? "terminal_failed" : "failed",
      leaseUntil: FieldValue.delete(),
      failedAt: FieldValue.serverTimestamp(),
      lastErrorCode: String(error.code || "unknown").slice(0, 120),
      partialCounts: counts,
      reviewCategories: error.categories || [],
    }); } catch (leaseError) {
      // A stale worker must never overwrite the winner or clear its lease.
      logger.warn("Deletion failure state could not be fenced", {code: leaseError.code || "unknown"});
    }
    throw error;
  }
}

function createDeleteUserAccount() {
  return onCall({
    region: "us-central1",
    maxInstances: 5,
    timeoutSeconds: 540,
    memory: "1GiB",
    enforceAppCheck: process.env.FUNCTIONS_EMULATOR !== "true",
  }, async (request) => {
    const uid = request.auth?.uid;
    if (!uid) {
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
      if (error.code === "deletion/review-required") {
        throw new HttpsError("failed-precondition", "Deletion is paused for ownership or retention review. Your deletion request is preserved.");
      }
      throw new HttpsError(
          "internal",
          "Account deletion did not finish. It is safe to retry.",
      );
    }
  });
}

function createResumeAccountDeletion() {
  return onSchedule({region: "us-central1", schedule: "every 15 minutes", timeoutSeconds: 540, maxInstances: 1}, async () => {
    const db = getFirestore();
    const jobs = await db.collection("account_deletion_jobs").where("resumableVersion", "==", 2)
        .where("status", "in", ["failed", "running"]).limit(5).get();
    for (const job of jobs.docs) {
      if (job.get("leaseUntil")?.toMillis() > Date.now()) continue;
      try { await runAccountDeletion({uid: job.id, db, auth: getAuth(), bucket: getStorage().bucket()}); }
      catch (error) { logger.warn("Account deletion requires another retry", {accountHash: job.get("accountHash"), code: error.code || "unknown"}); }
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
  createResumeAccountDeletion,
  runAccountDeletion,
  migrateSharedConversation,
  removeSharedMessagingIdentity,
};
