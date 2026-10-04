"use strict";
const test = require("node:test"), assert = require("node:assert/strict");
const fs = require("node:fs"), os = require("node:os"), path = require("node:path"), vm = require("node:vm");
const c = require("../tools/web_release_contract");
const {validateRequests, runReplay, pageCallable, verifiedReplay, createReplayObserver, RAW} = require("../tools/web_release_producers/browser-replay");
const {validatePilot} = require("../tools/web_release_producers/browser-pilot");
const {bindingId} = require("../functions/communications/qualification-isolation");
const {digest: registrationDigest} = require("../functions/public-web/accountless");
const {normalizePolicy} = require("../functions/attendance/v2");
function fixture(expired = false) {
  const now = Date.now(), runId = "webqa-20261004-1234567890", close = now - (expired ? 27 : 2) * 3600000;
  const f = {projectId: "attendus-staging", sourceSha: "a".repeat(40), candidateRunId: "123", runId,
    controlledRecipientDomain: "example.test", event: {id: `${runId}-pilot`}, eventClosesAt: new Date(close).toISOString()};
  for (const role of ["owner", "attendee", "staff", "unauthorized"]) f[role] = {uid: `${runId}-${role}`, email: `${runId}-${role}@example.test`};
  f.ownedFixtureIds = [f.event.id, ...["owner", "attendee", "staff", "unauthorized"].map((role) => f[role].uid)];
  const eventData = {customerUid: f.owner.uid, selectedDateTime: new Date(close - 7200000), eventDurationMinutes: 120,
    status: "active", private: false, checkInStaff: [f.staff.uid], eventRevision: 1,
    checkInPolicy: {version: 2, profile: "staff_entry", openingMode: "manual", eligibility: "registered_only"}};
  const event = {id: f.event.id, revision: 1, closesAt: f.eventClosesAt, effectiveClosesAt: new Date(close + 3600000).toISOString(), policySha256: c.digest(normalizePolicy(eventData))};
  const requests = {
    registration: {role: "attendee", name: "startPublicRegistrationV3", data: {eventId: f.event.id, idempotencyKey: `${runId}:account-registration`, fullName: "Controlled pilot attendee", email: f.attendee.email, answers: {access: "Controlled accessibility answer"}}},
    admission: {role: "staff", name: "submitCheckIn", data: {eventId: f.event.id, sessionId: "session-1", idempotencyKey: `${runId}:manual-admission`, credential: {type: "staff_roster", attendeeId: f.attendee.uid, registrationId: "reg-1"}, answers: ["Door access code--ans--Controlled door answer"]}},
    export: {role: "owner", name: "createEventExportV2", data: {eventId: f.event.id, idempotencyKey: `${runId}:pilot-export`}},
    announcement: {role: "owner", name: "sendEventAnnouncementV1", requestSha256: c.digest({eventId: f.event.id, previewToken: "announcement-1"})},
  };
  for (const value of Object.values(requests)) if (value.data) value.requestSha256 = c.digest(value.data);
  const receipt = {schemaVersion: 1, identity: validatePilot(f, f), startedAt: new Date(close - 7200000).toISOString(), completedAt: new Date(close - 3600000).toISOString(),
    assertions: [{id: "pilot-completed", expected: true, actual: true}], replayRequests: requests,
    pilot: {registrationIds: ["reg-1"], attendanceIds: ["attendance-1"], exportJobId: "export-1", announcementId: "announcement-1"},
    pilotExport: {jobId: "export-1", status: "complete", generation: "42", rowCount: 1, objectPath: "private-event-exports/export-1/lease-1.csv", expiresAt: new Date(close + 23 * 3600000).toISOString()},
    observations: [{phase: "after", event}]};
  const candidate = {projectId: f.projectId, sourceSha: f.sourceSha, candidateRunId: f.candidateRunId, webSha256: "b".repeat(64), deploymentSha256: "c".repeat(64), configSha256: "d".repeat(64),
    sourceFiles: {"tools/web_release_producers/browser.js": "e".repeat(64)}};
  const original = {receipt, pilot: receipt.pilot, provenance: {workflowRunId: "11", reportSha256: "1".repeat(64), receiptPath: "pilot-receipts.json", receiptSha256: c.digest(receipt)}};
  const context = {...f, fixture: f, deployment: {stateSha256: "f".repeat(64)}, priorEvidence: []};
  const snapshot = {state: {event: structuredClone(event), eventDocumentSha256: c.digest(eventData), records: {Attendance: [{id: "attendance-1", sha256: "a".repeat(64)}], EventExportJobs: expired ? [] : [{id: "export-1", sha256: "b".repeat(64)}]}, captures: [], rosterSha256: "c".repeat(64)},
    announcementData: {eventId: f.event.id, previewToken: "announcement-1"}, observedAt: new Date(now).toISOString(),
    exportDecision: {action: expired ? "omitted-expired" : "replay", exists: !expired, expiresAt: receipt.pilotExport.expiresAt, originalJobId: "export-1", originalGeneration: "42"}};
  const calls = [], connected = new Map();
  const adapters = {observe: async () => structuredClone(snapshot), connect: async (role, online) => {connected.set(role, online);}, invoke: async (role, name, data) => {
    const online = connected.get(role); calls.push({role, name, data: structuredClone(data), online});
    const time = new Date().toISOString();
    return {transport: "page-fetch", actorUid: f[role].uid, online, startedAt: time, finishedAt: time, httpStatus: online ? name === "submitCheckIn" ? 400 : 200 : null,
      status: online ? name === "submitCheckIn" ? "FAILED_PRECONDITION" : "OK" : "NETWORK_ERROR",
      result: online ? {registrationId: "reg-1", jobId: "export-1", announcementId: "announcement-1"} : null};
  }};
  return {f, context, candidate, original, snapshot, calls, adapters, eventData};
}

test("post-close replay uses exact retained envelopes, real disconnected response and unchanged private state", async () => {
  const f = fixture(), result = await runReplay({...f, ...f.adapters});
  assert.equal(result.requests.length, 4); assert.equal(f.calls.length, 8);
  for (let i = 0; i < f.calls.length; i += 2) {assert.equal(f.calls[i].online, false); assert.equal(f.calls[i + 1].online, true); assert.deepEqual(f.calls[i].data, f.calls[i + 1].data);}
  assert.ok(result.assertions.every((row) => c.digest(row.expected) === c.digest(row.actual)));
  assert.equal(JSON.stringify(result).includes("previewToken"), false);
});

test("expired export is omitted with original expiry proof and never recreated", async () => {
  const f = fixture(true), result = await runReplay({...f, ...f.adapters});
  assert.equal(result.exportDecision.action, "omitted-expired"); assert.equal(result.requests.length, 3);
  assert.equal(f.calls.some((row) => row.name === "createEventExportV2"), false);
});

test("wrong candidate, changed request and fake offline transport fail closed", async () => {
  for (const change of [
    (f) => {f.candidate.projectId = "orgami-66nxok";},
    (f) => {f.context.sourceSha = "9".repeat(40);},
    (f) => {f.original.receipt.replayRequests.registration.data.idempotencyKey += ":new";},
    (f) => {const invoke = f.adapters.invoke; f.adapters.invoke = async (...args) => ({...await invoke(...args), transport: "node-fetch"});},
    (f) => {f.adapters.connect = async () => {};},
    (f) => {f.snapshot.state.event.effectiveClosesAt = new Date(Date.now() + 60000).toISOString();},
    (f) => {f.snapshot.state.event.policySha256 = "different";},
  ]) {
    const f = fixture(); change(f); await assert.rejects(() => runReplay({...f, ...f.adapters}));
  }
});

test("changed admission/job/capture state or a different server receipt cannot pass", async () => {
  for (const change of [
    (f) => {const observe = f.adapters.observe; let count = 0; f.adapters.observe = async () => {const value = await observe(); if (++count > 2) value.state.records.Attendance.push({id: "unexpected", sha256: "new"}); return value;};},
    (f) => {const invoke = f.adapters.invoke; f.adapters.invoke = async (...args) => {const value = await invoke(...args); if (value.result) value.result.registrationId = "wrong"; return value;};},
  ]) {const f = fixture(); change(f); await assert.rejects(() => runReplay({...f, ...f.adapters}));}
});

test("page callable really executes browser fetch and exposes no auth or management bearer", async () => {
  const calls = []; let online = false;
  const page = {evaluate: (fn, args) => vm.runInNewContext(`(${fn.toString()})(args)`, {args, Date, AbortSignal, navigator: {onLine: online}, fetch: async (url, options) => {
    calls.push({url, options}); if (!online) throw new TypeError("offline");
    return {ok: true, status: 200, json: async () => ({result: {registrationId: "reg-1", claimToken: "DO-NOT-EMIT", manageUrl: "https://private.example/proof"}})};
  }})};
  const args = {name: "startPublicRegistrationV3", data: {eventId: "owned"}, token: "AUTH-SECRET", appCheckToken: "APP-SECRET", actorUid: "actor"};
  const off = await pageCallable(page, args); assert.equal(off.status, "NETWORK_ERROR"); assert.equal(off.online, false);
  online = true; const on = await pageCallable(page, args); assert.equal(on.status, "OK"); assert.equal(on.result.registrationId, "reg-1");
  assert.equal(calls.length, 2); assert.equal(calls[1].options.headers["X-Firebase-AppCheck"], "APP-SECRET");
  for (const secret of ["AUTH-SECRET", "APP-SECRET", "DO-NOT-EMIT", "private.example"]) assert.equal(JSON.stringify([off, on]).includes(secret), false);
});

function evidence(f, dir, gate, rawName, value, startedAt, finishedAt) {
  fs.writeFileSync(path.join(dir, rawName), JSON.stringify(value));
  return {schemaVersion: 1, gate, environment: "staging", projectId: f.candidate.projectId, sourceSha: f.candidate.sourceSha,
    candidateRunId: f.candidate.candidateRunId, candidateSha256: c.digest(f.candidate), webSha256: f.candidate.webSha256,
    deploymentSha256: f.candidate.deploymentSha256, configSha256: f.candidate.configSha256,
    producer: "tools/web_release_producers/browser.js", producerSha256: f.candidate.sourceFiles["tools/web_release_producers/browser.js"], workflowRunId: gate === "post-close-replay" ? "12" : "11",
    startedAt, finishedAt, observedStateSha256: f.context.deployment.stateSha256, assertions: value.assertions, blockers: [],
    rawFiles: {[rawName]: c.sha256(fs.readFileSync(path.join(dir, rawName)))}};
}
test("passive observations cannot replace provenanced replay; wrong source, raw bytes and timing are rejected", async (t) => {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), "attendus-replay-"));
  t.after(() => {assert.equal(path.dirname(path.resolve(dir)), path.resolve(os.tmpdir())); fs.rmSync(dir, {recursive: true});});
  const f = fixture(), original = evidence(f, dir, "browser-auth-guest-organizer", "pilot-receipts.json", f.original.receipt, f.original.receipt.startedAt, f.original.receipt.completedAt);
  f.original.provenance = {workflowRunId: original.workflowRunId, reportSha256: c.digest(original), receiptPath: "pilot-receipts.json", receiptSha256: original.rawFiles["pilot-receipts.json"]};
  f.context.priorEvidence = [{report: original, outputDir: dir}];
  assert.throws(() => verifiedReplay(f.candidate, f.context), /passive observations/);
  const raw = await runReplay({...f, ...f.adapters});
  const report = evidence(f, dir, "post-close-replay", RAW, raw, raw.startedAt, raw.completedAt);
  f.context.priorEvidence.push({report, outputDir: dir});
  assert.equal(verifiedReplay(f.candidate, f.context).receipt.requests.length, 4);
  report.sourceSha = "9".repeat(40); assert.throws(() => verifiedReplay(f.candidate, f.context), /different candidate/); report.sourceSha = f.candidate.sourceSha;
  fs.appendFileSync(path.join(dir, RAW), " "); assert.throws(() => verifiedReplay(f.candidate, f.context), /changed/);
  report.rawFiles[RAW] = c.sha256(fs.readFileSync(path.join(dir, RAW)));
  raw.requests[0].offline.startedAt = "not-a-time"; fs.writeFileSync(path.join(dir, RAW), JSON.stringify(raw)); report.rawFiles[RAW] = c.sha256(fs.readFileSync(path.join(dir, RAW)));
  assert.throws(() => verifiedReplay(f.candidate, f.context), /reconnect receipts/);
});

test("guarded observer rejects missing original receipts and premature export disappearance without writes", async () => {
  const f = fixture(), values = new Map(), now = new Date(), stamp = (iso) => ({toDate: () => new Date(iso)});
  values.set(`Events/${f.f.event.id}`, f.eventData);
  values.set(`QualificationScopes/${f.f.runId}`, {schemaVersion: 1, projectId: f.f.projectId, status: "active", mode: "capture", createdAt: now,
    expiresAt: new Date(Date.now() + 3600000), actorUids: ["owner", "attendee", "staff", "unauthorized"].map((role) => f.f[role].uid), recipientUids: ["owner", "attendee", "staff", "unauthorized"].map((role) => f.f[role].uid), eventIds: [f.f.event.id], organizationIds: [], conversationIds: [], recipientEmailHashes: []});
  values.set(`QualificationSetup/${f.f.runId}`, {...f.f, state: "seeded"});
  for (const [kind, id] of [["event", f.f.event.id], ...["owner", "attendee", "staff", "unauthorized"].map((role) => ["account", f.f[role].uid])]) values.set(`QualificationBindings/${bindingId(kind, id)}`, {schemaVersion: 1, projectId: f.f.projectId, runId: f.f.runId, state: "bound"});
  values.set("CheckInSessions/session-1", {eventId: f.f.event.id});
  values.set("RegisterAttendance/reg-1", {eventId: f.f.event.id, customerUid: f.f.attendee.uid, status: "confirmed"});
  values.set("Attendance/attendance-1", {eventId: f.f.event.id, customerUid: f.f.attendee.uid, status: "checked_in", registrationId: "reg-1", sessionId: "session-1"});
  const input = f.original.receipt.replayRequests.registration.data;
  values.set(`PublicRegistrationFlows/flow_${registrationDigest("v3", f.f.event.id, f.f.attendee.uid, input.idempotencyKey)}`, {eventId: f.f.event.id,
    ownerUid: f.f.attendee.uid, requestFingerprint: registrationDigest(input.fullName, input.email, JSON.stringify(Object.entries(input.answers))), result: {registrationId: "reg-1"}});
  values.set("EventAnnouncements/announcement-1", {eventId: f.f.event.id, actorUid: f.f.owner.uid, status: "complete"});
  values.set("EventExportJobs/export-1", {eventId: f.f.event.id, actorUid: f.f.owner.uid, status: "complete", generation: "42", expiresAt: stamp(f.original.receipt.pilotExport.expiresAt)});
  const snapshot = (key) => ({id: key.split("/").at(-1), exists: values.has(key), data: () => values.get(key), get: (field) => values.get(key)?.[field]});
  const db = {projectId: f.f.projectId, doc: (key) => ({key}), collection: (name) => ({where: (field, op, value) => ({limit: () => ({name, field, value})})}),
    runTransaction: async (work, options) => {assert.deepEqual(options, {readOnly: true}); return work({get: async (query) => {
      if (query.key) return snapshot(query.key);
      const docs = [...values].filter(([key, value]) => key.startsWith(query.name + "/") && value[query.field] === query.value).map(([key]) => snapshot(key)); return {size: docs.length, docs};
    }});}};
  const observe = createReplayObserver({fixture: f.f, candidateIdentity: f.context, db, original: f.original});
  assert.equal((await observe()).exportDecision.action, "replay");
  values.delete("EventExportJobs/export-1"); await assert.rejects(observe, /unexpired original export disappeared/);
  values.delete("Attendance/attendance-1"); await assert.rejects(observe, /Original admission/);
});
