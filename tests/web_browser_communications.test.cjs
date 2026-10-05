"use strict";
const {test} = require("node:test");
const assert = require("node:assert/strict");
const {createHash} = require("node:crypto");
const fs = require("node:fs"), os = require("node:os"), path = require("node:path");
const {runBrowserCommunications, validateCommunications, createCommunicationsObserver, previousDeletion} = require("../tools/web_release_producers/browser-communications");
const {digest, sha256} = require("../tools/web_release_contract");
function fixture() {
  const runId = "webqa-20261004-1234567890";
  const value = {runId, projectId: "attendus-staging", sourceSha: "a".repeat(40), candidateRunId: "1234",
    controlledRecipientDomain: "example.test", event: {id: `${runId}-pilot`}, eventClosesAt: new Date(Date.now() + 3600000).toISOString()};
  for (const role of ["owner", "attendee", "staff", "unauthorized", "administrator", "deletion"])
    value[role] = {uid: `${runId}-${role}`, email: `${runId}-${role}@example.test`};
  value.conversationId = [value.owner.uid, value.attendee.uid].sort().join("_");
  value.communications = {reminderEventId: `${runId}-reminder`, discoveryEventId: `${runId}-discovery`, pendingPushId: `${runId}-pending`};
  value.ownedFixtureIds = [value.event.id, value.conversationId, ...Object.values(value.communications),
    ...["owner", "attendee", "staff", "unauthorized", "administrator", "deletion"].map((role) => value[role].uid)];
  return value;
}
function adapters(f, {lostDeletionResponse = false, alreadyDeleted = false, timerFailed = false} = {}) {
  const calls = [], state = {deleted: alreadyDeleted, appFeedback: false};
  const hash = (text) => createHash("sha256").update(text).digest("hex");
  const capture = (sourceKey, recipientUid) => ({sourceKey, recipientUid, provider: "qualification_capture", valid: true, eventIds: []});
  const time = new Date(Date.now() + 3600000).toISOString();
  return {calls, observe: async () => ({observedAt: new Date(Date.parse(time) - 40 * 60000).toISOString(),
    captures: [capture("message:message-1", f.attendee.uid), capture("legacy:feedback:event_feedback/feedback-1:delivery-1", f.owner.uid),
      capture(`admin:${hash(`sendCustomNotifications:${f.administrator.uid}:${f.runId}:admin-notification`)}`, f.attendee.uid),
      capture(`pending:${f.communications.pendingPushId}`, f.attendee.uid)],
    sourceReceipts: {registration: true, message: true, feedback: true, adminOperation: true},
    pending: {sourceMatches: true, status: "qualification_capture"},
    reminder: {eventId: f.communications.reminderEventId, startsAt: new Date(Date.parse(time) + 3600000).toISOString(),
      jobs: [{id: "reminder-1", status: timerFailed ? "unknown" : "pending", dueAt: time, deadlineAt: time, reminderMinutes: 60}]},
    discovery: {eventId: f.communications.discoveryEventId,
      createdAt: new Date(Date.parse(time) - 46 * 60000).toISOString(), documentCreatedAt: new Date(Date.parse(time) - 46 * 60000).toISOString(),
      updatedAt: new Date(Date.parse(time) - 46 * 60000).toISOString(),
      items: [{id: "queue-1", status: "pending", readyAt: time,
        queuedAt: new Date(Date.parse(time) - 45 * 60000).toISOString(), updatedAt: new Date(Date.parse(time) - 45 * 60000).toISOString()}], deliveries: []},
    deletion: {uid: f.deletion.uid, authenticationExists: !state.deleted, profileExists: !state.deleted, userExists: !state.deleted,
      appFeedbackExists: state.appFeedback && !state.deleted, status: state.deleted ? "complete" : null, remaining: 0, verificationRecorded: state.deleted}}),
  callAs: async (role, name, data) => {
    calls.push({role, name, data: structuredClone(data)});
    switch (name) {
      case "getOrCreateDirectConversationV2": assert.equal(role, "owner"); assert.equal(data.otherUserId, f.attendee.uid); return {conversationId: f.conversationId};
      case "sendConversationMessageV2": assert.equal(data.conversationId, f.conversationId); return {messageId: "message-1"};
      case "communityMutationV1":
        if (role === "deletion") {assert.equal(data.action, "submitAppFeedback"); state.appFeedback = true; return {feedbackId: "appfeedback-1"};}
        assert.equal(role, "attendee"); assert.equal(data.eventId, f.event.id); assert.equal(data.action, "submitFeedback"); return {feedbackId: "feedback-1"};
      case "sendCustomNotifications": assert.equal(role, "administrator"); assert.equal(data.confirmation, true);
        assert.deepEqual(data.userIds, [f.attendee.uid]); return {pushSuccessCount: 0, pushFailureCount: 0};
      case "startPublicRegistrationV3": assert.equal(data.eventId, f.communications.reminderEventId); return {status: "confirmed", registrationId: "reminder-reg-1"};
      case "deleteUserAccount": assert.equal(role, "deletion"); assert.deepEqual(data, {}); state.deleted = true;
        if (lostDeletionResponse) throw Object.assign(Error("unavailable, private request contents"), {code: "deadline-exceeded"});
        return {status: "complete"};
      default: throw Error(`Unexpected mutation ${name}`);
    }
  }};
}
test("communications produce authenticated sources, observe real pending timers and delete only disposable identity last", async () => {
  const f = fixture(), mock = adapters(f);
  const report = await runBrowserCommunications({fixture: f, candidateIdentity: f, ...mock, timeoutMs: 10, pollIntervalMs: 0});
  assert.equal(mock.calls.at(-1).name, "deleteUserAccount");
  assert.equal(report.receipts.deletedUid, f.deletion.uid);
  assert.equal(report.receipts.messageId, "message-1"); assert.equal(report.receipts.feedbackId, "feedback-1");
  assert.equal(report.timers.reminder.jobs[0].status, "pending");
  assert.equal(report.timers.discovery.items[0].status, "pending");
  assert.equal(report.assertions.some((item) => /reminder.*delivered|discovery.*delivered/.test(item.id)), false);
  assert.deepEqual(mock.calls[1].data, mock.calls[2].data, "message retry retains request identity and content");
  assert.equal(mock.calls.some((item) => /cancel|reschedule|updateEvent/.test(item.name)), false);
  assert.equal(report.assertions.every((item) => JSON.stringify(item.expected) === JSON.stringify(item.actual)), true);
});
test("lost deletion response reconciles the original completed job without replaying deletion", async () => {
  const f = fixture(), mock = adapters(f, {lostDeletionResponse: true});
  const report = await runBrowserCommunications({fixture: f, candidateIdentity: f, ...mock, timeoutMs: 10, pollIntervalMs: 0});
  assert.equal(report.deletionAttempt.responseStatus, "unknown");
  assert.equal(mock.calls.filter((item) => item.name === "deleteUserAccount").length, 1);
  assert.equal(report.observations.at(-1).deletion.status, "complete");
  assert.ok(!JSON.stringify(report).includes("private request contents"));
});

test("discovery pending delay survives a real server commit lag without moving its deadline", async () => {
  const f = fixture(), mock = adapters(f), observe = mock.observe;
  mock.observe = async (...args) => ({...await observe(...args), observedAt: "2026-10-04T22:43:58.000Z",
    discovery: {eventId: f.communications.discoveryEventId, createdAt: "2026-10-04T22:31:34.442Z", documentCreatedAt: "2026-10-04T22:31:34.442Z",
      updatedAt: "2026-10-04T22:31:40.000Z", deliveries: [], items: [{id: "original-queue", status: "pending",
        readyAt: "2026-10-04T23:16:48.924Z", queuedAt: "2026-10-04T22:31:50.901Z",
        updatedAt: "2026-10-04T22:31:50.901Z"}]}});
  const report = await runBrowserCommunications({fixture: f, candidateIdentity: f, ...mock, timeoutMs: 10, pollIntervalMs: 0});
  assert.equal(report.timers.discovery.items[0].readyAt, "2026-10-04T23:16:48.924Z");
  assert.equal(mock.calls.at(-1).name, "deleteUserAccount");
});

test("pending discovery proof rejects an enqueue clock outside its retained source and commit interval", async () => {
  for (const change of [
    {source: {updatedAt: "2026-10-04T22:44:00.000Z"}},
    {source: {documentCreatedAt: "2026-10-04T22:32:00.000Z"}},
    {item: {queuedAt: "2026-10-04T22:31:48.000Z"}},
    {item: {updatedAt: "2026-10-04T22:31:49.000Z"}},
    {item: {readyAt: "not-a-timestamp"}},
    {observedAt: "2026-10-04T22:31:49.000Z"},
  ]) {
    const f = fixture(), mock = adapters(f), observe = mock.observe;
    mock.observe = async (...args) => ({...await observe(...args), observedAt: change.observedAt || "2026-10-04T22:43:58.000Z",
      discovery: {eventId: f.communications.discoveryEventId, createdAt: "2026-10-04T22:31:34.442Z", documentCreatedAt: "2026-10-04T22:31:34.442Z",
        updatedAt: "2026-10-04T22:31:40.000Z", ...change.source, deliveries: [], items: [{id: "original-queue", status: "pending",
          readyAt: "2026-10-04T23:16:48.924Z", queuedAt: "2026-10-04T22:31:50.901Z",
          updatedAt: "2026-10-04T22:31:50.901Z", ...change.item}]}});
    await assert.rejects(() => runBrowserCommunications({fixture: f, candidateIdentity: f, ...mock, timeoutMs: 10, pollIntervalMs: 0}),
        /discovery_preserves_real_45_minute_delay/);
    assert.equal(mock.calls.some((item) => item.name === "deleteUserAccount"), false);
  }
});

test("discovery metadata may finish updating after the enqueue clock was sampled", async () => {
  const f = fixture(), mock = adapters(f), observe = mock.observe;
  mock.observe = async (...args) => {
    const value = await observe(...args);
    const queuedAt = Date.parse(value.discovery.items[0].queuedAt);
    // maintainDiscoveryMetadata is independent of the enqueue trigger.
    value.discovery.updatedAt = new Date(queuedAt + 1977).toISOString();
    return value;
  };
  const report = await runBrowserCommunications({fixture: f, candidateIdentity: f, ...mock, timeoutMs: 10, pollIntervalMs: 0});
  assert.equal(report.assertions.find((item) => item.id === "discovery_preserves_real_45_minute_delay").actual, true);
});
test("predeleted identity without authenticated prior proof and failed timer sources block deletion", async () => {
  const f = fixture(), gone = adapters(f, {alreadyDeleted: true});
  await assert.rejects(() => runBrowserCommunications({fixture: f, candidateIdentity: f, ...gone}), /exists_before_authentication/);
  assert.equal(gone.calls.length, 0);
  const failed = adapters(f, {timerFailed: true});
  await assert.rejects(() => runBrowserCommunications({fixture: f, candidateIdentity: f, ...failed}), /reminder_source_not_failed/);
  assert.equal(failed.calls.some((item) => item.name === "deleteUserAccount"), false);
});
test("communications reject unrelated event, conversation, actor or nonstaging database before mutation", () => {
  const f = fixture();
  assert.throws(() => validateCommunications({...f, communications: {...f.communications, reminderEventId: f.event.id}}, f));
  assert.throws(() => validateCommunications({...f, conversationId: "unrelated"}, f));
  assert.throws(() => validateCommunications({...f, deletion: f.owner}, f));
  assert.throws(() => createCommunicationsObserver({fixture: f, candidateIdentity: f, db: {projectId: "orgami-66nxok"}}));
});

test("prior deletion reuse requires immutable successful browser evidence with matching candidate and raw receipt", () => {
  const f = fixture(), identity = validateCommunications(f, f);
  const root = fs.mkdtempSync(path.join(os.tmpdir(), "web-deletion-proof-"));
  try {
    const producer = "tools/web_release_producers/browser.js", hash = "a".repeat(64);
    const candidate = {projectId: f.projectId, sourceSha: f.sourceSha, candidateRunId: f.candidateRunId,
      webSha256: hash, deploymentSha256: hash, configSha256: hash, sourceFiles: {[producer]: hash}};
    const receipt = {schemaVersion: 1, identity, startedAt: "2026-10-03T10:01:00Z", completedAt: "2026-10-03T10:02:00Z",
      assertions: [{id: "deletion_job_completed_without_remaining_data", expected: ["complete", 0], actual: ["complete", 0]}],
      receipts: {deletedUid: f.deletion.uid, appFeedbackId: "actual-feedback"}};
    const raw = path.join(root, "communications-receipts.json"); fs.writeFileSync(raw, JSON.stringify(receipt));
    const report = {schemaVersion: 1, gate: "browser-auth-guest-organizer", environment: "staging", projectId: candidate.projectId,
      sourceSha: candidate.sourceSha, candidateRunId: candidate.candidateRunId, candidateSha256: digest(candidate),
      webSha256: hash, deploymentSha256: hash, configSha256: hash, producer, producerSha256: hash, workflowRunId: "456",
      startedAt: "2026-10-03T10:00:00Z", finishedAt: "2026-10-03T10:03:00Z", observedStateSha256: hash,
      assertions: receipt.assertions, blockers: [], rawFiles: {"communications-receipts.json": sha256(fs.readFileSync(raw))}};
    const input = {candidate, candidateIdentity: {...f, deployment: {stateSha256: hash}}, identity, fixture: f,
      priorEvidence: [{report, outputDir: root}]};
    assert.equal(previousDeletion(input).receipts.deletedUid, f.deletion.uid);
    assert.throws(() => previousDeletion({...input, candidateIdentity: {...f, deployment: {stateSha256: "b".repeat(64)}}}), /deployment differs/);
    fs.writeFileSync(raw, JSON.stringify({...receipt, receipts: {...receipt.receipts, deletedUid: f.owner.uid}}));
    assert.throws(() => previousDeletion(input), /Raw evidence changed/);
  } finally {
    const resolved = path.resolve(root), temp = path.resolve(os.tmpdir()) + path.sep;
    assert.ok(resolved.startsWith(temp) && path.basename(resolved).startsWith("web-deletion-proof-"));
    fs.rmSync(resolved, {recursive: true, force: true});
  }
});
