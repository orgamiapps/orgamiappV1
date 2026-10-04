"use strict";

const test = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const os = require("node:os");
const adapter = require("./deploy_web_functions");
const clone = (value) => JSON.parse(JSON.stringify(value));
const backend = (items) => ({endpoints: Object.fromEntries([...new Set(items.map((fn) => fn.region))].map((region) => [region, Object.fromEntries(items.filter((fn) => fn.region === region).map((fn) => [fn.id, fn]))]))});
function fixture() {
  const have = {id: "reviewed", project: "attendus-staging", region: "us-central1", platform: "gcfv2", runtime: "nodejs22", entryPoint: "reviewed", state: "ACTIVE", codebase: "default",
    eventTrigger: {eventType: "google.cloud.firestore.document.v1.created", retry: false, region: "nam5", eventFilters: {database: "(default)", namespace: "(default)"}, eventFilterPathPatterns: {document: "Events/{eventId}"}}};
  const want = clone(have); want.eventTrigger.retry = true;
  const predecessor = {projectId: have.project, functions: [adapter.publicEndpoint(have)]};
  const candidate = {sourceSha: "a".repeat(40), candidateRunId: "123", environment: "staging", projectId: have.project,
    predecessor: {staging: clone(predecessor)}, deployment: {functions: [want.id], deleteFunctions: [], retryAcknowledgements: [adapter.descriptor(want)]}};
  return {have, want, predecessor, candidate, options: {project: have.project, projectId: have.project, force: false, nonInteractive: true, only: "functions:reviewed"}};
}
function plan(fn) { return {regionalChangesets: {region: {endpointsToCreate: [], endpointsToUpdate: [{endpoint: fn, unsafe: false}], endpointsToDelete: [], endpointsToSkip: []}}}; }

test("pins the actual installed CLI version and every adapted call boundary", () => {
  const modules = adapter.loadPinned();
  assert.equal(JSON.parse(fs.readFileSync(path.join(modules.directory, "package.json"))).version, "15.25.1");
  assert.throws(() => adapter.assertPins(modules.directory, (file, encoding) => file.endsWith("package.json") ? '{"version":"15.25.2"}' : fs.readFileSync(file, encoding)), /version/);
  assert.throws(() => adapter.assertPins(modules.directory, (file, encoding) => file.endsWith("prompts.js") ? Buffer.from("modified") : fs.readFileSync(file, encoding)), /module/);
});

test("actual CLI fails before acknowledgement, succeeds after narrowly wrapped retry prompt", async () => {
  const f = fixture(); const modules = adapter.loadPinned();
  await assert.rejects(modules.prompts.promptForFailurePolicies(f.options, backend([f.want]), backend([f.have])), /Pass the --force option/);
  const originalDeletion = modules.prompts.promptForFunctionDeletion;
  const originalMin = modules.prompts.promptForMinInstances;
  const originalSecurity = modules.prompts.promptForSecurityChanges;
  const guards = adapter.installGuards(f, modules);
  try {
    await modules.prompts.promptForFailurePolicies(f.options, backend([f.want]), backend([f.have]));
    assert.equal(f.options.force, false);
    assert.equal(modules.prompts.promptForFunctionDeletion, originalDeletion);
    assert.equal(modules.prompts.promptForMinInstances, originalMin);
    assert.equal(modules.prompts.promptForSecurityChanges, originalSecurity);
    await assert.rejects(originalDeletion([f.have], f.options), /deletion cannot proceed/);
    await assert.rejects(originalMin(f.options, backend([{...f.want, minInstances: 1, availableMemoryMb: 256, cpu: 1}]), backend([f.have])), /minimum bill/);
    await assert.rejects(originalSecurity({default: {serviceAccountToDelete: "old-sa"}}, f.options), /Cannot opt out/);
    await assert.rejects(modules.prompts.promptForCleanupPolicyDays(f.options, ["us-central1"]), /could not set up cleanup policy/);
    assert.deepEqual(guards.receipt.transitions, [adapter.descriptor(f.want)]);
    assert.equal(guards.receipt.globalForce, false);
  } finally { guards.restore(); }
});

for (const [name, mutate] of [
  ["unreviewed retry", (f) => { f.candidate.deployment.retryAcknowledgements = []; }],
  ["approved retry turned off", (f) => { f.want.eventTrigger.retry = false; }],
  ["retry drift on live predecessor", (f) => { f.have.eventTrigger.retry = true; }],
  ["wrong project", (f) => { f.want.project = "orgami-66nxok"; }],
  ["changed generation", (f) => { f.want.platform = "gcfv1"; }],
  ["changed Function region", (f) => { f.want.region = "europe-west1"; }],
  ["changed Eventarc region", (f) => { f.want.eventTrigger.region = "eur3"; }],
  ["changed document", (f) => { f.want.eventTrigger.eventFilterPathPatterns.document = "Other/{id}"; }],
  ["changed database", (f) => { f.want.eventTrigger.eventFilters.database = "other"; }],
  ["changed namespace", (f) => { f.want.eventTrigger.eventFilters.namespace = "other"; }],
  ["changed trigger type", (f) => { f.want.eventTrigger.eventType = "google.cloud.firestore.document.v1.written"; }],
  ["changed entry point", (f) => { f.want.entryPoint = "other"; }],
  ["renamed Function", (f) => { f.want.id = "renamed"; }],
  ["extra descriptor field", (f) => { f.candidate.deployment.retryAcknowledgements[0].force = true; }],
  ["duplicate acknowledgement", (f) => { f.candidate.deployment.retryAcknowledgements.push(clone(f.candidate.deployment.retryAcknowledgements[0])); }],
  ["foreign frozen predecessor", (f) => { f.candidate.predecessor.staging.functions[0].region = "europe-west1"; }],
  ["deletion intent", (f) => { f.candidate.deployment.deleteFunctions = ["old"]; }],
]) test(`rejects ${name} before retry acknowledgement`, () => {
  const f = fixture(); mutate(f);
  assert.throws(() => adapter.validateBackends(f.candidate, f.predecessor, backend([f.want]), backend([f.have])));
});

test("permits reviewed already-enabled endpoints without replaying a new transition", () => {
  const f = fixture(); f.have.eventTrigger.retry = true;
  f.predecessor.functions = [adapter.publicEndpoint(f.have)]; f.candidate.predecessor.staging = clone(f.predecessor);
  assert.deepEqual(adapter.validateBackends(f.candidate, f.predecessor, backend([f.want]), backend([f.have])), []);
  f.want.eventTrigger.retry = false;
  assert.throws(() => adapter.validateBackends(f.candidate, f.predecessor, backend([f.want]), backend([f.have])), /cannot be disabled/);
});

test("new endpoints require exact reviewed descriptors and preserve predecessor", () => {
  const f = fixture(); const addition = {...clone(f.want), id: "newRetry", entryPoint: "newRetry"};
  f.candidate.deployment.functions = ["newRetry", "reviewed"];
  assert.throws(() => adapter.validateBackends(f.candidate, f.predecessor, backend([f.want, addition]), backend([f.have])), /Unreviewed newly/);
  f.candidate.deployment.retryAcknowledgements.push(adapter.descriptor(addition));
  assert.equal(adapter.validateBackends(f.candidate, f.predecessor, backend([f.want, addition]), backend([f.have])).length, 2);
  assert.throws(() => adapter.validateBackends(f.candidate, f.predecessor, backend([addition]), backend([f.have])), /selectors/);
});

for (const [name, change] of [
  ["delete", (p, f) => p.regionalChangesets.region.endpointsToDelete.push(f.have)],
  ["delete and recreate", (p, f) => { p.regionalChangesets.region.endpointsToUpdate[0].deleteAndRecreate = f.have; }],
  ["unsafe migration", (p) => { p.regionalChangesets.region.endpointsToUpdate[0].unsafe = true; }],
  ["unrelated managed service account", (p) => { p.serviceAccountToDelete = "old"; }],
  ["unrelated IAM role", (p) => { p.rolesToAdd = ["roles/owner"]; }],
  ["missing endpoint", (p) => { p.regionalChangesets.region.endpointsToUpdate = []; }],
]) test(`rejects actual planner ${name}`, () => {
  const f = fixture(); const p = plan(f.want); change(p, f);
  assert.throws(() => adapter.assertPlan(p, f.candidate));
});

test("actual pinned planner output is guarded before prepare continues or source upload", async (t) => {
  const f = fixture(); const modules = adapter.loadPinned(); let laterPrepare = 0; let uploads = 0;
  t.mock.method(modules.prepare, "prepare", async (_context, options, payload) => {
    await modules.prompts.promptForFailurePolicies(options, payload.functions.default.wantBackend, payload.functions.default.haveBackend);
    laterPrepare++;
  });
  t.mock.method(modules.deploy, "deploy", async () => { uploads++; });
  const guards = adapter.installGuards(f, modules);
  const context = {projectId: f.candidate.projectId, filters: [{codebase: "default", idChunks: ["reviewed"]}]};
  const payload = {functions: {default: {wantBackend: backend([f.want]), haveBackend: backend([f.have])}}};
  try {
    payload.functions.default.wantBackend.endpoints["us-central1"].reviewed.eventTrigger.region = "eur3";
    await assert.rejects(modules.prepare.prepare(context, f.options, payload), /identity\/trigger/);
    assert.equal(laterPrepare, 0); assert.equal(uploads, 0);
    payload.functions.default.wantBackend = backend([fixture().want]);
    await modules.prepare.prepare(context, f.options, payload);
    await modules.deploy.deploy(context, f.options, payload);
    assert.equal(laterPrepare, 1); assert.equal(uploads, 1);
    assert.ok(guards.receipt.plans.some((p) => p.phase === "prepare-before-upload"));
    payload.functions.default.wantBackend.endpoints["us-central1"].reviewed.eventTrigger.eventFilters.database = "other";
    await assert.rejects(modules.deploy.deploy(context, f.options, payload), /identity\/trigger/);
    assert.equal(uploads, 1);
    await assert.rejects(modules.prompts.promptForFailurePolicies({...f.options, force: true}, backend([f.want]), backend([f.have])), /broad force/);
  } finally { guards.restore(); }
});

test("receipt excludes environment payloads while binding actual predecessor metadata", async () => {
  const f = fixture(); f.have.environmentVariables = {SENSITIVE: "DO_NOT_PUBLISH"}; f.want.environmentVariables = clone(f.have.environmentVariables);
  f.predecessor.functions = [adapter.publicEndpoint(f.have)]; f.candidate.predecessor.staging = clone(f.predecessor);
  const modules = adapter.loadPinned(); const guards = adapter.installGuards(f, modules);
  try {
    await modules.prompts.promptForFailurePolicies(f.options, backend([f.want]), backend([f.have]));
    assert.doesNotMatch(JSON.stringify(guards.receipt), /DO_NOT_PUBLISH|SENSITIVE|environmentVariables/);
    f.have.environmentVariables.SENSITIVE = "changed";
    await assert.rejects(modules.prompts.promptForFailurePolicies(f.options, backend([f.want]), backend([f.have])), /drifted/);
  } finally { guards.restore(); }
});

test("all eleven reviewed production/staging descriptors pass the actual prompt with force false", async () => {
  const approvals = JSON.parse(fs.readFileSync(path.join(__dirname, "../config/web_function_retry_acknowledgements.json"))).functions;
  assert.equal(approvals.length, 11);
  for (const [environment, project] of [["staging", "attendus-staging"], ["production", "orgami-66nxok"]]) {
    const desired = approvals.map((item) => ({id: item.id, region: item.region, platform: item.platform, project, codebase: "default", runtime: "nodejs22", entryPoint: item.id, state: "ACTIVE",
      eventTrigger: {eventType: item.eventType, eventFilters: item.eventFilters, eventFilterPathPatterns: item.eventFilterPathPatterns, region: item.eventTriggerRegion, retry: true}}));
    const existing = desired.filter((item) => !["notifyOrgJoinRequestDecision", "triggerAIInsightsV2"].includes(item.id)).map((item) => ({...clone(item), eventTrigger: {...clone(item.eventTrigger), retry: false}}));
    const predecessor = {projectId: project, functions: existing.map(adapter.publicEndpoint)};
    const candidate = {sourceSha: "b".repeat(40), environment, projectId: project, predecessor: {[environment]: clone(predecessor)}, deployment: {functions: desired.map((item) => item.id).sort(), deleteFunctions: [], retryAcknowledgements: approvals}};
    const modules = adapter.loadPinned(); const guards = adapter.installGuards({candidate, predecessor}, modules);
    const options = {project, force: false, nonInteractive: true, only: candidate.deployment.functions.map((name) => `functions:${name}`).join(",")};
    try {
      await modules.prompts.promptForFailurePolicies(options, backend(desired), backend(existing));
      assert.equal(guards.receipt.transitions.length, 11); assert.equal(options.force, false);
    } finally { guards.restore(); }
  }
});

test("persisted pre-upload plan survives a deployment failure and publishes no error bearer", async (t) => {
  const temporaryBase = fs.realpathSync(os.tmpdir());
  const directory = fs.mkdtempSync(path.join(temporaryBase, "attendus-functions-plan-"));
  const owned = fs.realpathSync(directory);
  t.after(() => {
    if (fs.realpathSync(os.tmpdir()) !== temporaryBase || fs.lstatSync(directory).isSymbolicLink() || fs.realpathSync(directory) !== owned || !owned.startsWith(`${temporaryBase}${path.sep}`)) throw Error("Unsafe owned test cleanup");
    fs.rmSync(owned, {recursive: true});
  });
  const f = fixture(); const configPath = path.join(directory, "firebase.json"); const outputPath = path.join(directory, "receipt.json");
  fs.writeFileSync(configPath, JSON.stringify({functions: {source: "source", codebase: "default"}}));
  const modules = adapter.loadPinned(); const command = require(path.join(modules.directory, "lib/commands/deploy")).command;
  t.mock.method(modules.prepare, "prepare", async (_context, options, payload) => {
    await modules.prompts.promptForFailurePolicies(options, payload.functions.default.wantBackend, payload.functions.default.haveBackend);
  });
  let uploaded = false;
  t.mock.method(modules.deploy, "deploy", async () => {
    const saved = JSON.parse(fs.readFileSync(outputPath));
    assert.equal(saved.globalForce, false);
    assert.ok(saved.plans.some((item) => item.phase === "prepare-before-upload"));
    assert.ok(saved.plans.some((item) => item.phase === "before-upload"));
    uploaded = true;
    throw Error("transport failed https://example.test/?access_token=DO_NOT_PUBLISH");
  });
  t.mock.method(command, "runner", () => async (options) => {
    assert.equal(options.force, false);
    const context = {projectId: f.candidate.projectId};
    const payload = {functions: {default: {wantBackend: backend([f.want]), haveBackend: backend([f.have])}}};
    await modules.prepare.prepare(context, options, payload);
    await modules.deploy.deploy(context, options, payload);
  });
  await assert.rejects(adapter.run({...f, configPath, outputPath}), /transport failed/);
  assert.equal(uploaded, true);
  const saved = JSON.parse(fs.readFileSync(outputPath));
  assert.equal(saved.status, "failure");
  assert.doesNotMatch(JSON.stringify(saved), /DO_NOT_PUBLISH|access_token|example.test/);
  assert.ok(saved.finishedAt);
});
