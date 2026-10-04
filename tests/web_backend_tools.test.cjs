"use strict";
const test = require("node:test"), assert = require("node:assert/strict");
const fs = require("node:fs"), os = require("node:os"), path = require("node:path"), crypto = require("node:crypto");
const {captureRecoveryTarget} = require("../tools/capture_recovery_target");
const {compareRecoveryContent, digest, HEARTBEATS} = require("../tools/recovery_content");
const {FIRESTORE_DENY_ALL} = require("../functions/tools/recovery-target");
const {observationAssertions, summarizeCaptures} = require("../tools/web_release_producers/backend");
const {quotaReadiness, readAuthoritativeReadiness} = require("../tools/authoritative_data_readiness");
const hash = (value) => crypto.createHash("sha256").update(value).digest("hex");
test("recovery collector proves disabled services via read-only APIs and strict IAM without enabling anything", async (t) => {
  const project = "attendus-recovery-20261004", calls = [];
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), "attendus-recovery-test-"));
  t.after(() => { if (path.dirname(path.resolve(dir)) !== path.resolve(os.tmpdir())) throw Error("Invalid temporary test directory"); fs.rmSync(dir, {recursive: true}); });
  const client = {request: async (request) => {
    calls.push(request);
    if (request.url.endsWith(":getIamPolicy")) return {data: {etag: "test", bindings: [{role: "roles/owner", members: ["user:orgamiapps@gmail.com"]}]}};
    if (request.url.includes("serviceusage")) return {data: {services: ["firestore.googleapis.com", "firebaserules.googleapis.com"].map((name) => ({name: `projects/342600227354/services/${name}`, config: {name}, state: "ENABLED"}))}};
    if (request.url.endsWith("/releases")) return {data: {releases: [{name: `projects/${project}/releases/cloud.firestore`, rulesetName: `projects/${project}/rulesets/fixture`}]}};
    if (request.url.endsWith("/rulesets/fixture")) return {data: {source: {files: [{name: "firestore.rules", content: FIRESTORE_DENY_ALL}]}}};
    if (request.url.endsWith(`/projects/${project}`)) return {data: {projectId: project, projectNumber: "342600227354", lifecycleState: "ACTIVE", labels: {attendus_purpose: "recovery-proof"}}};
    assert.fail("Unreviewed API request");
  }};
  const result = await captureRecoveryTarget({outputDir: dir, client});
  assert.equal(result.verified.isolated, true);
  assert.equal(fs.existsSync(result.proofPath), true);
  assert.equal(calls.some((call) => call.url.includes(":enable") || /cloudfunctions|cloudscheduler|eventarc|run\.googleapis/.test(call.url)), false);
  assert.equal(calls.filter((call) => call.method === "POST").length, 1);
});
function content() {
  const source = {project: "orgami-66nxok", records: {[digest("Customers/opaque")]: "unchanged", [digest(HEARTBEATS[0])]: "before"}};
  const restored = {project: "attendus-recovery-20261004", records: {...source.records, [digest(HEARTBEATS[0])]: "after"}, heartbeatFields: {[HEARTBEATS[0]]: {fields: {cursor: {type: "nullValue", sha256: "same"}, updatedAt: {type: "timestampValue", sha256: "new"}}}}};
  for (const item of [source, restored]) { item.documents = Object.keys(item.records).length; item.contentSha256 = digest(item.records); }
  return {source, restored, fields: {[HEARTBEATS[0]]: {fields: {cursor: {type: "nullValue", sha256: "same"}, updatedAt: {type: "timestampValue", sha256: "old"}}}}};
}
test("recovery preserves raw mismatch and explains only exact heartbeat updatedAt drift", () => {
  const {source, restored, fields} = content();
  const comparison = compareRecoveryContent(source, restored, fields);
  assert.equal(comparison.exactIdentical, false); assert.equal(comparison.businessContentEquivalent, true);
  assert.deepEqual(comparison.differences.changedPaths, [digest(HEARTBEATS[0])]);
  restored.heartbeatFields[HEARTBEATS[0]].fields.cursor.sha256 = "different";
  assert.equal(compareRecoveryContent(source, restored, fields).businessContentEquivalent, false);
  restored.heartbeatFields[HEARTBEATS[0]].fields.cursor.sha256 = "same";
  restored.records[digest("Customers/opaque")] = "changed"; restored.contentSha256 = digest(restored.records);
  assert.equal(compareRecoveryContent(source, restored, fields).businessContentEquivalent, false);
});
test("recovery rejects missing records and inconsistent manifests", () => {
  const {source, restored, fields} = content();
  delete restored.records[digest("Customers/opaque")];
  assert.throws(() => compareRecoveryContent(source, restored, fields), /inconsistent/);
  restored.documents--; restored.contentSha256 = digest(restored.records);
  assert.equal(compareRecoveryContent(source, restored, fields).businessContentEquivalent, false);
});
test("observation treats failed/dead-letter/unknown work and replayed attempts as blockers", () => {
  const sample = {observedAt: "2026-10-05T12:00:00Z", eventClosesAt: "2026-10-04T10:00:00Z", eventRevision: 2, captures: [],
    jobs: [{path: "job", status: "complete", attempts: 1}]};
  for (const status of ["failed", "dead_letter", "delivery_unknown", "unknown", "queued"]) {
    assert.equal(observationAssertions({...sample, jobs: [{path: "job", status, attempts: 1}]}).some((row) => row.expected !== row.actual), true);
  }
  assert.equal(observationAssertions({...sample, jobs: [{path: "job", status: "complete", attempts: 2}]}, [sample]).find((row) => row.id.includes("increment_attempts")).actual, false);
});
test("capture evidence verifies identities/content without exporting payload or contact", () => {
  const data = {runId: "fixture-run", recipientUid: "fixture-user", sourceKey: "email:fixture", payload: {html: "private link"}, provider: "qualification_capture"};
  data.fingerprint = hash(JSON.stringify(data.payload));
  const id = hash(JSON.stringify([data.runId, data.recipientUid, data.sourceKey]));
  const summary = summarizeCaptures([{id, data: () => data}])[0];
  assert.equal(summary.contentMatches, true); assert.equal(summary.identityMatches, true);
  assert.equal(Object.hasOwn(summary, "payload"), false); assert.equal(JSON.stringify(summary).includes("private link"), false);
});

test("live readiness never invents counters and follows current authoritative unlimited policy", () => {
  const row = (id, value) => ({id, data: () => value});
  const customers = [row("missing", {}), row("negative", {eventsCreated: -1}), row("string", {eventsCreated: "0"}), row("premium", {}), row("granted", {}), row("basic", {}), row("valid", {eventsCreated: 0})];
  const subscriptions = [row("premium", {status: "active", tier: "premium"}), row("basic", {status: "active", tier: "basic"})];
  const result = quotaReadiness(customers, subscriptions, [row("granted", {unlimitedEventCreation: true})]);
  assert.equal(result.customerCounterMissing, 4); assert.equal(result.customerCounterInvalid, 2);
  assert.equal(result.effectiveCounterBlocked, 4); assert.equal(result.explicitUnlimited, 1); assert.equal(result.activePremium, 1);
  assert.equal(result.subscriptionCounterMissing, 2); assert.equal(JSON.stringify(result).includes('"missing"'), false);
  const cancelled = quotaReadiness([row("premium", {})], [row("premium", {status: "cancelled", tier: "premium"})], []);
  assert.equal(cancelled.effectiveCounterBlocked, 1);
  assert.equal(quotaReadiness([row("granted", {})], [], [row("granted", {unlimitedEventCreation: "true"})]).effectiveCounterBlocked, 1);
});

test("readiness inspects current admission links in a read-only transaction with contact-free projections", async () => {
  const values = {Customers: {person: {}}, subscriptions: {}, account_entitlements: {}, Events: {event: {status: "active"}},
    RegisterAttendance: {registration: {eventId: "event", customerUid: "person", status: "confirmed"}},
    Tickets: {ticket: {eventId: "event", customerUid: "person", status: "valid"}}, Attendance: {}};
  const requested = [];
  const db = {collection: (name) => ({select: (...fields) => ({limit: (maximum) => ({name, fields, maximum})})}),
    runTransaction: async (work, options) => {
      assert.equal(options.readOnly, true);
      return work({get: async (query) => {
        requested.push(query);
        const docs = Object.entries(values[query.name]).map(([id, data]) => ({id, data: () => data, get: (field) => data[field]}));
        return {size: docs.length, docs};
      }});
    }};
  const result = await readAuthoritativeReadiness(db, "orgami-66nxok");
  assert.equal(result.liveMigrationIssueCount, 1); assert.equal(result.quota.effectiveCounterBlocked, 1);
  assert.equal(result.liveMigrationIssues[0].type, "ambiguous_admission_link");
  assert.equal(requested.every((query) => query.maximum === 10001 && !query.fields.some((field) => /email|phone|contact/i.test(field))), true);
  assert.equal(JSON.stringify(result).includes('"person"'), false);
});
