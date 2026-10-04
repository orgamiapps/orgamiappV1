"use strict";

// Firebase has no retry-only noninteractive acknowledgement. Keep global force
// false; adapt only the pinned retry prompt, after checking its actual inputs.
const fs = require("node:fs");
const path = require("node:path");
const {digest, sha256, PROJECTS} = require("./web_release_contract");
const VERSION = "15.25.1";
const PINS = Object.freeze({
  "lib/deploy/functions/prompts.js": "64b265721a0d04289aa48755f02512ddde0f861545d7b135e433c9041538bff9",
  "lib/deploy/functions/release/planner.js": "b5ff3ad2b337f9aa79c09f78c4a8766768e82129f96b17a951611f27ff3e7bdf",
  "lib/deploy/functions/prepare.js": "7246ab3fa5927552614ca4078c6995cd05b2a58081f5cbe1a38f11a212d4af0f",
  "lib/deploy/functions/deploy.js": "93592080ba4e7d2e6057df1f34056ee6d1962e1a92a9447d2e3e69ca12b20e7e",
  "lib/deploy/functions/index.js": "2f29925b0f43d17962d9ddc85c0391dbb51818864adea52dc7b8c3b61a17e4da",
  "lib/deploy/functions/release/index.js": "03c7a0acae1ad8096370fcc263631947f048676ee4b42f3cd43dc0c64a3b6a6e",
  "lib/deploy/functions/release/fabricator.js": "34adc4107bacb3e21f51e854c79b5c2e1a8595683b94827df4afdab1e522f3de",
  "lib/deploy/index.js": "3312085417062367a78b7e53f679a920594f251b03bfc382a142e32e61cc6fbf",
  "lib/commands/deploy.js": "f79b5f7ae11e033e4dfe8ec4f2539a684422e346a22cf16355e908967a89fa5b",
  "lib/command.js": "8694788bf242975de8e0b1e5e532ea1e51723d78286a62741f4034abb21119fa",
  "lib/logger.js": "72eb50a1733b9d225cb01a5efb873503f4a542bd680f19c605ab461fa6feb229",
  "lib/deploy/extensions/prepare.js": "b47d8b26f01457f52b747f6e9c6509cec147f29926d913a9ede13e8cc7322be8",
  "lib/apiv2.js": "eada1f0c2f2bce92482647dcbf78fddff32eb6439d18f4a8cb26076fd2746db5", // gitleaks:allow Pinned CLI module SHA-256.
  "lib/gcp/cloudfunctionsv2.js": "c9fd8ed8e6faf0cad70051cdec048a7a222760384a14b45f5f01d38418d22752",
  "lib/api.js": "a13c173c36066ac62c711005534fc3bc071d49be8bb26df60303d88e818c5907", // gitleaks:allow Pinned CLI module SHA-256.
});
const PUBLIC_KEYS = ["id", "platform", "project", "region", "runtime", "entryPoint", "state", "codebase", "labels", "eventTrigger", "scheduleTrigger", "callableTrigger", "httpsTrigger", "serviceAccountEmail", "availableMemoryMb", "timeout", "minInstances", "maxInstances", "concurrency", "secretEnvironmentVariables"];
const key = (endpoint) => `${endpoint.region}/${endpoint.id}`;
const endpoints = (backend) => Object.values(backend?.endpoints || {}).flatMap((region) => Object.values(region));
const same = (a, b) => digest(a) === digest(b);
let installed = false;

function assertPins(directory, read = fs.readFileSync) {
  if (JSON.parse(read(path.join(directory, "package.json"), "utf8")).version !== VERSION) throw Error("Unreviewed firebase-tools version");
  for (const [file, expected] of Object.entries(PINS)) if (sha256(read(path.join(directory, file))) !== expected) throw Error(`Unreviewed firebase-tools module: ${file}`);
}
function loadPinned() {
  const directory = path.dirname(require.resolve("firebase-tools/package.json", {paths: [path.resolve(__dirname, "../functions")]}));
  assertPins(directory);
  return {directory, prompts: require(path.join(directory, "lib/deploy/functions/prompts")),
    planner: require(path.join(directory, "lib/deploy/functions/release/planner")),
    prepare: require(path.join(directory, "lib/deploy/functions/prepare")),
    deploy: require(path.join(directory, "lib/deploy/functions/deploy")),
    release: require(path.join(directory, "lib/deploy/functions/release"))};
}
function descriptor(endpoint) {
  return {id: endpoint.id, region: endpoint.region, platform: endpoint.platform,
    eventType: endpoint.eventTrigger?.eventType, eventFilters: endpoint.eventTrigger?.eventFilters || {},
    eventFilterPathPatterns: endpoint.eventTrigger?.eventFilterPathPatterns || {},
    eventTriggerRegion: endpoint.eventTrigger?.region};
}
function publicEndpoint(endpoint) {
  const result = Object.fromEntries(PUBLIC_KEYS.filter((name) => endpoint[name] !== undefined).map((name) => [name, endpoint[name]]));
  if (endpoint.environmentVariables) result.environmentVariablesSha256 = digest(endpoint.environmentVariables);
  return result;
}
function triggerIdentity(endpoint) {
  const kinds = ["eventTrigger", "scheduleTrigger", "callableTrigger", "httpsTrigger", "taskQueueTrigger", "blockingTrigger"].filter((name) => endpoint[name] !== undefined);
  if (kinds.length !== 1) throw Error(`Ambiguous trigger identity: ${endpoint.id}`);
  if (kinds[0] !== "eventTrigger") return {kind: kinds[0]};
  const event = {...endpoint.eventTrigger}; delete event.retry;
  return {kind: kinds[0], event};
}
function validateInputs(candidate, predecessor) {
  if (!candidate || PROJECTS[candidate.environment] !== candidate.projectId || !/^[a-f0-9]{40}$/.test(candidate.sourceSha || "") || predecessor?.projectId !== candidate.projectId) throw Error("Invalid candidate/project identity");
  if (!same(predecessor.functions, candidate.predecessor?.[candidate.environment]?.functions)) throw Error("Functions predecessor differs from frozen candidate");
  const names = candidate.deployment?.functions;
  if (!Array.isArray(names) || !names.length || names.some((name) => !/^[A-Za-z][A-Za-z0-9_]*$/.test(name)) || !same(names, [...new Set(names)].sort())) throw Error("Exact sorted Function selectors required");
  if (!Array.isArray(candidate.deployment.deleteFunctions) || candidate.deployment.deleteFunctions.length) throw Error("Function retirement is forbidden");
  if (!Array.isArray(predecessor.functions) || !predecessor.functions.length || new Set(predecessor.functions.map(key)).size !== predecessor.functions.length || predecessor.functions.some((fn) => !names.includes(fn.id) || fn.project !== candidate.projectId || fn.state !== "ACTIVE" || (fn.codebase || "default") !== "default")) throw Error("Missing, renamed or inactive predecessor Function");
  const approvals = candidate.deployment.retryAcknowledgements;
  if (!Array.isArray(approvals) || new Set(approvals.map(key)).size !== approvals.length) throw Error("Explicit retry acknowledgements required");
  for (const approval of approvals) {
    if (!names.includes(approval.id) || approval.platform !== "gcfv2" || !/^[a-z]+-[a-z]+[0-9]+$/.test(approval.region || "") || !/^[a-z0-9-]+$/.test(approval.eventTriggerRegion || "") || typeof approval.eventType !== "string" || !approval.eventType || !approval.eventFilters || !approval.eventFilterPathPatterns || !same(Object.keys(approval).sort(), ["id", "region", "platform", "eventType", "eventFilters", "eventFilterPathPatterns", "eventTriggerRegion"].sort())) throw Error("Malformed reviewed retry acknowledgement");
  }
  return {names, approvals, only: names.map((name) => `functions:${name}`).join(",")};
}
function validateBackends(candidate, predecessor, want, have) {
  const {names, approvals} = validateInputs(candidate, predecessor);
  const desired = endpoints(want); const existing = endpoints(have);
  if (!same(desired.map((fn) => fn.id).sort(), names) || new Set(desired.map(key)).size !== desired.length || desired.some((fn) => fn.project !== candidate.projectId || (fn.codebase || "default") !== "default")) throw Error("Actual Function selectors differ from frozen candidate");
  const recorded = [...predecessor.functions].sort((a, b) => key(a).localeCompare(key(b)));
  if (!same(existing.map(publicEndpoint).sort((a, b) => key(a).localeCompare(key(b))), recorded)) throw Error("Actual Functions or retry state drifted from predecessor");
  const wanted = new Map(desired.map((fn) => [key(fn), fn]));
  for (const previous of existing) {
    const next = wanted.get(key(previous));
    if (!next || next.platform !== previous.platform || next.entryPoint !== previous.entryPoint || !same(triggerIdentity(next), triggerIdentity(previous))) throw Error(`Function identity/trigger change is forbidden: ${previous.id}`);
    if (previous.eventTrigger?.retry === true && next.eventTrigger?.retry !== true) throw Error(`Existing retry policy cannot be disabled: ${previous.id}`);
  }
  for (const approval of approvals) {
    const next = wanted.get(key(approval));
    if (!next || next.eventTrigger?.retry !== true || !same(descriptor(next), approval)) throw Error(`Reviewed retry endpoint changed: ${approval.id}`);
  }
  const previous = new Map(existing.map((fn) => [key(fn), fn]));
  const transitions = desired.filter((fn) => fn.eventTrigger?.retry === true && previous.get(key(fn))?.eventTrigger?.retry !== true).map(descriptor).sort((a, b) => key(a).localeCompare(key(b)));
  const expected = approvals.filter((approval) => previous.get(key(approval))?.eventTrigger?.retry !== true).sort((a, b) => key(a).localeCompare(key(b)));
  if (!same(transitions, expected)) throw Error("Unreviewed newly retried Function");
  return transitions;
}
function assertPlan(plan, candidate) {
  if (!plan?.regionalChangesets || plan.serviceAccountToDelete || plan.serviceAccountToCreate || plan.rolesToAdd?.length || plan.rolesToRemove?.length) throw Error("Unreviewed deployment/security plan");
  const planned = [];
  for (const changes of Object.values(plan.regionalChangesets)) {
    if (!Array.isArray(changes.endpointsToDelete) || changes.endpointsToDelete.length) throw Error("Actual planner Function deletion is forbidden");
    for (const update of changes.endpointsToUpdate || []) {
      if (update.deleteAndRecreate || update.unsafe) throw Error("Actual planner Function recreation/unsafe migration is forbidden");
    }
    for (const [action, functions] of [["create", changes.endpointsToCreate], ["update", changes.endpointsToUpdate?.map((item) => item.endpoint)], ["skip", changes.endpointsToSkip]]) {
      if (!Array.isArray(functions)) throw Error("Incomplete actual deployment plan");
      for (const fn of functions) {
        if (!candidate.deployment.functions.includes(fn.id) || fn.project !== candidate.projectId) throw Error("Planner selected an unapproved Function");
        planned.push({id: fn.id, region: fn.region, platform: fn.platform, action});
      }
    }
  }
  if (!same(planned.map((fn) => fn.id).sort(), candidate.deployment.functions)) throw Error("Planner omitted or duplicated a Function");
  return planned.sort((a, b) => key(a).localeCompare(key(b)));
}
function assertEmptyExtensions(payload) {
  if (!Object.hasOwn(payload, "extensions")) return;
  const value = payload.extensions;
  // Pinned SDK discovery always supplies build.extensions={}, and the CLI
  // consequently retains payload.extensions={} when no instances exist.
  if (!value || Object.getPrototypeOf(value) !== Object.prototype || Object.keys(value).length) throw Error("Actual extension deployment is forbidden");
}
function installGuards({candidate, predecessor, outputPath, preflight = false}, modules = loadPinned()) {
  const {only} = validateInputs(candidate, predecessor);
  if (typeof preflight !== "boolean") throw Error("Explicit boolean preflight mode required");
  if (installed) throw Error("Concurrent Functions adapters are forbidden");
  installed = true;
  const original = {retry: modules.prompts.promptForFailurePolicies, planner: modules.planner.createDeploymentPlan,
    prepare: modules.prepare.prepare, deploy: modules.deploy.deploy, release: modules.release.release,
    uploadSourceV2: modules.deploy.uploadSourceV2};
  const receipt = {schemaVersion: 1, sourceSha: candidate.sourceSha, projectId: candidate.projectId,
    candidateRunId: candidate.candidateRunId, candidateSha256: digest(candidate), predecessorFunctionsSha256: digest(predecessor.functions),
    firebaseToolsVersion: VERSION, moduleHashes: PINS, globalForce: false, transitions: [], plans: [],
    mode: preflight ? "preflight" : "deploy", status: "preparing", startedAt: new Date().toISOString()};
  function persist() {
    if (!outputPath) return;
    const absolute = path.resolve(outputPath);
    fs.mkdirSync(path.dirname(absolute), {recursive: true});
    fs.writeFileSync(`${absolute}.pending`, JSON.stringify(receipt, null, 2) + "\n");
    fs.renameSync(`${absolute}.pending`, absolute);
  }
  let preparing = null;
  let phase = "release";
  const optionsGuard = (options) => {
    if (options.force !== false || options.nonInteractive !== true || options.interactive || options.dryRun !== preflight || options.except || options.only !== only || (options.projectId || options.project) !== candidate.projectId) throw Error("Functions adapter options changed or broad force requested");
  };
  modules.planner.createDeploymentPlan = async (args) => {
    if (args.codebase !== "default" || args.projectId !== candidate.projectId || args.deleteAll) throw Error("Unreviewed planner scope");
    validateBackends(candidate, predecessor, args.wantBackend, args.haveBackend);
    const plan = await original.planner(args);
    const functions = assertPlan(plan, candidate);
    receipt.plans.push({phase: preparing ? "prepare-before-upload" : phase, functions});
    persist(); // Durable before IAM continuation, source upload or applyPlan.
    return plan;
  };
  async function guardPayload(context, payload) {
    if (context.projectId !== candidate.projectId || !payload.functions || !same(Object.keys(payload.functions), ["default"])) throw Error("Unreviewed prepared deployment scope");
    assertEmptyExtensions(payload);
    for (const [codebase, values] of Object.entries(payload.functions)) await modules.planner.createDeploymentPlan({...values, codebase, projectId: context.projectId, filters: context.filters});
  }
  modules.prompts.promptForFailurePolicies = async (options, want, have) => {
    optionsGuard(options);
    receipt.transitions = validateBackends(candidate, predecessor, want, have);
    if (preparing) await guardPayload(preparing.context, preparing.payload);
    else await modules.planner.createDeploymentPlan({codebase: "default", projectId: candidate.projectId, wantBackend: want, haveBackend: have});
    // This clone is passed to this one original, hash-pinned prompt only.
    return original.retry({...options, force: true}, want, have);
  };
  modules.prepare.prepare = async (context, options, payload) => {
    optionsGuard(options); preparing = {context, payload};
    try { await original.prepare(context, options, payload); await guardPayload(context, payload); }
    finally { preparing = null; }
  };
  modules.deploy.deploy = async (context, options, payload) => {
    if (preflight) throw Error("Preflight cannot deploy or upload Function source");
    optionsGuard(options); phase = "before-upload";
    try { await guardPayload(context, payload); return await original.deploy(context, options, payload); }
    finally { phase = "release"; }
  };
  modules.deploy.uploadSourceV2 = async (...args) => {
    if (preflight) throw Error("Preflight cannot upload Function source");
    return original.uploadSourceV2(...args);
  };
  modules.release.release = async (context, options, payload) => {
    if (preflight) throw Error("Preflight cannot release Functions");
    optionsGuard(options);
    return original.release(context, options, payload);
  };
  return {receipt, persist, restore() {
    modules.prompts.promptForFailurePolicies = original.retry; modules.planner.createDeploymentPlan = original.planner;
    modules.prepare.prepare = original.prepare; modules.deploy.deploy = original.deploy;
    modules.deploy.uploadSourceV2 = original.uploadSourceV2; modules.release.release = original.release; installed = false;
  }};
}
function guardUnfinishedExecution(guards) {
  // An awaited promise alone does not keep Node alive. The pinned CLI's queue
  // can strand queued work after retry exhaustion, leaving command.runner()
  // unresolved even though the event loop is empty. Never turn that into an
  // exit-zero deployment. Do not resume/retry the queue or create a keepalive.
  let stopped = false, rejectUnfinished;
  const unfinished = new Promise((_, reject) => {rejectUnfinished = reject;});
  function fail(code) {
    if (stopped) return;
    const error = Object.assign(Error("Pinned Firebase CLI exited with unfinished execution; inspect the curated CLI log and reconcile deployed state."), {code});
    guards.receipt.status = "failure";
    guards.receipt.failureCode = code;
    guards.receipt.error = error.message;
    guards.receipt.finishedAt = new Date().toISOString();
    if (!process.exitCode) process.exitCode = 1;
    // The exit callback can only do synchronous work. persist() uses the same
    // atomic receipt replacement as the normal finalizer and retains all plans.
    try {guards.persist();}
    catch (_) {console.error("Could not persist the unfinished Functions failure receipt.");}
    rejectUnfinished(error);
  }
  const beforeExit = () => fail("cli-unsettled-before-exit");
  const exit = () => fail("cli-unsettled-exit");
  process.once("beforeExit", beforeExit); process.once("exit", exit);
  return {wait: (promise) => Promise.race([promise, unfinished]), stop() {
    stopped = true; process.removeListener("beforeExit", beforeExit); process.removeListener("exit", exit);
  }};
}
function installFunctionApiPacing({candidate, now = () => performance.now(), sleep = (ms) => new Promise((resolve) => setTimeout(resolve, ms))}) {
  const origin = "https://cloudfunctions.googleapis.com", region = "us-central1", interval = 1500;
  if (PROJECTS[candidate?.environment] !== candidate?.projectId || !Array.isArray(candidate?.deployment?.functions) ||
      !candidate.deployment.functions.length || candidate.deployment.functions.some((id) => !/^[A-Za-z][A-Za-z0-9_]*$/.test(id))) throw Error("Invalid Functions transport scope");
  const names = new Set(candidate.deployment.functions), base = `/v2/projects/${candidate.projectId}/locations/${region}/functions`;
  const original = globalThis.fetch;
  if (typeof original !== "function") throw Error("Pinned Functions transport requires global fetch");
  const receipt = {projectId: candidate.projectId, region, minimumStartSpacingMs: interval, startedRequests: 0, minimumObservedSpacingMs: null};
  let lastDispatch = -Infinity, lastObservedStart = -Infinity, dispatch = Promise.resolve();
  function selected(input, options) {
    const request = typeof Request !== "undefined" && input instanceof Request;
    const value = request ? input.url : typeof input === "string" || input instanceof URL ? input : null;
    if (value === null) return false;
    let url;
    try {url = new URL(value);} catch (_) {return false;}
    if (url.hostname !== "cloudfunctions.googleapis.com") return false;
    const method = String(options?.method ?? (request ? input.method : "GET")).toUpperCase();
    let pathname;
    try {pathname = decodeURIComponent(url.pathname);} catch (_) {pathname = url.pathname;}
    // Fabricator can attempt an internal delete/recreate after code 8 despite
    // a safe top-level plan. This adapter forbids every Function deletion.
    if (method === "DELETE" && /\/functions\//.test(pathname)) throw Error("Functions transport deletion is forbidden");
    const create = method === "POST" && /\/functions\/?$/.test(pathname);
    const update = method === "PATCH" && /\/functions(?:\/|$)/.test(pathname);
    if (!create && !update) return false;
    let id;
    if (create && url.pathname === base && [...url.searchParams.keys()].every((name) => name === "functionId") && url.searchParams.getAll("functionId").length === 1) id = url.searchParams.get("functionId");
    if (update && url.pathname.startsWith(base + "/") && [...url.searchParams.keys()].every((name) => name === "updateMask") && url.searchParams.getAll("updateMask").length <= 1) id = url.pathname.slice(base.length + 1);
    if (url.origin !== origin || url.username || url.password || url.hash || !names.has(id)) throw Error("Functions transport mutation is outside the frozen candidate project/region/name");
    return true;
  }
  function pacedFetch(...args) {
    let pace;
    try {pace = selected(args[0], args[1]);} catch (error) {return Promise.reject(error);}
    if (!pace) return Reflect.apply(original, this, args);
    const receiver = this;
    const start = dispatch.then(async () => {
      let current = now();
      while (current - lastDispatch < interval) {await sleep(interval - (current - lastDispatch)); current = now();}
      // Do not await the response here: only request starts are serialized. The
      // pinned apiv2 calls free global fetch for every internal retry, so those
      // attempts share this same start gate. Arguments and payload stay intact.
      const startedAt = now();
      try {return {response: Reflect.apply(original, receiver, args)};}
      finally {
        // Using the return from the synchronous fetch invocation as the next
        // lower bound also excludes any synchronous dispatch overhead.
        lastDispatch = now();
        const spacing = startedAt - lastObservedStart; lastObservedStart = startedAt;
        receipt.startedRequests++;
        if (Number.isFinite(spacing)) receipt.minimumObservedSpacingMs = receipt.minimumObservedSpacingMs === null ? spacing : Math.min(receipt.minimumObservedSpacingMs, spacing);
      }
    });
    dispatch = start.then(() => undefined, () => undefined);
    return start.then(({response}) => response);
  }
  globalThis.fetch = pacedFetch;
  return {receipt, restore() {globalThis.fetch = original;}};
}
async function run({candidate, configPath, predecessor, outputPath, preflight = false}) {
  const {only} = validateInputs(candidate, predecessor);
  const absoluteConfig = path.resolve(configPath);
  const config = JSON.parse(fs.readFileSync(absoluteConfig, "utf8"));
  const configurations = Array.isArray(config.functions) ? config.functions : [config.functions];
  if (configurations.length !== 1 || !configurations[0]?.source || (configurations[0].codebase || "default") !== "default" || config.extensions) throw Error("Only one frozen Functions codebase is supported");
  const modules = loadPinned(); const guards = installGuards({candidate, predecessor, outputPath, preflight}, modules);
  const execution = guardUnfinishedExecution(guards);
  let apiPacing;
  try {
    const api = require(path.join(modules.directory, "lib/api"));
    if (api.functionsOrigin() !== "https://cloudfunctions.googleapis.com" || api.functionsV2Origin() !== "https://cloudfunctions.googleapis.com") throw Error("Functions transport origin overrides are forbidden");
    apiPacing = installFunctionApiPacing({candidate}); guards.receipt.apiPacing = apiPacing.receipt;
    guards.persist();
    // The programmatic runner defaults to a silent logger. Enable only its
    // ordinary info console transport, never a debug log or inherited DEBUG.
    const previousDebug = process.env.DEBUG; const previousCli = process.env.IS_FIREBASE_CLI;
    try { delete process.env.DEBUG; process.env.IS_FIREBASE_CLI = "true"; require(path.join(modules.directory, "lib/logger")).useConsoleLoggers(); }
    finally {
      if (previousDebug === undefined) delete process.env.DEBUG; else process.env.DEBUG = previousDebug;
      if (previousCli === undefined) delete process.env.IS_FIREBASE_CLI; else process.env.IS_FIREBASE_CLI = previousCli;
    }
    const command = require(path.join(modules.directory, "lib/commands/deploy")).command;
    // Firebase's supported dry run still performs predeploy/prepare, including
    // possible prerequisite API enablement. It must not upload/release Functions.
    await execution.wait(Promise.resolve().then(() => command.runner()({project: candidate.projectId, config: absoluteConfig, only, nonInteractive: true, force: false, dryRun: preflight})));
    if (!guards.receipt.plans.some((plan) => plan.phase === "prepare-before-upload") ||
        (preflight ? guards.receipt.plans.some((plan) => plan.phase !== "prepare-before-upload") : !guards.receipt.plans.some((plan) => plan.phase === "release"))) throw Error("Pinned CLI did not execute required plan guards");
    guards.receipt.status = preflight ? "preflight-passed" : "success";
    return guards.receipt;
  } catch (error) {
    guards.receipt.status = "failure";
    guards.receipt.error ||= "Functions deployment failed; inspect the curated CLI log.";
    throw error;
  } finally {
    apiPacing?.restore();
    execution.stop();
    guards.receipt.finishedAt = new Date().toISOString(); guards.restore();
    guards.persist();
  }
}
if (require.main === module) {
  const [candidateFile, configPath, predecessorFile, outputPath, mode, extra] = process.argv.slice(2);
  if (!candidateFile || !configPath || !predecessorFile || !outputPath || (mode !== undefined && mode !== "--preflight") || extra) { console.error("Usage: node tools/deploy_web_functions.js <candidate.json> <config.json> <predecessor.json> <receipt.json> [--preflight]"); process.exitCode = 1; }
  else Promise.resolve().then(() => run({candidate: JSON.parse(fs.readFileSync(candidateFile, "utf8")), configPath,
    predecessor: JSON.parse(fs.readFileSync(predecessorFile, "utf8")), outputPath, preflight: mode === "--preflight"})).catch((error) => { console.error(error.message); process.exitCode = 1; });
}
module.exports = {VERSION, PINS, assertPins, loadPinned, descriptor, publicEndpoint, validateInputs, validateBackends, assertPlan, assertEmptyExtensions, installGuards, installFunctionApiPacing, run};
