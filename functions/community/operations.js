"use strict";

const crypto = require("node:crypto");
const {onCall, HttpsError} = require("firebase-functions/v2/https");

const OPTIONS = {region: "us-central1", enforceAppCheck: process.env.FUNCTIONS_EMULATOR !== "true"};
const fail = (code, message) => { throw new HttpsError(code, message); };
const identifier = (value) => typeof value === "string" && /^[A-Za-z0-9._:-]{1,128}$/.test(value) ? value : fail("invalid-argument", "A valid identifier is required.");
function canonical(value) {
  if (Array.isArray(value)) return value.map(canonical);
  if (value && typeof value === "object") return Object.fromEntries(Object.keys(value).sort().map((key) => [key, canonical(value[key])]));
  return value;
}
const hash = (...values) => crypto.createHash("sha256").update(JSON.stringify(canonical(values))).digest("hex");
function text(value, max, required = false) {
  if ((value === null || value === undefined) && !required) return "";
  if (typeof value !== "string" || value.trim().length > max || (required && !value.trim())) fail("invalid-argument", "Text is missing or too long.");
  return value.trim();
}
function millis(value) {
  if (value?.toMillis) return value.toMillis();
  if (typeof value === "number") return value;
  if (typeof value === "string") return Date.parse(value);
  return NaN;
}
function list(value) { return [...new Set(Array.isArray(value) ? value.filter((uid) => typeof uid === "string") : [])]; }
function setLike(likes, uid, liked) {
  if (typeof liked !== "boolean") fail("invalid-argument", "Choose whether to like this item.");
  const next = new Set(list(likes));
  if (liked) next.add(uid); else next.delete(uid);
  if (next.size > 10000) fail("resource-exhausted", "This item has reached its interaction limit.");
  return [...next];
}
function votePoll(post, uid, optionIndex, now = Date.now()) {
  if (post.type !== "poll" || post.isClosed === true || post.isActive === false ||
      (post.endDate !== null && post.endDate !== undefined && (!Number.isFinite(millis(post.endDate)) || millis(post.endDate) <= now))) {
    fail("failed-precondition", "This poll is closed.");
  }
  if (!Array.isArray(post.options) || post.options.length < 2 || post.options.length > 20 ||
      !Number.isInteger(optionIndex) || optionIndex < 0 || optionIndex >= post.options.length) fail("invalid-argument", "Choose an available poll option.");
  const options = post.options.map((option) => ({...option, votes: list(option.votes)}));
  const votedElsewhere = options.some((option, index) => index !== optionIndex && option.votes.includes(uid));
  if (!post.allowMultipleVotes && votedElsewhere) fail("already-exists", "You have already voted in this poll.");
  options[optionIndex].votes = setLike(options[optionIndex].votes, uid, true);
  const voters = new Set();
  for (const option of options) {
    option.voteCount = option.votes.length;
    for (const voter of option.votes) voters.add(voter);
  }
  if (voters.size > 10000) fail("resource-exhausted", "This poll has reached its interaction limit.");
  return {options, voters: [...voters], totalVotes: voters.size};
}
function feedPost(input, uid, profile, isAdmin, stamp, admin) {
  if (!input || !["photo", "poll", "announcement"].includes(input.type)) fail("invalid-argument", "Choose a supported post type.");
  if (input.type !== "photo" && !isAdmin) fail("permission-denied", "Only group administrators can publish polls and announcements.");
  const post = {type: input.type, authorId: uid, createdBy: uid,
    authorName: text(profile.name || profile.displayName || profile.username || "Member", 200),
    authorRole: isAdmin ? "Admin" : "Member", createdAt: stamp(), likes: [], commentCount: 0,
    isPinned: isAdmin && input.isPinned === true, isHidden: false};
  if (input.type === "photo") {
    if (!Array.isArray(input.imageUrls) || input.imageUrls.length < 1 || input.imageUrls.length > 10 ||
        input.imageUrls.some((url) => typeof url !== "string" || url.length > 4096 || !/^https:\/\//.test(url))) fail("invalid-argument", "Add between one and ten image URLs.");
    post.caption = text(input.caption, 5000); post.imageUrls = input.imageUrls;
  } else if (input.type === "announcement") {
    post.title = text(input.title, 200, true); post.content = text(input.content, 10000, true);
  } else {
    post.question = text(input.question, 500, true);
    if (!Array.isArray(input.options) || input.options.length < 2 || input.options.length > 20) fail("invalid-argument", "A poll needs two to twenty options.");
    post.options = input.options.map((option) => ({text: text(typeof option === "string" ? option : option?.text, 200, true), votes: [], voteCount: 0}));
    post.allowMultipleVotes = input.allowMultipleVotes === true;
    post.totalVotes = 0; post.voters = []; post.isActive = true; post.isClosed = false;
    const end = (input.endDate === null || input.endDate === undefined) ? null : millis(input.endDate);
    if (end !== null && (!Number.isFinite(end) || end <= Date.now())) fail("invalid-argument", "Poll end time must be in the future.");
    post.endDate = end === null ? null : admin.firestore.Timestamp.fromMillis(end);
  }
  return post;
}

function createCommunityOperations(admin) {
  const db = admin.firestore();
  const stamp = () => admin.firestore.FieldValue.serverTimestamp();
  const communityMutationV1 = onCall(OPTIONS, async (request) => {
    const uid = request.auth?.uid;
    if (!uid || request.auth.token?.firebase?.sign_in_provider === "anonymous") fail("unauthenticated", "Sign in to participate.");
    const data = request.data || {};
    const action = data.action;
    const feedbackAction = ["submitFeedback", "feedbackStatus", "submitAppFeedback"].includes(action);
    const appFeedback = action === "submitAppFeedback";
    const eventId = (data.eventId === null || data.eventId === undefined) ? null : identifier(data.eventId);
    const orgId = (data.organizationId === null || data.organizationId === undefined) ? null : identifier(data.organizationId);
    const postId = (data.postId === null || data.postId === undefined) ? null : identifier(data.postId);
    const commentId = (data.commentId === null || data.commentId === undefined) ? null : identifier(data.commentId);
    const eventRef = eventId ? db.collection("Events").doc(eventId) : null;
    const orgRef = orgId ? db.collection("Organizations").doc(orgId) : null;
    const postRef = eventRef || (orgRef && postId ? orgRef.collection("Feed").doc(postId) : null);
    if (!appFeedback && !postRef) fail("invalid-argument", "An event or group post is required.");
    const feedbackId = crypto.randomUUID();
    // Rate accounting is separate from the mutation transaction so every
    // validation/read below still precedes its writes.
    if (action !== "feedbackStatus") await db.runTransaction(async (tx) => {
      const ref = db.collection("service_rate_limits").doc(`community_${hash(uid)}`);
      const current = await tx.get(ref);
      const now = Date.now();
      const active = now - Number(current.get("windowStartedAtMs") || 0) < 60000;
      const count = active ? Number(current.get("count") || 0) : 0;
      if (count >= 120) fail("resource-exhausted", "Too many attempts. Try again shortly.");
      tx.set(ref, {count: count + 1, windowStartedAtMs: active ? current.get("windowStartedAtMs") : now, expiresAt: new Date(now + 120000)});
    });
    return db.runTransaction(async (tx) => {
      const [deletion, profile, event, organization, member, post] = await Promise.all([
        tx.get(db.collection("account_deletion_jobs").doc(uid)), tx.get(db.collection("Customers").doc(uid)),
        eventRef ? tx.get(eventRef) : null, orgRef ? tx.get(orgRef) : null,
        orgRef ? tx.get(orgRef.collection("Members").doc(uid)) : null,
        !eventRef && postRef ? tx.get(postRef) : null,
      ]);
      if (deletion.exists) fail("failed-precondition", "Account deletion is in progress.");
      if (eventRef && !event.exists) fail("not-found", "Event not found.");
      const eventData = event?.data() || {};
      if (orgRef && (!organization.exists || (eventRef && eventData.organizationId !== orgId))) fail("not-found", "Group content not found.");
      const isMember = member?.get("status") === "approved";
      const isAdmin = isMember && ["admin", "owner"].includes(String(member.get("role") || "").toLowerCase());
      const eventHost = eventData.customerUid === uid || (eventData.coHosts || []).includes(uid);
      if (orgRef && !isMember) fail("permission-denied", "Approved group membership is required.");
      if (eventRef && eventData.private === true && !eventHost && !isAdmin && !(eventData.accessList || []).includes(uid)) fail("permission-denied", "Event access is required.");
      if (!eventRef && !orgRef && !appFeedback) fail("invalid-argument", "A group is required.");
      if (!feedbackAction && !eventRef && !post.exists && action !== "createFeed") fail("not-found", "Post not found.");
      const target = eventRef ? eventData : post?.data() || {};
      if (target.deleted === true) {
        if (action === "deleteFeed" && (isAdmin || target.authorId === uid || target.createdBy === uid)) return {success: true};
        fail("not-found", "This content has been deleted.");
      }
      if (!feedbackAction && target.isHidden === true && !isAdmin && !eventHost) fail("permission-denied", "This content is hidden.");

      // A private marker preserves anonymous-display feedback without publishing
      // its actor ID. It also serializes all retries for one event and account.
      if (feedbackAction) {
        const markerRef = db.collection("feedback_submissions").doc(hash(uid, appFeedback ? "app" : eventId, appFeedback ? identifier(data.submissionId) : "event"));
        const marker = await tx.get(markerRef);
        if (action === "feedbackStatus") return {submitted: marker.exists};
        const rating = data.rating;
        if (!Number.isInteger(rating) || rating < 1 || rating > 5 || typeof data.isAnonymous !== "boolean") fail("invalid-argument", "Choose a rating from one to five.");
        const comment = text(data.comment, 4000);
        const contact = appFeedback && !data.isAnonymous ? {
          name: text(data.name || profile.get("name"), 200), email: text(data.email || profile.get("email"), 320),
          contactNumber: text(data.contactNumber, 80),
        } : {};
        const fingerprint = hash(rating, comment, data.isAnonymous, contact);
        if (marker.exists) {
          if (marker.get("fingerprint") !== fingerprint) fail("already-exists", "Feedback has already been submitted.");
          return {success: true, feedbackId: marker.get("feedbackId")};
        }
        if (!appFeedback) {
          const attended = await tx.get(db.collection("Attendance").where("eventId", "==", eventId).where("customerUid", "==", uid));
          if (!attended.docs.some((doc) => doc.get("voided") !== true && doc.get("status") !== "voided")) fail("permission-denied", "Only attendees can leave event feedback.");
        }
        const feedback = {rating, comment: comment || null, isAnonymous: data.isAnonymous, userId: data.isAnonymous ? null : uid, timestamp: stamp()};
        if (appFeedback) {
          Object.assign(feedback, contact);
        } else feedback.eventId = eventId;
        tx.create(db.collection(appFeedback ? "app_feedback" : "event_feedback").doc(feedbackId), feedback);
        tx.create(markerRef, {userId: uid, feedbackId, fingerprint, createdAt: stamp()});
        return {success: true, feedbackId};
      }

      if (["setEventAccess", "setEventCoHost", "approveAccessRequest", "rejectAccessRequest"].includes(action)) {
        if (!eventRef || eventData.customerUid !== uid) fail("permission-denied", "Only the event owner can manage access and co-hosts.");
        const targetUid = identifier(data.userId);
        if (targetUid === uid) fail("invalid-argument", "The event owner cannot be changed through access settings.");
        const decision = ["approveAccessRequest", "rejectAccessRequest"].includes(action);
        const enabled = action === "setEventAccess" ? data.allowed : action === "setEventCoHost" ? data.enabled : action === "approveAccessRequest";
        if (typeof enabled !== "boolean") fail("invalid-argument", "Choose whether access is enabled.");
        const accessRef = eventRef.collection("AccessRequests").doc(targetUid);
        const [targetProfile, targetDeletion, accessRequest] = await Promise.all([
          tx.get(db.collection("Customers").doc(targetUid)), tx.get(db.collection("account_deletion_jobs").doc(targetUid)), decision ? tx.get(accessRef) : null,
        ]);
        if (enabled && (!targetProfile.exists || targetDeletion.exists)) fail("failed-precondition", "This account is unavailable.");
        if (decision && (!accessRequest.exists || accessRequest.get("userId") !== targetUid)) fail("not-found", "Access request not found.");
        if (decision && !["pending", enabled ? "approved" : "declined"].includes(accessRequest.get("status"))) fail("failed-precondition", "This access request has already been decided.");
        const field = action === "setEventCoHost" ? "coHosts" : "accessList";
        const current = new Set(list(eventData[field]));
        if (enabled) current.add(targetUid); else current.delete(targetUid);
        if (current.size > 1000) fail("resource-exhausted", "The event access list is full.");
        tx.update(eventRef, {[field]: [...current]});
        if (decision) tx.update(accessRef, {status: enabled ? "approved" : "declined", decidedBy: uid, decidedAt: stamp()});
      } else if (action === "createFeed") {
        if (eventRef) fail("invalid-argument", "Choose a group feed.");
        const fingerprint = hash(data.post);
        if (post.exists) {
          if (post.get("authorId") !== uid || post.get("creationFingerprint") !== fingerprint) fail("already-exists", "This post identifier is already in use.");
          return {success: true, postId};
        }
        tx.create(postRef, {...feedPost(data.post, uid, profile.data() || {}, isAdmin, stamp, admin), creationFingerprint: fingerprint});
      } else if (action === "votePoll") {
        if (eventRef) fail("invalid-argument", "Choose a group poll.");
        tx.update(postRef, votePoll(target, uid, data.optionIndex));
      } else if (["setLike", "setEventLike"].includes(action)) {
        const ref = commentId ? postRef.collection("Comments").doc(commentId) : postRef;
        const current = commentId ? await tx.get(ref) : eventRef ? event : post;
        if (!current.exists) fail("not-found", "Content not found.");
        tx.update(ref, {likes: setLike(current.get("likes"), uid, data.liked)});
      } else if (action === "addComment") {
        identifier(commentId);
        const comment = text(data.comment, 4000, true);
        const ref = postRef.collection("Comments").doc(commentId);
        const current = await tx.get(ref);
        if (current.exists) {
          if (current.get("userId") !== uid || current.get("comment") !== comment) fail("already-exists", "This comment identifier is already in use.");
          return {success: true, commentId};
        }
        tx.create(ref, {userId: uid, userName: text(profile.get("name") || profile.get("username") || "Member", 200),
          userPhotoUrl: profile.get("profilePictureUrl") || null, comment, createdAt: stamp(), likes: []});
        tx.update(postRef, {commentCount: Math.max(0, Number(target.commentCount) || 0) + 1});
      } else if (action === "deleteComment") {
        identifier(commentId);
        const ref = postRef.collection("Comments").doc(commentId);
        const current = await tx.get(ref);
        if (!current.exists) return {success: true};
        if (current.get("userId") !== uid && !isAdmin && !eventHost) fail("permission-denied", "Only the author or moderator can delete this comment.");
        tx.delete(ref); tx.update(postRef, {commentCount: Math.max(0, (Number(target.commentCount) || 0) - 1)});
      } else if (["updateFeed", "updateEvent"].includes(action)) {
        if (!isAdmin) fail("permission-denied", "Group administrator access is required.");
        if ((action === "updateEvent") !== Boolean(eventRef)) fail("invalid-argument", "Choose the correct content type.");
        const updates = data.updates;
        const allowed = eventRef ? ["isPinned", "pinnedOrder", "isHidden"] : ["isPinned", "pinnedOrder", "isHidden", "isClosed"];
        if (!updates || typeof updates !== "object" || !Object.keys(updates).length || Object.keys(updates).some((field) => !allowed.includes(field))) fail("invalid-argument", "Unsupported moderation change.");
        for (const [field, value] of Object.entries(updates)) {
          if (field === "pinnedOrder" ? !Number.isSafeInteger(value) || value < 0 : typeof value !== "boolean") fail("invalid-argument", "Invalid moderation value.");
        }
        if ("isClosed" in updates && target.type !== "poll") fail("invalid-argument", "Only polls can be closed.");
        tx.update(postRef, {...updates, moderatedBy: uid, moderatedAt: stamp()});
      } else if (["approveEvent", "rejectEvent"].includes(action)) {
        if (!eventRef || !isAdmin) fail("permission-denied", "Group administrator access is required.");
        const desired = action === "approveEvent" ? "scheduled" : "rejected";
        if (eventData.status === desired && eventData.moderatedBy === uid) return {success: true};
        if (eventData.status !== "pending_approval") fail("failed-precondition", "Only pending events can be approved or rejected.");
        tx.update(eventRef, {status: desired, moderatedBy: uid, moderatedAt: stamp(), eventRevision: (Number(eventData.eventRevision) || 0) + 1});
      } else if (action === "deleteFeed") {
        if (eventRef || (!isAdmin && target.authorId !== uid && target.createdBy !== uid)) fail("permission-denied", "Only the author or moderator can delete this post.");
        // Tombstone keeps child comments inaccessible and prevents orphaned data
        // from becoming visible if a client reuses the original post identifier.
        tx.update(postRef, {isHidden: true, deleted: true, deletedBy: uid, deletedAt: stamp()});
      } else fail("invalid-argument", "Unknown community action.");
      return {success: true, ...(postId ? {postId} : {}), ...(commentId ? {commentId} : {})};
    });
  });
  return {communityMutationV1};
}

module.exports = {createCommunityOperations, votePoll, setLike, feedPost};
