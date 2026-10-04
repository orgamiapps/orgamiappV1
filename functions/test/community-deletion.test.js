"use strict";
const test = require("node:test");
const assert = require("node:assert/strict");
const {memoryAdmin} = require("./helpers/community-memory");
const {cleanupCommunityAccountData, inspectCommunityAccountData, isOwnedUpload} = require("../community/account-deletion");
function fixture() {
  const admin = memoryAdmin({
    "account_deletion_jobs/member": {status: "running"},
    "Organizations/group/Members/member": {userId: "member"},
    "Organizations/group/Feed/own": {authorId: "member", createdBy: "member", authorEmail: "private@example.test", imageUrls: ["https://private.test"], caption: "Private", type: "photo", commentCount: 1},
    "Organizations/group/Feed/other": {authorId: "other", type: "poll", commentCount: 1, likes: ["member", "other"], voters: ["member", "other"], totalVotes: 2,
      options: [{text: "One", votes: ["member", "other"], voteCount: 2}]},
    "Organizations/group/Feed/own/Comments/survivor": {userId: "other", comment: "Preserve"},
    "Organizations/group/Feed/other/Comments/own": {userId: "member", comment: "Remove"},
    "Organizations/group/Feed/other/Comments/other": {userId: "other", comment: "Preserve", likes: ["member", "other"]},
    "Events/event": {customerUid: "other", likes: ["member", "other"], accessList: ["member", "other"], moderatedBy: "member"},
    "feedback_submissions/marker": {userId: "member", feedbackId: "anonymous"},
    "event_feedback/anonymous": {userId: null, eventId: "event", rating: 4, comment: "Private feedback"},
    "event_analytics/event": {feedbackAnalytics: {totalRatings: 2, averageRating: 4, commentSummaries: ["Private feedback", "Other feedback"]}},
  });
  const files = new Set(["groups/group/photos/member_123_0.jpg", "groups/group/photos/member_other_123_0.jpg", "groups/unrelated/photos/member_123_0.jpg"]);
  const reads = [];
  const bucket = {getFiles: async (options) => {
    reads.push(options.prefix);
    return [[...files].filter((name) => name.startsWith(options.prefix)).map((name) => ({name, delete: async () => { files.delete(name); }}))];
  }};
  let alive = true;
  const job = admin.db.doc("account_deletion_jobs/member");
  const lease = {transaction: async (callback) => admin.db.runTransaction(async (tx) => {
    if (!alive) throw Error("Lease lost");
    const result = await callback(tx);
    if (!alive) throw Error("Lease lost");
    return result;
  }), checkpoint: async (data) => lease.transaction(async (tx) => tx.set(job, data, {merge: true}))};
  return {admin, files, reads, bucket, counts: {job, lease}, loseLease: () => { alive = false; }};
}
test("community deletion removes owned content and identity while preserving others and reconciling counts", async () => {
  const f = fixture();
  await cleanupCommunityAccountData(f.admin.db, f.bucket, "member", f.counts);
  await cleanupCommunityAccountData(f.admin.db, f.bucket, "member", f.counts);
  const data = f.admin.db.values;
  const own = data.get("Organizations/group/Feed/own");
  assert.equal(own.deleted, true); assert.equal(own.authorId, undefined); assert.equal(own.authorEmail, undefined); assert.equal(own.caption, undefined);
  assert.equal(data.get("Organizations/group/Feed/own/Comments/survivor").comment, "Preserve");
  const other = data.get("Organizations/group/Feed/other");
  assert.equal(other.authorId, "other"); assert.equal(other.commentCount, 0); assert.deepEqual(other.voters, ["other"]); assert.equal(other.options[0].voteCount, 1);
  assert.deepEqual(data.get("Organizations/group/Feed/other/Comments/other").likes, ["other"]);
  assert.deepEqual(data.get("Events/event").accessList, ["other"]);
  assert.equal(data.has("event_feedback/anonymous"), false); assert.equal(data.has("feedback_submissions/marker"), false);
  assert.deepEqual(data.get("event_analytics/event").feedbackAnalytics.commentSummaries, ["Other feedback"]);
  assert.equal(f.files.has("groups/group/photos/member_123_0.jpg"), false);
  assert.equal(f.files.has("groups/group/photos/member_other_123_0.jpg"), true);
  assert.equal(f.files.has("groups/unrelated/photos/member_123_0.jpg"), true);
  assert.equal(f.reads.every((prefix) => prefix === "groups/group/photos/member_"), true);
  assert.equal((await inspectCommunityAccountData(f.admin.db, f.bucket, "member")).every((entry) => entry.clear), true);
});
test("community cleanup will not commit any mutation after a lost deletion lease", async () => {
  const f = fixture(); f.loseLease();
  await assert.rejects(cleanupCommunityAccountData(f.admin.db, f.bucket, "member", f.counts), /Lease lost/);
  assert.equal(f.admin.db.values.get("Organizations/group/Feed/own").authorId, "member");
  assert.equal(f.files.has("groups/group/photos/member_123_0.jpg"), true);
});
test("upload cleanup validates the entire uploader prefix and generated filename shape", () => {
  assert.equal(isOwnedUpload("groups/group/photos/member_123_0.jpg", "group", "member"), true);
  assert.equal(isOwnedUpload("groups/group/photos/member_other_123_0.jpg", "group", "member"), false);
  assert.equal(isOwnedUpload("groups/other/photos/member_123_0.jpg", "group", "member"), false);
});
