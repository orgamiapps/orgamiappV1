"use strict";
// These unit fixtures use injected providers; model ordinary production policy explicitly.
process.env.GCLOUD_PROJECT = "orgami-66nxok";
delete process.env.GOOGLE_CLOUD_PROJECT;
const test = require("node:test");
const assert = require("node:assert/strict");
const {memoryAdmin} = require("./helpers/community-memory");
const {createDiscoveryNotificationHandlers, eligible, nearbyInterest} = require("../discovery/notifications");
const {tokenHash} = require("../notifications/push-tokens");
const {ROOT_DOCUMENTS} = require("../account/dispositions");
const now = Date.parse("2026-10-03T14:00:00Z");
const ready = now + 45 * 60 * 1000;
const rootPath = "discovery_notification_batches/member";
function fixture(t, ids = ["one"]) {
  const before = process.env.FUNCTIONS_EMULATOR;
  process.env.FUNCTIONS_EMULATOR = "false";
  t.after(() => { if (before === undefined) delete process.env.FUNCTIONS_EMULATOR; else process.env.FUNCTIONS_EMULATOR = before; });
  const admin = memoryAdmin({"users/member": {fcmToken: "fixture-token"}, "Customers/owner/followers/member": {userId: "member"}});
  const installationHash = tokenHash("discovery-installation");
  admin.db.values.set(`PushTokenBindings/${tokenHash("fixture-token")}`, {ownerUid: "member", installationHash, generation: 1, status: "active"});
  admin.db.values.set(`PushInstallations/${installationHash}`, {ownerUid: "member", tokenHash: tokenHash("fixture-token"), generation: 1, operation: "register"});
  for (const id of ids) admin.db.values.set(`Events/${id}`, {title: `Original ${id}`, private: false, status: "scheduled", customerUid: "owner",
    selectedDateTime: new Date(now + 24 * 3600000), eventDuration: 2, locationType: "online"});
  const messages = [];
  admin.messaging = () => ({send: async (message) => { messages.push(message); return "provider-accepted"; }});
  return {admin, messages, handlers: createDiscoveryNotificationHandlers(admin), root: admin.db.doc(rootPath)};
}
function docs(admin, prefix) { return [...admin.db.values.entries()].filter(([key]) => key.startsWith(prefix)); }
function notices(admin) { return docs(admin, "users/member/notifications/"); }
function deliveries(admin) { return docs(admin, `${rootPath}/deliveries/`); }

test("discovery rechecks public visibility and current titles instead of queued cached content", async (t) => {
  const {admin, handlers, messages} = fixture(t, ["one", "private", "deleted", "rejected"]);
  for (const id of ["one", "private", "deleted", "rejected"]) await handlers.enqueue("member", id, now);
  admin.db.values.get("Events/one").title = "Current public title";
  admin.db.values.get("Events/private").private = true;
  admin.db.values.delete("Events/deleted");
  admin.db.values.get("Events/rejected").status = "rejected";
  await handlers.deliver(ready);
  assert.equal(notices(admin).length, 1);
  assert.deepEqual(notices(admin)[0][1].eventIds, ["one"]);
  assert.equal(messages.length, 1); assert.equal(messages[0].notification.body, "Current public title");
  assert.equal(messages[0].data.recipientUid, "member");
  assert.equal(deliveries(admin)[0][1].state, "accepted");
  assert.equal(await handlers.enqueue("member", "one", ready), false);
  await handlers.deliver(ready + 3600000);
  assert.equal(messages.length, 1); assert.equal(notices(admin).length, 1);
});

test("prepared work resumes after a crash and concurrent workers produce one inbox and one push", async (t) => {
  const {admin, handlers, root, messages} = fixture(t);
  await handlers.enqueue("member", "one", now);
  const claim = await handlers.prepare(root, ready);
  assert.equal((await claim.get()).get("state"), "prepared");
  assert.equal(notices(admin).length, 0);
  await Promise.all([handlers.deliverUser("member", ready), handlers.deliverUser("member", ready)]);
  assert.equal(messages.length, 1); assert.equal(notices(admin).length, 1);
  assert.equal((await root.get()).get("activeDeliveryId"), undefined);
});

test("lost handoff acknowledgement is durable unknown and never replays a possibly accepted push", async (t) => {
  const {admin, handlers, root, messages} = fixture(t, ["one", "two"]);
  await handlers.enqueue("member", "one", now);
  const claim = await handlers.prepare(root, ready);
  // Simulate process death immediately after the provider-attempt reservation.
  await handlers.reserveHandoff(root, claim, ready);
  await handlers.deliverUser("member", ready);
  assert.equal(messages.length, 0); assert.equal(notices(admin).length, 1);
  assert.equal((await claim.get()).get("state"), "delivery_unknown");
  await handlers.enqueue("member", "two", ready);
  admin.messaging = () => ({send: async (message) => { messages.push(message); throw Error("Provider acknowledgement lost"); }});
  await handlers.deliverUser("member", ready + 3600000);
  await handlers.deliverUser("member", ready + 7200000);
  assert.equal(messages.length, 1); assert.equal(notices(admin).length, 2);
  assert.equal(deliveries(admin).filter(([, data]) => data.state === "delivery_unknown").length, 2);
});

test("newly enqueued events survive an active delivery and do not postpone prior deadlines", async (t) => {
  const {admin, handlers, root, messages} = fixture(t, ["one", "two", "three"]);
  await handlers.enqueue("member", "one", now);
  await handlers.enqueue("member", "two", now + 1000);
  assert.equal((await root.get()).get("deliverAfter").getTime(), ready);
  const claim = await handlers.prepare(root, ready);
  await handlers.enqueue("member", "three", ready);
  assert.equal((await root.get()).get("activeDeliveryId"), claim.id);
  await handlers.deliverUser("member", ready);
  assert.equal(messages.length, 1);
  assert.equal((await root.get()).get("deliverAfter").getTime(), ready + 1000);
  await handlers.deliverUser("member", ready + 3600000);
  assert.equal(messages.length, 2);
  assert.deepEqual(notices(admin).map(([, data]) => data.eventIds).flat().sort(), ["one", "three", "two"]);
});

test("current preferences, follow state, account deletion and token ownership gate handoff", async (t) => {
  for (const reason of ["disabled", "unfollowed", "deleting", "token-transferred"]) {
    await t.test(reason, async (subtest) => {
      const {admin, handlers, root, messages} = fixture(subtest);
      await handlers.enqueue("member", "one", now);
      await handlers.prepare(root, ready);
      if (reason === "disabled") admin.db.values.set("users/member/settings/notifications", {newEvents: false});
      if (reason === "unfollowed") admin.db.values.delete("Customers/owner/followers/member");
      if (reason === "deleting") admin.db.values.set("account_deletion_jobs/member", {status: "running"});
      if (reason === "token-transferred") admin.db.values.get(`PushTokenBindings/${tokenHash("fixture-token")}`).ownerUid = "another";
      await handlers.deliverUser("member", ready);
      assert.equal(messages.length, 0);
      assert.equal(notices(admin).length, reason === "token-transferred" ? 1 : 0);
      if (reason === "deleting") {
        const size = admin.db.values.size;
        assert.equal(await handlers.enqueue("member", "one", ready), false);
        await handlers.deliverUser("member", ready + 3600000);
        assert.equal(admin.db.values.size, size);
      }
    });
  }
  assert.ok(ROOT_DOCUMENTS.includes("discovery_notification_batches"));
});

test("delivery drains bounded groups without losing the eleventh pending event", async (t) => {
  const ids = Array.from({length: 11}, (_, index) => `event-${index}`);
  const {admin, handlers, messages, root} = fixture(t, ids);
  for (const id of ids) await handlers.enqueue("member", id, now);
  await handlers.deliverUser("member", ready);
  assert.equal(messages.length, 1); assert.equal(notices(admin)[0][1].eventIds.length, 10);
  assert.ok((await root.get()).get("deliverAfter"));
  await handlers.deliverUser("member", ready);
  assert.equal(messages.length, 2);
  assert.equal(new Set(notices(admin).flatMap(([, data]) => data.eventIds)).size, 11);
  assert.equal((await root.get()).get("deliverAfter"), undefined);
});

test("legacy pending batches migrate without cached titles; sending batches remain unknown", async (t) => {
  const {admin, handlers, messages} = fixture(t, ["one", "two"]);
  admin.db.values.set(rootPath, {uid: "member", eventIds: ["one"], eventTitles: ["Untrusted cached title"], status: "pending", deliverAfter: new Date(now)});
  await handlers.deliverUser("member", ready);
  assert.equal(messages.length, 1); assert.equal(messages[0].notification.body, "Original one");
  // Represent an old crashed sending record. It is retained for review only.
  admin.db.values.set(rootPath, {uid: "member", eventIds: ["two"], eventTitles: ["Old cached title"], status: "sending", deliverAfter: new Date(now)});
  await handlers.deliverUser("member", ready);
  assert.equal(messages.length, 1);
  assert.equal(docs(admin, `${rootPath}/events/`).filter(([, data]) => data.status === "legacy_delivery_unknown").length, 1);
  assert.equal(admin.db.values.get(rootPath).eventTitles, undefined);
});

test("nearby eligibility requires explicit public active event and valid current opt-in coordinates", () => {
  const event = {private: false, status: "scheduled", selectedDateTime: new Date(now + 86400000), latitude: 35, longitude: -80, categories: ["Music"]};
  assert.equal(eligible(event, new Date(now)), true);
  for (const update of [{private: undefined}, {private: true}, {status: "rejected"}, {deleted: true}, {isHidden: true}]) assert.equal(eligible({...event, ...update}, new Date(now)), false);
  const preferences = {nearbyInterestNotifications: true, latitude: 35, longitude: -80, notificationRadius: 25, preferredCategories: ["music"]};
  assert.equal(nearbyInterest(event, preferences), true);
  assert.equal(nearbyInterest(event, {...preferences, nearbyInterestNotifications: false}), false);
  assert.equal(nearbyInterest(event, {...preferences, latitude: null}), false);
  assert.equal(nearbyInterest(event, {...preferences, preferredCategories: ["sports"]}), false);
});

test("nearby-only recipients use Customers discovery preferences and current opt-out suppresses delivery", async (t) => {
  const {admin, handlers, messages} = fixture(t);
  admin.db.values.delete("Customers/owner/followers/member");
  Object.assign(admin.db.values.get("Events/one"), {locationType: "in_person", latitude: 35, longitude: -80});
  const path = "Customers/member/Discovery/preferences";
  admin.db.values.set(path, {nearbyInterestNotifications: true, latitude: 35, longitude: -80, preferredCategories: []});
  assert.equal(await handlers.enqueue("member", "one", now), true);
  admin.db.values.get(path).nearbyInterestNotifications = false;
  await handlers.deliverUser("member", ready);
  assert.equal(messages.length, 0); assert.equal(notices(admin).length, 0);
});
