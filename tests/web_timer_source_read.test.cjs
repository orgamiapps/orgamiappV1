"use strict";
const test = require("node:test"), assert = require("node:assert/strict"), crypto = require("node:crypto");
const {memoryAdmin} = require("../functions/test/helpers/community-memory");
const {bindingId} = require("../functions/communications/qualification-isolation");
const {readOriginalTimerSource, sourceIdentity, fullTimestamp} = require("../tools/web_release_producers/timer-source-read");
const now = Date.parse("2026-10-04T12:00:00Z"), hash = (value) => crypto.createHash("sha256").update(JSON.stringify(value)).digest("hex");
function setup() {
  const runId = "webqa-20261004-aaaaaaaaaa", sourceSha = "a".repeat(40), candidateRunId = "1234";
  const candidate = {environment: "staging", projectId: "attendus-staging", sourceSha, candidateRunId};
  const fixture = {...candidate, runId, controlledRecipientDomain: "example.test", runStartsAt: new Date(now).toISOString(), eventClosesAt: new Date(now + 105 * 60000).toISOString(),
    event: {id: "pilot"}, privateEventId: "private", secondEventId: "second", canaryEventId: "canary", largeRoster: {eventId: "large"},
    communications: {reminderEventId: "reminder", discoveryEventId: "discovery", pendingPushId: `${runId}-pending`}};
  for (const role of ["owner", "attendee", "staff", "unauthorized", "administrator", "deletion"]) fixture[role] = {uid: `${runId}-${role}`, email: `${runId}-${role}@example.test`};
  fixture.conversationId = [fixture.owner.uid, fixture.attendee.uid].sort().join("_");
  const ids = ["pilot", "private", "second", "canary", "large", "reminder", "discovery"];
  fixture.ownedFixtureIds = [...ids, fixture.conversationId, ...["owner", "attendee", "staff", "unauthorized", "administrator", "deletion"].map((role) => fixture[role].uid)];
  const initial = {
    [`QualificationScopes/${runId}`]: {schemaVersion: 1, projectId: candidate.projectId, status: "active", mode: "capture", createdAt: new Date(now), expiresAt: new Date(now + 72 * 3600000),
      actorUids: [fixture.owner.uid, fixture.attendee.uid], recipientUids: [fixture.owner.uid, fixture.attendee.uid], eventIds: ids, organizationIds: [], conversationIds: [], recipientEmailHashes: []},
    [`QualificationSetup/${runId}`]: {...candidate, state: "seeded", ownedFixtureIds: fixture.ownedFixtureIds},
    [`Customers/${fixture.owner.uid}/followers/${fixture.attendee.uid}`]: {userId: fixture.attendee.uid},
  };
  for (const id of ["reminder", "discovery"]) initial[`Events/${id}`] = {customerUid: fixture.owner.uid, eventRevision: 1, status: "active", private: false, isHidden: false,
    createdAt: new Date(now), selectedDateTime: new Date(now + 4 * 3600000), eventDurationMinutes: 120};
  for (const [kind, id] of [["event", "reminder"], ["event", "discovery"], ["account", fixture.owner.uid], ["account", fixture.attendee.uid]]) initial[`QualificationBindings/${bindingId(kind, id)}`] = {schemaVersion: 1, projectId: candidate.projectId, runId, state: "bound"};
  const {db} = memoryAdmin(initial); db.projectId = candidate.projectId;
  const tx = db.runTransaction;
  db.runTransaction = (fn, options) => {assert.deepEqual(options, {readOnly: true}); return tx((transaction) => fn({get: transaction.get}));};
  const itemPath = `discovery_notification_batches/${fixture.attendee.uid}/events/${hash("discovery")}`;
  return {db, candidate, fixture, now: () => now + 1000, itemPath};
}
test("absent early timer is recorded honestly and never qualifies delivery", async () => {
  const f = setup(), before = [...f.db.values]; const row = await readOriginalTimerSource(f);
  assert.equal(row.discoveryPhase, "absent"); assert.equal(row.originalTimersVerified, false); assert.equal(row.qualifiesCandidate, false);
  assert.equal(row.discoveryItem.path, f.itemPath); assert.equal(row.identity.discoveryRecipientUid, f.fixture.attendee.uid); assert.deepEqual([...f.db.values], before);
  assert.equal(row.discoveryItem.createTime, null);
  assert.equal(row.reminderQueues.every((item) => item.createTime === null), true);
});

test("server creation provenance retains nanoseconds independently of mutable fields and updates", async () => {
  const f = setup(), serverCreated = {seconds: now / 1000, nanoseconds: 123456789};
  let serverUpdated = {seconds: now / 1000 + 1, nanoseconds: 876543210};
  // Add metadata to this test's snapshots only, without changing shared memoryAdmin.
  const transact = f.db.runTransaction;
  f.db.runTransaction = (fn, options) => transact((tx) => fn({get: async (ref) => {
    const row = await tx.get(ref);
    return Object.assign(Object.create(Object.getPrototypeOf(row)), row, {
      createTime: row.exists ? serverCreated : undefined,
      updateTime: row.exists ? serverUpdated : undefined,
    });
  }}), options);
  f.db.values.get("Events/discovery").createTime = new Date(now - 3600000);
  const first = await readOriginalTimerSource(f), event = first.events.find((row) => row.id === "discovery");
  assert.deepEqual(event.createTime, serverCreated);
  assert.deepEqual(event.createdAt, {seconds: now / 1000, nanoseconds: 0});
  assert.deepEqual(event.updateTime, serverUpdated);
  assert.notEqual(event.createTime, serverCreated, "Evidence must copy timestamp metadata");
  serverUpdated = {seconds: now / 1000 + 2, nanoseconds: 111222333};
  f.db.values.get("Events/discovery").createTime = new Date(now + 3600000);
  const second = (await readOriginalTimerSource(f)).events.find((row) => row.id === "discovery");
  assert.deepEqual(second.createTime, serverCreated);
  assert.deepEqual(second.createdAt, event.createdAt);
  assert.deepEqual(second.updateTime, serverUpdated);
  assert.notDeepEqual(second.updateTime, event.updateTime);
});
test("pending source stores exact full timestamps and original candidate/recipient identity", async () => {
  const f = setup(); f.db.values.set(f.itemPath, {eventId: "discovery", status: "pending", queuedAt: new Date(now), readyAt: new Date(now + 45 * 60000)});
  const row = await readOriginalTimerSource(f); assert.equal(row.discoveryPhase, "pending-observed");
  assert.deepEqual(row.discoveryItem.queuedAt, {seconds: now / 1000, nanoseconds: 0}); assert.deepEqual(row.identity, sourceIdentity(f.candidate, f.fixture));
  assert.equal(row.reminderQueues.every((item) => !item.exists), true);
});
test("claimed source cannot pretend a pending timestamp survived", async () => {
  const f = setup(); f.db.values.set(f.itemPath, {eventId: "discovery", status: "claimed", deliveryId: "delivery", claimedAt: new Date(now)});
  const row = await readOriginalTimerSource(f); assert.equal(row.discoveryPhase, "not-pending"); assert.equal(row.discoveryItem.queuedAt, null); assert.equal(row.originalTimersVerified, false);
});
for (const [name, mutate] of [
  ["wrong project", (f) => {f.db.projectId = "orgami-66nxok";}],
  ["wrong candidate source", (f) => {f.candidate.sourceSha = "b".repeat(40);}],
  ["scope extension", (f) => {f.db.values.get(`QualificationScopes/${f.fixture.runId}`).eventIds.push("extra");}],
  ["retired event binding", (f) => {f.db.values.get(`QualificationBindings/${bindingId("event", "discovery")}`).state = "retired";}],
  ["changed source schedule", (f) => {f.db.values.get("Events/discovery").selectedDateTime = new Date(now + 5 * 3600000);}],
  ["deleting attendee", (f) => {f.db.values.set(`account_deletion_jobs/${f.fixture.attendee.uid}`, {status: "running"});}],
  ["supplemental organizer reserved", (f) => {f.db.values.set(`QualificationSetup/${f.fixture.runId}/supplemental/organizer`, {status: "reserved"});}],
  ["item identity collision", (f) => {f.db.values.set(f.itemPath, {eventId: "foreign", status: "pending"});}],
]) test(`${name} is rejected without writes`, async () => {const f = setup(); mutate(f); const before = [...f.db.values]; await assert.rejects(readOriginalTimerSource(f)); assert.deepEqual([...f.db.values], before);});
test("timestamp retains nanoseconds", () => {assert.deepEqual(fullTimestamp({seconds: 1, nanoseconds: 987654321}), {seconds: 1, nanoseconds: 987654321}); assert.throws(() => fullTimestamp({seconds: 1, nanoseconds: 1e9}));});
