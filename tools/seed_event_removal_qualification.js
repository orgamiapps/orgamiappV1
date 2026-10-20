"use strict";

// Supplemental, create-only staging fixture. Every mutation is attempted once.
// An uncertain result is inspected with reconcile; this tool never resumes it.
const fs = require("node:fs"), path = require("node:path"), crypto = require("node:crypto");
const {execFileSync} = require("node:child_process");
const c = require("./event_removal_contract");
const PREFIX = `projects/${c.PROJECT}/databases/(default)/documents/`;
const FIRESTORE = `https://firestore.googleapis.com/v1/${PREFIX.slice(0, -1)}`;
const AUTH = `https://identitytoolkit.googleapis.com/v1/projects/${c.PROJECT}/accounts`;
const bindingId = (kind, id) => `${kind}_${c.sha(id)}`;
const read = file => JSON.parse(fs.readFileSync(file, "utf8").replace(/^\uFEFF/, ""));
const date = value => new Date(value);
function prepare({repo, candidate, receipt, canonical, now = new Date(), randomBytes = crypto.randomBytes}) {
  c.need(canonical?.projectId === c.PROJECT && canonical.state === "seeded" &&
    String(canonical.candidateRunId) === String(candidate.candidateRunId) &&
    canonical.sourceSha === candidate.sourceSha, "CANONICAL_CANDIDATE_DIFFERS");
  const canonicalEventIds = [canonical.event?.id, canonical.privateEventId, canonical.secondEventId,
    canonical.canaryEventId, canonical.largeRoster?.eventId, canonical.communications?.reminderEventId,
    canonical.communications?.discoveryEventId];
  const runId = `webqa-${now.toISOString().slice(0, 10).replaceAll("-", "")}-${randomBytes(5).toString("hex")}`;
  const fixture = {schemaVersion: 1, purpose: "event-removal-live", projectId: c.PROJECT,
    runId, state: "prepared", preparedAt: now.toISOString(), candidateRunId: String(candidate.candidateRunId),
    sourceSha: candidate.sourceSha, candidateSha256: c.digest(candidate), stagingStateSha256: receipt.stateSha256,
    deploymentReceiptSha256: c.digest(receipt), canonicalRunId: canonical.runId, canonicalEventIds,
    firebase: structuredClone(canonical.firebase), mapsApiKey: canonical.mapsApiKey,
    organizationId: `${runId}-community`, roles: {}, events: {},
    history: {}, ownedFixtureIds: []};
  for (const role of c.ROLE_KEYS) fixture.roles[role] = {uid: `${runId}-${role}`,
    email: `${runId}-${role}@example.test`, password: randomBytes(30).toString("base64url") + "aA1!"};
  for (const key of c.EVENT_KEYS) fixture.events[key] = {id: `${runId}-${key}`,
    title: `Removal QA ${key} ${runId.slice(-10)}`,
    private: ["privateDelete", "privateCancel", "restricted"].includes(key)};
  for (const key of ["publicCancel", "privateCancel"]) fixture.history[key] = {
    registrationId: `${runId}-${key}-registration`, ticketId: `${runId}-${key}-ticket`,
    attendanceId: `${runId}-${key}-attendance`,
  };
  c.need(/^AIza[0-9A-Za-z_-]{35}$/.test(fixture.mapsApiKey || ""), "MAPS_CONFIGURATION_INVALID");
  fixture.ownedFixtureIds = [...c.ROLE_KEYS.map(key => fixture.roles[key].uid),
    ...c.EVENT_KEYS.map(key => fixture.events[key].id), fixture.organizationId,
    ...Object.values(fixture.history).flatMap(value => Object.values(value))];
  c.validateContext({repo, candidate, receipt, fixture});
  return fixture;
}
function buildDocuments(fixture) {
  const now = date(fixture.preparedAt), start = new Date(now.getTime() + 24 * 3600000);
  c.need(Number.isFinite(now.getTime()), "PREPARATION_TIME_INVALID");
  const owner = fixture.roles.owner.uid, viewer = fixture.roles.viewer.uid, runId = fixture.runId;
  const marker = {qualificationRunId: runId, syntheticFixture: true};
  const scope = [{path: `QualificationScopes/${runId}`, data: {schemaVersion: 1, projectId: c.PROJECT,
    status: "active", mode: "capture", createdAt: now, expiresAt: new Date(now.getTime() + 72 * 3600000),
    actorUids: c.ROLE_KEYS.map(key => fixture.roles[key].uid),
    recipientUids: c.ROLE_KEYS.map(key => fixture.roles[key].uid),
    recipientEmailHashes: c.ROLE_KEYS.map(key => c.sha(fixture.roles[key].email.toLowerCase())),
    eventIds: c.EVENT_KEYS.map(key => fixture.events[key].id), organizationIds: [fixture.organizationId],
    conversationIds: []}}];
  for (const [kind, ids] of [["account", c.ROLE_KEYS.map(key => fixture.roles[key].uid)],
    ["event", c.EVENT_KEYS.map(key => fixture.events[key].id)], ["organization", [fixture.organizationId]]]) {
    for (const id of ids) scope.push({path: `QualificationBindings/${bindingId(kind, id)}`,
      data: {schemaVersion: 1, projectId: c.PROJECT, runId, state: "bound"}});
  }
  const business = [];
  for (const role of c.ROLE_KEYS) {
    const actor = fixture.roles[role], name = `Removal QA ${role}`;
    business.push({path: `Customers/${actor.uid}`, data: {uid: actor.uid, name, email: actor.email,
      username: `removal${runId.slice(-10)}_${role}`, bio: "Synthetic supplemental removal acceptance fixture.",
      isDiscoverable: false, eventsCreated: role === "owner" ? 6 : 0, groupsCreated: role === "owner" ? 1 : 0,
      favorites: role === "viewer" ? c.EVENT_KEYS.slice(0, 5).map(key => fixture.events[key].id) : [],
      createdAt: now, ...marker}});
    business.push({path: `users/${actor.uid}`, data: {uid: actor.uid, displayName: name,
      email: actor.email, createdAt: now, ...marker}});
  }
  business.push({path: `Organizations/${fixture.organizationId}`, data: {id: fixture.organizationId,
    name: `Removal QA community ${runId.slice(-10)}`, description: "Synthetic removal acceptance only.",
    category: "Other", publicPageEnabled: false, defaultEventVisibility: "private",
    createdBy: owner, createdAt: now, ...marker}});
  for (const role of ["owner", "viewer"]) business.push({
    path: `Organizations/${fixture.organizationId}/Members/${fixture.roles[role].uid}`,
    data: {userId: fixture.roles[role].uid, role: role === "owner" ? "owner" : "member",
      status: "approved", joinedAt: now, ...marker}});
  for (const key of c.EVENT_KEYS) {
    const event = fixture.events[key], history = fixture.history[key];
    business.push({path: `Events/${event.id}`, data: {id: event.id, title: event.title,
      description: "Synthetic supplemental event removal acceptance fixture. Not a real event.",
      imageUrl: "", customerUid: owner, organizationId: fixture.organizationId, groupName: "Removal QA community",
      private: event.private, status: "active", isHidden: false, eventRevision: 1,
      selectedDateTime: start, eventDurationMinutes: 120, eventTimeZone: "America/New_York",
      location: "Synthetic test venue", locationType: "in_person",
      latitude: 40.7829, longitude: -73.9654, city: "New York", regionCode: "NY", countryCode: "US",
      ticketsEnabled: Boolean(history), ticketPrice: 0, maxTickets: 20, issuedTickets: history ? 1 : 0,
      reservedTickets: 0, confirmedRegistrationCount: history ? 1 : 0,
      registrationPolicy: {mode: "rsvp", capacity: 20, waitlistEnabled: false},
      eventReminderPolicy: "none", createdAt: now, ...marker}});
    if (!history) continue;
    c.need(history.registrationId === `${runId}-${key}-registration` &&
      history.ticketId === `${runId}-${key}-ticket` && history.attendanceId === `${runId}-${key}-attendance`,
    "HISTORY_SCOPE_INVALID");
    business.push({path: `RegisterAttendance/${history.registrationId}`, data: {id: history.registrationId,
      eventId: event.id, customerUid: viewer, realName: "Removal QA viewer", userName: "Removal QA viewer",
      identityType: "account", status: "confirmed", ticketId: history.ticketId, answers: [],
      registrationDateTime: now, createdAt: now, ...marker}});
    business.push({path: `Tickets/${history.ticketId}`, data: {id: history.ticketId, eventId: event.id,
      registrationId: history.registrationId, customerUid: viewer, customerName: "Removal QA viewer",
      eventTitle: event.title, eventImageUrl: "", eventLocation: "Synthetic test venue",
      eventDateTime: start, issuedDateTime: now, ticketCode: history.ticketId, status: "valid",
      revoked: false, isUsed: false, price: 0, isPaid: true, createdAt: now, ...marker}});
    business.push({path: `Attendance/${history.attendanceId}`, data: {id: history.attendanceId,
      eventId: event.id, customerUid: viewer, realName: "Removal QA viewer", userName: "Removal QA viewer",
      ticketId: history.ticketId, attendanceDateTime: now, checkedInAt: now,
      status: "checked_in", source: "synthetic_qualification_fixture", answers: [], createdAt: now, ...marker}});
  }
  scope.push({path: `QualificationSetup/${runId}`, data: {schemaVersion: 1, projectId: c.PROJECT,
    sourceSha: fixture.sourceSha, candidateRunId: fixture.candidateRunId, candidateSha256: fixture.candidateSha256,
    deploymentReceiptSha256: fixture.deploymentReceiptSha256, purpose: fixture.purpose,
    state: "provisioning", createdAt: now, ownedFixtureIds: fixture.ownedFixtureIds}});
  c.need(scope.length === 12 && business.length === 21 &&
    new Set([...scope, ...business].map(doc => doc.path)).size === 33, "FIXTURE_DOCUMENT_SCOPE_INVALID");
  return {scope, business};
}
function encode(value) {
  if (value instanceof Date) return {timestampValue: value.toISOString()};
  if (value === null) return {nullValue: null};
  if (Array.isArray(value)) return {arrayValue: {values: value.map(encode)}};
  if (typeof value === "string") return {stringValue: value};
  if (typeof value === "boolean") return {booleanValue: value};
  if (typeof value === "number" && Number.isFinite(value)) return Number.isInteger(value) ?
    {integerValue: String(value)} : {doubleValue: value};
  c.need(value && typeof value === "object", "FIRESTORE_VALUE_INVALID");
  return {mapValue: {fields: Object.fromEntries(Object.entries(value).map(([key, item]) => [key, encode(item)]))}};
}
function makeApi({fixture, auth, accessToken, fetchImpl = fetch}) {
  const docs = buildDocuments(fixture), allowed = new Set([...docs.scope, ...docs.business].map(doc => doc.path));
  const canonicalPaths = fixture.canonicalEventIds.map(id => `Events/${id}`);
  const readAllowed = new Set([...allowed, ...canonicalPaths]);
  const actors = c.ROLE_KEYS.map(key => fixture.roles[key]);
  const attempted = new Set();
  c.need(accessToken === undefined || typeof accessToken === "string" && /^[^\s]{1,16000}$/.test(accessToken),
    "ACCESS_TOKEN_INVALID");
  c.need(accessToken !== undefined || typeof auth?.getRequestHeaders === "function", "AUTH_HEADERS_REQUIRED");
  async function request(url, data) {
    const headers = new Headers(accessToken === undefined ? await auth.getRequestHeaders(url) : {});
    if (accessToken !== undefined) headers.set("authorization", `Bearer ${accessToken}`);
    c.need(headers.has("authorization"), "AUTHORIZATION_MISSING");
    headers.set("x-goog-user-project", c.PROJECT); headers.set("content-type", "application/json");
    const response = await fetchImpl(url, {method: "POST", headers, body: JSON.stringify(data),
      redirect: "error", signal: AbortSignal.timeout(45000)});
    c.need(response.ok, "PROVIDER_REQUEST_FAILED");
    const text = await response.text();
    c.need(Buffer.byteLength(text) < 4 * 1024 * 1024, "PROVIDER_RESPONSE_TOO_LARGE");
    try { return JSON.parse(text); } catch { c.need(false, "PROVIDER_JSON_INVALID"); }
  }
  function markAttempt(key) {
    c.need(!attempted.has(key), "MUTATION_ALREADY_ATTEMPTED");
    attempted.add(key);
  }
  return {
    async documents(paths) {
      c.need(paths.length <= 100 && new Set(paths).size === paths.length && paths.every(p => readAllowed.has(p)),
        "READ_SCOPE_INVALID");
      const rows = await request(FIRESTORE + ":batchGet", {documents: paths.map(p => PREFIX + p)});
      c.need(Array.isArray(rows) && rows.length === paths.length, "DOCUMENT_RESPONSE_INCOMPLETE");
      const found = new Map();
      for (const row of rows) {
        const name = row.found?.name || row.missing;
        c.need(typeof name === "string" && name.startsWith(PREFIX) && paths.includes(name.slice(PREFIX.length)) &&
          !found.has(name.slice(PREFIX.length)), "DOCUMENT_RESPONSE_SCOPE_INVALID");
        found.set(name.slice(PREFIX.length), row.found || null);
      }
      return found;
    },
    async accounts() {
      const result = await request(AUTH + ":lookup", {localId: actors.map(a => a.uid), email: actors.map(a => a.email)});
      c.need(!result.nextPageToken && (!result.users || Array.isArray(result.users)), "AUTH_RESPONSE_INVALID");
      return result.users || [];
    },
    async createAccount(actor) {
      c.need(actors.some(a => c.digest(a) === c.digest(actor)), "AUTH_CREATE_SCOPE_INVALID");
      markAttempt(`account:${actor.uid}`);
      return request(AUTH, {localId: actor.uid, email: actor.email, password: actor.password,
        emailVerified: true, displayName: `Removal QA ${actor.uid.split("-").at(-1)}`});
    },
    async createDocuments(documents) {
      c.need(documents.length > 0 && documents.length <= 33 &&
        new Set(documents.map(d => d.path)).size === documents.length &&
        documents.every(doc => allowed.has(doc.path) &&
          [...docs.scope, ...docs.business].some(expected => expected.path === doc.path &&
            c.digest(encode(expected.data)) === c.digest(encode(doc.data)))), "CREATE_SCOPE_INVALID");
      markAttempt(`documents:${c.digest(documents.map(doc => doc.path).sort())}`);
      return request(FIRESTORE + ":commit", {writes: documents.map(doc => ({
        update: {name: PREFIX + doc.path, fields: encode(doc.data).mapValue.fields},
        currentDocument: {exists: false},
      }))});
    },
  };
}
async function verifyDeployment({repo, candidate, receipt, execute = execFileSync}) {
  // captureState invokes Firebase CLI with inherited stderr. A piped worker is
  // the boundary: nested diagnostics cannot bypass the sanitized parent catch.
  const worker = `
    const fs=require("node:fs"),path=require("node:path");
    const input=JSON.parse(fs.readFileSync(0,"utf8")),root=process.cwd();
    const contract=require(path.join(root,"tools/web_release_contract"));
    const state=require(path.join(root,"tools/web_release_state"));
    (async()=>{
      contract.validateCandidate(input.candidate,"staging");
      const capture=state.verifyState(input.candidate,await state.captureState("attendus-staging"),
        JSON.parse(fs.readFileSync(path.join(root,"firestore.indexes.json"))));
      if(capture.stateSha256!==input.receipt.stateSha256)throw Error("changed");
      process.stdout.write(JSON.stringify({stateSha256:capture.stateSha256}));
    })().catch(()=>{process.exitCode=1;});
  `;
  let output;
  try {
    output = execute(process.execPath, ["-e", worker], {cwd: repo, encoding: "utf8",
      input: JSON.stringify({candidate, receipt}), timeout: 180000, maxBuffer: 2 * 1024 * 1024,
      stdio: ["pipe", "pipe", "pipe"]});
    c.need(JSON.parse(output).stateSha256 === receipt.stateSha256, "STAGING_DEPLOYMENT_CHANGED");
  } catch { c.need(false, "STAGING_DEPLOYMENT_CHECK_FAILED"); }
}
function canonicalHashes(documents, fixture) {
  return Object.fromEntries(fixture.canonicalEventIds.map(id => {
    const doc = documents.get(`Events/${id}`);
    c.need(doc?.createTime && doc.updateTime, "CANONICAL_EVENT_MISSING");
    return [id, c.digest(doc)];
  }));
}
function checkAccounts(actual, fixture, expectedCount) {
  c.need(actual.length === expectedCount && new Set(actual.map(a => a.localId)).size === actual.length,
    "AUTH_CREATE_READBACK_DIFFERS");
  for (const user of actual) c.need(c.ROLE_KEYS.some(key => fixture.roles[key].uid === user.localId &&
    fixture.roles[key].email === user.email) && user.emailVerified === true && !user.disabled,
  "AUTH_CREATE_IDENTITY_DIFFERS");
}
function verifyCreatedDocuments(expected, actual) {
  const discoveryFields = new Set(["geohash", "discoveryLocationValid", "primaryDiscoveryCategoryId",
    "discoveryCategoryIds", "discoveryCategorySource", "discoveryCategoryVersion", "discoveryMetadataUpdatedAt"]);
  for (const row of expected) {
    const current = actual.get(row.path);
    c.need(current?.name === PREFIX + row.path && current.createTime && current.updateTime,
      "SEED_DOCUMENT_READBACK_MISSING");
    const wanted = normalizedFields(encode(row.data).mapValue.fields);
    const got = normalizedFields(current.fields);
    c.need(got && Object.entries(wanted).every(([key, value]) => Object.hasOwn(got, key) &&
      c.digest(got[key]) === c.digest(value)),
      "SEED_DOCUMENT_VALUES_CHANGED");
    c.need(Object.keys(got).every(key => Object.hasOwn(wanted, key) ||
      row.path.startsWith("Events/") && discoveryFields.has(key)), "UNREVIEWED_TRIGGER_FIELDS");
  }
}
async function apply({repo, candidate, receipt, fixture, directory, api, verify = verifyDeployment}) {
  c.validateContext({repo, candidate, receipt, fixture});
  const age = Date.now() - Date.parse(fixture.preparedAt);
  c.need(fixture.state === "prepared" && age >= 0 && age < 2 * 3600000,
    "FRESH_PREPARED_FIXTURE_REQUIRED");
  const {scope, business} = buildDocuments(fixture), all = [...scope, ...business];
  await verify({repo, candidate, receipt});
  const before = await api.documents([...all.map(doc => doc.path), ...fixture.canonicalEventIds.map(id => `Events/${id}`)]);
  c.need(all.every(doc => before.get(doc.path) === null) && (await api.accounts()).length === 0,
    "FIXTURE_ID_ALREADY_EXISTS");
  const baseline = canonicalHashes(before, fixture);
  const canonicalEventVersions = Object.fromEntries(fixture.canonicalEventIds.map(id => {
    const doc = before.get(`Events/${id}`);
    return [id, {createTime: doc.createTime, updateTime: doc.updateTime}];
  }));
  const journal = c.createJournal(path.join(directory, "seed-attempt"));
  journal("start", {runId: fixture.runId, candidateSha256: fixture.candidateSha256,
    deploymentReceiptSha256: fixture.deploymentReceiptSha256, fixtureSha256: c.digest(fixture),
    scopePaths: scope.map(d => d.path), businessPaths: business.map(d => d.path)});
  c.save(path.join(directory, "canonical-before-private.json"), baseline);
  async function once(operation, identity, action) {
    journal("intent", {operation, identity});
    try { const value = await action(); journal("acknowledged", {operation, identity}); return value; }
    catch { journal("uncertain", {operation, identity, automaticRetry: false}); c.need(false, "SEED_OUTCOME_UNCERTAIN_RECONCILE"); }
  }
  await once("create-isolation", c.digest(scope.map(d => d.path)), () => api.createDocuments(scope));
  for (const [index, key] of c.ROLE_KEYS.entries()) {
    const actor = fixture.roles[key];
    const response = await once("create-auth", actor.uid, () => api.createAccount(actor));
    c.need(response.localId === actor.uid, "AUTH_CREATE_ACK_DIFFERS");
    checkAccounts(await api.accounts(), fixture, index + 1);
  }
  await verify({repo, candidate, receipt});
  await once("create-business", c.digest(business.map(d => d.path)), () => api.createDocuments(business));
  const current = await api.documents([...all.map(doc => doc.path), ...fixture.canonicalEventIds.map(id => `Events/${id}`)]);
  verifyCreatedDocuments(all, current);
  c.need(c.digest(canonicalHashes(current, fixture)) === c.digest(baseline), "CANONICAL_PILOT_CHANGED");
  checkAccounts(await api.accounts(), fixture, 3);
  await verify({repo, candidate, receipt});
  const seeded = {...fixture, state: "seeded", seededAt: new Date().toISOString(),
    canonicalEventSha256: baseline, canonicalEventVersions};
  c.save(path.join(directory, "seeded-fixture-private.json"), seeded);
  journal("complete", {fixtureSha256: c.digest(seeded), documentsCreated: 33, accountsCreated: 3,
    canonicalUnchanged: true});
  return {status: "seeded", runId: fixture.runId, documentsCreated: 33, accountsCreated: 3,
    canonicalUnchanged: true, privateContext: path.join(directory, "seeded-fixture-private.json")};
}
async function reconcile({repo, candidate, receipt, fixture, api, verify = verifyDeployment}) {
  c.validateContext({repo, candidate, receipt, fixture});
  await verify({repo, candidate, receipt});
  const {scope, business} = buildDocuments(fixture), all = [...scope, ...business];
  const docs = await api.documents(all.map(d => d.path)), users = await api.accounts();
  const counts = {missing: 0, exact: 0, changed: 0};
  for (const expected of all) {
    const actual = docs.get(expected.path);
    if (!actual) counts.missing++;
    else if (c.digest(normalizedFields(actual.fields)) === c.digest(normalizedFields(encode(expected.data).mapValue.fields))) counts.exact++;
    else counts.changed++;
  }
  const known = users.filter(user => c.ROLE_KEYS.some(key => fixture.roles[key].uid === user.localId &&
    fixture.roles[key].email === user.email));
  return {status: "reconciled-read-only", runId: fixture.runId, documents: counts,
    accountsPresent: known.length, foreignAccounts: users.length - known.length,
    automaticResumeAllowed: false, cloudWrites: 0};
}
function normalizedFields(value) {
  if (Array.isArray(value)) return value.map(normalizedFields);
  if (value && typeof value === "object") {
    if (Object.keys(value).length === 1 && value.timestampValue) return {timestampValue: new Date(value.timestampValue).toISOString()};
    return Object.fromEntries(Object.entries(value).map(([key, item]) => [key, normalizedFields(item)]));
  }
  return value;
}
async function main(argv) {
  const [mode, ...rest] = argv, args = c.options(rest), repo = path.resolve(args.repo || path.join(__dirname, ".."));
  c.need(["prepare", "apply", "reconcile"].includes(mode), "MODE_INVALID");
  c.assertLiveEnvironment();
  const candidate = read(args.candidate), receipt = read(args.receipt);
  c.sourceCheck(repo, candidate);
  if (mode === "prepare") {
    const fixture = prepare({repo, candidate, receipt, canonical: read(args.canonical)});
    const directory = c.privateDirectory(repo, args.directory);
    c.save(path.join(directory, "prepared-fixture-private.json"), fixture);
    return {status: "prepared", runId: fixture.runId, privateContext: path.join(directory, "prepared-fixture-private.json"),
      accounts: 3, events: 6, cloudWrites: 0};
  }
  const context = path.resolve(args.context), directory = path.dirname(context);
  c.need(directory.startsWith(path.resolve(repo, "build") + path.sep) &&
    fs.realpathSync(context) === context, "PRIVATE_CONTEXT_PATH_INVALID");
  const fixture = read(context);
  c.validateContext({repo, candidate, receipt, fixture});
  const accessToken = process.env.ATTENDUS_AUDIT_ACCESS_TOKEN;
  const auth = accessToken === undefined ? await require(path.join(repo, "tools/web_release_state")).googleClient() : undefined;
  const api = makeApi({fixture, auth, accessToken});
  return (mode === "apply" ? apply : reconcile)({repo, candidate, receipt, fixture, directory, api});
}
if (require.main === module) main(process.argv.slice(2)).then(result => console.log(JSON.stringify(result)))
  .catch(error => { console.error(JSON.stringify({status: "blocked", code: c.safeCode(error), noAutomaticRetry: true})); process.exitCode = 1; });
module.exports = {prepare, buildDocuments, encode, makeApi, apply, reconcile, verifyDeployment,
  verifyCreatedDocuments, canonicalHashes, bindingId};
