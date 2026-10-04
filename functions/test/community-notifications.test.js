"use strict";
// These unit fixtures use injected providers; model ordinary production policy explicitly.
process.env.GCLOUD_PROJECT = "orgami-66nxok";
delete process.env.GOOGLE_CLOUD_PROJECT;
const test = require("node:test");
const assert = require("node:assert/strict");
const {memoryAdmin} = require("./helpers/community-memory");
const {createLegacyNotificationSender, canNotifyNearby} = require("../notifications/legacy-delivery");
const {createCommunityNotificationHandlers} = require("../community/notifications");
const {tokenHash} = require("../notifications/push-tokens");
function bind(admin, uid, token) {
  const installationHash = tokenHash(`test-installation-${uid}`);
  admin.db.values.set(`PushTokenBindings/${tokenHash(token)}`, {ownerUid: uid, installationHash, generation: 1, status: "active"});
  admin.db.values.set(`PushInstallations/${installationHash}`, {ownerUid: uid, tokenHash: tokenHash(token), generation: 1, operation: "register", invalidated: false});
}
const notices = (values, uid) => [...values.keys()].filter((key) => key.startsWith(`users/${uid}/notifications/`));
test("nearby broadcasts exclude private, pending and cancelled events", () => {
  const event = {private: false, status: "scheduled", eventLocation: {latitude: 1, longitude: 1}};
  assert.equal(canNotifyNearby(event), true);
  assert.equal(canNotifyNearby({...event, private: true}), false);
  for (const status of ["pending_approval", "rejected", "cancelled"]) assert.equal(canNotifyNearby({...event, status}), false);
});
test("join requests select approved lowercase admins and deduplicate replay", async () => {
  const admin = memoryAdmin({"Organizations/group/JoinRequests/member": {status: "pending"},
    "Organizations/group/Members/admin": {role: "admin", status: "approved"},
    "Organizations/group/Members/pending": {role: "Admin", status: "pending"},
    "Organizations/group/Members/ordinary": {role: "Member", status: "approved"}});
  const handler = createCommunityNotificationHandlers(admin).joinRequest;
  const event = {id: "same-event", params: {orgId: "group", userId: "member"}, data: await admin.db.doc("Organizations/group/JoinRequests/member").get()};
  await Promise.all([handler(event), handler(event)]);
  assert.equal(notices(admin.db.values, "admin").length, 1);
  assert.equal(notices(admin.db.values, "pending").length, 0);
  assert.equal(notices(admin.db.values, "ordinary").length, 0);
});
test("declining a join request produces one requester notice, respecting preferences and deletion", async () => {
  const admin = memoryAdmin({"Organizations/group": {name: "Group"}, "Organizations/group/JoinRequests/member": {userId: "member", status: "declined"}});
  const handler = createCommunityNotificationHandlers(admin).joinDecision;
  const event = {id: "decline-one", params: {orgId: "group", userId: "member"}, data: {
    before: {exists: true, get: () => "pending"}, after: await admin.db.doc("Organizations/group/JoinRequests/member").get()}};
  await handler(event); await handler(event);
  assert.equal(notices(admin.db.values, "member").length, 1);
  admin.db.values.set("users/member/settings/notifications", {organizationUpdates: false});
  await handler({...event, id: "decline-two"});
  assert.equal(notices(admin.db.values, "member").length, 1);
  admin.db.values.delete("users/member/settings/notifications");
  admin.db.values.set("account_deletion_jobs/member", {status: "running"});
  await handler({...event, id: "decline-three"});
  assert.equal(notices(admin.db.values, "member").length, 1);
});
test("uncertain push outcomes retain a durable marker and never resend on trigger replay", async (t) => {
  const before = process.env.FUNCTIONS_EMULATOR;
  process.env.FUNCTIONS_EMULATOR = "false";
  t.after(() => { if (before === undefined) delete process.env.FUNCTIONS_EMULATOR; else process.env.FUNCTIONS_EMULATOR = before; });
  const admin = memoryAdmin({"users/member": {fcmToken: "fixture-token"}});
  bind(admin, "member", "fixture-token");
  let calls = 0;
  admin.messaging = () => ({send: async () => { calls++; throw Error("Acknowledgement lost"); }});
  const send = createLegacyNotificationSender(admin);
  const notice = {type: "org_update", title: "Update", body: "Body"};
  await send("member", notice, admin.db, "source");
  await send("member", notice, admin.db, "source");
  assert.equal(calls, 1); assert.equal(notices(admin.db.values, "member").length, 1);
  assert.equal([...admin.db.values.entries()].find(([key]) => key.startsWith("LegacyNotificationDeliveries/"))[1].state, "delivery_unknown");
});

test("push handoff suppresses a token changed after reservation", async (t) => {
  const before = process.env.FUNCTIONS_EMULATOR;
  process.env.FUNCTIONS_EMULATOR = "false";
  t.after(() => { if (before === undefined) delete process.env.FUNCTIONS_EMULATOR; else process.env.FUNCTIONS_EMULATOR = before; });
  const admin = memoryAdmin({"users/member": {fcmToken: "old-device"}});
  bind(admin, "member", "old-device");
  let calls = 0, transactions = 0;
  admin.messaging = () => ({send: async () => { calls++; }});
  const run = admin.db.runTransaction;
  admin.db.runTransaction = async (work) => {
    const result = await run(work);
    if (++transactions === 1) admin.db.values.set("users/member", {fcmToken: "new-device"});
    return result;
  };
  const result = await createLegacyNotificationSender(admin)("member", {type: "org_update", title: "Update", body: "Body"}, admin.db, "changed-token");
  assert.equal(result.status, "suppressed"); assert.equal(calls, 0);
  assert.equal([...admin.db.values.entries()].find(([key]) => key.startsWith("LegacyNotificationDeliveries/"))[1].state, "suppressed");
});
