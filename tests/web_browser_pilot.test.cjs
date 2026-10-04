"use strict";
const {test} = require("node:test");
const assert = require("node:assert/strict");
const {createHash} = require("node:crypto");
const {runBrowserPilot, createPilotObserver, createGuestProofObserver, validatePilot} = require("../tools/web_release_producers/browser-pilot");
const {bindingId, emailHash} = require("../functions/communications/qualification-isolation");
const roles = ["owner", "attendee", "staff", "unauthorized"];
function fixture() {
  const runId = "webqa-20261004-1234567890";
  const value = {runId, projectId: "attendus-staging", sourceSha: "a".repeat(40), candidateRunId: "1234",
    controlledRecipientDomain: "example.test", event: {id: `${runId}-pilot`}, eventClosesAt: new Date(Date.now() + 3600000).toISOString()};
  for (const role of roles) value[role] = {uid: `${runId}-${role}`, email: `${runId}-${role}@example.test`};
  value.ownedFixtureIds = [value.event.id, ...roles.map((role) => value[role].uid)];
  return value;
}
function adapters(f, {allowUnauthorized = false, unsafeProvider = false, unknownRegistration = false} = {}) {
  const calls = [], state = {registered: false, admitted: false, announced: false, previews: 0};
  const event = {id: f.event.id, closesAt: f.eventClosesAt, revision: 1};
  return {calls, state,
    observe: async () => ({event, inboxCount: 0,
      registrations: state.registered ? [{id: "reg-1", status: "confirmed", identityType: "account"}] : [],
      attendance: state.admitted ? [{id: "attendance-1", registrationId: "reg-1", status: "checked_in"}] : [],
      priorAnnouncement: state.announced ? {previewToken: "preview-1", count: 1, status: "complete"} : null,
      captures: state.announced ? [{id: "capture-1", sourceKey: "announcement:preview-1", recipientUid: f.attendee.uid,
        provider: "qualification_capture", contentMatches: true, identityMatches: true},
      {id: "capture-email-1", sourceKey: "email:message-1", provider: "qualification_capture", contentMatches: true, identityMatches: true}] : [],
      messages: state.announced ? [{id: "message-1", announcementId: "preview-1", status: unsafeProvider ? "delivery_unknown" : "accepted", provider: "qualification_capture"}] : []}),
    callAs: async (role, name, data) => {
      calls.push({role, name, data: structuredClone(data)});
      assert.equal(data.eventId, f.event.id);
      if (role === "unauthorized") {
        if (allowUnauthorized) return {};
        throw Object.assign(Error("permission denied"), {status: "PERMISSION_DENIED"});
      }
      switch (name) {
        case "startPublicRegistrationV3":
          if (unknownRegistration) throw Object.assign(Error("transport timeout with secret URL"), {code: "deadline-exceeded"});
          assert.equal(role, "attendee"); assert.deepEqual(data.answers, {access: "Controlled accessibility answer"});
          state.registered = true; return {status: "confirmed", registrationId: "reg-1", claimToken: "NEVER-EMIT", manageUrl: "https://secret.example/proof"};
        case "startCheckInSession": assert.equal(role, "staff"); return {sessionId: "session-1"};
        case "submitCheckIn": {
          assert.equal(role, "staff"); assert.equal(data.credential.type, "staff_roster");
          assert.equal(data.credential.registrationId, "reg-1"); assert.deepEqual(data.answers, ["Door access code--ans--Controlled door answer"]);
          const created = !state.admitted; state.admitted = true; return {attendanceId: "attendance-1", created, status: "checked_in"};
        }
        case "listEventRosterV2": return {rows: [{registrationId: "reg-1", attendanceIds: ["attendance-1"]}]};
        case "createEventExportV2": return {jobId: "export-1"};
        case "getEventExportV2": return {status: "complete", rowCount: 1, generation: "123", url: "https://secret.example/signed"};
        case "previewEventAnnouncementV1": state.previews++; assert.equal(data.audience, "attendees"); return {previewToken: "preview-1", count: 1};
        case "sendEventAnnouncementV1": state.announced = true; return {announcementId: "preview-1", count: 1};
        case "getEventAnnouncementV1": return {status: "complete", failed: 0, unknown: 0, inAppStored: 0};
        default: throw Error(`Unexpected callable ${name}`);
      }
    }};
}
test("browser pilot uses exact authenticated APIs, safe receipts and explicit same-key retries", async () => {
  const f = fixture(), mock = adapters(f);
  const report = await runBrowserPilot({fixture: f, candidateIdentity: f, ...mock, timeoutMs: 100, pollIntervalMs: 0});
  assert.deepEqual(report.pilot, {registrationIds: ["reg-1"], attendanceIds: ["attendance-1"], exportJobId: "export-1", announcementId: "preview-1"});
  assert.ok(report.assertions.length >= 20);
  assert.ok(report.assertions.every((row) => JSON.stringify(row.expected) === JSON.stringify(row.actual)));
  assert.ok(!JSON.stringify(report).includes("NEVER-EMIT"));
  assert.ok(!JSON.stringify(report).includes("secret.example"));
  assert.equal(mock.calls.some((row) => /cancel|reschedule|updateEvent/.test(row.name)), false);
  const submissions = mock.calls.filter((row) => row.name === "submitCheckIn" && row.role === "staff");
  assert.deepEqual(submissions[0].data, submissions[1].data);
  assert.notEqual(submissions[1].data.idempotencyKey, submissions[2].data.idempotencyKey);
  await runBrowserPilot({fixture: f, candidateIdentity: f, ...mock, timeoutMs: 100, pollIntervalMs: 0});
  assert.equal(mock.state.previews, 1, "a rerun reuses the actual prior announcement, never sends a fresh preview");
});
test("pilot blocks wrong targets, identity drift, unowned roles and missing private observer before calls", async () => {
  const f = fixture();
  for (const change of [{projectId: "orgami-66nxok"}, {sourceSha: "b".repeat(40)}, {candidateRunId: "different"}]) {
    assert.throws(() => validatePilot(f, {...f, ...change}));
  }
  assert.throws(() => validatePilot({...f, ownedFixtureIds: [f.event.id]}, f));
  await assert.rejects(() => runBrowserPilot({fixture: f, candidateIdentity: f, callAs: () => assert.fail("must not call")}), /observation/);
});
test("authorization failures and unknown transport outcomes cannot become successful pilot evidence", async () => {
  const f = fixture(), mock = adapters(f, {allowUnauthorized: true});
  await assert.rejects(() => runBrowserPilot({fixture: f, candidateIdentity: f, ...mock}), (error) => {
    assert.equal(error.pilotReport.assertions.at(-1).actual, "unexpected-success");
    assert.equal(error.pilotReport.pilot.announcementId, null); return true;
  });
  const uncertain = adapters(f, {unknownRegistration: true});
  await assert.rejects(() => runBrowserPilot({fixture: f, candidateIdentity: f, ...uncertain}), (error) => {
    assert.ok(!JSON.stringify(error.pilotReport).includes("secret URL")); return true;
  });
  assert.equal(uncertain.calls.length, 1, "unknown mutation outcomes are not automatically retried");
  await assert.rejects(() => runBrowserPilot({fixture: f, candidateIdentity: f, ...adapters(f, {unsafeProvider: true})}), /delivery requires review/);
});
test("private observer validates actual scope, setup and bindings and exposes no capture payload", async () => {
  const f = fixture(), now = new Date(), values = new Map();
  values.set(`Events/${f.event.id}`, {customerUid: f.owner.uid, status: "active", private: false, checkInStaff: [f.staff.uid], eventRevision: 1,
    checkInPolicy: {eligibility: "registered_only"},
    selectedDateTime: new Date(Date.parse(f.eventClosesAt) - 7200000), eventDurationMinutes: 120});
  values.set(`QualificationScopes/${f.runId}`, {schemaVersion: 1, projectId: f.projectId, status: "active", mode: "capture", createdAt: now,
    expiresAt: new Date(now.getTime() + 3600000), actorUids: roles.map((role) => f[role].uid), recipientUids: roles.map((role) => f[role].uid),
    eventIds: [f.event.id], organizationIds: [], conversationIds: [], recipientEmailHashes: []});
  values.set(`QualificationSetup/${f.runId}`, {...f, state: "seeded"});
  for (const [kind, id] of [["event", f.event.id], ...roles.map((role) => ["account", f[role].uid])])
    values.set(`QualificationBindings/${bindingId(kind, id)}`, {schemaVersion: 1, projectId: f.projectId, runId: f.runId, state: "bound"});
  const snapshot = (path) => ({exists: values.has(path), id: path.split("/").at(-1), get: (key) => values.get(path)?.[key], data: () => values.get(path)});
  const queries = [];
  const hash = (value) => createHash("sha256").update(value).digest("hex");
  const payload = {title: "Private synthetic message", manageUrl: "https://secret.example/proof"};
  const captureId = hash(JSON.stringify([f.runId, f.attendee.uid, "announcement:preview-1"]));
  const capturePath = `QualificationCaptures/${captureId}`;
  values.set(capturePath, {runId: f.runId, recipientUid: f.attendee.uid, sourceKey: "announcement:preview-1", eventIds: [f.event.id],
    provider: "qualification_capture", payload, fingerprint: hash(JSON.stringify(payload))});
  function query(name) {
    return {where: (...args) => {queries.push({name, args}); return query(name);}, limit: () => query(name),
      doc: (id) => ({collection: (sub) => query(`${name}/${id}/${sub}`)}),
      get: async () => name === "QualificationCaptures" ? {docs: [snapshot(capturePath)], size: 1} : {docs: [], size: 0}};
  }
  const db = {projectId: f.projectId, doc: (path) => ({path}), collection: query,
    runTransaction: (work, options) => {assert.deepEqual(options, {readOnly: true}); return work({get: async (ref) => snapshot(ref.path)});}};
  const observer = createPilotObserver({fixture: f, candidateIdentity: f, db});
  const value = await observer();
  assert.equal(value.event.closesAt, f.eventClosesAt); assert.equal(value.inboxCount, 0);
  assert.equal(value.captures[0].contentMatches, true); assert.equal(value.captures[0].identityMatches, true);
  assert.ok(!JSON.stringify(value).includes("secret.example"));
  assert.ok(queries.some((q) => q.name === "QualificationCaptures" && q.args[2] === f.runId));
  values.get(`QualificationBindings/${bindingId("account", f.staff.uid)}`).state = "tombstone";
  await assert.rejects(observer, /scope changed/);
  assert.throws(() => createPilotObserver({fixture: f, candidateIdentity: f, db: {...db, projectId: "orgami-66nxok"}}));
});

function guestProofFixture() {
  const f = fixture(), now = new Date(), values = new Map(), sha = (value) => createHash("sha256").update(value).digest("hex");
  const proof = "x".repeat(43), manageUrl = `https://attendus-staging.web.app/manage/${proof}`;
  const recipientEmailHash = emailHash(`${f.runId}-guest@example.test`), sourceKey = "email:registration_flow_123";
  const captureId = sha(JSON.stringify([f.runId, recipientEmailHash, sourceKey]));
  const payload = {messageId: "registration_flow_123", templateId: "guest_registration_confirmation", eventId: f.event.id,
    text: `View registration: ${manageUrl}`, html: `<a href="${manageUrl}">View registration</a>`};
  values.set(`Events/${f.event.id}`, {customerUid: f.owner.uid, status: "active", private: false, checkInStaff: [f.staff.uid],
    checkInPolicy: {eligibility: "registered_only"}, selectedDateTime: new Date(Date.parse(f.eventClosesAt) - 7200000), eventDurationMinutes: 120});
  values.set(`QualificationScopes/${f.runId}`, {schemaVersion: 1, projectId: f.projectId, status: "active", mode: "capture", createdAt: now,
    expiresAt: new Date(now.getTime() + 3600000), actorUids: roles.map((role) => f[role].uid), recipientUids: roles.map((role) => f[role].uid),
    eventIds: [f.event.id], organizationIds: [], conversationIds: [], recipientEmailHashes: [recipientEmailHash]});
  values.set(`QualificationSetup/${f.runId}`, {...f, state: "seeded"});
  for (const [kind, id] of [["event", f.event.id], ...roles.map((role) => ["account", f[role].uid])])
    values.set(`QualificationBindings/${bindingId(kind, id)}`, {schemaVersion: 1, projectId: f.projectId, runId: f.runId, state: "bound"});
  values.set(`QualificationCaptures/${captureId}`, {schemaVersion: 1, runId: f.runId, recipientEmailHash, recipientUid: null,
    sourceKey, eventIds: [f.event.id], provider: "qualification_capture", payload, fingerprint: sha(JSON.stringify(payload)),
    capturedAt: now, expiresAt: new Date(now.getTime() + 3600000)});
  values.set("OutboundMessages/registration_flow_123", {status: "accepted", provider: "qualification_capture", captureId,
    eventId: f.event.id, templateId: payload.templateId, registrationId: "registration_123", guestId: "guest_123", payload: {manageUrl}});
  values.set(`GuestManageTokens/${sha(proof)}`, {status: "active", registrationId: "registration_123", guestId: "guest_123", expiresAt: new Date(now.getTime() + 3600000)});
  values.set("RegisterAttendance/registration_123", {eventId: f.event.id, guestId: "guest_123", customerUid: "anonymous-guest", identityType: "guest", status: "confirmed"});
  values.set("GuestAttendees/guest_123", {ownerUid: "anonymous-guest"});
  const snapshot = (path) => ({exists: values.has(path), id: path.split("/").at(-1), get: (key) => values.get(path)?.[key], data: () => values.get(path)});
  const db = {projectId: f.projectId, doc: (path) => ({path}), collection: (name) => ({where: (field, op, value) => {
    assert.equal(name, "QualificationCaptures"); assert.deepEqual([field, op, value], ["runId", "==", f.runId]);
    return {limit: (limit) => {assert.equal(limit, 1001); return {query: name};}};
  }}), runTransaction: (work, options) => {
    assert.deepEqual(options, {readOnly: true});
    return work({get: async (ref) => ref.query ? {size: 1, docs: [snapshot(`QualificationCaptures/${captureId}`)]} : snapshot(ref.path)});
  }};
  return {f, values, captureId, proof, manageUrl, notBefore: new Date(now.getTime() - 1000).toISOString(),
    observe: createGuestProofObserver({fixture: f, candidateIdentity: f, db})};
}

test("guest proof observer resolves only a recent captured email to its current admission without mutations", async () => {
  const f = guestProofFixture(), result = await f.observe({notBefore: f.notBefore});
  assert.deepEqual(Object.keys(result).sort(), ["captureId", "fingerprint", "manageUrl", "registrationId", "status"]);
  assert.equal(result.manageUrl, f.manageUrl); assert.equal(result.registrationId, "registration_123");
  assert.equal(result.status, "confirmed"); assert.equal(result.captureId, f.captureId);
  f.values.get("OutboundMessages/registration_flow_123").status = "sending";
  assert.equal(await f.observe({notBefore: f.notBefore}), null, "await source delivery acknowledgement after the capture commits");
});

test("guest proof observer never reuses an older capture or releases wrong-recipient evidence", async () => {
  const f = guestProofFixture(), capture = f.values.get(`QualificationCaptures/${f.captureId}`);
  capture.capturedAt = new Date(Date.parse(f.notBefore) - 1);
  assert.equal(await f.observe({notBefore: f.notBefore}), null);
  capture.capturedAt = new Date(); capture.recipientEmailHash = "f".repeat(64);
  assert.equal(await f.observe({notBefore: f.notBefore}), null);
  await assert.rejects(() => f.observe({notBefore: "invalid"}), /recent browser/);
});

test("guest proof observer blocks tampering, production links, revoked tokens and deletion", async () => {
  for (const mutate of [
    (f) => {f.values.get(`QualificationCaptures/${f.captureId}`).fingerprint = "0".repeat(64);},
    (f) => {f.values.get("OutboundMessages/registration_flow_123").payload.manageUrl = `https://attendus.app/manage/${f.proof}`;},
    (f) => {f.values.get(`GuestManageTokens/${createHash("sha256").update(f.proof).digest("hex")}`).status = "revoked";},
    (f) => {f.values.set("account_deletion_jobs/anonymous-guest", {status: "pending"});},
    (f) => {f.values.get("RegisterAttendance/registration_123").eventId = "another-event";},
  ]) {
    const f = guestProofFixture(); mutate(f); await assert.rejects(() => f.observe({notBefore: f.notBefore}));
  }
});
