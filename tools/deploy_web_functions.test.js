"use strict";

const test = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const os = require("node:os");
const {spawnSync} = require("node:child_process");
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
  return {have, want, predecessor, candidate, options: {project: have.project, projectId: have.project, force: false, nonInteractive: true, dryRun: false, only: "functions:reviewed"}};
}
function plan(fn) { return {regionalChangesets: {region: {endpointsToCreate: [], endpointsToUpdate: [{endpoint: fn, unsafe: false}], endpointsToDelete: [], endpointsToSkip: []}}}; }
function ownedDirectory(t) {
  const temporaryBase = fs.realpathSync(os.tmpdir());
  const directory = fs.mkdtempSync(path.join(temporaryBase, "attendus-functions-plan-"));
  const owned = fs.realpathSync(directory);
  t.after(() => {
    if (fs.realpathSync(os.tmpdir()) !== temporaryBase || fs.lstatSync(directory).isSymbolicLink() || fs.realpathSync(directory) !== owned || !owned.startsWith(`${temporaryBase}${path.sep}`)) throw Error("Unsafe owned test cleanup");
    fs.rmSync(owned, {recursive: true});
  });
  return directory;
}

function offlineChild(t, body) {
  const directory = ownedDirectory(t), outputPath = path.join(directory, "receipt.json");
  const fixturePath = path.join(directory, "fixture.json"), configPath = path.join(directory, "firebase.json");
  fs.writeFileSync(fixturePath, JSON.stringify(fixture()));
  fs.writeFileSync(configPath, JSON.stringify({functions: {source: "source", codebase: "default"}}));
  const script = path.join(directory, "offline-child.cjs");
  fs.writeFileSync(script, `"use strict";
    const fs = require("node:fs"), path = require("node:path");
    for (const protocol of ["node:http", "node:https"]) {
      const network = require(protocol); network.request = network.get = () => {throw Error("Offline test forbids network");};
    }
    globalThis.fetch = () => {throw Error("Offline test forbids fetch");};
    const adapter = require(${JSON.stringify(path.join(__dirname, "deploy_web_functions.js"))});
    const modules = adapter.loadPinned();
    const {QueueExecutor} = require(path.join(modules.directory, "lib/deploy/functions/release/executor"));
    const f = JSON.parse(fs.readFileSync(${JSON.stringify(fixturePath)}));
    const configPath = ${JSON.stringify(configPath)}, outputPath = ${JSON.stringify(outputPath)};
    const backend = (fn) => ({endpoints: {[fn.region]: {[fn.id]: fn}}});
    const payload = {functions: {default: {wantBackend: backend(f.want), haveBackend: backend(f.have)}}};
    const context = {projectId: f.candidate.projectId};
    async function strandedQueue() {
      const executor = new QueueExecutor({concurrency: 1, retries: 0, backoff: 1, maxBackoff: 1});
      const trace = [];
      const first = executor.run(async () => {trace.push("first-started"); throw Object.assign(Error("offline429"), {code: 429});})
        .catch((error) => {trace.push("first-rejected"); throw error;});
      const second = executor.run(async () => {trace.push("second-started");});
      process.once("beforeExit", () => console.log(JSON.stringify({trace, stats: executor.queue.stats(), cursor: executor.queue.cursor, total: executor.queue.total})));
      await Promise.allSettled([first, second]);
      console.log("queue-completed");
    }
    ${body}
  `);
  const env = Object.fromEntries(["PATH", "SystemRoot", "WINDIR", "TEMP", "TMP", "PATHEXT"].filter((key) => process.env[key]).map((key) => [key, process.env[key]]));
  const child = spawnSync(process.execPath, [script], {cwd: directory, env, encoding: "utf8", timeout: 20000});
  assert.equal(child.error, undefined, child.stderr || child.error?.message);
  assert.equal(child.signal, null);
  return {...child, receipt: fs.existsSync(outputPath) ? JSON.parse(fs.readFileSync(outputPath, "utf8")) : null};
}

test("actual pinned QueueExecutor exits zero while a retry-exhausted task strands later promises", (t) => {
  const child = offlineChild(t, "strandedQueue().catch(() => {process.exitCode = 1;});");
  assert.equal(child.status, 0); assert.doesNotMatch(child.stdout, /queue-completed|second-started/);
  const evidence = JSON.parse(child.stdout.trim().split("\n").at(-1));
  assert.deepEqual(evidence.trace, ["first-started", "first-rejected"]);
  assert.equal(evidence.stats.active, 0); assert.equal(evidence.stats.complete, 1); assert.equal(evidence.total, 2); assert.equal(evidence.cursor, 1);
});

for (const preflight of [false, true]) test(`unfinished pinned CLI ${preflight ? "preflight" : "deployment"} fails closed in a real child process`, (t) => {
  const child = offlineChild(t, `
    modules.prepare.prepare = async (_context, options, payload) => modules.prompts.promptForFailurePolicies(options, payload.functions.default.wantBackend, payload.functions.default.haveBackend);
    modules.release.release = async () => {await modules.planner.createDeploymentPlan({...payload.functions.default, codebase: "default", projectId: f.candidate.projectId}); await strandedQueue();};
    const command = require(path.join(modules.directory, "lib/commands/deploy")).command;
    command.runner = () => async (options) => {await modules.prepare.prepare(context, options, payload); ${preflight ? "await strandedQueue();" : "await modules.release.release(context, options, payload);"}};
    adapter.run({...f, configPath, outputPath, preflight: ${preflight}}).catch((error) => {console.error(error.message); process.exitCode = 1;});
  `);
  assert.equal(child.status, 1, child.stdout + child.stderr);
  assert.equal(child.receipt.status, "failure"); assert.equal(child.receipt.failureCode, "cli-unsettled-before-exit");
  assert.ok(child.receipt.finishedAt); assert.equal(child.receipt.globalForce, false);
  assert.ok(child.receipt.plans.some((item) => item.phase === "prepare-before-upload"));
  assert.doesNotMatch(child.stdout, /queue-completed|second-started/);
});

test("explicit zero exit while CLI is unresolved preserves a failed terminal receipt", (t) => {
  const child = offlineChild(t, `
    modules.prepare.prepare = async (_context, options, payload) => modules.prompts.promptForFailurePolicies(options, payload.functions.default.wantBackend, payload.functions.default.haveBackend);
    const command = require(path.join(modules.directory, "lib/commands/deploy")).command;
    command.runner = () => async (options) => {await modules.prepare.prepare(context, options, payload); process.exit(0);};
    adapter.run({...f, configPath, outputPath}).catch(() => {process.exitCode = 1;});
  `);
  assert.equal(child.status, 1); assert.equal(child.receipt.status, "failure");
  assert.equal(child.receipt.failureCode, "cli-unsettled-exit"); assert.ok(child.receipt.finishedAt);
});

for (const outcome of ["success", "rejection"]) test(`a normally settled CLI ${outcome} keeps its terminal status and removes exit guards`, (t) => {
  const child = offlineChild(t, `
    modules.prepare.prepare = async (_context, options, payload) => modules.prompts.promptForFailurePolicies(options, payload.functions.default.wantBackend, payload.functions.default.haveBackend);
    modules.release.release = async () => {
      await modules.planner.createDeploymentPlan({...payload.functions.default, codebase: "default", projectId: f.candidate.projectId});
      ${outcome === "rejection" ? 'throw Error("ordinary synthetic rejection https://example.test/?access_token=DO_NOT_PUBLISH");' : ''}
    };
    const command = require(path.join(modules.directory, "lib/commands/deploy")).command;
    command.runner = () => async (options) => {await modules.prepare.prepare(context, options, payload); await modules.release.release(context, options, payload);};
    const listeners = {before: process.listenerCount("beforeExit"), exit: process.listenerCount("exit")}, originalFetch = globalThis.fetch;
    adapter.run({...f, configPath, outputPath}).catch(() => {process.exitCode = 1;}).finally(() => {
      console.log(JSON.stringify({beforeListeners: process.listenerCount("beforeExit") - listeners.before, exitListeners: process.listenerCount("exit") - listeners.exit, fetchRestored: globalThis.fetch === originalFetch}));
    });
  `);
  assert.equal(child.status, outcome === "success" ? 0 : 1);
  assert.equal(child.receipt.status, outcome === "success" ? "success" : "failure");
  assert.equal(child.receipt.failureCode, undefined); assert.ok(child.receipt.finishedAt);
  assert.doesNotMatch(JSON.stringify(child.receipt), /DO_NOT_PUBLISH|access_token|example.test/);
  assert.deepEqual(JSON.parse(child.stdout.trim().split("\n").at(-1)), {beforeListeners: 0, exitListeners: 0, fetchRestored: true});
});

test("unfinished execution preserves an explicit preexisting nonzero exit code", (t) => {
  const child = offlineChild(t, `
    const command = require(path.join(modules.directory, "lib/commands/deploy")).command;
    command.runner = () => async () => process.exit(23);
    adapter.run({...f, configPath, outputPath}).catch(() => {process.exitCode = 1;});
  `);
  assert.equal(child.status, 23); assert.equal(child.receipt.status, "failure");
  assert.equal(child.receipt.failureCode, "cli-unsettled-exit"); assert.ok(child.receipt.finishedAt);
});

test("actual mutation starts are spaced after late wakeups without serializing responses or poisoning the queue", async (t) => {
  const {candidate} = fixture(), starts = [], bodies = [], headers = new Headers({"x-test": "unchanged"});
  const url = "https://cloudfunctions.googleapis.com/v2/projects/attendus-staging/locations/us-central1/functions/reviewed?updateMask=labels";
  let clock = 0, sleeps = 0, finishFirst;
  const firstResult = {first: true}, thirdResult = {third: true}, rejected = Error("unchanged rejection");
  const previous = globalThis.fetch, receiver = {marker: true};
  const transport = function (...args) {
    assert.equal(this, receiver); starts.push(clock); bodies.push(args);
    if (starts.length === 1) return new Promise((resolve) => {finishFirst = () => resolve(firstResult);});
    if (starts.length === 2) return Promise.reject(rejected);
    return Promise.resolve(thirdResult);
  };
  globalThis.fetch = transport;
  const pacing = adapter.installFunctionApiPacing({candidate, now: () => clock, sleep: async (ms) => {clock += ms + (sleeps++ === 0 ? 7000 : 0);}});
  t.after(() => {pacing.restore(); globalThis.fetch = previous;});
  const options = {method: "PATCH", body: '{"name":"unchanged"}', headers};
  const first = globalThis.fetch.call(receiver, url, options);
  const second = globalThis.fetch.call(receiver, url, options).catch((error) => error);
  const third = globalThis.fetch.call(receiver, url, options);
  assert.equal(await third, thirdResult); assert.equal(await second, rejected);
  assert.deepEqual(starts, [0, 8500, 10000]);
  finishFirst(); assert.equal(await first, firstResult);
  assert.ok(bodies.every(([input, actual]) => input === url && actual === options && actual.headers === headers));
  assert.equal(pacing.receipt.startedRequests, 3); assert.equal(pacing.receipt.minimumObservedSpacingMs, 1500);
  pacing.restore(); assert.equal(globalThis.fetch, transport);
});

test("Request and string scopes preserve inputs while unrelated reads and APIs bypass the start queue", async (t) => {
  const {candidate} = fixture(), calls = [], previous = globalThis.fetch, result = Promise.resolve({unchanged: true}); let clock = 0, sleeps = 0;
  const transport = function (...args) {calls.push({receiver: this, args}); return result;}; globalThis.fetch = transport;
  const pacing = adapter.installFunctionApiPacing({candidate, now: () => clock, sleep: async (ms) => {sleeps++; clock += ms;}});
  t.after(() => {pacing.restore(); globalThis.fetch = previous;});
  const base = "https://cloudfunctions.googleapis.com/v2/projects/attendus-staging/locations/us-central1/functions", receiver = {};
  const request = new Request(base + "/reviewed?updateMask=labels", {method: "PATCH", body: "request-body"});
  await globalThis.fetch.call(receiver, request);
  const options = {method: "POST", body: "create-body", headers: new Headers({test: "original"})};
  await globalThis.fetch.call(receiver, base + "?functionId=reviewed", options);
  assert.equal(calls[0].args[0], request); assert.equal(request.bodyUsed, false);
  assert.equal(calls[1].args[1], options); assert.equal(calls[1].receiver, receiver);
  const bypass = [
    [base + "/reviewed", {method: "GET"}], [base + ":generateUploadUrl", {method: "POST"}],
    ["https://serviceusage.googleapis.com/v1/projects/attendus-staging/services/cloudfunctions.googleapis.com:enable", {method: "POST"}],
    ["https://storage.googleapis.com/source-archive", {method: "PUT", body: "archive"}],
    ["https://cloudfunctions.googleapis.com/v2/projects/other/locations/europe-west1/functions/foreign", {method: "GET"}],
    [request, {method: "GET"}],
  ];
  for (const args of bypass) assert.equal(globalThis.fetch.call(receiver, ...args), result);
  assert.equal(sleeps, 1); assert.equal(pacing.receipt.startedRequests, 2);
  for (const [index, args] of bypass.entries()) assert.deepEqual(calls[index + 2], {receiver, args});
});

test("transport rejects out-of-scope Function mutations and all Function deletes before dispatch", async (t) => {
  const {candidate} = fixture(), previous = globalThis.fetch; let calls = 0;
  globalThis.fetch = async () => {calls++;}; const pacing = adapter.installFunctionApiPacing({candidate});
  t.after(() => {pacing.restore(); globalThis.fetch = previous;});
  const origin = "https://cloudfunctions.googleapis.com", base = `${origin}/v2/projects/attendus-staging/locations/us-central1/functions`;
  for (const [url, method] of [
    [base.replace("attendus-staging", "orgami-66nxok") + "/reviewed", "PATCH"],
    [base.replace("us-central1", "europe-west1") + "/reviewed", "PATCH"],
    [base + "/foreign", "PATCH"], [base + "?functionId=foreign", "POST"],
    [base + "?functionId=reviewed&functionId=reviewed", "POST"], [base + "?functionId=reviewed&extra=1", "POST"],
    [base.replace("/v2/", "/v1/") + "/reviewed", "PATCH"], [base.replace("https:", "http:") + "/reviewed", "PATCH"],
    [base + "/reviewed", "DELETE"], [base.replace("/v2/", "/v1/") + "/foreign", "DELETE"],
  ]) await assert.rejects(globalThis.fetch(url, {method}), /forbidden|outside the frozen/);
  assert.equal(calls, 0);
});

test("actual pinned apiv2 runtime fetch retries are paced and preserve the real response", async (t) => {
  const {candidate} = fixture(), modules = adapter.loadPinned();
  const {Client} = require(path.join(modules.directory, "lib/apiv2"));
  const client = new Client({urlPrefix: "https://cloudfunctions.googleapis.com", apiVersion: "v2", auth: false});
  const previous = globalThis.fetch, seen = []; let clock = 0;
  globalThis.fetch = async (url, options) => {
    seen.push({at: clock, url, method: options.method, body: options.body, headers: options.headers});
    if (seen.length === 1) throw Object.assign(Error("synthetic premature close"), {code: "ECONNRESET"});
    return new Response(JSON.stringify({name: "offline-operation"}), {status: 200, headers: {"content-type": "application/json"}});
  };
  const pacing = adapter.installFunctionApiPacing({candidate, now: () => clock, sleep: async (ms) => {clock += ms;}});
  t.after(() => {pacing.restore(); globalThis.fetch = previous;});
  const body = {name: "projects/attendus-staging/locations/us-central1/functions/reviewed", labels: {test: "original"}};
  const response = await client.patch(body.name, body, {queryParams: {updateMask: "labels"}, retries: 1, retryMinTimeout: 1, retryMaxTimeout: 1});
  assert.deepEqual(response.body, {name: "offline-operation"}); assert.equal(response.status, 200);
  assert.deepEqual(seen.map((item) => item.at), [0, 1500]);
  assert.ok(seen.every((item) => item.method === "PATCH" && item.body === JSON.stringify(body)));
  assert.equal(seen[0].headers.get("connection"), "keep-alive"); assert.equal(seen[1].headers.get("connection"), "close");
  assert.equal(pacing.receipt.startedRequests, 2);
});

test("actual pinned GCFv2 delete client cannot dispatch the internal delete/recreate fallback", async (t) => {
  const {candidate} = fixture(), modules = adapter.loadPinned();
  const apiv2 = require(path.join(modules.directory, "lib/apiv2"));
  t.mock.method(apiv2.Client.prototype, "addAuthHeader", async (options) => options);
  const gcf = require(path.join(modules.directory, "lib/gcp/cloudfunctionsv2"));
  const previous = globalThis.fetch; let requests = 0; globalThis.fetch = async () => {requests++; throw Error("Unexpected transport");};
  const pacing = adapter.installFunctionApiPacing({candidate});
  t.after(() => {pacing.restore(); globalThis.fetch = previous;});
  await assert.rejects(gcf.deleteFunction("projects/attendus-staging/locations/us-central1/functions/reviewed"), /Failed to update function/);
  assert.equal(requests, 0);
});

test("actual pinned GCFv2 create and update shapes both traverse the same paced transport", async (t) => {
  const {candidate} = fixture(), modules = adapter.loadPinned();
  const apiv2 = require(path.join(modules.directory, "lib/apiv2"));
  t.mock.method(apiv2.Client.prototype, "addAuthHeader", async (options) => options);
  const gcf = require(path.join(modules.directory, "lib/gcp/cloudfunctionsv2"));
  const previous = globalThis.fetch, requests = []; let clock = 0;
  globalThis.fetch = async (url, options) => {
    requests.push({at: clock, url: new URL(url), method: options.method, body: JSON.parse(options.body)});
    return new Response(JSON.stringify({name: "offline-operation"}), {status: 200, headers: {"content-type": "application/json"}});
  };
  const pacing = adapter.installFunctionApiPacing({candidate, now: () => clock, sleep: async (ms) => {clock += ms;}});
  t.after(() => {pacing.restore(); globalThis.fetch = previous;});
  const name = "projects/attendus-staging/locations/us-central1/functions/reviewed";
  const cloudFunction = {name, buildConfig: {runtime: "nodejs22", entryPoint: "reviewed"}, serviceConfig: {}};
  assert.deepEqual(await gcf.createFunction(clone(cloudFunction)), {name: "offline-operation"});
  assert.deepEqual(await gcf.updateFunction(clone(cloudFunction)), {name: "offline-operation"});
  assert.deepEqual(requests.map((row) => row.at), [0, 1500]);
  assert.equal(requests[0].method, "POST"); assert.equal(requests[0].url.searchParams.get("functionId"), "reviewed");
  assert.equal(requests[1].method, "PATCH"); assert.ok(requests[1].url.searchParams.get("updateMask"));
  assert.ok(requests.every((row) => row.body.name === name && row.body.buildConfig.entryPoint === "reviewed"));
});

test("origin overrides fail before CLI execution and restore the original fetch", async (t) => {
  const f = fixture(), directory = ownedDirectory(t), configPath = path.join(directory, "firebase.json"), outputPath = path.join(directory, "receipt.json");
  fs.writeFileSync(configPath, JSON.stringify({functions: {source: "source", codebase: "default"}}));
  const previous = process.env.FIREBASE_FUNCTIONS_V2_URL, originalFetch = globalThis.fetch;
  process.env.FIREBASE_FUNCTIONS_V2_URL = "https://unreviewed.example.test";
  try {
    await assert.rejects(adapter.run({...f, configPath, outputPath}), /origin overrides/);
    assert.equal(globalThis.fetch, originalFetch);
    const receipt = JSON.parse(fs.readFileSync(outputPath)); assert.equal(receipt.status, "failure"); assert.deepEqual(receipt.plans, []);
  } finally {
    if (previous === undefined) delete process.env.FIREBASE_FUNCTIONS_V2_URL; else process.env.FIREBASE_FUNCTIONS_V2_URL = previous;
  }
});

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
    const options = {project, force: false, nonInteractive: true, dryRun: false, only: candidate.deployment.functions.map((name) => `functions:${name}`).join(",")};
    try {
      await modules.prompts.promptForFailurePolicies(options, backend(desired), backend(existing));
      assert.equal(guards.receipt.transitions.length, 11); assert.equal(options.force, false);
    } finally { guards.restore(); }
  }
});

test("persisted pre-upload plan survives a deployment failure and publishes no error bearer", async (t) => {
  const directory = ownedDirectory(t);
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

test("actual pinned empty dynamic-extension preparation is accepted; real plans and malformed records fail", async (t) => {
  const f = fixture(); const modules = adapter.loadPinned();
  const load = (name) => require(path.join(modules.directory, name));
  const extensionPrepare = load("lib/deploy/extensions/prepare");
  t.mock.method(load("lib/extensions/extensionsHelper"), "ensureExtensionsApiEnabled", async () => {});
  t.mock.method(load("lib/requirePermissions"), "requirePermissions", async () => {});
  t.mock.method(load("lib/deploy/extensions/planner"), "haveDynamic", async () => []);
  const extensionPayload = {};
  await extensionPrepare.prepareDynamicExtensions({}, {...f.options, projectNumber: "123456789", config: {src: {functions: {source: "source", codebase: "default"}}}}, extensionPayload, {default: {extensions: {}}});
  assert.deepEqual(extensionPayload, {});
  adapter.assertEmptyExtensions({});
  adapter.assertEmptyExtensions({extensions: extensionPayload});
  for (const value of [null, undefined, [], false, "", {instancesToCreate: []}, {instancesToDelete: [{instanceId: "real"}]}]) assert.throws(() => adapter.assertEmptyExtensions({extensions: value}), /extension deployment/);
  t.mock.method(modules.prepare, "prepare", async (_context, options, payload) => {
    payload.extensions = extensionPayload;
    await modules.prompts.promptForFailurePolicies(options, payload.functions.default.wantBackend, payload.functions.default.haveBackend);
  });
  const guards = adapter.installGuards(f, modules);
  try {
    await modules.prepare.prepare({projectId: f.candidate.projectId}, f.options, {functions: {default: {wantBackend: backend([f.want]), haveBackend: backend([f.have])}}});
    assert.ok(guards.receipt.plans.some((item) => item.phase === "prepare-before-upload"));
  } finally { guards.restore(); }
});

test("diagnostic preflight mode rejects any upload/deploy/release and dry-run mismatch", async () => {
  const f = fixture(); const modules = adapter.loadPinned();
  const guards = adapter.installGuards({...f, preflight: true}, modules);
  try {
    await assert.rejects(modules.prepare.prepare({}, {...f.options, dryRun: false}, {}), /options changed/);
    await assert.rejects(modules.deploy.deploy({}, {...f.options, dryRun: true}, {}), /Preflight cannot deploy/);
    await assert.rejects(modules.deploy.uploadSourceV2(), /Preflight cannot upload/);
    await assert.rejects(modules.release.release({}, {...f.options, dryRun: true}, {}), /Preflight cannot release/);
    assert.equal(guards.receipt.mode, "preflight");
  } finally { guards.restore(); }
  const ordinary = adapter.installGuards(f, modules);
  try { await assert.rejects(modules.prepare.prepare({}, {...f.options, dryRun: true}, {}), /options changed/); }
  finally { ordinary.restore(); }
});

test("supported CLI dryRun preparation records preflight-passed, never deployment success", async (t) => {
  const f = fixture(); const directory = ownedDirectory(t); const configPath = path.join(directory, "firebase.json"); const outputPath = path.join(directory, "preflight.json");
  fs.writeFileSync(configPath, JSON.stringify({functions: {source: "source", codebase: "default"}}));
  const modules = adapter.loadPinned(); const command = require(path.join(modules.directory, "lib/commands/deploy")).command;
  const actualDeploy = require(path.join(modules.directory, "lib/deploy")).deploy;
  t.mock.method(require(path.join(modules.directory, "lib/track")), "trackGA4", async () => {});
  t.mock.method(modules.prepare, "prepare", async (_context, options, payload) => {
    assert.equal(options.dryRun, true); assert.equal(options.force, false);
    payload.extensions = {};
    payload.functions = {default: {wantBackend: backend([f.want]), haveBackend: backend([f.have])}};
    await modules.prompts.promptForFailurePolicies(options, payload.functions.default.wantBackend, payload.functions.default.haveBackend);
  });
  // Replace authentication/project resolution only. The pinned CLI's actual
  // lifecycle selects prepare and must skip its guarded upload/release targets.
  t.mock.method(command, "runner", () => async (options) => {
    assert.equal(options.dryRun, true);
    await actualDeploy(["functions"], {...options, projectId: f.candidate.projectId,
      config: {projectDir: directory, get: (target) => target === "functions" ? {source: "source"} : undefined}});
  });
  const result = await adapter.run({...f, configPath, outputPath, preflight: true});
  const saved = JSON.parse(fs.readFileSync(outputPath));
  assert.equal(result.status, "preflight-passed"); assert.equal(saved.status, "preflight-passed");
  assert.equal(saved.mode, "preflight"); assert.equal(saved.globalForce, false);
  assert.ok(saved.plans.length); assert.ok(saved.plans.every((item) => item.phase === "prepare-before-upload"));
});
