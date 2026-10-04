"use strict";

const millis = (value) => value?.toMillis?.() ?? (value instanceof Date ? value.getTime() : NaN);

async function anonymizeExpiredGuestContacts(admin, now = Date.now()) {
  const db = admin.firestore();
  const cutoff = admin.firestore.Timestamp.fromMillis(now);
  let cursor = null, scanned = 0, anonymized = 0, retired = 0, hasMore = true;
  while (hasMore) {
    let query = db.collection("GuestAttendees").where("retentionAt", "<=", cutoff)
        .orderBy("retentionAt").orderBy("__name__").limit(200);
    if (cursor) query = query.startAfter(cursor);
    const page = await query.get();
    if (page.empty) break;
    scanned += page.size;
    for (let offset = 0; offset < page.docs.length; offset += 20) {
      const results = await Promise.all(page.docs.slice(offset, offset + 20).map((document) => db.runTransaction(async (tx) => {
        const current = await tx.get(document.ref);
        if (!current.exists || !Number.isFinite(millis(current.get("retentionAt"))) || millis(current.get("retentionAt")) > now) return "skipped";
        const owners = [...new Set([current.get("ownerUid"), current.get("claimedByUid")].filter(Boolean))];
        const guards = await Promise.all(owners.map((uid) => tx.get(db.collection("account_deletion_jobs").doc(uid))));
        if (guards.some((guard) => guard.exists)) return "skipped";
        const next = {...current.data()};
        // Claimed accounts follow authenticated account-retention rules. Remove
        // terminal schedule entries so they cannot starve later guest records.
        delete next.retentionAt;
        const terminal = Boolean(next.claimedByUid || next.anonymizedAt);
        if (!terminal) Object.assign(next, {fullName: "Former attendee", greetingName: null,
          encryptedEmail: null, maskedEmail: "Expired", emailHash: null,
          verificationStatus: "expired", anonymizedAt: admin.firestore.FieldValue.serverTimestamp()});
        tx.set(current.ref, next);
        return terminal ? "retired" : "anonymized";
      })));
      anonymized += results.filter((result) => result === "anonymized").length;
      retired += results.filter((result) => result === "retired").length;
    }
    cursor = page.docs[page.docs.length - 1];
    hasMore = page.size === 200;
  }
  return {scanned, anonymized, retired};
}
module.exports = {anonymizeExpiredGuestContacts};
