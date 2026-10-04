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
  const temporaryBase = fs.realpathSync(os.tmpdir());
  const outputRoot = fs.mkdtempSync(path.join(temporaryBase, "attendus-rehearsal-"));
  const owned = fs.realpathSync(outputRoot);
  t.after(() => {
    if (fs.realpathSync(os.tmpdir()) !== temporaryBase || fs.lstatSync(outputRoot).isSymbolicLink() || fs.realpathSync(outputRoot) !== owned || !owned.startsWith(`${temporaryBase}${path.sep}`)) throw Error("Unsafe owned test cleanup");
    fs.rmSync(owned, {recursive: true});
  });
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
  const state = {patches: 0, failPatch: null, driftPatch: null, nonempty: false, copyResolved: false, corruptPatch: null, foreignCopy: false};
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
    const fn = clone(functions.get(resource)); let source = clone(request.data.buildConfig.source.storageSource);
    if (state.copyResolved) {
      const resolved = {bucket: state.foreignCopy ? "unrelated-project-sources" : "gcf-v2-sources-925344893088-us-central1",
        object: `${resource.split("/").at(-1)}/function-source.zip`, generation: String(100 + state.patches)};
      objects.set(objectKey(resolved), state.corruptPatch === state.patches ? Buffer.from("wrong deployed bytes") : objects.get(objectKey(source)));
      source = resolved;
    }
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
test("new candidates cannot substitute historical empty counters for retained-isolation proofs", async (t) => {
  const f = fixture(t), retired = require("./retired_web_qualification");
  const receipt = await r.rehearse(f);
  f.candidate.sourceFiles = {[retired.FILE]: sha256(fs.readFileSync(path.join(__dirname, "..", retired.FILE)))};
  receipt.candidateSha256 = digest(f.candidate);
  for (const check of [receipt.emptyBefore, ...Object.values(receipt.representatives).flatMap((item) => [item.emptyDuring, item.emptyAfter])]) {
    delete check.retiredIsolation; check.collections.QualificationScopes = 0; check.collections.QualificationBindings = 0;
  }
  await assert.rejects(() => r.verifyRehearsal({...f, receipt}), /proof differs/);
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
test("actual GCF archive copying preserves byte/configuration proof across all eight transitions", async (t) => {
  const f = fixture(t); f.state.copyResolved = true;
  const receipt = await r.rehearse(f), verified = await r.verifyRehearsal({...f, receipt});
  assert.equal(verified.operations.length, 8);
  for (const item of Object.values(receipt.representatives)) for (const phase of ["rollback", "restoration"]) {
    assert.equal(item[phase].requestedSource.bucket, "attendus-recovery-20261004-backups");
    assert.equal(item[phase].source.bucket, "gcf-v2-sources-925344893088-us-central1");
    assert.equal(item[phase].source.sha256, item[phase].requestedSource.sha256);
    assert.equal(item[phase].source.size, item[phase].requestedSource.size);
  }
});
test("copied source with different bytes fails and retains operation evidence while restoring candidate", async (t) => {
  const f = fixture(t); f.state.copyResolved = true; f.state.corruptPatch = 1;
  await assert.rejects(() => r.rehearse(f), /archive bytes differ/);
  const item = JSON.parse(fs.readFileSync(f.output)).representatives.publicWeb;
  assert.equal(f.state.patches, 2); assert.ok(item.restoration);
  assert.match(item.rollbackAttempt.operation, /operation-1$/);
  assert.ok(item.rollbackAttempt.completedAt);
  assert.equal(item.restoration.source.sha256, item.candidateSource.backup.sha256);
});
test("matching bytes cannot authorize an unrelated resolved source bucket", async (t) => {
  const f = fixture(t); f.state.copyResolved = true; f.state.foreignCopy = true;
  await assert.rejects(() => r.rehearse(f), /Candidate restoration failed/);
  const item = JSON.parse(fs.readFileSync(f.output)).representatives.publicWeb;
  assert.match(item.failure, /resolved source boundary/);
  assert.match(item.restorationFailure, /resolved source boundary/);
});
test("API event filter ordering is canonical while values, operators and duplicates remain guarded", () => {
  const fn = {name: "trigger", eventTrigger: {eventType: "written", eventFilters: [
    {attribute: "namespace", value: "(default)"},
    {attribute: "document", value: "Events/{id}", operator: "match-path-pattern"},
    {attribute: "database", value: "(default)"},
  ]}, serviceConfig: {timeoutSeconds: 60}};
  const original = clone(fn), reordered = clone(fn); reordered.eventTrigger.eventFilters.reverse();
  assert.equal(digest(r.stableConfig(fn)), digest(r.stableConfig(reordered)));
  assert.deepEqual(fn, original);
  for (const change of [
    (value) => {value.eventTrigger.eventFilters[1].value = "Other/{id}";},
    (value) => {delete value.eventTrigger.eventFilters[1].operator;},
    (value) => {value.serviceConfig.timeoutSeconds = 99;},
  ]) {const changed = clone(fn); change(changed); assert.notEqual(digest(r.stableConfig(fn)), digest(r.stableConfig(changed)));}
  const duplicate = clone(fn); duplicate.eventTrigger.eventFilters.push(clone(duplicate.eventTrigger.eventFilters[0]));
  assert.throws(() => r.stableConfig(duplicate), /Ambiguous event filter/);
});
test("operation filter reordering does not hide source or configuration proof", async (t) => {
  const f = fixture(t); f.state.copyResolved = true;
  const name = `projects/${r.PROJECT}/locations/us-central1/functions/triggerAIInsights`;
  f.functions.get(name).eventTrigger.eventFilters.push({attribute: "database", value: "(default)"});
  const receipt = await r.rehearse(f);
  for (const phase of ["rollback", "restoration"]) f.operations.get(receipt.representatives.triggerAIInsights[phase].operation).response.eventTrigger.eventFilters.reverse();
  assert.equal((await r.verifyRehearsal({...f, receipt})).operations.length, 8);
  const forged = clone(receipt); forged.representatives.publicWeb.restoration.requestedSource.sha256 = "0".repeat(64);
  await assert.rejects(() => r.verifyRehearsal({...f, receipt: forged}), /submitted archive bytes differ/);
});
for (const failedPhase of ["rollback", "restoration"]) test(`acknowledged ${failedPhase} operation is saved before a polling failure`, async (t) => {
  const f = fixture(t), request = f.client.request, failedPatch = failedPhase === "rollback" ? 1 : 2;
  let persistedBeforeFailedRead = false;
  f.client.request = async (input) => {
    if (input.url.endsWith(`/operations/operation-${failedPatch}`)) {
      const attempt = JSON.parse(fs.readFileSync(f.output)).representatives.publicWeb[`${failedPhase}Attempt`];
      assert.equal(attempt.operation, `projects/${r.PROJECT}/locations/us-central1/operations/operation-${failedPatch}`);
      assert.equal(attempt.completedAt, null);
      assert.match(attempt.requestedSource.sha256, /^[a-f0-9]{64}$/);
      persistedBeforeFailedRead = true;
      throw Error("Injected operation read failure after PATCH acknowledgement");
    }
    const result = await request(input);
    if (input.method === "PATCH" && f.state.patches === failedPatch) return {data: {name: result.data.name, done: false,
      metadata: {target: result.data.metadata.target, createTime: result.data.metadata.createTime}}};
    return result;
  };
  await assert.rejects(() => r.rehearse({...f, patch: (client, name, source, options) => r.patchSource(client, name, source, {...options, sleep: async () => {}})}),
    failedPhase === "rollback" ? /Injected operation read failure/ : /Candidate restoration failed/);
  const receipt = JSON.parse(fs.readFileSync(f.output)), item = receipt.representatives.publicWeb;
  assert.equal(persistedBeforeFailedRead, true);
  assert.equal(f.state.patches, 2);
  assert.equal(Object.keys(receipt.representatives).length, 1);
  assert.equal(receipt.completedAt, undefined);
  assert.match(item[`${failedPhase}Attempt`].operation, new RegExp(`operation-${failedPatch}$`));
  if (failedPhase === "rollback") assert.ok(item.restoration);
  else assert.match(item.restorationFailure, /Injected operation read failure/);
});
