"use strict";
const test = require("node:test");
const assert = require("node:assert/strict");
const {validateContext, inspectJobs, previewRelease, pilotReceipt, runtimeFlags, inspectPilotExport} = require("./web_release_producers/operations");
const fs = require("node:fs"), os = require("node:os"), path = require("node:path");
const {digest, sha256} = require("./web_release_contract");
test("operational evidence cannot target production or an unowned event", () => {
  const candidate = {environment: "staging", projectId: "attendus-staging"};
  const context = {projectId: "attendus-staging", baseUrl: "https://attendus-staging.web.app", fixture: {runId: "owned_run_20261004", owner: {uid: "owner"}, event: {id: "owned"}, ownedFixtureIds: ["owned"], eventClosesAt: "2026-10-04T12:00:00Z"}};
  assert.equal(validateContext(candidate, context).runId, context.fixture.runId);
  assert.throws(() => validateContext({...candidate, environment: "production", projectId: "orgami-66nxok"}, context));
  assert.throws(() => validateContext(candidate, {...context, baseUrl: "https://attendus.app"}));
  assert.throws(() => validateContext(candidate, {...context, fixture: {}}));
  for (const name of ["FIRESTORE_EMULATOR_HOST", "FIREBASE_AUTH_EMULATOR_HOST", "FIREBASE_STORAGE_EMULATOR_HOST", "STORAGE_EMULATOR_HOST", "FIREBASE_DATABASE_EMULATOR_HOST"]) {
    assert.throws(() => validateContext(candidate, context, {[name]: "127.0.0.1:9299"}), /deployed isolated staging/);
  }
});
test("failed, unknown, stranded and still pending closed-event jobs fail qualification", () => {
  const observations = inspectJobs([{id: "failed", status: "failed"}, {id: "unknown", status: "delivery_unknown"},
    {id: "stuck", status: "processing", leaseUntil: "2026-10-04T11:00:00Z"}], "2026-10-04T13:00:00Z", "2026-10-04T12:00:00Z");
  assert.deepEqual(observations[0].actual, ["failed", "unknown"]);
  assert.deepEqual(observations[1].actual, ["stuck"]);
  assert.deepEqual(observations[2].actual, ["failed", "unknown", "stuck"]);
});
test("rollback rehearsal rejects live channels and cross-project versions before network access", async () => {
  const client = {request() {throw Error("must not request");}};
  await assert.rejects(previewRelease(client, {}, "live", "sites/attendus-staging/versions/prior"), /dedicated staging preview/);
  await assert.rejects(previewRelease(client, {}, "qa-rollback-1234567812345678", "sites/orgami-66nxok/versions/prior"), /dedicated staging preview/);
});
test("pilot requires immutable browser evidence and rejects changed receipts or deployment", () => {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), "web-pilot-proof-"));
  try {
    const producer = "tools/web_release_producers/browser.js", hash = "a".repeat(64);
    const candidate = {projectId: "attendus-staging", sourceSha: "b".repeat(40), candidateRunId: "123",
      webSha256: hash, deploymentSha256: hash, configSha256: hash, sourceFiles: {[producer]: hash}};
    const fixture = {runId: "webqa-20261004-1234567890", event: {id: "pilot"}, pilot: {registrationIds: ["fabricated"]}};
    const context = {fixture, deployment: {stateSha256: hash}};
    assert.throws(() => pilotReceipt(candidate, context), /immutable browser evidence/);
    const receipt = {schemaVersion: 1, identity: {schemaVersion: 1, projectId: candidate.projectId, sourceSha: candidate.sourceSha,
      candidateRunId: candidate.candidateRunId, runId: fixture.runId, eventId: fixture.event.id},
    startedAt: "2026-10-03T10:01:00Z", completedAt: "2026-10-03T10:02:00Z", assertions: [{id: "created", expected: true, actual: true}],
    pilot: {registrationIds: ["actual-registration"], attendanceIds: ["actual-attendance"], exportJobId: "actual-export", announcementId: "actual-announcement"}};
    const rawPath = path.join(root, "pilot-receipts.json"); fs.writeFileSync(rawPath, JSON.stringify(receipt));
    const report = {schemaVersion: 1, gate: "browser-auth-guest-organizer", environment: "staging", projectId: candidate.projectId,
      sourceSha: candidate.sourceSha, candidateRunId: candidate.candidateRunId, candidateSha256: digest(candidate),
      webSha256: hash, deploymentSha256: hash, configSha256: hash, producer, producerSha256: hash, workflowRunId: "456",
      startedAt: "2026-10-03T10:00:00Z", finishedAt: "2026-10-03T10:03:00Z", observedStateSha256: hash,
      assertions: receipt.assertions, blockers: [], rawFiles: {"pilot-receipts.json": sha256(fs.readFileSync(rawPath))}};
    context.priorEvidence = [{report, outputDir: root}];
    assert.deepEqual(pilotReceipt(candidate, context).pilot, receipt.pilot);
    assert.throws(() => pilotReceipt(candidate, {...context, deployment: {stateSha256: "c".repeat(64)}}), /deployment differs/);
    fs.writeFileSync(rawPath, JSON.stringify({...receipt, pilot: fixture.pilot}));
    assert.throws(() => pilotReceipt(candidate, context), /Raw evidence changed/);
  } finally {fs.rmSync(root, {recursive: true, force: true});}
});
test("live paid/provider flags and fixture rollout scope must stay restricted", () => {
  const fixture = {event: {id: "owned-event"}, ownedFixtureIds: ["owned-event", "owner"], firebase: {appCheckSiteKey: "public-site-key"}};
  const publicWeb = {publicPagesEnabled: true, inlineRegistrationEnabled: true, accountlessRegistrationEnabled: true,
    paidTicketCheckoutEnabled: false, appCheckSiteKey: "public-site-key"};
  const attendance = {appleDelivery: {enabled: false}, googleDelivery: {enabled: false},
    corePasses: {enabled: true, eventIds: ["owned-event"], userIds: ["owner"]},
    smartArrival: {enabled: true, eventIds: ["owned-event"], userIds: ["owner"]}};
  assert.equal(runtimeFlags(publicWeb, attendance, fixture).paidTicketCheckoutEnabled, false);
  assert.throws(() => runtimeFlags({...publicWeb, paidTicketCheckoutEnabled: true}, attendance, fixture), /flags changed/);
  assert.throws(() => runtimeFlags(publicWeb, {...attendance, appleDelivery: {enabled: true}}, fixture), /flags changed/);
  assert.throws(() => runtimeFlags(publicWeb, {...attendance, corePasses: {...attendance.corePasses, allEvents: true}}, fixture), /outside owned/);
  assert.throws(() => runtimeFlags(publicWeb, {...attendance, smartArrival: {...attendance.smartArrival, userIds: []}}, fixture), /outside owned/);
});

function exportFixture() {
  const jobId = "e".repeat(64);
  const original = {jobId, status: "complete", generation: "roster-generation", rowCount: 2,
    objectPath: `private-event-exports/${jobId}/lease-fixture.csv`, expiresAt: "2026-10-05T10:00:00.000Z"};
  return {pilot: {exportJobId: jobId, registrationIds: ["registration"]},
    receipt: {pilotExport: original, completedAt: "2026-10-04T10:01:00.000Z"},
    fixture: {event: {id: "owned-event"}, owner: {uid: "owner"}},
    current: {...original, id: jobId, eventId: "owned-event", actorUid: "owner"},
    readMetadata: async () => ({name: original.objectPath, generation: "123456789", size: "10"}),
    now: Date.parse("2026-10-04T11:00:00Z")};
}
test("pilot export completion remains verifiable after documented expiry and object cleanup", async () => {
  const input = exportFixture();
  assert.equal((await inspectPilotExport(input)).disposition, "complete_unexpired");
  const after = {...input, now: Date.parse(input.receipt.pilotExport.expiresAt),
    readMetadata: async () => {throw Object.assign(Error("absent"), {code: 404});}};
  for (const current of [input.current, undefined]) {
    const result = await inspectPilotExport({...after, current});
    assert.equal(result.disposition, "completed_then_expired_object_removed");
    assert.equal(result.objectPresent, false);
    assert.equal(result.jobPresent, !!current);
  }
});
test("pilot export rejects early disappearance, retained expired bytes, or changed identity", async () => {
  const input = exportFixture();
  await assert.rejects(inspectPilotExport({...input, current: undefined}), /before expiry/);
  await assert.rejects(inspectPilotExport({...input, readMetadata: async () => null}), /unavailable before expiry/);
  await assert.rejects(inspectPilotExport({...input, now: Date.parse(input.receipt.pilotExport.expiresAt)}), /has not been removed/);
  for (const change of [{generation: "recreated"}, {eventId: "other-event"}, {actorUid: "other-owner"}, {rowCount: 3},
    {expiresAt: "2026-10-06T10:00:00.000Z"}, {objectPath: "private-event-exports/other.csv"}]) {
    await assert.rejects(inspectPilotExport({...input, current: {...input.current, ...change}}), /changed or recreated/);
  }
});
test("pilot export requires original pre-expiry provenance and propagates access denial", async () => {
  const input = exportFixture();
  await assert.rejects(inspectPilotExport({...input, receipt: {...input.receipt, completedAt: input.receipt.pilotExport.expiresAt}}), /pre-expiry/);
  await assert.rejects(inspectPilotExport({...input, receipt: {completedAt: input.receipt.completedAt}}), /pre-expiry/);
  await assert.rejects(inspectPilotExport({...input, receipt: {...input.receipt,
    pilotExport: {...input.receipt.pilotExport, objectPath: "private-event-exports/foreign/fixture.csv"}}}), /pre-expiry/);
  const denied = Object.assign(Error("access denied"), {code: 403});
  await assert.rejects(inspectPilotExport({...input, now: Date.parse(input.receipt.pilotExport.expiresAt),
    readMetadata: async () => {throw denied;}}), (error) => error === denied);
});
