"use strict";
const test = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs"), path = require("node:path"), vm = require("node:vm");
const {createRequire} = require("node:module");
const {validateLiveEnvironment, apply} = require("./seed_web_qualification");
const {desiredMetadata} = require("../functions/discovery/maintenance");

async function executeIsolatedSeeder({state = "prepared", observe = () => {}} = {}) {
  const sourcePath = path.join(__dirname, "seed_web_qualification.js"), realRequire = createRequire(sourcePath);
  const privateFile = path.resolve(__dirname, "../build/fixture-test-private.json"), runId = "webqa-20261004-aabbccddee";
  const roles = ["owner", "attendee", "unauthorized", "staff", "administrator", "deletion"];
  const fixture = {projectId: "attendus-staging", state, runId,
    firebase: {storageBucket: "attendus-staging.firebasestorage.app", appCheckSiteKey: "synthetic-public-key"},
    event: {id: `${runId}-pilot`, title: "Controlled web qualification pilot"}, privateEventId: `${runId}-private`,
    secondEventId: `${runId}-second`, canaryEventId: `${runId}-analytics`, largeRoster: {eventId: `${runId}-large`, expectedRows: 1201},
    organizationId: `${runId}-community`, conversationId: `${runId}-conversation`,
    communications: {reminderEventId: `${runId}-reminder`, discoveryEventId: `${runId}-discovery`, pendingPushId: `${runId}-pending`}};
  for (const role of roles) fixture[role] = {uid: `${runId}-${role}`, email: `${runId}-${role}@example.test`, password: "synthetic-not-a-real-password"};
  const eventIds = [fixture.event.id, fixture.privateEventId, fixture.secondEventId, fixture.canaryEventId,
    fixture.largeRoster.eventId, fixture.communications.reminderEventId, fixture.communications.discoveryEventId];
  fixture.ownedFixtureIds = [...roles.map(role => fixture[role].uid), ...eventIds, fixture.organizationId, fixture.conversationId, fixture.communications.pendingPushId];
  const candidate = {sourceSha: "a".repeat(40), candidateRunId: "123"};
  const receipt = {candidateSha256: "candidate-hash", environment: "staging", sourceSha: candidate.sourceSha, stateSha256: "state-hash"};
  const documents = new Map(), authCreates = [], fileWrites = new Map();
  observe({documents, authCreates, fileWrites});
  const db = {collection: () => ({limit: () => ({get: async () => ({size: 0})})}),
    doc: id => ({path: id, create: async value => {assert.equal(documents.has(id), false); documents.set(id, value);},
      set: async value => {documents.set(id, value);}, update: async value => {documents.set(id, {...documents.get(id), ...value});}}),
    batch: () => ({create(ref, value) {assert.equal(documents.has(ref.path), false); documents.set(ref.path, value);}, commit: async () => {}}),
    terminate: async () => {}};
  const dependencies = name => {
    if (name === "firebase-admin/app") return {initializeApp: () => ({}), applicationDefault: () => ({}), deleteApp: async () => {}};
    if (name === "firebase-admin/firestore") return {getFirestore: () => db};
    if (name === "firebase-admin/auth") return {getAuth: () => ({createUser: async account => {authCreates.push(account);}, setCustomUserClaims: async () => {}})};
    throw Error("Unapproved fixture test dependency");
  };
  const mockedRequire = name => {
    if (name === "node:fs") return {readFileSync(file) {
      if (file === privateFile) return JSON.stringify(fixture);
      if (file === "candidate") return JSON.stringify(candidate);
      if (file === "receipt") return JSON.stringify(receipt);
      if (file === path.resolve(__dirname, "../firestore.indexes.json")) return "{}";
      throw Error("Unexpected fixture test file read");
    }, writeFileSync(file, value) {fileWrites.set(file, value);}};
    if (name === "node:module") return {createRequire: () => dependencies};
    if (name === "node:child_process") return {execFileSync: () => {}};
    if (name === "./web_release_contract") return {validateCandidate: value => value, digest: () => "candidate-hash"};
    if (name === "./web_release_state") return {captureState: async () => ({}), verifyState: () => ({stateSha256: "state-hash"})};
    return realRequire(name);
  };
  const module = {exports: {}};
  vm.runInNewContext(fs.readFileSync(sourcePath, "utf8"), {require: mockedRequire, module, __dirname, process: {env: {}}, console, Date, Buffer});
  await module.exports.apply(privateFile, "candidate", "receipt");
  return {fixture, eventIds, roles, documents, authCreates, persistedFixture: JSON.parse(fileWrites.get(privateFile))};
}

test("actual new-run seed creates two positive Maps fixtures without adding events, accounts or timer changes", async () => {
  const {fixture, eventIds, roles, documents, authCreates, persistedFixture} = await executeIsolatedSeeder();
  const events = [...documents].filter(([id]) => /^Events\/[^/]+$/.test(id));
  assert.equal(events.length, 7); assert.equal(authCreates.length, 6);
  assert.deepEqual(authCreates.map(account => account.uid), roles.map(role => fixture[role].uid));
  const expectedIds = [fixture.secondEventId, fixture.canaryEventId];
  const physical = events.filter(([, row]) => Number.isFinite(row.latitude) && Number.isFinite(row.longitude));
  assert.deepEqual(physical.map(([id]) => id.slice(7)).sort(), [...expectedIds].sort());
  assert.equal(new Set(physical.map(([, row]) => `${row.latitude},${row.longitude}`)).size, 2);
  for (const [id, row] of physical) {
    assert.equal(row.private, false); assert.equal(row.status, "active"); assert.equal(row.locationType, "in_person");
    assert.equal(row.city, "New York"); assert.equal(row.regionCode, "NY"); assert.equal(row.countryCode, "US");
    assert.match(row.locationName, /^Synthetic qualification venue [AB]$/);
    assert.match(row.location, /synthetic test location/i);
    const derived = desiredMetadata(row);
    assert.equal(derived.discoveryLocationValid, true); assert.equal(row.discoveryLocationValid, true);
    assert.equal(row.geohash, derived.geohash); assert.notEqual(row.geohash, "");
    assert.equal(row.id, id.slice(7)); assert.equal(row.eventRevision, 1); assert.equal(row.ticketsEnabled, false);
  }
  const started = Date.parse(persistedFixture.runStartsAt);
  for (const [, row] of events) {
    const future = [fixture.communications.reminderEventId, fixture.communications.discoveryEventId].includes(row.id);
    assert.equal(row.selectedDateTime.getTime(), started + (future ? 4 * 3600000 : -15 * 60000));
    assert.equal(row.eventDurationMinutes, 120); assert.equal(row.eventTimeZone, "America/New_York");
  }
  assert.equal(Date.parse(persistedFixture.eventClosesAt), started + 105 * 60000);
  const scope = documents.get(`QualificationScopes/${fixture.runId}`);
  assert.deepEqual(Array.from(scope.eventIds), eventIds);
  assert.deepEqual(Array.from(scope.actorUids), roles.filter(role => role !== "deletion").map(role => fixture[role].uid));
  assert.deepEqual(Array.from(scope.recipientUids), Array.from(scope.actorUids)); assert.equal(scope.mode, "capture");
  assert.equal(documents.get("AppConfig/attendance").smartArrival.eventIds[0], fixture.event.id);
  assert.equal(documents.get("AppConfig/attendance").appleDelivery.enabled, false);
  assert.equal(documents.get("AppConfig/attendance").googleDelivery.enabled, false);
});

test("positive Maps seeding cannot be applied to an existing seeded fixture", async () => {
  let activity;
  await assert.rejects(executeIsolatedSeeder({state: "seeded", observe(value) {activity = value;}}), /fresh prepared staging fixture/);
  assert.equal(activity.documents.size, 0); assert.equal(activity.authCreates.length, 0); assert.equal(activity.fileWrites.size, 0);
});

test("live staging setup rejects each emulator endpoint before reading inputs or writing data", async () => {
  validateLiveEnvironment({});
  for (const name of ["FIRESTORE_EMULATOR_HOST", "FIREBASE_AUTH_EMULATOR_HOST", "FIREBASE_STORAGE_EMULATOR_HOST", "STORAGE_EMULATOR_HOST", "FIREBASE_DATABASE_EMULATOR_HOST"]) {
    assert.throws(() => validateLiveEnvironment({[name]: "127.0.0.1:9190"}), /cannot use emulator/);
  }
  const original = process.env.FIREBASE_AUTH_EMULATOR_HOST;
  try {
    process.env.FIREBASE_AUTH_EMULATOR_HOST = "127.0.0.1:9190";
    await assert.rejects(apply("missing-private-context", "missing-candidate", "missing-receipt"), /cannot use emulator/);
  } finally {
    if (original === undefined) delete process.env.FIREBASE_AUTH_EMULATOR_HOST;
    else process.env.FIREBASE_AUTH_EMULATOR_HOST = original;
  }
});
