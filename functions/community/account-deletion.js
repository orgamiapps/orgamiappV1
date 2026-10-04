"use strict";

const FEED_FIELDS = ["authorId", "createdBy", "moderatedBy", "deletedBy", "likes", "voters"];
const EVENT_FIELDS = ["likes", "accessList", "moderatedBy", "deletedBy"];
function withoutUid(data, uid) {
  const cleaned = {...data};
  for (const field of ["likes", "voters", "accessList"]) if (Array.isArray(cleaned[field])) cleaned[field] = cleaned[field].filter((value) => value !== uid);
  for (const field of ["createdBy", "moderatedBy", "deletedBy"]) if (cleaned[field] === uid) delete cleaned[field];
  if (Array.isArray(cleaned.options)) {
    cleaned.options = cleaned.options.map((option) => ({...option,
      votes: (option.votes || []).filter((value) => value !== uid),
      voteCount: (option.votes || []).filter((value) => value !== uid).length}));
    cleaned.voters = [...new Set(cleaned.options.flatMap((option) => option.votes))];
    cleaned.totalVotes = cleaned.voters.length;
  }
  return cleaned;
}
function ownedGroup(path) {
  const segments = path.split("/");
  return segments[0] === "Organizations" && segments.length >= 4 ? segments[1] : null;
}
function groupUploadPrefix(orgId, uid) { return `groups/${orgId}/photos/${uid}_`; }
function isOwnedUpload(name, orgId, uid) {
  const prefix = groupUploadPrefix(orgId, uid);
  // The upload helper writes uid_epochMilliseconds_index.jpg. Validate the
  // suffix so account "a" cannot delete account "a_b" uploads by prefix.
  return name.startsWith(prefix) && /^\d+_\d+\.[A-Za-z0-9]+$/.test(name.slice(prefix.length));
}
async function groupUploads(bucket, orgId, uid, visit) {
  let options = {prefix: groupUploadPrefix(orgId, uid), maxResults: 200, autoPaginate: false};
  do {
    const [files, next] = await bucket.getFiles(options);
    for (const file of files) if (isOwnedUpload(file.name, orgId, uid)) await visit(file);
    options = next || null;
  } while (options);
}
async function cleanupCommunityAccountData(db, bucket, uid, counts) {
  const checkpoint = await counts.job.get();
  const orgIds = new Set(checkpoint.get("communityOrganizationIds") || []);
  // Only index-selected memberships/content establish storage ownership scope.
  const memberships = await db.collectionGroup("Members").where("userId", "==", uid).get();
  for (const doc of memberships.docs) { const id = ownedGroup(doc.ref.path); if (id) orgIds.add(id); }
  async function checkpointGroups() { await counts.lease.checkpoint({communityOrganizationIds: [...orgIds]}); }
  async function drain(query, work) {
    let page = await query.limit(100).get();
    while (!page.empty) {
      for (const document of page.docs) await work(document);
      page = await query.limit(100).get();
    }
  }
  for (const field of FEED_FIELDS) {
    const operator = ["likes", "voters"].includes(field) ? "array-contains" : "==";
    await drain(db.collectionGroup("Feed").where(field, operator, uid), async (doc) => {
      const orgId = ownedGroup(doc.ref.path); if (orgId) orgIds.add(orgId);
      // Persist storage scope before author identity is removed; retries retain it.
      await checkpointGroups();
      await counts.lease.transaction(async (tx) => {
        const live = await tx.get(doc.ref);
        if (!live.exists) return;
        const data = live.data();
        const author = data.authorId || data.createdBy;
        const clean = author === uid ? {type: data.type || "photo", deleted: true, isHidden: true,
          authorName: "Deleted member", commentCount: Number(data.commentCount) || 0, likes: [], deletedAt: new Date()} : withoutUid(data, uid);
        tx.set(doc.ref, clean);
        tx.set(counts.job, {lastCompletedItem: doc.ref.path}, {merge: true});
      });
    });
  }
  await drain(db.collectionGroup("Comments").where("userId", "==", uid), async (doc) => {
    const orgId = ownedGroup(doc.ref.path); if (orgId) orgIds.add(orgId);
    await checkpointGroups();
    const segments = doc.ref.path.split("/");
    const parent = segments.length > 2 ? db.doc(segments.slice(0, -2).join("/")) : null;
    await counts.lease.transaction(async (tx) => {
      const [live, post] = await Promise.all([tx.get(doc.ref), parent ? tx.get(parent) : null]);
      if (!live.exists || live.get("userId") !== uid) return;
      tx.delete(doc.ref);
      if (post?.exists) tx.update(parent, {commentCount: Math.max(0, (Number(post.get("commentCount")) || 0) - 1)});
      tx.set(counts.job, {lastCompletedItem: doc.ref.path}, {merge: true});
    });
  });
  for (const [query, field] of [[db.collectionGroup("Comments"), "likes"], ...EVENT_FIELDS.map((field) => [db.collection("Events"), field])]) {
    await drain(query.where(field, ["likes", "accessList"].includes(field) ? "array-contains" : "==", uid), async (doc) => {
      await counts.lease.transaction(async (tx) => {
        const live = await tx.get(doc.ref);
        if (!live.exists) return;
        tx.set(doc.ref, withoutUid(live.data(), uid));
        tx.set(counts.job, {lastCompletedItem: doc.ref.path}, {merge: true});
      });
    });
  }
  // Remove anonymous feedback via its private ownership marker, then named
  // feedback as well. Also remove copied comment text from analytics summaries.
  async function eraseFeedback(ref, marker = null) {
    await counts.lease.transaction(async (tx) => {
      const live = await tx.get(ref);
      const eventId = live.get("eventId");
      const analyticsRef = eventId ? db.collection("event_analytics").doc(eventId) : null;
      const analytics = analyticsRef ? await tx.get(analyticsRef) : null;
      if (live.exists) {
        const comment = live.get("comment");
        if (typeof comment === "string" && analytics?.get("feedbackAnalytics")) {
          const summary = comment.slice(0, 100) + (comment.length > 100 ? "..." : "");
          const data = analytics.get("feedbackAnalytics");
          tx.update(analyticsRef, {feedbackAnalytics: {...data, commentSummaries: (data.commentSummaries || []).filter((value) => value !== summary)}});
        }
        tx.delete(ref);
      }
      if (marker) tx.delete(marker);
      tx.set(counts.job, {lastCompletedItem: ref.path}, {merge: true});
    });
  }
  await drain(db.collection("feedback_submissions").where("userId", "==", uid), async (marker) => {
    const id = marker.get("feedbackId");
    if (typeof id !== "string" || !/^[A-Za-z0-9._:-]{1,128}$/.test(id)) throw Error("Invalid feedback ownership marker");
    await eraseFeedback(db.collection("event_feedback").doc(id));
    await eraseFeedback(db.collection("app_feedback").doc(id), marker.ref);
  });
  await drain(db.collection("event_feedback").where("userId", "==", uid), async (doc) => eraseFeedback(doc.ref));
  await checkpointGroups();
  for (const orgId of orgIds) await groupUploads(bucket, orgId, uid, async (file) => {
    await counts.lease.checkpoint({phase: "remove_group_uploads", communityOrganizationIds: [...orgIds]});
    await file.delete({ignoreNotFound: true});
  });
}

async function inspectCommunityAccountData(db, bucket, uid) {
  const checks = [];
  const queryCheck = async (name, query) => checks.push({category: `community:${name}`, clear: (await query.limit(1).get()).empty});
  for (const field of FEED_FIELDS) await queryCheck(`Feed:${field}`, db.collectionGroup("Feed").where(field, ["likes", "voters"].includes(field) ? "array-contains" : "==", uid));
  for (const field of ["userId", "likes"]) await queryCheck(`Comments:${field}`, db.collectionGroup("Comments").where(field, field === "likes" ? "array-contains" : "==", uid));
  for (const field of EVENT_FIELDS) await queryCheck(`Events:${field}`, db.collection("Events").where(field, ["likes", "accessList"].includes(field) ? "array-contains" : "==", uid));
  const job = await db.collection("account_deletion_jobs").doc(uid).get();
  let uploadsClear = true;
  for (const orgId of job.get("communityOrganizationIds") || []) await groupUploads(bucket, orgId, uid, async () => { uploadsClear = false; });
  checks.push({category: "community:group_uploads", clear: uploadsClear});
  return checks;
}
module.exports = {cleanupCommunityAccountData, inspectCommunityAccountData, withoutUid, isOwnedUpload};
