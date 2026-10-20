"use strict";
const test = require("node:test"), assert = require("node:assert/strict");
const c = require("./event_removal_contract");
const {createMutationGuard, assertCurated, waitForSnapshot, readOnlyDataRequest} = require("./event_removal_live_acceptance");
function inputs() {
  const candidate = {projectId: c.PROJECT, environment: "staging", sourceSha: "a".repeat(40), candidateRunId: "123"};
  const receipt = {environment: "staging", sourceSha: candidate.sourceSha, candidateSha256: c.digest(candidate),
    stateSha256: "b".repeat(64), verifiedAt: new Date().toISOString()};
  const runId = "webqa-20261020-0123456789";
  const fixture = {schemaVersion: 1, purpose: "event-removal-live", state: "seeded", projectId: c.PROJECT, runId,
    candidateRunId: candidate.candidateRunId, sourceSha: candidate.sourceSha, candidateSha256: c.digest(candidate),
    deploymentReceiptSha256: c.digest(receipt), stagingStateSha256: receipt.stateSha256,
    canonicalRunId: "webqa-20261020-9876543210", canonicalEventIds: Array.from({length: 7}, (_, i) => `canonical-${i}`),
    organizationId: `${runId}-community`,
    roles: Object.fromEntries(c.ROLE_KEYS.map(role => [role, {uid: `${runId}-${role}`, email: `${runId}-${role}@example.test`,
      password: `Synthetic-password-${role}-123456789`} ])),
    events: Object.fromEntries(c.EVENT_KEYS.map(key => [key, {id: `${runId}-${key}`, title: `Removal QA ${key}`,
      private: ["privateDelete", "privateCancel", "restricted"].includes(key)}])),
    history: Object.fromEntries(["publicCancel", "privateCancel"].map(key => [key, {
      registrationId: `${runId}-${key}-registration`, ticketId: `${runId}-${key}-ticket`, attendanceId: `${runId}-${key}-attendance`}])),
    mapsApiKey: "AIza" + "m".repeat(35),
    firebase: {projectId: c.PROJECT, projectNumber: "925344893088", apiKey: "AIza" + "x".repeat(35),
      appId: "1:925344893088:web:test", storageBucket: "attendus-staging.firebasestorage.app", appCheckSiteKey: "k".repeat(25)}};
  fixture.ownedFixtureIds = [...Object.values(fixture.roles).map(x => x.uid), ...Object.values(fixture.events).map(x => x.id),
    fixture.organizationId, ...Object.values(fixture.history).flatMap(Object.values)];
  return {candidate, receipt, fixture};
}
function auth(uid) {return `Bearer a.${Buffer.from(JSON.stringify({user_id: uid})).toString("base64url")}.c`;}
function deletion(fixture, extra = {}) {
  return {name: "deleteEmptyEventV1", data: {eventId: fixture.events.publicDelete.id,
    requestId: "qualified-request-1", expectedEventRevision: 1, ...extra},
  authorization: auth(fixture.roles.owner.uid), appCheckToken: "not-retained"};
}
test("exact independent fixture is accepted and canonical or extra scope fails closed", () => {
  const context = inputs(); assert.equal(c.validateContext(context), context.fixture);
  context.fixture.ownedFixtureIds.push("unowned");
  assert.throws(() => c.validateContext(context), {code: "OWNED_SCOPE_NOT_EXACT"});
  context.fixture.ownedFixtureIds.pop(); context.fixture.canonicalEventIds[0] = context.fixture.events.publicDelete.id;
  assert.throws(() => c.validateContext(context), {code: "EVENT_SCOPE_INVALID"});
});
test("candidate and deployment identity cannot be substituted", () => {
  const context = inputs(); context.receipt.stateSha256 = "c".repeat(64);
  assert.throws(() => c.validateContext(context), {code: "FIXTURE_PROVENANCE_INVALID"});
});
test("only armed own actor and event can mutate; real App Check header is mandatory", () => {
  const {fixture} = inputs(), events = [], guard = createMutationGuard({fixture, journal: (...x) => events.push(x)});
  assert.throws(() => guard.begin(deletion(fixture)), {code: "UNARMED_OR_FOREIGN_MUTATION"});
  guard.arm("deleteEmptyEventV1", "publicDelete");
  assert.throws(() => guard.begin({...deletion(fixture), authorization: auth(fixture.roles.viewer.uid)}), {code: "BOUND_BROWSER_CREDENTIALS_REQUIRED"});
  assert.throws(() => guard.begin({...deletion(fixture), appCheckToken: null}), {code: "BOUND_BROWSER_CREDENTIALS_REQUIRED"});
  assert.throws(() => guard.begin(deletion(fixture, {eventId: "canonical-1"})), {code: "UNARMED_OR_FOREIGN_MUTATION"});
  assert.equal(events.length, 0);
  guard.begin(deletion(fixture)); assert.equal(events[0][0], "mutation-intent");
});
test("lost response retries exact request once without creating a new operation", () => {
  const {fixture} = inputs(), journal = [], guard = createMutationGuard({fixture, journal: (...x) => journal.push(x)});
  guard.arm("deleteEmptyEventV1", "publicDelete");
  const first = guard.begin(deletion(fixture)); guard.unknown(first);
  assert.equal(guard.reconcile({events: {publicDelete: {exists: true}}}), false);
  const replay = guard.begin(deletion(fixture)); assert.equal(first, replay);
  guard.outcome(replay, {result: {status: "deleted", affectedEventIds: [fixture.events.publicDelete.id]}});
  assert.equal(guard.reconcile({events: {publicDelete: {exists: false}}}), true);
  assert.equal(guard.summaries.length, 1); assert.equal(first.attempts, 2);
  assert.equal(journal.filter(([name]) => name === "mutation-intent").length, 1);
  assert.throws(() => guard.begin(deletion(fixture, {requestId: "replacement-request"})), {code: "REQUEST_REUSE_NOT_IDEMPOTENT"});
});
test("non-idempotent preview cannot retry after an uncertain response", () => {
  const {fixture} = inputs(), guard = createMutationGuard({fixture, journal() {}});
  guard.arm("previewEventCancellationV1", "publicCancel");
  const request = {name: "previewEventCancellationV1", data: {eventId: fixture.events.publicCancel.id, recurrenceScope: "this_occurrence"},
    authorization: auth(fixture.roles.owner.uid), appCheckToken: "real-token"};
  const operation = guard.begin(request); guard.unknown(operation);
  assert.throws(() => guard.begin(request), {code: "REQUEST_REUSE_NOT_IDEMPOTENT"});
  assert.equal(guard.reconcile({events: {publicCancel: {exists: true, status: "active"}}}), false);
});
test("recurrence overrides and unbound cancellation identity are rejected", () => {
  const {fixture} = inputs(), guard = createMutationGuard({fixture, journal() {}});
  const base = {authorization: auth(fixture.roles.owner.uid), appCheckToken: "real-token"};
  guard.arm("previewEventCancellationV1", "publicCancel");
  assert.throws(() => guard.begin({...base, name: "previewEventCancellationV1",
    data: {eventId: fixture.events.publicCancel.id, recurrenceScope: "entire_series"}}), {code: "RECURRENCE_SCOPE_FORBIDDEN"});
  assert.throws(() => guard.begin({...base, name: "previewEventCancellationV1",
    data: {eventId: fixture.events.publicCancel.id, scope: "this_occurrence"}}), {code: "UNREVIEWED_MUTATION_FIELDS"});
  guard.arm("cancelEventV1", "publicCancel");
  assert.throws(() => guard.begin({...base, name: "cancelEventV1",
    data: {eventId: fixture.events.publicCancel.id, previewToken: "preview", reason: "Controlled removal qualification"}}),
  {code: "REMOVAL_IDENTITY_REQUIRED"});
});
test("stale revision rejection reconciles only with preserved source", () => {
  const {fixture} = inputs(), guard = createMutationGuard({fixture, journal() {}});
  guard.arm("deleteEmptyEventV1", "publicDelete");
  const operation = guard.begin(deletion(fixture)); guard.outcome(operation, {error: {status: "FAILED_PRECONDITION"}});
  assert.equal(guard.reconcile({events: {publicDelete: {exists: true}}}), true);
});
test("private credentials and raw tokens cannot enter curated reports", () => {
  const {fixture} = inputs(); assert.doesNotThrow(() => assertCurated({case: "privateDelete", passed: true}, fixture));
  for (const value of [fixture.roles.owner.password, fixture.roles.viewer.email, fixture.roles.outsider.uid, "Bearer abc.def.ghi"]) {
    assert.throws(() => assertCurated({value}, fixture));
  }
});
test("server reconciliation fails immediately on canonical pilot drift", async () => {
  let reads = 0;
  await assert.rejects(waitForSnapshot(async () => {reads++; return {canonical: {unchanged: false}};}, () => true),
    {code: "CANONICAL_PILOT_CHANGED"});
  assert.equal(reads, 1);
});
test("emulators and App Check diagnostic credentials cannot become live evidence", () => {
  assert.doesNotThrow(() => c.assertLiveEnvironment({}));
  for (const env of [{FIRESTORE_EMULATOR_HOST: "127.0.0.1:8080"}, {STAGING_APPCHECK_DEBUG_TOKEN: "secret"}]) {
    assert.throws(() => c.assertLiveEnvironment(env), {code: "LIVE_ENVIRONMENT_REQUIRED"});
  }
});
test("direct Firestore, Storage and hosted writes cannot bypass armed mutation guard", () => {
  const root = "https://firestore.googleapis.com/v1/projects/attendus-staging/databases/(default)/documents";
  for (const [method, url] of [
    ["PATCH", `${root}/Events/owned`], ["DELETE", `${root}/Events/owned`], ["POST", `${root}/Events`],
    ["POST", `${root}:commit`], ["POST", `${root}:batchWrite`], ["POST", `${root}:beginTransaction`],
    ["POST", "https://firestore.googleapis.com/google.firestore.v1.Firestore/Write/channel?database=projects%2Fattendus-staging%2Fdatabases%2F(default)"],
    ["DELETE", "https://firebasestorage.googleapis.com/v0/b/attendus-staging.firebasestorage.app/o/file"],
    ["POST", `${c.ORIGIN}/api/registration`],
  ]) assert.equal(readOnlyDataRequest(url, method), false, `${method} ${url}`);
  for (const [method, url] of [
    ["GET", `${root}/Events/owned`], ["POST", `${root}:batchGet`], ["POST", `${root}:runQuery`],
    ["POST", `${root}:runAggregationQuery`],
    ["POST", "https://firestore.googleapis.com/google.firestore.v1.Firestore/Listen/channel?database=projects%2Fattendus-staging%2Fdatabases%2F(default)"],
    ["GET", `${c.ORIGIN}/app/discover`],
  ]) assert.equal(readOnlyDataRequest(url, method), true, `${method} ${url}`);
});
module.exports = {inputs};
