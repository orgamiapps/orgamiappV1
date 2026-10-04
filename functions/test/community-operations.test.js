"use strict";
const test = require("node:test");
const assert = require("node:assert/strict");
const {memoryAdmin} = require("./helpers/community-memory");
const {createCommunityOperations, votePoll} = require("../community/operations");
const request = (uid, data, provider = "password") => ({auth: {uid, token: {firebase: {sign_in_provider: provider}}}, data});
function fixture() {
  const admin = memoryAdmin({"Organizations/group": {createdBy: "owner"},
    "Organizations/group/Members/owner": {role: "Admin", status: "approved"},
    "Organizations/group/Members/member": {role: "Member", status: "approved"},
    "Organizations/group/Members/pending": {role: "Member", status: "pending"},
    "Customers/member": {name: "Real Member"},
    "Events/event": {customerUid: "owner", organizationId: "group", private: false, status: "pending_approval"},
  });
  const operation = createCommunityOperations(admin).communityMutationV1;
  const call = (uid, action, data = {}) => operation.run(request(uid, {organizationId: "group", postId: "post", action, ...data}));
  return {admin, call, values: admin.db.values, operation};
}
const photo = {type: "photo", caption: "A photo", imageUrls: ["https://example.test/image.jpg"], authorId: "forged", likes: ["fake"], isPinned: true};
const poll = {type: "poll", question: "When?", options: [{text: "Today"}, {text: "Tomorrow"}]};

test("feed creation binds actor, checks approved membership and initializes protected counts", async () => {
  const {call, values, operation} = fixture();
  await assert.rejects(call("pending", "createFeed", {post: photo}), {code: "permission-denied"});
  await assert.rejects(call("outsider", "createFeed", {post: photo}), {code: "permission-denied"});
  await assert.rejects(operation.run(request("member", {action: "createFeed", organizationId: "group", postId: "anon", post: photo}, "anonymous")), {code: "unauthenticated"});
  await call("member", "createFeed", {post: photo});
  const post = values.get("Organizations/group/Feed/post");
  assert.equal(post.authorId, "member"); assert.equal(post.createdBy, "member"); assert.equal(post.authorName, "Real Member");
  assert.deepEqual(post.likes, []); assert.equal(post.isPinned, false);
  await call("member", "createFeed", {post: photo});
  await assert.rejects(call("member", "createFeed", {post: {...photo, caption: "different"}}), {code: "already-exists"});
  await assert.rejects(call("member", "createFeed", {postId: "poll", post: poll}), {code: "permission-denied"});
});
test("concurrent repeated comments and likes preserve identity and exact counts", async () => {
  const {call, values} = fixture();
  await call("member", "createFeed", {post: photo});
  await Promise.all([call("member", "addComment", {commentId: "comment", comment: "Hello"}), call("member", "addComment", {commentId: "comment", comment: "Hello"})]);
  assert.equal(values.get("Organizations/group/Feed/post").commentCount, 1);
  await assert.rejects(call("owner", "addComment", {commentId: "comment", comment: "Overwrite"}), {code: "already-exists"});
  await Promise.all([call("member", "setLike", {liked: true}), call("owner", "setLike", {liked: true})]);
  await call("member", "setLike", {liked: true});
  assert.deepEqual(values.get("Organizations/group/Feed/post").likes.sort(), ["member", "owner"]);
  await call("member", "deleteComment", {commentId: "comment"});
  await call("member", "deleteComment", {commentId: "comment"});
  assert.equal(values.get("Organizations/group/Feed/post").commentCount, 0);
});
test("poll votes are actor-bound, duplicate-safe and respect close, end and option bounds", async () => {
  const {call, values} = fixture();
  await call("owner", "createFeed", {post: poll});
  await Promise.all([call("member", "votePoll", {optionIndex: 0}), call("member", "votePoll", {optionIndex: 0})]);
  assert.equal(values.get("Organizations/group/Feed/post").totalVotes, 1);
  await assert.rejects(call("member", "votePoll", {optionIndex: 1}), {code: "already-exists"});
  await assert.rejects(call("member", "votePoll", {optionIndex: 99}), {code: "invalid-argument"});
  await call("owner", "updateFeed", {updates: {isClosed: true}});
  await assert.rejects(call("member", "votePoll", {optionIndex: 0}), {code: "failed-precondition"});
  assert.throws(() => votePoll({...poll, endDate: Date.now() - 1}, "member", 0), {code: "failed-precondition"});
});
test("moderation cannot change lifecycle, other groups, counters or auth; deletion blocks interactions", async () => {
  const {call, values} = fixture();
  await call("member", "createFeed", {post: photo});
  await assert.rejects(call("member", "updateFeed", {updates: {isPinned: true}}), {code: "permission-denied"});
  await assert.rejects(call("owner", "updateFeed", {updates: {likes: ["forged"]}}), {code: "invalid-argument"});
  await assert.rejects(call("owner", "updateEvent", {eventId: "event", updates: {status: "cancelled"}}), {code: "invalid-argument"});
  await call("owner", "approveEvent", {eventId: "event"});
  assert.equal(values.get("Events/event").status, "scheduled");
  await call("owner", "approveEvent", {eventId: "event"});
  await assert.rejects(call("owner", "rejectEvent", {eventId: "event"}), {code: "failed-precondition"});
  await call("member", "deleteFeed"); await call("member", "deleteFeed");
  await assert.rejects(call("owner", "addComment", {commentId: "late", comment: "Late"}), {code: "not-found"});
  values.set("account_deletion_jobs/member", {status: "requested"});
  await assert.rejects(call("member", "createFeed", {postId: "new", post: photo}), {code: "failed-precondition"});
});
test("anonymous-display feedback is attendee-bound, private, validated and duplicate-safe", async () => {
  const {operation, values} = fixture();
  const input = {action: "submitFeedback", eventId: "event", rating: 5, comment: "Great", isAnonymous: true};
  await assert.rejects(operation.run(request("member", input)), {code: "permission-denied"});
  values.set("Attendance/member-event", {eventId: "event", customerUid: "member"});
  const [a, b] = await Promise.all([operation.run(request("member", input)), operation.run(request("member", input))]);
  assert.equal(a.feedbackId, b.feedbackId);
  assert.equal(values.get(`event_feedback/${a.feedbackId}`).userId, null);
  assert.equal((await operation.run(request("member", {action: "feedbackStatus", eventId: "event"}))).submitted, true);
  assert.equal((await operation.run(request("owner", {action: "feedbackStatus", eventId: "event"}))).submitted, false);
  await assert.rejects(operation.run(request("member", {...input, rating: "5"})), {code: "invalid-argument"});
  await assert.rejects(operation.run(request("member", {...input, rating: 6})), {code: "invalid-argument"});
  await assert.rejects(operation.run(request("member", {...input, rating: 4})), {code: "already-exists"});
});
test("app feedback preserves anonymous display and idempotent submission identity", async () => {
  const {operation, values} = fixture();
  const input = {action: "submitAppFeedback", submissionId: "form-submit", rating: 4, comment: "Helpful", isAnonymous: true, email: "hidden@example.test"};
  const a = await operation.run(request("member", input));
  const b = await operation.run(request("member", input));
  assert.equal(a.feedbackId, b.feedbackId);
  const data = values.get(`app_feedback/${a.feedbackId}`);
  assert.equal(data.userId, null); assert.equal(data.email, undefined);
});

test("only the owner can grant cohosts or decide access requests, with target-deletion checks", async () => {
  const {operation, values} = fixture();
  values.get("Events/event").coHosts = ["member"];
  values.set("Events/event/AccessRequests/member", {userId: "member", status: "pending"});
  const invoke = (uid, action, fields) => operation.run(request(uid, {eventId: "event", action, ...fields}));
  await assert.rejects(invoke("member", "setEventCoHost", {userId: "owner", enabled: true}), {code: "permission-denied"});
  await assert.rejects(invoke("owner", "setEventAccess", {userId: "owner", allowed: false}), {code: "invalid-argument"});
  await invoke("owner", "approveAccessRequest", {userId: "member"});
  await invoke("owner", "approveAccessRequest", {userId: "member"});
  assert.deepEqual(values.get("Events/event").accessList, ["member"]);
  assert.equal(values.get("Events/event/AccessRequests/member").status, "approved");
  await assert.rejects(invoke("owner", "rejectAccessRequest", {userId: "member"}), {code: "failed-precondition"});
  values.set("account_deletion_jobs/member", {status: "requested"});
  await assert.rejects(invoke("owner", "setEventCoHost", {userId: "member", enabled: true}), {code: "failed-precondition"});
  await invoke("owner", "setEventCoHost", {userId: "member", enabled: false});
  assert.deepEqual(values.get("Events/event").coHosts, []);
});
