"use strict";

// Only the pre-fixture staging deployment calls this tool. It never deletes a
// function or modifies trigger/service configuration. Every attempted source
// rollback is followed by a candidate-source restoration, including failures.
const fs = require("node:fs");
const path = require("node:path");
const {digest, sha256} = require("./web_release_contract");
const {googleClient} = require("./web_release_state");
const PROJECT = "attendus-staging";
const SCOPE = "Four representative Gen2 source-only rollback/restorations; no deletions or full-fleet rollback claim";
const OPERATION = /^projects\/attendus-staging\/locations\/us-central1\/operations\/[A-Za-z0-9_-]+$/;
const REPRESENTATIVES = Object.freeze({publicWeb: "http", triggerAIInsights: "firestore-updated",
  aggregateAdminMetricsDaily: "scheduled", getOrganizerEventRegistrationsV1: "callable"});
const EMPTY_COLLECTIONS = Object.freeze(["Events", "Customers", "RegisterAttendance", "Tickets", "Attendance", "GuestAttendees",
  "Conversations", "EventAnnouncements", "EventExportJobs", "OutboundMessages", "scheduledNotifications", "pendingPush",
  "Notifications", "QualificationScopes", "QualificationBindings"]);
const sourceOf = (fn) => fn.buildConfig?.sourceProvenance?.resolvedStorageSource || fn.buildConfig?.source?.storageSource;
function sourceIdentity(source) {
  if (typeof source?.bucket !== "string" || !/^[a-z0-9][a-z0-9._-]{1,220}$/.test(source.bucket) || typeof source.object !== "string" || !source.object || source.object.length > 1024 || /[\x00-\x1f]/.test(source.object) || !/^[1-9][0-9]*$/.test(String(source.generation || ""))) throw Error("An immutable source object generation is required");
  return {bucket: source.bucket, object: source.object, generation: String(source.generation)};
}
function stableConfig(fn) {
  const serviceConfig = {...fn.serviceConfig}; delete serviceConfig.revision;
  const eventTrigger = fn.eventTrigger ? {...fn.eventTrigger} : null;
  // The v2 API returns these conjunctive filters in varying array order even
  // when updateTime is unchanged. Preserve every value/operator; reject
  // ambiguous duplicate attributes instead of dropping a filter.
  if (Array.isArray(eventTrigger?.eventFilters)) {
    const attributes = new Set();
    eventTrigger.eventFilters = eventTrigger.eventFilters.map((filter) => {
      if (typeof filter?.attribute !== "string" || !filter.attribute || typeof filter.value !== "string" || attributes.has(filter.attribute)) throw Error("Ambiguous event filter configuration");
      attributes.add(filter.attribute); return {...filter};
    }).sort((a, b) => a.attribute.localeCompare(b.attribute));
  }
  return {name: fn.name, environment: fn.environment, runtime: fn.buildConfig?.runtime, entryPoint: fn.buildConfig?.entryPoint,
    buildEnvironment: fn.buildConfig?.environmentVariables || {}, buildServiceAccount: fn.buildConfig?.serviceAccount || null,
    dockerRepository: fn.buildConfig?.dockerRepository || null, serviceConfig, eventTrigger, labels: fn.labels || {}};
}
function validateArchives(manifest, predecessor) {
  if (manifest.schemaVersion !== 1 || !Array.isArray(manifest.entries) || predecessor.projectId !== PROJECT) throw Error("Invalid staged predecessor archive manifest");
  const entries = manifest.entries.filter((entry) => entry.projectId === PROJECT);
  const byName = new Map();
  for (const entry of entries) {
    if (!entry.functionName?.startsWith(`projects/${PROJECT}/locations/`) || byName.has(entry.functionName) || !/^[a-f0-9]{64}$/.test(entry.original?.sha256 || "") || entry.original.sha256 !== entry.backup?.sha256) throw Error("Ambiguous or unhashed predecessor archive");
    const original = sourceIdentity(entry.original); const backup = sourceIdentity(entry.backup);
    if (backup.bucket !== "attendus-recovery-20261004-backups" || !backup.object.startsWith(`backend-source/${PROJECT}/`)) throw Error("Backup archive is outside the private staging source prefix");
    byName.set(entry.functionName, {...entry, original: {...original, sha256: entry.original.sha256}, backup: {...backup, sha256: entry.backup.sha256}});
  }
  const functions = predecessor.functionSources;
  if (!Array.isArray(functions) || functions.length !== byName.size) throw Error("Every staged predecessor function must have a retained archive");
  for (const fn of functions) {
    const entry = byName.get(fn.name);
    if (!entry || fn.environment !== "GEN_2" || digest(sourceIdentity(fn.source)) !== digest(sourceIdentity(entry.original))) throw Error("Archive original differs from captured predecessor source");
  }
  for (const [name, type] of Object.entries(REPRESENTATIVES)) {
    const fn = predecessor.functions.find((entry) => entry.id === name);
    if (!fn || fn.region !== "us-central1" || !byName.has(`projects/${PROJECT}/locations/us-central1/functions/${name}`)) throw Error(`Required representative missing: ${name}`);
    if (type === "firestore-updated" && fn.eventTrigger?.eventType !== "google.cloud.firestore.document.v1.updated" ||
        type === "scheduled" && !fn.scheduleTrigger || type === "callable" && !fn.callableTrigger ||
        type === "http" && (!fn.httpsTrigger || fn.callableTrigger)) throw Error(`Predecessor representative type changed: ${name}`);
  }
  return byName;
}
async function assertEmpty(client) {
  const collections = {};
  for (const collection of EMPTY_COLLECTIONS) {
    const response = (await client.request({url: `https://firestore.googleapis.com/v1/projects/${PROJECT}/databases/(default)/documents/${collection}`, params: {pageSize: 1}})).data;
    if (response.documents?.length || response.nextPageToken) throw Error(`Backend rehearsal requires empty ${collection}`);
    collections[collection] = 0;
  }
  const accounts = (await client.request({url: `https://identitytoolkit.googleapis.com/v1/projects/${PROJECT}/accounts:batchGet`, params: {maxResults: 2}})).data;
  const users = accounts.users || [];
  if (accounts.nextPageToken || users.length > 1 || users.some((user) => user.email || user.phoneNumber || user.providerUserInfo?.length)) throw Error("Backend rehearsal requires no identified Auth users");
  return {checkedAt: new Date().toISOString(), collections, anonymousAuthCount: users.length};
}
async function objectBytes(client, source) {
  const identity = sourceIdentity(source); const url = `https://storage.googleapis.com/storage/v1/b/${encodeURIComponent(identity.bucket)}/o/${encodeURIComponent(identity.object)}`;
  const metadata = (await client.request({url, params: {generation: identity.generation}})).data;
  if (String(metadata.generation) !== identity.generation || Number(metadata.size) <= 0 || Number(metadata.size) > 32 * 1024 * 1024) throw Error("Source archive generation or size mismatch");
  const bytes = Buffer.from((await client.request({url, params: {generation: identity.generation, alt: "media"}, responseType: "arraybuffer"})).data);
  if (bytes.length !== Number(metadata.size)) throw Error("Source archive byte length differs");
  return {...identity, sha256: sha256(bytes), size: bytes.length};
}
async function readFunction(client, name) {
  if (!/^projects\/attendus-staging\/locations\/us-central1\/functions\/[A-Za-z0-9_]+$/.test(name)) throw Error("Rehearsal cannot target production or another region");
  return (await client.request({url: `https://cloudfunctions.googleapis.com/v2/${name}`})).data;
}
async function resolvedArchive(client, name, fn, requested) {
  if (fn?.name !== name || fn.environment !== "GEN_2") throw Error("Resolved archive belongs to another function");
  const source = sourceIdentity(sourceOf(fn)), id = name.split("/").at(-1);
  const identical = digest(source) === digest(sourceIdentity(requested));
  if (!identical && (source.bucket !== "gcf-v2-sources-925344893088-us-central1" || source.object !== `${id}/function-source.zip`)) throw Error("Unexpected resolved source boundary");
  const actual = await objectBytes(client, source);
  if (actual.sha256 !== requested.sha256 || actual.size !== requested.size) throw Error("Resolved archive bytes differ from the submitted pinned archive");
  return actual;
}
async function retainCandidateSource(client, source, runId, id) {
  if (!/^[1-9][0-9]*$/.test(String(runId)) || !Object.hasOwn(REPRESENTATIVES, id)) throw Error("Invalid private candidate archive identity");
  const original = await objectBytes(client, source);
  const bucket = "attendus-recovery-20261004-backups";
  const object = `backend-source/${PROJECT}/candidates/${runId}/${id}/source.zip`;
  const url = `https://storage.googleapis.com/storage/v1/b/${encodeURIComponent(original.bucket)}/o/${encodeURIComponent(original.object)}/copyTo/b/${bucket}/o/${encodeURIComponent(object)}`;
  const copied = (await client.request({method: "POST", url, params: {sourceGeneration: original.generation, ifGenerationMatch: 0}, data: {}})).data;
  const backup = await objectBytes(client, {bucket, object, generation: copied.generation});
  if (backup.sha256 !== original.sha256 || backup.size !== original.size) throw Error("Private candidate archive copy differs from the deployed candidate");
  return {original, backup};
}
async function patchSource(client, name, source, {timeoutMs = 15 * 60000, sleep = (ms) => new Promise((resolve) => setTimeout(resolve, ms)), onOperation = () => {}} = {}) {
  const readyDeadline = Date.now() + timeoutMs;
  let before = await readFunction(client, name); // Enforces the target boundary before any write.
  while (before.state === "DEPLOYING") {
    if (Date.now() >= readyDeadline) throw Error(`Prior function deployment did not settle: ${name}`);
    await sleep(10000); before = await readFunction(client, name);
  }
  if (!["ACTIVE", "FAILED"].includes(before.state)) throw Error("Function is not in a recoverable deployment state");
  const requestedSource = await objectBytes(client, source);
  if (source.sha256 && requestedSource.sha256 !== source.sha256 || source.size && requestedSource.size !== source.size) throw Error("Submitted archive differs from its retained proof");
  const operation = (await client.request({method: "PATCH", url: `https://cloudfunctions.googleapis.com/v2/${name}`,
    params: {updateMask: "buildConfig.source"}, data: {name, buildConfig: {source: {storageSource: sourceIdentity(source)}}}})).data;
  if (!OPERATION.test(operation.name || "")) throw Error("Unexpected function operation identity");
  const proof = {operation: operation.name, startedAt: operation.metadata?.createTime || null,
    completedAt: operation.metadata?.endTime || null, requestedSource};
  try {
    // Persist the acknowledged operation before polling. A timeout or failed
    // GET must retain the exact operation needed to reconcile this attempt.
    await onOperation(proof);
    const deadline = Date.now() + timeoutMs; let current = operation;
    while (!current.done) {
      if (Date.now() >= deadline) throw Error(`Source deployment operation timed out: ${operation.name}`);
      await sleep(10000);
      current = (await client.request({url: `https://cloudfunctions.googleapis.com/v2/${operation.name}`})).data;
      if (current.name !== operation.name) throw Error("Polled function operation identity differs");
    }
    proof.startedAt = current.metadata?.createTime || null;
    proof.completedAt = current.metadata?.endTime || null;
    if (current.error || current.response?.name !== name || current.metadata?.target && current.metadata.target !== name) throw Error(`Source operation did not succeed for the exact function: ${operation.name}`);
    proof.source = await resolvedArchive(client, name, current.response, requestedSource);
    const fresh = await readFunction(client, name);
    if (fresh.state !== "ACTIVE" || digest(sourceIdentity(sourceOf(fresh))) !== digest(sourceIdentity(proof.source)) ||
        digest(stableConfig(fresh)) !== digest(stableConfig(current.response))) throw Error(`Live function source/configuration differs after operation: ${operation.name}`);
    return {...proof, configurationSha256: digest(stableConfig(fresh)), revision: fresh.serviceConfig?.revision || null};
  } catch (error) { error.operationReceipt = proof; throw error; }
}
async function rehearse({candidate, predecessor, manifest, output, client = null, patch = patchSource, checkEmpty = assertEmpty, retain = retainCandidateSource}) {
  if (candidate.environment !== "staging" || candidate.projectId !== PROJECT || candidate.candidateRunId !== process.env.GITHUB_RUN_ID || candidate.sourceSha !== process.env.GITHUB_SHA) throw Error("Rehearsal is restricted to the current staging candidate workflow");
  const archives = validateArchives(manifest, predecessor); client ||= await googleClient();
  const receipt = {schemaVersion: 1, projectId: PROJECT, candidateRunId: candidate.candidateRunId, sourceSha: candidate.sourceSha,
    candidateSha256: digest(candidate), predecessorSha256: digest(predecessor), archiveManifestSha256: digest(manifest),
    scope: SCOPE, representatives: {}, startedAt: new Date().toISOString()};
  fs.mkdirSync(path.dirname(output), {recursive: true});
  const save = () => fs.writeFileSync(output, JSON.stringify(receipt, null, 2) + "\n");
  receipt.emptyBefore = await checkEmpty(client); save();
  // Confirm every private backup still exists at its immutable generation before touching a function.
  for (const entry of archives.values()) {
    const backup = sourceIdentity(entry.backup);
    const metadata = (await client.request({url: `https://storage.googleapis.com/storage/v1/b/${encodeURIComponent(backup.bucket)}/o/${encodeURIComponent(backup.object)}`, params: {generation: backup.generation}})).data;
    if (String(metadata.generation) !== backup.generation || Number(metadata.size) <= 0) throw Error("Retained predecessor archive unavailable");
  }
  for (const [id, type] of Object.entries(REPRESENTATIVES)) {
    const name = `projects/${PROJECT}/locations/us-central1/functions/${id}`;
    const current = await readFunction(client, name); const archive = archives.get(name);
    const priorFunction = predecessor.functions.find((fn) => fn.id === id);
    if (current.environment !== "GEN_2" || current.state !== "ACTIVE" || current.buildConfig.runtime !== priorFunction.runtime || current.buildConfig.entryPoint !== priorFunction.entryPoint) throw Error("Representative runtime or entrypoint is incompatible with its predecessor");
    const candidateSource = sourceIdentity(sourceOf(current)); const candidateHash = digest(stableConfig(current));
    const retained = await objectBytes(client, archive.backup);
    if (retained.sha256 !== archive.backup.sha256) throw Error("Private rollback archive content changed");
    // Own a write-once private copy before the prior source can overwrite a
    // mutable function-source.zip object in Google's deployment bucket.
    const forwardArchive = await retain(client, candidateSource, candidate.candidateRunId, id);
    const item = receipt.representatives[id] = {name, type, runtime: current.buildConfig.runtime, entryPoint: current.buildConfig.entryPoint,
      candidateConfigurationSha256: candidateHash, priorSource: retained, candidateSource: forwardArchive}; save();
    let attempted = false; let failure;
    try {
      await checkEmpty(client); attempted = true;
      item.rollback = await patch(client, name, archive.backup, {onOperation: (proof) => { item.rollbackAttempt = proof; save(); }}); save();
      if (item.rollback.configurationSha256 !== candidateHash) throw Error("Rollback changed service, trigger, runtime or entrypoint configuration");
      item.emptyDuring = await checkEmpty(client); save();
    } catch (error) { failure = error; item.failure = String(error.message); if (error.operationReceipt) item.rollbackAttempt = error.operationReceipt; save(); }
    finally {
      if (attempted) {
        try {
          item.restoration = await patch(client, name, forwardArchive.backup, {onOperation: (proof) => { item.restorationAttempt = proof; save(); }}); save();
          if (item.restoration.configurationSha256 !== candidateHash) throw Error("Restoration changed non-source configuration");
          item.emptyAfter = await checkEmpty(client); save();
        } catch (error) { item.restorationFailure = String(error.message); if (error.operationReceipt) item.restorationAttempt = error.operationReceipt; save(); throw Error(`Candidate restoration failed for ${id}; stop and recover using the retained operation/source receipt`, {cause: error}); }
      }
    }
    if (failure) throw failure;
  }
  receipt.completedAt = new Date().toISOString(); save(); return receipt;
}
async function verifyRehearsal({candidate, receipt, manifest, client = null}) {
  if (candidate?.environment !== "staging" || candidate.projectId !== PROJECT) throw Error("Rehearsal verification is restricted to staging candidates");
  validateArchives(manifest, candidate.predecessor.staging);
  if (receipt?.schemaVersion !== 1 || receipt.scope !== SCOPE || receipt.projectId !== PROJECT || receipt.candidateRunId !== candidate.candidateRunId || receipt.sourceSha !== candidate.sourceSha || receipt.candidateSha256 !== digest(candidate) || receipt.predecessorSha256 !== digest(candidate.predecessor.staging) || receipt.archiveManifestSha256 !== digest(manifest) || !Number.isFinite(Date.parse(receipt.startedAt)) || !Number.isFinite(Date.parse(receipt.completedAt)) || Date.parse(receipt.completedAt) < Date.parse(receipt.startedAt) || digest(Object.keys(receipt.representatives || {}).sort()) !== digest(Object.keys(REPRESENTATIVES).sort())) throw Error("Backend rehearsal receipt differs from the frozen candidate");
  client ||= await googleClient(); const evidence = [];
  for (const [id, type] of Object.entries(REPRESENTATIVES)) {
    const item = receipt.representatives[id]; const name = `projects/${PROJECT}/locations/us-central1/functions/${id}`;
    if (item.name !== name || item.type !== type || item.failure || item.restorationFailure || !item.rollback || !item.restoration) throw Error("Incomplete representative rollback/restoration");
    const archive = manifest.entries.find((entry) => entry.functionName === name && entry.projectId === PROJECT);
    if (item.priorSource.sha256 !== archive.backup.sha256 || digest(sourceIdentity(item.priorSource)) !== digest(sourceIdentity(archive.backup)) || !/^[a-f0-9]{64}$/.test(item.candidateSource.original.sha256 || "") || item.candidateSource.original.sha256 !== item.candidateSource.backup.sha256 || item.candidateSource.backup.bucket !== "attendus-recovery-20261004-backups" || item.candidateSource.backup.object !== `backend-source/${PROJECT}/candidates/${candidate.candidateRunId}/${id}/source.zip`) throw Error("Rehearsal archive identities differ");
    for (const phase of ["rollback", "restoration"]) {
      const recorded = item[phase]; const expected = phase === "rollback" ? item.priorSource : item.candidateSource.backup;
      if (!OPERATION.test(recorded.operation || "")) throw Error("Unexpected rehearsal operation resource");
      const operation = (await client.request({url: `https://cloudfunctions.googleapis.com/v2/${recorded.operation}`})).data;
      if (operation.done !== true || operation.error || operation.response?.name !== name || operation.metadata?.target && operation.metadata.target !== name ||
          digest(sourceIdentity(recorded.requestedSource)) !== digest(sourceIdentity(expected)) ||
          digest(sourceIdentity(sourceOf(operation.response))) !== digest(sourceIdentity(recorded.source)) ||
          digest(stableConfig(operation.response)) !== item.candidateConfigurationSha256 || recorded.configurationSha256 !== item.candidateConfigurationSha256) throw Error("Actual completed operation does not prove the recorded source-only transition");
      const requested = await objectBytes(client, expected);
      if (requested.sha256 !== expected.sha256 || digest(requested) !== digest(recorded.requestedSource)) throw Error("Recorded submitted archive bytes differ");
      const resolved = await resolvedArchive(client, name, operation.response, requested);
      if (digest(resolved) !== digest(recorded.source)) throw Error("Recorded resolved archive bytes differ");
      const start = Date.parse(operation.metadata?.createTime), end = Date.parse(operation.metadata?.endTime);
      if (!Number.isFinite(start) || !Number.isFinite(end) || end < start || start < Date.parse(receipt.startedAt) - 60000 || end > Date.parse(receipt.completedAt) + 60000 || phase === "restoration" && start < Date.parse(item.rollback.completedAt)) throw Error("Rehearsal operation time/phase order differs");
      if (operation.metadata.createTime !== recorded.startedAt || operation.metadata.endTime !== recorded.completedAt) throw Error("Recorded operation timing was modified");
      evidence.push({function: id, type, phase, operation: recorded.operation, requestedSource: requested, source: resolved, startedAt: operation.metadata.createTime, completedAt: operation.metadata.endTime});
    }
    const fresh = await readFunction(client, name);
    if (fresh.state !== "ACTIVE" || digest(stableConfig(fresh)) !== item.candidateConfigurationSha256 || digest(sourceIdentity(sourceOf(fresh))) !== digest(sourceIdentity(item.restoration.source))) throw Error("Representative no longer has the restored candidate source/configuration");
    const restored = await objectBytes(client, item.candidateSource.backup);
    if (restored.sha256 !== item.candidateSource.original.sha256) throw Error("Retained candidate restoration bytes differ");
    for (const check of [receipt.emptyBefore, item.emptyDuring, item.emptyAfter]) if (!check || !Number.isFinite(Date.parse(check.checkedAt)) || EMPTY_COLLECTIONS.some((collection) => check.collections?.[collection] !== 0) || !Number.isInteger(check.anonymousAuthCount) || check.anonymousAuthCount < 0 || check.anonymousAuthCount > 1) throw Error("Pre-fixture empty-project evidence is incomplete");
  }
  return {schemaVersion: 1, sourceSha: candidate.sourceSha, candidateRunId: candidate.candidateRunId, receiptSha256: digest(receipt),
    scope: receipt.scope, verifiedAt: new Date().toISOString(), operations: evidence};
}
module.exports = {PROJECT, SCOPE, REPRESENTATIVES, EMPTY_COLLECTIONS, sourceIdentity, stableConfig, validateArchives, assertEmpty, objectBytes, readFunction, retainCandidateSource, patchSource, rehearse, verifyRehearsal};
