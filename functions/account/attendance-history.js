"use strict";
const {onDocumentWritten} = require("firebase-functions/v2/firestore");
const {onCall, HttpsError} = require("firebase-functions/v2/https");
const {key, allDocuments} = require("../events/roster");
const {instant} = require("../events/schedule");
const {requireEvent} = require("../events/access");
const {encryptEmail, decryptEmail, CONTACT_KMS_KEY_NAME} = require("../public-web/accountless");

function evidence(id, data) {
  const checkedIn = instant(data.checkedInAt || data.attendanceDateTime);
  const provenWithoutTime = data.isSignedIn === true || data.checkedIn === true || ["checked_in", "checked_out", "attended", "present"].includes(data.status);
  if ((!checkedIn && !provenWithoutTime) || !data.eventId) return null;
  return {eventId: data.eventId, sourceAttendanceHash: key(id),
    checkedInAt: checkedIn?.toISOString() || null, timestampQuality: checkedIn ? "recorded" : "unknown", checkedOutAt: instant(data.checkedOutAt)?.toISOString() || null,
    verificationSource: data.verificationSource || data.signInMethod || data.method || data.checkInMethod || "unknown",
    status: data.status || "recorded", voided: data.voided === true,
    provenance: "recorded_attendance", version: 1};
}

function evidenceFingerprint(stamp) {
  return key(JSON.stringify(Object.fromEntries(Object.keys(stamp).sort().map((field) => [field, stamp[field]]))));
}

function sourceCorrectionId(stamp) {
  const fields = ["eventId", "sourceAttendanceHash", "checkedInAt", "timestampQuality", "checkedOutAt",
    "verificationSource", "status", "voided", "provenance", "version", "admissionGroupId"];
  return key(JSON.stringify(Object.fromEntries(fields.filter((field) => stamp[field] !== undefined).map((field) => [field, stamp[field]]))));
}

function verifyArchivedEvidence(original, corrections, expected) {
  const matches = (candidate) => Object.entries(expected).every(([field, value]) => JSON.stringify(candidate?.[field]) === JSON.stringify(value));
  if (original.evidenceFingerprint) {
    const {evidenceFingerprint: recordedFingerprint, ...stamp} = original;
    if (evidenceFingerprint(stamp) !== recordedFingerprint) throw new Error("Original attendance evidence fingerprint changed");
  } else if (!matches(original)) {
    // Legacy archives without a committed original fingerprint cannot prove a
    // changed original merely because a later correction matches today's source.
    throw new Error("Original attendance evidence requires review");
  }
  for (const correction of corrections) {
    const data = correction.data;
    if (data.source === "attendance_record_update") {
      if (!data.evidence || sourceCorrectionId(data.evidence) !== correction.id ||
          data.evidence.eventId !== expected.eventId || data.evidence.sourceAttendanceHash !== expected.sourceAttendanceHash ||
          data.evidence.admissionGroupId !== expected.admissionGroupId) {
        throw new Error("Attendance correction chain verification failed");
      }
    } else if (!["void", "note"].includes(data.operation) || !data.actorUid ||
        data.fingerprint !== key(JSON.stringify([data.operation, data.reason]))) {
      throw new Error("Attendance manager correction verification failed");
    }
  }
  return true;
}

async function archiveAttendance(db, id, data, {anonymize = false, lease = null} = {}) {
  const transaction = lease ? lease.transaction : (work) => db.runTransaction(work);
  const stamp = evidence(id, data);
  if (!stamp) return null;
  const uid = data.customerUid || data.userId || null;
  const ref = db.collection("HistoricalAttendance").doc(key(id));
  const identityRef = db.collection("AttendanceHistoryIdentities").doc(ref.id);
  const previous = await ref.get();
  const grouping = data.admissionKey || (data.ticketId ? `ticket:${data.ticketId}` : data.registrationId ? `registration:${data.registrationId}` : `attendance:${id}`);
  const groupRef = db.collection("AttendanceArchiveGroups").doc(key(`${data.eventId}:${grouping}`));
  stamp.admissionGroupId = await transaction(async (tx) => {
    const group = await tx.get(groupRef);
    const deleting = uid ? await tx.get(db.collection("account_deletion_jobs").doc(uid)) : null;
    const groupId = previous.get("admissionGroupId") || group.get("groupId") || require("node:crypto").randomUUID();
    if (!group.exists && (!deleting?.exists || anonymize)) tx.create(groupRef, {groupId, eventId: data.eventId, ownerUid: uid});
    return groupId;
  });
  if (anonymize && previous.exists) {
    const corrections = (await allDocuments(ref.collection("corrections"))).map((doc) => ({id: doc.id, data: doc.data()}));
    verifyArchivedEvidence(previous.data(), corrections, stamp);
  }
  const identity = {recordedName: data.realName || data.userName || null, originalAccountId: uid,
    registrationContact: data.email || data.customerEmail || null,
    missing: [!data.realName && !data.userName ? "recorded_name" : null,
      !data.email && !data.customerEmail ? "registration_contact" : null].filter(Boolean),
    provenance: "attendance_record_only"};
  if (!anonymize && data.registrationId) {
    const registration = await db.collection("RegisterAttendance").doc(data.registrationId).get();
    if (registration.exists && registration.get("eventId") === data.eventId) {
      identity.registrationName = registration.get("realName") || registration.get("userName") || null;
      identity.provenance = "attendance_and_linked_registration";
      const guestId = registration.get("guestId");
      if (guestId) {
        const guest = await db.collection("GuestAttendees").doc(guestId).get();
        if (guest.get("encryptedEmail")) {
          identity.registrationContact = await decryptEmail(guest.get("encryptedEmail"));
          identity.missing = identity.missing.filter((field) => field !== "registration_contact");
        }
      }
    }
  }
  // Encryption never uses today's profile as a substitute for recorded identity.
  const encrypted = anonymize ? null : await encryptEmail(JSON.stringify(identity));
  await transaction(async (tx) => {
    const [existing, personal, deletion] = await Promise.all([tx.get(ref), tx.get(identityRef),
      uid ? tx.get(db.collection("account_deletion_jobs").doc(uid)) : Promise.resolve(null)]);
    if (!existing.exists) tx.create(ref, {...stamp, evidenceFingerprint: evidenceFingerprint(stamp)});
    else if (!Object.entries(stamp).every(([field, value]) => JSON.stringify(existing.get(field)) === JSON.stringify(value))) {
      const revision = key(JSON.stringify(stamp));
      const correction = ref.collection("corrections").doc(revision);
      if (!(await tx.get(correction)).exists) tx.create(correction, {evidence: stamp,
        source: "attendance_record_update", recordedAt: new Date()});
    }
    if (anonymize || deletion?.exists) tx.delete(identityRef);
    else if (!personal.exists) tx.create(identityRef, {eventId: stamp.eventId, ownerUid: uid,
      encryptedIdentity: encrypted, createdAt: new Date()});
  });
  const verified = await ref.get();
  if (!verified.exists || verified.get("eventId") !== stamp.eventId || verified.get("sourceAttendanceHash") !== key(id)) throw new Error("Attendance archival verification failed");
  const matches = (candidate) => Object.entries(stamp).every(([field, value]) => JSON.stringify(candidate?.[field]) === JSON.stringify(value));
  if (!matches(verified.data())) {
    const correction = await ref.collection("corrections").doc(key(JSON.stringify(stamp))).get();
    if (!matches(correction.get("evidence"))) throw new Error("Attendance correction verification failed");
  }
  if (anonymize && (await identityRef.get()).exists) throw new Error("Attendance anonymization verification failed");
  return ref.id;
}

async function archiveBeforeDeletion(db, uid, {lease = null} = {}) {
  const records = new Map();
  for (const field of ["customerUid", "userId"]) {
    for (const doc of await allDocuments(db.collection("Attendance").where(field, "==", uid))) records.set(doc.id, doc);
  }
  let count = 0;
  for (const doc of records.values()) {
    if (await archiveAttendance(db, doc.id, doc.data(), {anonymize: true, lease})) count++;
    else {
      const review = db.collection("AttendanceArchiveReview").doc(key(doc.id));
      const data = {sourcePath: doc.ref.path, ownerUid: uid, reason: "insufficient_attendance_evidence", createdAt: new Date()};
      if (lease) await lease.transaction(async (tx) => tx.set(review, data, {merge: true}));
      else await review.set(data, {merge: true});
      const error = new Error("Attendance evidence requires review before deletion");
      error.code = "deletion/review-required";
      error.categories = ["attendance:insufficient_evidence"];
      throw error;
    }
  }
  for (const doc of await allDocuments(db.collection("AttendanceHistoryIdentities").where("ownerUid", "==", uid))) {
    if (lease) await lease.transaction(async (tx) => tx.delete(doc.ref));
    else await doc.ref.delete();
  }
  return count;
}

function createAttendanceHistory(admin) {
  const db = admin.firestore();
  const options = {region: "us-central1", enforceAppCheck: process.env.FUNCTIONS_EMULATOR !== "true", secrets: [CONTACT_KMS_KEY_NAME]};
  return {
    archiveRecordedAttendance: onDocumentWritten({document: "Attendance/{id}", region: "us-central1", secrets: [CONTACT_KMS_KEY_NAME]}, async (change) => {
      if (change.data?.after.exists) await archiveAttendance(db, change.params.id, change.data.after.data());
    }),
    getAttendanceHistoryV1: onCall(options, async (request) => {
      const access = await requireEvent(db, request);
      let query = db.collection("HistoricalAttendance").where("eventId", "==", access.eventId).orderBy("__name__");
      if (request.data.cursor) query = query.startAfter(String(request.data.cursor));
      const result = await query.limit(101).get();
      const records = await Promise.all(result.docs.slice(0, 100).map(async (doc) => ({id: doc.id, ...doc.data(),
        corrections: (await allDocuments(doc.ref.collection("corrections"))).map((change) => ({id: change.id, ...change.data()}))})));
      return {records,
        nextCursor: result.size > 100 ? result.docs[99].id : null};
    }),
    getAttendanceHistoryIdentityV1: onCall(options, async (request) => {
      const access = await requireEvent(db, request);
      const id = String(request.data.historyId || "");
      const reason = String(request.data.reason || "").trim();
      if (!/^[a-f0-9]{64}$/.test(id) || reason.length < 10 || reason.length > 500) throw new HttpsError("invalid-argument", "A history ID and access reason are required.");
      return db.runTransaction(async (tx) => {
        const doc = await tx.get(db.collection("AttendanceHistoryIdentities").doc(id));
        const event = await tx.get(access.document.ref);
        if (!(await require("../events/access").capabilities(db, access.uid, event.data(), tx)).manageEvent) throw new HttpsError("permission-denied", "Event access changed.");
        if (!doc.exists || doc.get("eventId") !== access.eventId) throw new HttpsError("not-found", "Identifying information is unavailable or has been removed.");
        const owner = doc.get("ownerUid");
        if (owner && (await tx.get(db.collection("account_deletion_jobs").doc(owner))).exists) throw new HttpsError("not-found", "Identifying information is being removed.");
        const identity = JSON.parse(await decryptEmail(doc.get("encryptedIdentity")));
        tx.create(db.collection("admin_audit_logs").doc(), {action: "attendance.history.identity.read", actorUid: access.uid, targetId: id, eventId: access.eventId, reason, createdAt: new Date()});
        return {identity};
      });
    }),
    correctAttendanceHistoryV1: onCall(options, async (request) => {
      const access = await requireEvent(db, request);
      const id = String(request.data.historyId || ""); const reason = String(request.data.reason || "").trim();
      const operation = request.data.operation;
      if (!/^[a-f0-9]{64}$/.test(id) || !["void", "note"].includes(operation) || reason.length < 10 || reason.length > 1000) throw new HttpsError("invalid-argument", "Choose a correction and explain its reason.");
      const ref = db.collection("HistoricalAttendance").doc(id);
      const record = await ref.get();
      if (!record.exists || record.get("eventId") !== access.eventId) throw new HttpsError("not-found", "Attendance not found.");
      const requestKey = String(request.data.idempotencyKey || key(`${access.uid}:${operation}:${reason}`));
      if (!/^[A-Za-z0-9._:-]{1,180}$/.test(requestKey)) throw new HttpsError("invalid-argument", "Invalid correction key.");
      const correction = ref.collection("corrections").doc(key(`${access.uid}:${requestKey}`));
      const fingerprint = key(JSON.stringify([operation, reason]));
      await db.runTransaction(async (tx) => {
        const event = await tx.get(access.document.ref);
        if (!(await require("../events/access").capabilities(db, access.uid, event.data(), tx)).manageEvent) throw new HttpsError("permission-denied", "Event access changed.");
        const prior = await tx.get(correction);
        if (prior.exists) {
          if (prior.get("fingerprint") !== fingerprint) throw new HttpsError("already-exists", "Correction key conflicts.");
          return;
        }
        tx.create(correction, {operation, reason, fingerprint, actorUid: access.uid, createdAt: new Date()});
      });
      return {correctionId: correction.id};
    }),
  };
}
module.exports = {evidence, evidenceFingerprint, sourceCorrectionId, verifyArchivedEvidence, archiveAttendance, archiveBeforeDeletion, createAttendanceHistory};
