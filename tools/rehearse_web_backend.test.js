"use strict";
const test = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");
const os = require("node:os");
const path = require("node:path");
const {digest, sha256} = require("./web_release_contract");
const r = require("./rehearse_web_backend");
const clone = (value) => JSON.parse(JSON.stringify(value));
function fixture(t) {
  const outputRoot = fs.mkdtempSync(path.join(os.tmpdir(), "attendus-rehearsal-"));
  t.after(() => fs.rmSync(outputRoot, {recursive: true, force: true}));
  const oldRun = process.env.GITHUB_RUN_ID, oldSha = process.env.GITHUB_SHA;
  process.env.GITHUB_RUN_ID = "123"; process.env.GITHUB_SHA = "a".repeat(40);
  t.after(() => {
    if (oldRun === undefined) delete process.env.GITHUB_RUN_ID; else process.env.GITHUB_RUN_ID = oldRun;
    if (oldSha === undefined) delete process.env.GITHUB_SHA; else process.env.GITHUB_SHA = oldSha;
  });
  const objects = new Map(), functions = new Map(), operations = new Map(), calls = [];
  const objectKey = (source) => `${source.bucket}/${source.object}/${source.generation}`;
  const manifest = {schemaVersion: 1, entries: []};
  const predecessor = {projectId: r.PROJECT, functions: [], functionSources: []};
  for (const [id, type] of Object.entries(r.REPRESENTATIVES)) {
    const name = `projects/${r.PROJECT}/locations/us-central1/functions/${id}`;
    const prior = Buffer.from(`old-${id}`), current = Buffer.from(`candidate-${id}`);
    const original = {bucket: "old-sources", object: `${id}.zip`, generation: "1", sha256: sha256(prior)};
    const backup = {bucket: "attendus-recovery-20261004-backups", object: `backend-source/${r.PROJECT}/${id}/old.zip`, generation: "2", sha256: sha256(prior)};
    const source = {bucket: "current-sources", object: `${id}.zip`, generation: "3"};
    objects.set(objectKey(backup), prior); objects.set(objectKey(source), current);
    manifest.entries.push({projectId: r.PROJECT, functionName: name, original, backup});
    predecessor.functionSources.push({name, environment: "GEN_2", source: r.sourceIdentity(original)});
    predecessor.functions.push({id, region: "us-central1", runtime: "nodejs22", entryPoint: id,
      ...(type === "http" ? {httpsTrigger: {}} : {}), ...(type === "callable" ? {callableTrigger: {}} : {}),
      ...(type === "scheduled" ? {scheduleTrigger: {}} : {}),
      ...(type === "firestore-updated" ? {eventTrigger: {eventType: "google.cloud.firestore.document.v1.updated"}} : {})});
    functions.set(name, {name, environment: "GEN_2", state: "ACTIVE", buildConfig: {runtime: "nodejs22", entryPoint: id,
      source: {storageSource: source}, sourceProvenance: {resolvedStorageSource: source}},
      serviceConfig: {revision: "initial", timeoutSeconds: 60, environmentVariables: {PRIVATE: "never-in-receipt"}},
      ...(type === "firestore-updated" ? {eventTrigger: {eventType: "google.cloud.firestore.document.v1.updated", eventFilters: [{attribute: "document", value: "event_analytics/{docId}"}]}} : {})});
  }
  const candidate = {environment: "staging", projectId: r.PROJECT, candidateRunId: "123", sourceSha: "a".repeat(40), predecessor: {staging: predecessor}};
  const state = {patches: 0, failPatch: null, driftPatch: null, nonempty: false};
  const client = {request: async (request) => {
    calls.push(clone(request)); const url = new URL(request.url);
    if (url.hostname === "firestore.googleapis.com") return {data: {documents: state.nonempty ? [{name: "live-record"}] : []}};
    if (url.hostname === "identitytoolkit.googleapis.com") return {data: {users: [{localId: "anonymous"}]}};
    if (url.hostname === "storage.googleapis.com") {
      const copy = url.pathname.match(/^\/storage\/v1\/b\/([^/]+)\/o\/([^/]+)\/copyTo\/b\/([^/]+)\/o\/([^/]+)$/);
      if (copy) {
        assert.equal(request.params.ifGenerationMatch, 0);
        const prior = {bucket: decodeURIComponent(copy[1]), object: decodeURIComponent(copy[2]), generation: request.params.sourceGeneration};
        const target = {bucket: decodeURIComponent(copy[3]), object: decodeURIComponent(copy[4]), generation: "4"};
        if (objects.has(objectKey(target))) throw Error("write-once copy exists");
        objects.set(objectKey(target), objects.get(objectKey(prior))); return {data: {generation: "4"}};
      }
      const match = url.pathname.match(/^\/storage\/v1\/b\/([^/]+)\/o\/([^/]+)$/);
      assert.ok(match); const source = {bucket: decodeURIComponent(match[1]), object: decodeURIComponent(match[2]), generation: request.params.generation};
      const bytes = objects.get(objectKey(source)); if (!bytes) throw Error("Object missing");
      return {data: request.params.alt === "media" ? bytes : {generation: source.generation, size: String(bytes.length)}};
    }
    const resource = url.pathname.slice("/v2/".length);
    if (resource.includes("/operations/")) return {data: clone(operations.get(resource))};
    assert.ok(functions.has(resource), `Unexpected request ${request.url}`);
    if (request.method !== "PATCH") return {data: clone(functions.get(resource))};
    state.patches++;
    assert.equal(request.params.updateMask, "buildConfig.source");
    assert.deepEqual(Object.keys(request.data).sort(), ["buildConfig", "name"]);
    assert.deepEqual(Object.keys(request.data.buildConfig), ["source"]);
    const fn = clone(functions.get(resource)); const source = clone(request.data.buildConfig.source.storageSource);
    fn.buildConfig.source = {storageSource: source}; fn.buildConfig.sourceProvenance = {resolvedStorageSource: source};
    fn.serviceConfig.revision = `revision-${state.patches}`;
    if (state.driftPatch === state.patches) fn.serviceConfig.timeoutSeconds = 99;
    functions.set(resource, fn);
    const name = `projects/${r.PROJECT}/locations/us-central1/operations/operation-${state.patches}`;
    const now = new Date().toISOString(); const operation = {name, done: true, metadata: {target: resource, createTime: now, endTime: now}, response: fn};
    if (state.failPatch === state.patches) operation.error = {code: 13, message: "Injected deployment failure after write"};
    operations.set(name, clone(operation)); return {data: operation};
  }};
  return {candidate, predecessor, manifest, output: path.join(outputRoot, "rehearsal.json"), client, calls, state, functions, operations};
}
test("all four actual source-only transitions are restored and independently verified", async (t) => {
  const f = fixture(t); const receipt = await r.rehearse(f);
  const verified = await r.verifyRehearsal({...f, receipt});
  assert.equal(f.state.patches, 8); assert.equal(verified.operations.length, 8); assert.equal(verified.receiptSha256, digest(receipt));
  assert.equal(JSON.stringify(receipt).includes("never-in-receipt"), false);
  assert.equal(f.calls.filter((call) => call.method === "POST").length, 4);
  assert.equal(f.calls.filter((call) => call.method === "DELETE").length, 0);
  for (const fn of f.functions.values()) assert.match(fn.buildConfig.source.storageSource.object, /^backend-source\/attendus-staging\/candidates\/123\//);
});
test("a failed rollback still restores the retained candidate and leaves failed evidence", async (t) => {
  const f = fixture(t); f.state.failPatch = 1;
  await assert.rejects(() => r.rehearse(f), /did not succeed/);
  const receipt = JSON.parse(fs.readFileSync(f.output));
  assert.equal(f.state.patches, 2); assert.ok(receipt.representatives.publicWeb.failure); assert.ok(receipt.representatives.publicWeb.restoration);
  assert.equal(receipt.completedAt, undefined);
  await assert.rejects(() => r.verifyRehearsal({...f, receipt}), /differs/);
});
test("restoration failure stops the fleet and retains recovery operation/source evidence", async (t) => {
  const f = fixture(t); f.state.failPatch = 2;
  await assert.rejects(() => r.rehearse(f), /Candidate restoration failed/);
  const receipt = JSON.parse(fs.readFileSync(f.output));
  assert.equal(f.state.patches, 2); assert.ok(receipt.representatives.publicWeb.restorationFailure);
  assert.ok(receipt.representatives.publicWeb.candidateSource.backup.generation);
  assert.equal(Object.keys(receipt.representatives).length, 1);
});
test("non-source configuration drift cannot be hidden by a successful source restoration", async (t) => {
  const f = fixture(t); f.state.driftPatch = 1;
  await assert.rejects(() => r.rehearse(f), /Candidate restoration failed/);
  const item = JSON.parse(fs.readFileSync(f.output)).representatives.publicWeb;
  assert.match(item.failure, /changed service/); assert.match(item.restorationFailure, /non-source/);
});
test("production, incomplete predecessors and live staging records fail before writes", async (t) => {
  const f = fixture(t);
  await assert.rejects(() => r.rehearse({...f, candidate: {...f.candidate, projectId: "orgami-66nxok", environment: "production"}}), /restricted/);
  await assert.rejects(() => r.verifyRehearsal({...f, candidate: {...f.candidate, environment: "production"}, receipt: {}}), /restricted/);
  assert.throws(() => r.validateArchives({...f.manifest, entries: f.manifest.entries.slice(1)}, f.predecessor), /Every staged/);
  f.state.nonempty = true; await assert.rejects(() => r.rehearse(f), /requires empty/);
  assert.equal(f.calls.filter((call) => ["PATCH", "POST", "DELETE"].includes(call.method)).length, 0);
});
test("operation proof is reread and mismatched live API source evidence is rejected", async (t) => {
  const f = fixture(t); const receipt = await r.rehearse(f);
  const operation = f.operations.get(receipt.representatives.publicWeb.rollback.operation);
  operation.response.buildConfig.sourceProvenance.resolvedStorageSource.generation = "999";
  await assert.rejects(() => r.verifyRehearsal({...f, receipt}), /Actual completed operation/);
});
test("receipt scope, archive paths, timing and empty-project counts cannot be forged", async (t) => {
  const f = fixture(t); const receipt = await r.rehearse(f);
  for (const mutate of [
    (value) => { value.scope = "All functions verified"; },
    (value) => { value.startedAt = "invalid"; },
    (value) => { value.representatives.publicWeb.candidateSource.backup.object = "backend-source/production/other.zip"; },
    (value) => { value.emptyBefore.anonymousAuthCount = -1; },
    (value) => { value.representatives.publicWeb.rollback.operation += "/../../functions/other"; },
  ]) {
    const changed = clone(receipt); mutate(changed);
    await assert.rejects(() => r.verifyRehearsal({...f, receipt: changed}));
  }
});
