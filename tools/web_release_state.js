"use strict";

// Read-only deployment identity. The caller supplies Google ADC; no credentials are printed.
const {execFileSync} = require("node:child_process");
const fs = require("node:fs");
const path = require("node:path");
const {digest, sha256, PROJECTS} = require("./web_release_contract");
const {inspect} = require("./verify_firestore_indexes");
const root = path.resolve(__dirname, "..");

async function googleClient() {
  const {GoogleAuth} = require(require.resolve("google-auth-library", {paths: [path.join(root, "functions")]}));
  return new GoogleAuth({scopes: ["https://www.googleapis.com/auth/cloud-platform"]}).getClient();
}
async function pages(client, url, key, params = {}) {
  const result = []; let token; let pageCount = 0;
  do {
    const response = (await client.request({url, params: {...params, ...(token ? {pageToken: token} : {})}})).data;
    if (++pageCount > 100 || response.unreachable?.length || response[key] !== undefined && !Array.isArray(response[key])) throw Error("Incomplete or unbounded deployment inventory");
    result.push(...(response[key] || [])); token = response.nextPageToken;
  } while (token);
  return result;
}
async function captureFunctionSources(projectId, client) {
  const [v1, v2] = await Promise.all([
    pages(client, `https://cloudfunctions.googleapis.com/v1/projects/${projectId}/locations/-/functions`, "functions"),
    pages(client, `https://cloudfunctions.googleapis.com/v2/projects/${projectId}/locations/-/functions`, "functions"),
  ]);
  const sources = new Map();
  for (const fn of v1) {
    if (!fn.name?.startsWith(`projects/${projectId}/locations/`)) throw Error("Cross-project Functions source metadata");
    sources.set(fn.name, {name: fn.name, environment: "GEN_1", versionId: fn.versionId || null,
      sourceArchiveUrl: fn.sourceArchiveUrl?.startsWith("gs://") ? fn.sourceArchiveUrl : null,
      repositorySource: fn.sourceRepository?.deployedUrl || null});
  }
  const queue = [...v2];
  await Promise.all(Array.from({length: 8}, async () => {
    while (queue.length) {
      const fn = queue.shift();
      if (!fn.name?.startsWith(`projects/${projectId}/locations/`)) throw Error("Cross-project Functions source metadata");
      if (fn.environment === "GEN_1") continue;
      const resolved = fn.buildConfig?.sourceProvenance?.resolvedStorageSource || fn.buildConfig?.source?.storageSource;
      const source = resolved ? {bucket: resolved.bucket, object: resolved.object, generation: resolved.generation || null} : null;
      const service = fn.serviceConfig?.service;
      let revision = fn.serviceConfig?.revision; let images = [];
      if (service) {
        if (!service.startsWith(`projects/${projectId}/locations/`)) throw Error("Cross-project Cloud Run service");
        const run = (await client.request({url: `https://run.googleapis.com/v2/${service}`})).data;
        revision = run.latestReadyRevision || revision;
        if (revision && !revision.startsWith("projects/")) revision = `${service}/revisions/${revision}`;
        if (!revision?.startsWith(`${service}/revisions/`)) throw Error("Cloud Run revision identity unavailable");
        const deployed = (await client.request({url: `https://run.googleapis.com/v2/${revision}`})).data;
        images = (deployed.containers || []).map((container) => ({uri: container.image, digest: container.image?.match(/@sha256:([a-f0-9]{64})$/)?.[1] || container.imageDigest || deployed.imageDigest || null}));
        if (!images.length) throw Error("Cloud Run revision has no container image metadata");
      }
      sources.set(fn.name, {name: fn.name, environment: fn.environment || "GEN_2", build: fn.buildConfig?.build || null,
        source, service: service || null, revision: revision || null, images});
    }
  }));
  return [...sources.values()].sort((a, b) => a.name.localeCompare(b.name));
}
function firebase(args) {
  const entry = require.resolve("firebase-tools/lib/bin/firebase", {paths: [path.join(root, "functions")]});
  return execFileSync(process.execPath, [entry, ...args], {cwd: root, encoding: "utf8", maxBuffer: 20 * 1024 * 1024, stdio: ["ignore", "pipe", "inherit"]});
}
async function captureState(projectId, client = null) {
  if (!Object.values(PROJECTS).includes(projectId)) throw Error("Unsupported deployment project");
  client ||= await googleClient();
  const firestore = `https://firestore.googleapis.com/v1/projects/${projectId}/databases/(default)/collectionGroups/-`;
  const [hosting, releases, functions, indexes, fields, functionSources] = await Promise.all([
    client.request({url: `https://firebasehosting.googleapis.com/v1beta1/sites/${projectId}/releases`, params: {pageSize: 1}}).then((r) => r.data.releases?.[0]),
    pages(client, `https://firebaserules.googleapis.com/v1/projects/${projectId}/releases`, "releases"),
    Promise.resolve().then(() => JSON.parse(firebase(["functions:list", "--project", projectId, "--json"])).result),
    pages(client, `${firestore}/indexes`, "indexes"), pages(client, `${firestore}/fields`, "fields", {filter: "indexConfig.usesAncestorConfig=false OR ttlConfig:*"}), captureFunctionSources(projectId, client),
  ]);
  if (!hosting?.version?.name || !Array.isArray(functions)) throw Error("Incomplete Hosting/Functions predecessor inventory");
  const rules = [];
  for (const release of releases.filter((item) => item.name.includes("/releases/cloud.firestore") || item.name.includes("/releases/firebase.storage/"))) {
    const set = (await client.request({url: `https://firebaserules.googleapis.com/v1/${release.rulesetName}`})).data;
    if (!set.source?.files?.length) throw Error("Ruleset source unavailable");
    rules.push({release: release.name, rulesetName: release.rulesetName,
      files: set.source.files.map((file) => ({name: file.name, sha256: sha256(file.content)})).sort((a, b) => a.name.localeCompare(b.name))});
  }
  if (!rules.some((rule) => rule.release.endsWith("/cloud.firestore")) || !rules.some((rule) => rule.release.includes("/firebase.storage/"))) throw Error("Firestore or Storage active rules inventory missing");
  const publicFunctions = functions.map((fn) => {
    const metadata = Object.fromEntries(["id", "platform", "project", "region", "runtime", "entryPoint", "state", "codebase", "labels", "eventTrigger", "scheduleTrigger", "callableTrigger", "httpsTrigger", "serviceAccountEmail", "availableMemoryMb", "timeout", "minInstances", "maxInstances", "concurrency", "secretEnvironmentVariables"].filter((key) => fn[key] !== undefined).map((key) => [key, fn[key]]));
    // Bind plain environment changes without retaining possible credential values.
    if (fn.environmentVariables) metadata.environmentVariablesSha256 = digest(fn.environmentVariables);
    return metadata;
  });
  const state = {projectId, hostingVersion: hosting.version.name, hostingRelease: hosting.name,
    functions: publicFunctions.sort((a, b) => a.id.localeCompare(b.id)), rules: rules.sort((a, b) => a.release.localeCompare(b.release)),
    functionSources,
    indexes: indexes.sort((a, b) => a.name.localeCompare(b.name)), fields: fields.filter((field) => field.indexConfig || field.ttlConfig).sort((a, b) => a.name.localeCompare(b.name))};
  return {state, stateSha256: digest(state), capturedAt: new Date().toISOString()};
}
function verifyState(candidate, capture, manifest) {
  const state = capture.state;
  if (state.projectId !== candidate.projectId) throw Error("Remote project differs from candidate");
  const wanted = candidate.deployment.functions; const actual = state.functions.map((fn) => fn.id).sort();
  if (digest(wanted) !== digest(actual) || state.functions.some((fn) => fn.state !== "ACTIVE")) throw Error("Function inventory drift or inactive function");
  for (const trigger of [candidate.deployment.triggerTransition.legacy, candidate.deployment.triggerTransition.replacement]) {
    const deployed = state.functions.find((fn) => fn.id === trigger.name);
    if (deployed.region !== "us-central1" || deployed.eventTrigger?.eventType !== trigger.eventType) throw Error(`Trigger identity mismatch: ${trigger.name}`);
    const filters = deployed.eventTrigger.eventFilters || {};
    const patterns = deployed.eventTrigger.eventFilterPathPatterns || {};
    if ((patterns.document || filters.document) !== "event_analytics/{docId}") throw Error(`Trigger document mismatch: ${trigger.name}`);
  }
  for (const rule of state.rules) {
    if (rule.release.includes("/cloud.firestore/")) continue; // Named databases are preserved and drift-bound, never overwritten.
    const expected = rule.release.endsWith("/cloud.firestore") ? candidate.deployment.firestoreRulesSha256 : candidate.deployment.storageRulesSha256;
    if (rule.files.length !== 1 || rule.files[0].sha256 !== expected) throw Error("Deployed Firestore/Storage rules differ from frozen source");
  }
  const result = inspect(manifest, state.indexes, state.fields);
  if (Object.values(result).some((entries) => entries.length)) throw Error(`Indexes/TTL do not match: ${JSON.stringify(result)}`);
  return capture;
}
async function main() {
  const [command, projectId, output] = process.argv.slice(2);
  if (command !== "capture" || !output) throw Error("Usage: node tools/web_release_state.js capture <project-id> <output.json>");
  fs.writeFileSync(output, JSON.stringify(await captureState(projectId), null, 2) + "\n");
}
if (require.main === module) main().catch((error) => { console.error(error.message); process.exitCode = 1; });
module.exports = {captureState, captureFunctionSources, verifyState, firebase, googleClient, pages};
