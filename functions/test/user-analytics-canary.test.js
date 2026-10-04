"use strict";
const assert = require("node:assert/strict");
const test = require("node:test");
const {cleanupCanaryFixtures, createCanaryReminderPreferences} = require("../tools/canary-user-analytics");
const {reminderDocumentId} = require("../notifications/scheduled-reminders");

const suffix = "1790546063855";
const ownerId = `__analytics_canary_owner_${suffix}`;
const eventIds = ["first", "second"].map((part) => `__analytics_canary_${part}_${suffix}`);
const queuePaths = eventIds.map((id) => `scheduledNotifications/${reminderDocumentId(id, ownerId)}`);
const settingsPath = `users/${ownerId}/settings/notifications`;

function database(entries) {
  const data = new Map(Object.entries(entries));
  const operations = [];
  const ref = (path) => ({path, collection: (name) => ({doc: (id) => ref(`${path}/${name}/${id}`)}),
    get: async () => snapshot(path), delete: async () => {operations.push(["delete", path]); data.delete(path);}});
  const snapshot = (path) => ({ref: ref(path), exists: data.has(path), data: () => data.get(path), get: (key) => data.get(path)?.[key]});
  const db = {collection: (name) => ({doc: (id) => ref(`${name}/${id}`)}),
    runTransaction: async (fn) => {
      const writes = [];
      const result = await fn({get: async (reference) => snapshot(reference.path),
        delete: (reference) => writes.push(["delete", reference.path]),
        create: (reference, value) => {assert.equal(data.has(reference.path), false); writes.push(["create", reference.path, value]);}});
      for (const [kind, path, value] of writes) {
        operations.push([kind, path]);
        if (kind === "delete") data.delete(path); else data.set(path, value);
      }
      return result;
    }};
  return {db, data, operations};
}

function fixture() {
  return Object.fromEntries([
    ...eventIds.map((id) => [`Events/${id}`, {customerUid: ownerId, syntheticCanary: true}]),
    ...eventIds.map((id, i) => [queuePaths[i], {eventId: id, userId: ownerId, type: "event_reminder",
      deliveryState: "cancelled", terminalReason: "event_deleted", sent: false, leaseUntil: null, pushDispatching: false, claimId: null}]),
    [settingsPath, {eventReminders: false, syntheticCanary: true, canaryOwnerId: ownerId}],
    ["scheduledNotifications/unrelated", {type: "event_reminder", userId: "real-user"}],
  ]);
}

test("analytics canary cleanup removes its two reminders after events, preserving unrelated rows", async () => {
  const {db, data, operations} = database(fixture());
  await cleanupCanaryFixtures(db, ownerId, eventIds, {settingsCreated: true});
  for (const path of queuePaths) assert.equal(data.has(path), false, `orphan reminder retained: ${path}`);
  assert.equal(data.has(settingsPath), false);
  assert.equal(data.has("scheduledNotifications/unrelated"), true);
  const lastEventDelete = Math.max(...eventIds.map((id) => operations.findIndex(([, path]) => path === `Events/${id}`)));
  const firstQueueDelete = Math.min(...queuePaths.map((name) => operations.findIndex(([, path]) => path === name)));
  assert.ok(firstQueueDelete > lastEventDelete);
});

test("canary disables reminders with create-only preferences before any events exist", async () => {
  const {db, data, operations} = database({});
  await createCanaryReminderPreferences(db, ownerId, eventIds);
  assert.deepEqual(data.get(settingsPath), {eventReminders: false, syntheticCanary: true, canaryOwnerId: ownerId});
  assert.deepEqual(operations, [["create", settingsPath]]);
  await assert.rejects(createCanaryReminderPreferences(db, ownerId, eventIds), /already in use/);
});

test("preference setup preserves a preexisting canary event or account", async () => {
  for (const path of [`Events/${eventIds[0]}`, `Customers/${ownerId}`, `users/${ownerId}`]) {
    const {db, data, operations} = database({[path]: {preserve: true}});
    await assert.rejects(createCanaryReminderPreferences(db, ownerId, eventIds), /already in use/);
    assert.deepEqual(operations, []);
    assert.equal(data.has(settingsPath), false);
  }
});

test("cleanup preserves a changed event owner and never broadens the fixture identity", async () => {
  const {db, data, operations} = database({...fixture(), [`Events/${eventIds[0]}`]: {customerUid: "someone-else", syntheticCanary: true}});
  await assert.rejects(cleanupCanaryFixtures(db, ownerId, eventIds), /ownership changed/);
  await assert.rejects(cleanupCanaryFixtures(db, "real-user", eventIds), /Exact analytics/);
  assert.deepEqual(operations, []);
  assert.equal(data.has(queuePaths[0]), true);
});

test("active or unknown reminder dispatch remains available for review", async () => {
  for (const change of [{deliveryState: "processing"}, {deliveryState: "unknown"}, {pushDispatching: true},
    {claimId: "live-claim"}, {leaseUntil: {toMillis: () => Date.now() + 60000}}, {userId: "other-user"}]) {
    const entries = fixture();
    entries[queuePaths[0]] = {...entries[queuePaths[0]], ...change};
    const {db, data} = database(entries);
    await assert.rejects(cleanupCanaryFixtures(db, ownerId, eventIds, {settingsCreated: true}), /requires review/);
    assert.equal(data.has(queuePaths[0]), true);
    assert.equal(data.has(queuePaths[1]), true);
    assert.equal(data.has(settingsPath), true);
  }
});

test("cleanup deletes only the preference created by this invocation and preserves changes", async () => {
  const unowned = database(fixture());
  await cleanupCanaryFixtures(unowned.db, ownerId, eventIds);
  assert.equal(unowned.data.has(settingsPath), true);
  const changed = fixture();
  changed[settingsPath].otherPreference = true;
  const owned = database(changed);
  await assert.rejects(cleanupCanaryFixtures(owned.db, ownerId, eventIds, {settingsCreated: true}), /preference changed/);
  assert.equal(owned.data.has(settingsPath), true);
  assert.equal(owned.data.has(queuePaths[0]), true);
});
