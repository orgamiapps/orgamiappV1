"use strict";
const test = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");
const os = require("node:os");
const path = require("node:path");
const vm = require("node:vm");
const c = require("./web_release_contract");
const {verifyState, captureFunctionSources, pages} = require("./web_release_state");
const {options, materializeBackend, materializeRules} = require("./web_release_pipeline");
const {publishEvidence, retainReports, selectedGates} = require("./web_release_evidence");
const hash = "a".repeat(64); const sourceSha = "a".repeat(40);
function candidate(environment = "staging") {
  const value = {schemaVersion: 1, sourceSha, candidateRunId: "123", environment, projectId: c.PROJECTS[environment], releaseId: hash,
    sourceFiles: {"tools/web_release_producers/backend.js": hash, "tools/web_release_producers/browser.js": hash, "tools/web_release_producers/operations.js": hash, "tools/web_release_producers/safari.js": hash},
    webFiles: {"index.html": hash, [`releases/${hash}/main.dart.js`]: hash, "firebase-messaging-sw.js": hash},
    deployment: {functions: ["triggerAIInsights", "triggerAIInsightsV2"], deleteFunctions: [], retryAcknowledgements: [], firebaseConfigSha256: hash, firestoreRulesSha256: hash, storageRulesSha256: hash,
      triggerTransition: {legacy: {name: "triggerAIInsights", eventType: "google.cloud.firestore.document.v1.updated"}, replacement: {name: "triggerAIInsightsV2", eventType: "google.cloud.firestore.document.v1.written"}}},
    predecessor: {production: {hostingVersion: "sites/orgami-66nxok/versions/prior"}, staging: {hostingVersion: "sites/attendus-staging/versions/prior"}}};
  value.sourceManifestSha256 = c.digest(value.sourceFiles); value.webSha256 = c.digest(value.webFiles); value.deploymentSha256 = c.digest(value.deployment);
  value.configSha256 = c.digest({environment, projectId: value.projectId, firebaseConfig: hash, worker: hash});
  return value;
}
function report(gate, value, now) {
  return {schemaVersion: 1, gate, environment: "staging", projectId: c.PROJECTS.staging, sourceSha, candidateRunId: "123",
    candidateSha256: c.digest(value), webSha256: value.webSha256, deploymentSha256: value.deploymentSha256, configSha256: value.configSha256,
    producer: `tools/web_release_producers/${c.GATE_PRODUCERS[gate][0]}.js`, producerSha256: hash, workflowRunId: "456", startedAt: new Date(now).toISOString(), finishedAt: new Date(now).toISOString(),
    observedStateSha256: hash, assertions: [{id: "real-query-count", expected: 2, actual: 2}], blockers: [], rawFiles: {"raw.json": hash},
    ...(gate === "event-close-replay-observation" ? {window: {eventClosesAt: new Date(now - 86400000).toISOString(), replayObservedAt: new Date(now).toISOString()}} : {})};
}
function fixture() {
  const value = candidate(); const production = candidate("production"); const now = Date.now() - 1000;
  const reports = c.GATES.map((gate) => report(gate, value, now));
  for (let hour = 0; hour <= 24; hour++) reports.push(report("observation", value, now - (24 - hour) * 3600000));
  const replay = report("post-close-replay", value, now - 22 * 3600000);
  replay.window = {eventClosesAt: new Date(now - 86400000).toISOString(), effectiveClosesAt: new Date(now - 23 * 3600000).toISOString(), replayExecutedAt: replay.finishedAt};
  reports.push(replay);
  Object.assign(reports.find((row) => row.gate === "event-close-replay-observation").window,
      {effectiveClosesAt: replay.window.effectiveClosesAt, replayExecutedAt: replay.finishedAt, replayReportSha256: c.digest(replay)});
  const deployment = {candidateSha256: c.digest(value), environment: "staging", verifiedAt: new Date(now - 86400000 - 60000).toISOString(), stateSha256: hash};
  return {value, production, now, reports, deployment};
}
test("one frozen candidate qualifies only with every gate and continuous post-close observations", () => {
  const f = fixture(); const receipt = c.qualify(f.value, f.production, f.deployment, f.reports, f.now);
  assert.equal(receipt.sourceSha, sourceSha); assert.equal(receipt.requiredGates.length, 13);
});
test("candidate must retain its explicitly reviewed retry acknowledgement manifest", () => {
  const value = candidate();
  delete value.deployment.retryAcknowledgements;
  value.deploymentSha256 = c.digest(value.deployment);
  assert.throws(() => c.validateCandidate(value, "staging"), /retry acknowledgements/);
});
test("elapsed time alone, missing gate and unresolved journey blockers cannot qualify", () => {
  for (const modify of [
    (f) => { f.reports = f.reports.filter((item) => item.gate === "observation"); },
    (f) => { f.reports[0].blockers.push("Account switch leaks former recipient"); },
    (f) => { f.reports[0].assertions[0].actual = 1; },
  ]) {
    const f = fixture(); modify(f); assert.throws(() => c.qualify(f.value, f.production, f.deployment, f.reports, f.now), /gate missing|blockers|assertion failed/);
  }
});
test("observation gap, stale tail and short post-close interval are rejected", () => {
  for (const modify of [
    (f) => { f.reports.splice(c.GATES.length + 8, 1); },
    (f) => { f.now += 76 * 60000; },
    (f) => { f.reports.find((r) => r.window).window.eventClosesAt = new Date(f.now - 23 * 3600000).toISOString(); },
  ]) {
    const f = fixture(); modify(f); assert.throws(() => c.qualify(f.value, f.production, f.deployment, f.reports, f.now), /gap|fresh|24 hours/);
  }
});
test("different environment, source, artifact, deployment and producer evidence cannot replay", () => {
  for (const change of [
    (f) => { f.reports[0].projectId = c.PROJECTS.production; },
    (f) => { f.reports[0].sourceSha = "b".repeat(40); },
    (f) => { f.reports[0].webSha256 = "b".repeat(64); },
    (f) => { f.reports[0].observedStateSha256 = "b".repeat(64); },
    (f) => { f.reports[0].producerSha256 = "b".repeat(64); },
    (f) => { f.reports[0].producer = "tools/web_release_producers/backend.js"; },
  ]) {
    const f = fixture(); change(f); assert.throws(() => c.qualify(f.value, f.production, f.deployment, f.reports, f.now), /candidate|drifted|Producer|producer/);
  }
});
test("same-source production configuration and prior deployment are mandatory", () => {
  const f = fixture(); f.production.predecessor.production.hostingVersion = "changed";
  assert.throws(() => c.qualify(f.value, f.production, f.deployment, f.reports, f.now), /one frozen source/);
  const value = candidate(); value.webFiles["injected.js"] = hash;
  assert.throws(() => c.validateCandidate(value, "staging"), /digest mismatch/);
});

test("passive post-close observations without an immutable actual replay cannot qualify", () => {
  for (const alter of [
    (f) => {f.reports = f.reports.filter((row) => row.gate !== "post-close-replay");},
    (f) => {f.reports.find((row) => row.gate === "event-close-replay-observation").window.replayReportSha256 = "0".repeat(64);},
    (f) => {f.reports.find((row) => row.gate === "event-close-replay-observation").window.replayExecutedAt = new Date(f.now - 24 * 3600000).toISOString();},
  ]) {
    const f = fixture(); alter(f); assert.throws(() => c.qualify(f.value, f.production, f.deployment, f.reports, f.now), /authenticated post-close/);
  }
  assert.deepEqual(selectedGates("browser", "post-close-replay"), ["post-close-replay"]);
  for (const producer of ["backend", "operations", "safari"]) assert.throws(() => selectedGates(producer, "post-close-replay"), /requires browser/);
  assert.throws(() => selectedGates("browser", "observation"), /not supported/);
});
test("raw files are rehashed and traversal paths rejected", () => {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), "attendus-raw-"));
  try {
    const value = candidate(); const evidence = report("observation", value, Date.now() - 1000);
    fs.writeFileSync(path.join(dir, "raw.json"), "{}"); evidence.rawFiles["raw.json"] = c.sha256("{}");
    c.validateEvidence(evidence, value, dir);
    fs.writeFileSync(path.join(dir, "raw.json"), "changed"); assert.throws(() => c.validateEvidence(evidence, value, dir), /changed/);
    for (const name of ["../secret", "/absolute", "C:/file", "sub\\file"]) assert.throws(() => c.relativeFile(name), /Unsafe/);
  } finally { fs.rmSync(dir, {recursive: true, force: true}); }
});
test("only first successful allowlisted same-repository same-SHA manual run is trusted", () => {
  const valid = {repository: {full_name: c.REPOSITORY}, head_repository: {full_name: c.REPOSITORY}, head_sha: sourceSha, path: c.WORKFLOWS.evidence, event: "workflow_dispatch", status: "completed", conclusion: "success", run_attempt: 1, head_branch: "codex/project-debugging-20261003"};
  c.validateRun(valid, "evidence", sourceSha, c.REPOSITORY);
  for (const change of [{event: "push"}, {conclusion: "failure"}, {head_sha: "b".repeat(40)}, {run_attempt: 2}, {path: ".github/workflows/untrusted.yml"}, {head_repository: {full_name: "attacker/fork"}}]) assert.throws(() => c.validateRun({...valid, ...change}, "evidence", sourceSha, c.REPOSITORY), /Untrusted/);
  assert.throws(() => c.validateRun(valid, "evidence", sourceSha, "attacker/fork"), /Attendus repository/);
});
test("deployed default rules and both trigger event types are checked; named DB rules are preserved", () => {
  const value = candidate();
  const state = {projectId: value.projectId, functions: value.deployment.functions.map((id, i) => ({id, state: "ACTIVE", region: "us-central1", eventTrigger: {eventType: i ? value.deployment.triggerTransition.replacement.eventType : value.deployment.triggerTransition.legacy.eventType, eventFilterPathPatterns: {document: "event_analytics/{docId}"}}})),
    rules: [{release: "projects/attendus-staging/releases/cloud.firestore", files: [{sha256: hash}]}, {release: "projects/attendus-staging/releases/cloud.firestore/named", files: [{sha256: "different-unchanged-named-database"}]}, {release: "projects/attendus-staging/releases/firebase.storage/bucket", files: [{sha256: hash}]}], indexes: [], fields: []};
  verifyState(value, {state}, {indexes: [], fieldOverrides: []});
  state.functions[0].eventTrigger.eventType = value.deployment.triggerTransition.replacement.eventType;
  assert.throws(() => verifyState(value, {state}, {indexes: []}), /Trigger identity/);
  state.functions[0].eventTrigger.eventType = value.deployment.triggerTransition.legacy.eventType; state.rules[0].files[0].sha256 = "changed";
  assert.throws(() => verifyState(value, {state}, {indexes: []}), /rules differ/);
});
test("CLI parser rejects ambiguous or missing values", () => {
  assert.deepEqual(options(["--candidate-run", "123"]), {"candidate-run": "123"});
  assert.throws(() => options(["--candidate-run", "123", "--candidate-run", "456"]));
  assert.throws(() => options(["--output", "--candidate-run"]));
});

test("publication includes only declared evidence and rejects private/debug files", () => {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), "attendus-publish-")); const dir = path.join(root, "run"); fs.mkdirSync(dir);
  try {
    fs.mkdirSync(path.join(dir, "reports"));
    fs.writeFileSync(path.join(dir, "reports.json"), "{}"); fs.writeFileSync(path.join(dir, "raw.json"), "{}");
    fs.writeFileSync(path.join(dir, "firebase-debug.log"), "PRIVATE ENV");
    fs.writeFileSync(path.join(dir, "reports/observation.json"), JSON.stringify({rawFiles: {"raw.json": hash}}));
    const published = publishEvidence(dir, ["reports/observation.json"]);
    assert.equal(fs.existsSync(path.join(published, "firebase-debug.log")), false);
    assert.equal(fs.existsSync(path.join(published, "raw.json")), true);
    fs.writeFileSync(path.join(dir, "reports/observation.json"), JSON.stringify({rawFiles: {"firebase-debug.log": hash}}));
    assert.throws(() => publishEvidence(dir, ["reports/observation.json"]), /private\/debug/);
  } finally { fs.rmSync(root, {recursive: true, force: true}); }
});

test("predecessor source capture retains immutable build/revision metadata without environment values", async () => {
  const name = "projects/attendus-staging/locations/us-central1/functions/test";
  const service = "projects/attendus-staging/locations/us-central1/services/test";
  const client = {request: async ({url}) => {
    if (url.includes("cloudfunctions.googleapis.com/v1/")) return {data: {functions: []}};
    if (url.includes("cloudfunctions.googleapis.com/v2/")) return {data: {functions: [{name, environment: "GEN_2", buildConfig: {build: "build-1", source: {storageSource: {bucket: "private-code", object: "source.zip", generation: "7"}}}, serviceConfig: {service, environmentVariables: {SECRET: "do-not-persist"}}}]}};
    if (url.endsWith("/revisions/test-00001")) return {data: {containers: [{image: `registry/image@sha256:${hash}`, env: [{value: "do-not-persist"}]}]}};
    return {data: {latestReadyRevision: `${service}/revisions/test-00001`, template: {containers: [{env: [{value: "do-not-persist"}]}]}}};
  }};
  const result = await captureFunctionSources("attendus-staging", client);
  assert.equal(result[0].source.generation, "7"); assert.equal(result[0].images[0].digest, hash);
  assert.equal(result[0].revision, `${service}/revisions/test-00001`);
  assert.equal(JSON.stringify(result).includes("do-not-persist"), false);
});

test("partial cloud inventory cannot become a release predecessor", async () => {
  await assert.rejects(() => pages({request: async () => ({data: {functions: [], unreachable: ["us-central1"]}})}, "https://example.invalid", "functions"), /Incomplete/);
});

test("Firestore field override filter persists across every pagination request", async () => {
  const calls = []; const filter = "indexConfig.usesAncestorConfig=false OR ttlConfig:*";
  const result = await pages({request: async (request) => { calls.push(request); return {data: calls.length === 1 ? {fields: [{name: "one"}], nextPageToken: "next"} : {fields: [{name: "two"}]}}; }}, "https://firestore.googleapis.com/example/fields", "fields", {filter});
  assert.equal(result.length, 2); assert.deepEqual(calls.map((call) => call.params.filter), [filter, filter]);
  assert.equal(calls[1].params.pageToken, "next");
});

test("backend deployment materialization excludes untracked local files and detects changed tracked files", () => {
  const temp = fs.mkdtempSync(path.join(os.tmpdir(), "attendus-backend-")); fs.mkdirSync(path.join(temp, "functions"));
  try {
    const sourceFiles = {};
    for (const [name, value] of [["index.js", "exports.test=1;"], ["package-lock.json", "{}"]]) {
      fs.writeFileSync(path.join(temp, "functions", name), value); sourceFiles[`functions/${name}`] = c.sha256(value);
    }
    fs.writeFileSync(path.join(temp, "functions", "untracked-secret.env"), "never-upload");
    const readSources = () => Object.fromEntries(Object.keys(sourceFiles).map((name) => [name, fs.readFileSync(path.join(temp, name))]));
    const dir = materializeBackend({sourceFiles}, temp, path.join(temp, "build"), readSources);
    assert.deepEqual(Object.keys(c.files(dir)).sort(), ["index.js", "package-lock.json"]);
    fs.writeFileSync(path.join(temp, "functions", "index.js"), "modified");
    assert.throws(() => materializeBackend({sourceFiles}, temp, path.join(temp, "build"), readSources), /source changed/);
  } finally { fs.rmSync(temp, {recursive: true, force: true}); }
});

test("Git source decoding preserves exact committed text/binary bytes independently of worktree line endings", () => {
  const oid = "a".repeat(40); const binary = Buffer.from([0, 13, 10, 255]);
  const output = Buffer.concat([Buffer.from(`${oid} blob 4\n`), binary, Buffer.from("\n")]);
  const decoded = c.decodeGitBlobs([{name: "functions/file.bin", oid}], output);
  assert.deepEqual(decoded["functions/file.bin"], binary);
  assert.throws(() => c.decodeGitBlobs([{name: "file", oid}], output.subarray(0, -2)), /Invalid|Truncated/);
});

test("rule/config deployment uses committed bytes instead of CRLF workspace files", () => {
  const temp = fs.mkdtempSync(path.join(os.tmpdir(), "attendus-rules-"));
  try {
    const committed = {"firebase.json": Buffer.from("{\n}\n"), "firestore.indexes.json": Buffer.from("{\n}\n"),
      "firestore.rules": Buffer.from("rules_version = '2';\n"), "storage.rules": Buffer.from("rules_version = '2';\n")};
    for (const [name, bytes] of Object.entries(committed)) fs.writeFileSync(path.join(temp, name), bytes.toString().replaceAll("\n", "\r\n"));
    const candidate = {sourceFiles: Object.fromEntries(Object.entries(committed).map(([name, bytes]) => [name, c.sha256(bytes)]))};
    const target = materializeRules(candidate, temp, path.join(temp, "build"), () => committed);
    assert.deepEqual(c.files(target), Object.assign(Object.create(null), candidate.sourceFiles));
    assert.notEqual(c.sha256(fs.readFileSync(path.join(temp, "firestore.rules"))), candidate.sourceFiles["firestore.rules"]);
    assert.throws(() => materializeRules(candidate, temp, path.join(temp, "build"), () => ({...committed, "storage.rules": Buffer.from("modified")})), /source changed/);
  } finally { fs.rmSync(temp, {recursive: true, force: true}); }
});

test("blocked gates preserve curated diagnostics and raw hashes without entering passing evidence", () => {
  const temp = fs.mkdtempSync(path.join(os.tmpdir(), "attendus-blocked-")); const output = path.join(temp, "run"); fs.mkdirSync(output);
  const oldRun = process.env.GITHUB_RUN_ID; process.env.GITHUB_RUN_ID = "456";
  try {
    fs.writeFileSync(path.join(output, "health.json"), JSON.stringify({settled: true}));
    fs.writeFileSync(path.join(output, "replay.json"), JSON.stringify({hours: 2}));
    fs.writeFileSync(path.join(output, "firebase-debug.log"), "PRIVATE ENV");
    const now = new Date().toISOString();
    const index = retainReports({output, candidate: candidate(), producerPath: "tools/web_release_producers/backend.js", source: hash,
      startedAt: now, finishedAt: now, after: {stateSha256: hash}, result: {gates: {
        observation: {assertions: [{id: "health", expected: true, actual: true}], blockers: [], rawPaths: ["health.json"]},
        "event-close-replay-observation": {assertions: [{id: "hours", expected: 24, actual: 2}], blockers: ["Post-close observation is incomplete"], rawPaths: ["replay.json"]},
      }}});
    assert.equal(index.qualificationStatus, "blocked"); assert.deepEqual(index.reports, ["reports/observation.json"]);
    assert.deepEqual(index.diagnosticReports, ["diagnostics/event-close-replay-observation.json"]);
    const retained = JSON.parse(fs.readFileSync(path.join(`${output}-publish`, index.diagnosticReports[0])));
    assert.equal(retained.rawFiles["replay.json"], c.sha256(fs.readFileSync(path.join(output, "replay.json"))));
    assert.equal(retained.assertions[0].actual, 2); assert.equal(retained.blockers.length, 1);
    assert.equal(fs.existsSync(path.join(`${output}-publish`, "firebase-debug.log")), false);
    assert.throws(() => c.validateEvidence(retained, candidate(), `${output}-publish`), /blockers|assertion failed/);
  } finally {
    if (oldRun === undefined) delete process.env.GITHUB_RUN_ID; else process.env.GITHUB_RUN_ID = oldRun;
    fs.rmSync(temp, {recursive: true, force: true});
  }
});
test("unsafe raw paths and producer execution failures retain only safe blocked indexes", () => {
  const temp = fs.mkdtempSync(path.join(os.tmpdir(), "attendus-unsafe-")); const output = path.join(temp, "run"); fs.mkdirSync(output);
  try {
    fs.writeFileSync(path.join(output, "firebase-debug.log"), "PRIVATE ENV"); const now = new Date().toISOString();
    const index = retainReports({output, candidate: candidate(), producerPath: "tools/web_release_producers/backend.js", source: hash,
      startedAt: now, finishedAt: now, result: {gates: {observation: {rawPaths: ["firebase-debug.log", "../private.json"], assertions: [], blockers: []}}}, collectionFailure: "deployment-recheck-failed"});
    assert.equal(index.qualificationStatus, "blocked"); assert.equal(index.reports.length, 0);
    const retained = JSON.parse(fs.readFileSync(path.join(`${output}-publish`, index.diagnosticReports[0])));
    assert.deepEqual(retained.rawFiles, {}); assert.equal(fs.existsSync(path.join(`${output}-publish`, "firebase-debug.log")), false);
    const empty = path.join(temp, "empty");
    const failed = retainReports({output: empty, candidate: candidate(), result: null, collectionFailure: "producer-execution-failed"});
    assert.equal(failed.qualificationStatus, "blocked"); assert.equal(fs.existsSync(path.join(`${empty}-publish`, "reports.json")), true);
  } finally { fs.rmSync(temp, {recursive: true, force: true}); }
});

// Execute the real deploy orchestration with the real strict empty-project
// reader. Only remote transport, artifact validation and later mutations are
// mocked, so moving this prerequisite after deployment makes these tests fail.
function stagingPrerequisiteHarness({environment = "staging", blocked = null} = {}) {
  const ownedTemp = fs.realpathSync(fs.mkdtempSync(path.join(os.tmpdir(), "attendus-deploy-prerequisite-")));
  const output = path.join(ownedTemp, "receipt", "deployment.json");
  const value = candidate(environment); const state = value.predecessor[environment];
  const calls = []; const requests = [];
  const client = {async request(request) {
    requests.push(request);
    assert.equal(request.method, undefined, "prerequisite transport must be read-only");
    if (request.url.includes("/documents/")) {
      assert.ok(request.url.startsWith("https://firestore.googleapis.com/v1/projects/attendus-staging/databases/(default)/documents/"));
      assert.deepEqual(request.params, {pageSize: 1});
      const collection = request.url.split("/").at(-1);
      return {data: collection === blocked ? {documents: [{name: `${request.url}/existing`}]} : {}};
    }
    assert.equal(request.url, "https://identitytoolkit.googleapis.com/v1/projects/attendus-staging/accounts:batchGet");
    assert.deepEqual(request.params, {maxResults: 2});
    return {data: {users: [{localId: "existing-anonymous"}]}};
  }};
  const rehearsal = require("./rehearse_web_backend");
  const module = {exports: {}};
  const controlledRequire = (name) => {
    if (name === "./web_release_contract") return {...c, validateArtifact() { calls.push("validate-artifact"); }};
    if (name === "./web_release_state") return {async captureState() { calls.push("capture-state"); return {state}; },
      async googleClient() { calls.push("empty-project-client"); return client; },
      firebase() { calls.push("resource-mutation"); throw Error("Unexpected resource deployment"); }};
    if (name === "./rehearse_web_backend") return {...rehearsal, validateArchives() { calls.push("validate-archives"); }};
    if (name === "./bridge_web_assets") return {planBridge() { calls.push("plan-bridge"); },
      async publishBridge() { calls.push("resource-mutation"); throw Error("Unexpected Hosting mutation"); }};
    if (name === "node:child_process") return {execFileSync() { calls.push("resource-mutation"); throw Error("Unexpected CLI preparation/deployment"); }};
    if (name === "node:fs") return {...fs, mkdtempSync() { calls.push("materialize-resources"); throw Error("Test stop at resource materialization"); }};
    return require(name);
  };
  vm.runInNewContext(fs.readFileSync(path.join(__dirname, "web_release_pipeline.js"), "utf8"),
      {module, exports: module.exports, require: controlledRequire, __dirname, process, console, Buffer}, {filename: "web_release_pipeline.js"});
  return {value, state, output, calls, requests, run: () => module.exports.deploy(value, ownedTemp, state, output),
    receipt: () => JSON.parse(fs.readFileSync(path.join(path.dirname(output), "staging-empty-prerequisite.json"))),
    cleanup() {
      const resolved = fs.realpathSync(ownedTemp); const tempRoot = fs.realpathSync(os.tmpdir());
      assert.equal(resolved, ownedTemp); assert.ok(path.relative(tempRoot, resolved) && !path.relative(tempRoot, resolved).startsWith("..") && !path.isAbsolute(path.relative(tempRoot, resolved)));
      fs.rmSync(resolved, {recursive: true});
    }};
}
test("staging deploy rejects nonempty scheduledNotifications before materialization or any mutation", async () => {
  const harness = stagingPrerequisiteHarness({blocked: "scheduledNotifications"});
  try {
    await assert.rejects(harness.run(), /Backend rehearsal requires empty scheduledNotifications/);
    assert.deepEqual(harness.calls, ["validate-artifact", "capture-state", "empty-project-client"]);
    assert.equal(harness.requests.at(-1).url.split("/").at(-1), "scheduledNotifications");
    assert.equal(fs.existsSync(path.join(path.dirname(harness.output), "staging-empty-prerequisite.json")), false);
  } finally { harness.cleanup(); }
});
test("empty staging prerequisite is durably timestamped and candidate-bound before materialization", async () => {
  const harness = stagingPrerequisiteHarness(); const startedAt = Date.now();
  try {
    await assert.rejects(harness.run(), /Test stop at resource materialization/);
    assert.deepEqual(harness.calls, ["validate-artifact", "capture-state", "empty-project-client", "validate-archives", "plan-bridge", "materialize-resources"]);
    const receipt = harness.receipt();
    assert.equal(receipt.kind, "staging-empty-prerequisite"); assert.equal(receipt.projectId, "attendus-staging");
    assert.equal(receipt.candidateSha256, c.digest(harness.value)); assert.equal(receipt.sourceSha, harness.value.sourceSha);
    assert.equal(receipt.candidateRunId, harness.value.candidateRunId); assert.equal(receipt.predecessorStateSha256, c.digest(harness.state));
    assert.ok(Date.parse(receipt.startedAt) >= startedAt && Date.parse(receipt.verifiedAt) >= Date.parse(receipt.startedAt));
    assert.equal(receipt.verifiedAt, receipt.checks.checkedAt); assert.equal(receipt.checks.anonymousAuthCount, 1);
    assert.deepEqual(receipt.checks.collections, Object.fromEntries(require("./rehearse_web_backend").EMPTY_COLLECTIONS.map((name) => [name, 0])));
    assert.equal(harness.requests.length, require("./rehearse_web_backend").EMPTY_COLLECTIONS.length + 1);
  } finally { harness.cleanup(); }
});
test("production deployment never invokes the staging-only empty-project prerequisite", async () => {
  const harness = stagingPrerequisiteHarness({environment: "production", blocked: "scheduledNotifications"});
  try {
    await assert.rejects(harness.run(), /Test stop at resource materialization/);
    assert.deepEqual(harness.calls, ["validate-artifact", "capture-state", "plan-bridge", "materialize-resources"]);
    assert.equal(harness.requests.length, 0); assert.equal(fs.existsSync(path.join(path.dirname(harness.output), "staging-empty-prerequisite.json")), false);
  } finally { harness.cleanup(); }
});
