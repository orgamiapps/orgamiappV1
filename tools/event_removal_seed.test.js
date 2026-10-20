"use strict";
const test = require("node:test"), assert = require("node:assert/strict");
const fs = require("node:fs"), os = require("node:os"), path = require("node:path");
const seed = require("./seed_event_removal_qualification"), c = require("./event_removal_contract");
const {createObserver} = require("./event_removal_observer");
const PREFIX = `projects/${c.PROJECT}/databases/(default)/documents/`;
function input() {
  const candidate = {environment: "staging", projectId: c.PROJECT, sourceSha: "a".repeat(40), candidateRunId: "123"};
  const receipt = {environment: "staging", sourceSha: candidate.sourceSha,
    candidateSha256: c.digest(candidate), stateSha256: "b".repeat(64), verifiedAt: new Date().toISOString()};
  const canonical = {projectId: c.PROJECT, state: "seeded", sourceSha: candidate.sourceSha, candidateRunId: "123",
    runId: "webqa-20261020-0000000000", mapsApiKey: "AIza" + "M".repeat(35),
    event: {id: "canonical-pilot"}, privateEventId: "canonical-private",
    secondEventId: "canonical-second", canaryEventId: "canonical-analytics", largeRoster: {eventId: "canonical-large"},
    communications: {reminderEventId: "canonical-reminder", discoveryEventId: "canonical-discovery"},
    firebase: {projectId: c.PROJECT, projectNumber: "925344893088", apiKey: "AIza" + "A".repeat(35),
      appId: "1:925344893088:web:fixture", storageBucket: "attendus-staging.firebasestorage.app",
      appCheckSiteKey: "synthetic-site-key-for-tests"}};
  const fixture = seed.prepare({candidate, receipt, canonical, now: new Date(Date.now() - 1000),
    randomBytes: count => Buffer.alloc(count, 1)});
  return {candidate, receipt, fixture};
}
function temporary(t) {
  const base = fs.realpathSync(os.tmpdir()), dir = fs.mkdtempSync(path.join(base, "removal-seed-test-"));
  t.after(() => {
    assert.equal(fs.realpathSync(dir), dir); assert.ok(dir.startsWith(base + path.sep));
    assert.equal(fs.lstatSync(dir).isSymbolicLink(), false); fs.rmSync(dir, {recursive: true});
  });
  return dir;
}
function provider(value, {loseAccountResponse = false} = {}) {
  const docs = new Map(value.fixture.canonicalEventIds.map(id => [`Events/${id}`, {
    name: PREFIX + `Events/${id}`, fields: {title: {stringValue: "canonical"}},
    createTime: "2026-10-20T10:00:00.000000001Z", updateTime: "2026-10-20T10:00:00.000000002Z",
  }]));
  const users = [], calls = [];
  const api = {
    documents: async paths => new Map(paths.map(p => [p, docs.get(p) || null])),
    accounts: async () => structuredClone(users),
    createDocuments: async rows => {
      calls.push({type: "commit", paths: rows.map(r => r.path)});
      assert.ok(rows.every(r => !docs.has(r.path)));
      rows.forEach(row => docs.set(row.path, {name: PREFIX + row.path, fields: seed.encode(row.data).mapValue.fields,
        createTime: "2026-10-20T10:01:00Z", updateTime: "2026-10-20T10:01:00Z"}));
      return {commitTime: "2026-10-20T10:01:00Z"};
    },
    createAccount: async actor => {
      calls.push({type: "account", uid: actor.uid});
      assert.ok(docs.has(`QualificationBindings/${seed.bindingId("account", actor.uid)}`));
      assert.ok(docs.has(`QualificationSetup/${value.fixture.runId}`));
      users.push({localId: actor.uid, email: actor.email, emailVerified: true});
      if (loseAccountResponse) throw Error("lost response");
      return {localId: actor.uid};
    },
  };
  return {api, docs, users, calls};
}
test("fixture is distinct, create-only, future-retirable and truthful synthetic history", () => {
  const value = input(), {fixture} = value, docs = seed.buildDocuments(fixture);
  assert.match(fixture.runId, /^webqa-\d{8}-[a-f0-9]{10}$/);
  assert.equal(docs.scope.length, 12); assert.equal(docs.business.length, 21);
  assert.equal(fixture.ownedFixtureIds.length, 16);
  assert.ok([...docs.scope, ...docs.business].every(d => !d.path.startsWith("AppConfig/") &&
    !fixture.canonicalEventIds.some(id => d.path === `Events/${id}`)));
  const profiles = docs.business.filter(d => d.path.startsWith("Customers/"));
  assert.equal(profiles.find(d => d.path.endsWith(fixture.roles.viewer.uid)).data.favorites.length, 5);
  assert.ok(docs.business.filter(d => /^(Tickets|Attendance|RegisterAttendance)\//.test(d.path))
    .every(d => d.data.syntheticFixture && d.data.customerUid === fixture.roles.viewer.uid));
  assert.equal(docs.scope.find(d => d.path.startsWith("QualificationSetup/")).data.state, "provisioning");
});
test("successful seeding creates isolation before accounts and business then pins canonical versions", async t => {
  const value = input(), fake = provider(value), directory = temporary(t);
  const result = await seed.apply({...value, ...fake, directory, verify: async () => {}});
  assert.equal(result.accountsCreated, 3); assert.equal(result.documentsCreated, 33);
  assert.deepEqual(fake.calls.map(x => x.type), ["commit", "account", "account", "account", "commit"]);
  const seeded = JSON.parse(fs.readFileSync(result.privateContext));
  assert.equal(seeded.state, "seeded");
  assert.equal(Object.keys(seeded.canonicalEventVersions).length, 7);
  assert.ok(fs.readdirSync(path.join(directory, "seed-attempt")).some(name => name.endsWith("-complete.json")));
});
test("uncertain Auth response stops once, retains lineage and reconciles without resuming", async t => {
  const value = input(), fake = provider(value, {loseAccountResponse: true}), directory = temporary(t);
  await assert.rejects(() => seed.apply({...value, ...fake, directory, verify: async () => {}}),
    {code: "SEED_OUTCOME_UNCERTAIN_RECONCILE"});
  assert.equal(fake.calls.length, 2);
  const report = await seed.reconcile({...value, ...fake, verify: async () => {}});
  assert.equal(report.documents.exact, 12); assert.equal(report.documents.missing, 21);
  assert.equal(report.accountsPresent, 1); assert.equal(report.cloudWrites, 0);
  assert.equal(report.automaticResumeAllowed, false);
  await assert.rejects(() => seed.apply({...value, ...fake, directory, verify: async () => {}}),
    {code: "FIXTURE_ID_ALREADY_EXISTS"});
  assert.equal(fake.calls.length, 2);
});
test("existing fixture paths and deployment drift stop before writes", async t => {
  const value = input(), fake = provider(value), directory = temporary(t);
  fake.docs.set(`Events/${value.fixture.events.race.id}`, {existing: true});
  await assert.rejects(() => seed.apply({...value, ...fake, directory, verify: async () => {}}),
    {code: "FIXTURE_ID_ALREADY_EXISTS"});
  assert.equal(fake.calls.length, 0);
  await assert.rejects(() => seed.apply({...value, ...fake, directory, verify: async () => {
    throw Object.assign(Error("drift"), {code: "STAGING_DEPLOYMENT_CHANGED"});
  }}), {code: "STAGING_DEPLOYMENT_CHANGED"});
  assert.equal(fake.calls.length, 0);
});
test("future preparation time fails before any provider access", async t => {
  const value = input(), fake = provider(value);
  value.fixture.preparedAt = new Date(Date.now() + 60000).toISOString();
  await assert.rejects(() => seed.apply({...value, ...fake, directory: temporary(t), verify: async () => {}}),
    {code: "FRESH_PREPARED_FIXTURE_REQUIRED"});
  assert.equal(fake.calls.length, 0);
});
test("lost Firestore commit response is reconciled read-only without retrying or claiming complete", async t => {
  for (const phase of [1, 2]) {
    const value = input(), fake = provider(value), original = fake.api.createDocuments, directory = temporary(t);
    let commits = 0;
    fake.api.createDocuments = async rows => {
      const result = await original(rows);
      if (++commits === phase) throw Error("lost commit acknowledgement");
      return result;
    };
    await assert.rejects(() => seed.apply({...value, ...fake, directory, verify: async () => {}}),
      {code: "SEED_OUTCOME_UNCERTAIN_RECONCILE"});
    const report = await seed.reconcile({...value, ...fake, verify: async () => {}});
    assert.equal(report.documents.exact, phase === 1 ? 12 : 33);
    assert.equal(report.accountsPresent, phase === 1 ? 0 : 3);
    assert.equal(commits, phase);
    assert.equal(fs.existsSync(path.join(directory, "seeded-fixture-private.json")), false);
  }
});
test("readback checks all supplied values and permits only known trigger additions", () => {
  const value = input(), rows = seed.buildDocuments(value.fixture).business;
  const docs = new Map(rows.map(row => [row.path, {name: PREFIX + row.path,
    createTime: "2026-10-20T10:00:00Z", updateTime: "2026-10-20T10:00:00Z",
    fields: seed.encode(row.data).mapValue.fields}]));
  const event = docs.get(`Events/${value.fixture.events.publicDelete.id}`);
  event.fields.discoveryLocationValid = {booleanValue: true};
  seed.verifyCreatedDocuments(rows, docs);
  event.fields.customerUid = {stringValue: "foreign"};
  assert.throws(() => seed.verifyCreatedDocuments(rows, docs), {code: "SEED_DOCUMENT_VALUES_CHANGED"});
  event.fields.customerUid = {stringValue: value.fixture.roles.owner.uid};
  event.fields.unreviewed = {stringValue: "unexpected"};
  assert.throws(() => seed.verifyCreatedDocuments(rows, docs), {code: "UNREVIEWED_TRIGGER_FIELDS"});
});
test("deployment capture pipes nested stdout/stderr and sanitizes failure diagnostics", async () => {
  const value = input();
  await seed.verifyDeployment({...value, repo: "synthetic-root", execute: (_binary, _args, options) => {
    assert.deepEqual(options.stdio, ["pipe", "pipe", "pipe"]);
    assert.ok(options.timeout <= 180000);
    return JSON.stringify({stateSha256: value.receipt.stateSha256});
  }});
  await assert.rejects(() => seed.verifyDeployment({...value, execute: () => {
    throw Object.assign(Error("sensitive-provider-output"), {stderr: "private-token"});
  }}), error => error.code === "STAGING_DEPLOYMENT_CHECK_FAILED" &&
    !error.message.includes("sensitive") && !error.message.includes("private-token"));
});
test("native transport sends only scoped creates with exists:false and cannot replay401/403/lost response", async () => {
  const {fixture} = input();
  for (const status of [401, 403, "lost"]) {
    let attempts = 0;
    const api = seed.makeApi({fixture, accessToken: "synthetic-token", fetchImpl: async (_url, init) => {
      attempts++; assert.equal(init.redirect, "error");
      assert.equal(init.headers.get("x-goog-user-project"), c.PROJECT);
      assert.ok(JSON.parse(init.body).writes.every(w => w.currentDocument.exists === false && !w.delete));
      if (status === "lost") throw Error("lost");
      return new Response("redacted", {status});
    }});
    const docs = seed.buildDocuments(fixture).scope;
    await assert.rejects(() => api.createDocuments(docs));
    await assert.rejects(() => api.createDocuments(docs), {code: "MUTATION_ALREADY_ATTEMPTED"});
    assert.equal(attempts, 1);
    await assert.rejects(() => api.createDocuments([{path: "AppConfig/publicWeb", data: {}}]), {code: "CREATE_SCOPE_INVALID"});
    assert.equal(attempts, 1);
  }
});
test("Auth endpoint is exact-project account creation and rejects actor substitution", async () => {
  const {fixture} = input(), calls = [];
  const api = seed.makeApi({fixture, accessToken: "synthetic-token", fetchImpl: async (url, init) => {
    calls.push({url, body: JSON.parse(init.body)}); return new Response(JSON.stringify({localId: fixture.roles.owner.uid}));
  }});
  await api.createAccount(fixture.roles.owner);
  assert.equal(calls[0].url, `https://identitytoolkit.googleapis.com/v1/projects/${c.PROJECT}/accounts`);
  assert.equal(calls[0].body.localId, fixture.roles.owner.uid);
  await assert.rejects(() => api.createAccount({...fixture.roles.owner, uid: "foreign"}), {code: "AUTH_CREATE_SCOPE_INVALID"});
  await assert.rejects(() => api.createAccount(fixture.roles.owner), {code: "MUTATION_ALREADY_ATTEMPTED"});
});
function timestamp(iso) {
  const ms = Date.parse(iso), fractional = /\.(\d+)Z$/.exec(iso)?.[1] || "";
  return {seconds: Math.floor(ms / 1000), nanoseconds: Number(fractional.padEnd(9, "0")),
    toDate: () => new Date(ms), toMillis: () => ms};
}
function observerProvider(fixture) {
  const docs = new Map([...seed.buildDocuments(fixture).scope, ...seed.buildDocuments(fixture).business]
    .map(row => [row.path, row.data]));
  const versions = new Map();
  fixture.canonicalEventVersions = {};
  for (const id of fixture.canonicalEventIds) {
    docs.set(`Events/${id}`, {title: "canonical"});
    const times = {createTime: "2026-10-20T10:00:00.000000001Z", updateTime: "2026-10-20T10:00:00.000000002Z"};
    fixture.canonicalEventVersions[id] = {...times}; versions.set(`Events/${id}`, times);
  }
  function snapshot(key) {
    const data = docs.get(key), convert = value => value instanceof Date ?
      timestamp(value.toISOString()) : value;
    return {exists: Boolean(data), id: key.split("/").at(-1), data: () => data,
      get: field => convert(data?.[field]),
      createTime: timestamp(versions.get(key)?.createTime || "2026-10-20T10:00:00Z"),
      updateTime: timestamp(versions.get(key)?.updateTime || "2026-10-20T10:00:00Z")};
  }
  const reads = [], db = {projectId: c.PROJECT,
    doc: key => ({get: async () => {reads.push(key); return snapshot(key);}}),
    collection: collection => ({where: (field, op, value) => {
      assert.equal(field, "eventId"); assert.equal(op, "==");
      assert.ok(c.EVENT_KEYS.some(key => fixture.events[key].id === value));
      return {limit: count => {assert.equal(count, 101); return {get: async () => ({
        docs: [...docs.keys()].filter(key => key.startsWith(collection + "/") &&
          docs.get(key).eventId === value).map(snapshot),
      })};}};
    }}),
  };
  return {docs, versions, db, reads};
}
test("observer proves scoped cancellation history and detects canonical nanosecond drift", async () => {
  const value = input(); value.fixture.state = "seeded";
  const fake = observerProvider(value.fixture), observe = createObserver({...value, db: fake.db});
  const initial = await observe(); assert.equal(initial.scope.active, true); assert.equal(initial.scope.boundCount, 10);
  fake.docs.delete(`Events/${value.fixture.events.publicDelete.id}`);
  fake.docs.get(`Events/${value.fixture.events.privateCancel.id}`).status = "cancelled";
  const result = await observe();
  assert.equal(result.events.publicDelete.status, "deleted");
  assert.equal(result.events.privateCancel.status, "cancelled");
  assert.equal(result.events.privateCancel.historyPreserved, true);
  assert.equal(result.events.privateCancel.registrations, 1);
  assert.equal(result.events.privateCancel.tickets, 1);
  assert.equal(result.events.privateCancel.attendance, 1);
  assert.equal(result.canonical.unchanged, true);
  fake.versions.get(`Events/${value.fixture.canonicalEventIds[0]}`).updateTime = "2026-10-20T10:00:00.000000003Z";
  assert.equal((await observe()).canonical.changedCount, 1);
  assert.equal(JSON.stringify(result).includes(value.fixture.roles.viewer.email), false);
  assert.equal(JSON.stringify(result).includes(value.fixture.roles.owner.password), false);
});
test("observer refuses unseeded fixtures or absent canonical baseline", () => {
  const value = input();
  assert.throws(() => createObserver({...value, db: {projectId: c.PROJECT}}), {code: "SEEDED_FIXTURE_REQUIRED"});
  value.fixture.state = "seeded";
  assert.throws(() => createObserver({...value, db: {projectId: c.PROJECT}}), {code: "CANONICAL_BASELINE_REQUIRED"});
});
test("observer independently rejects wrong project and emulator/debug environment", () => {
  const value = input(); value.fixture.state = "seeded";
  const fake = observerProvider(value.fixture);
  assert.throws(() => createObserver({...value, db: {...fake.db, projectId: "orgami-66nxok"}}),
    {code: "OBSERVER_DATABASE_SCOPE_INVALID"});
  assert.throws(() => createObserver({...value, db: fake.db, environment: {FIRESTORE_EMULATOR_HOST: "localhost:8080"}}),
    {code: "LIVE_ENVIRONMENT_REQUIRED"});
  assert.throws(() => createObserver({...value, db: {...fake.db, _settings: {host: "localhost:8080"}}}),
    {code: "OBSERVER_DATABASE_SCOPE_INVALID"});
});
test("observer rejects scope expansion, expiry, binding-schema drift and substituted history owner", async () => {
  for (const mutate of [
    (fake, fixture) => {fake.docs.get(`QualificationScopes/${fixture.runId}`).recipientUids.push("foreign");},
    (fake, fixture) => {fake.docs.get(`QualificationScopes/${fixture.runId}`).expiresAt = new Date(0);},
    (fake, fixture) => {fake.docs.get(`QualificationBindings/${seed.bindingId("event", fixture.events.race.id)}`).schemaVersion = 2;},
  ]) {
    const value = input(); value.fixture.state = "seeded";
    const fake = observerProvider(value.fixture); mutate(fake, value.fixture);
    assert.equal((await createObserver({...value, db: fake.db})()).scope.active, false);
  }
  const value = input(); value.fixture.state = "seeded";
  const fake = observerProvider(value.fixture);
  fake.docs.get(`Tickets/${value.fixture.history.publicCancel.ticketId}`).customerUid = "foreign";
  assert.equal((await createObserver({...value, db: fake.db})()).events.publicCancel.historyPreserved, false);
});
