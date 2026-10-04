"use strict";
const test = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs"), path = require("node:path"), os = require("node:os");
const r = require("./retired_web_qualification");
const {digest, sha256} = require("./web_release_contract");
const {assertEmpty, EMPTY_COLLECTIONS} = require("./rehearse_web_backend");
const clone = (value) => JSON.parse(JSON.stringify(value));
function fixture() {
  const runId = "webqa-20261004-0123456789", sourceSha = "a".repeat(40), candidateRunId = "123";
  const stringValue = (value) => ({stringValue: value});
  const common = {schemaVersion: {integerValue: "1"}, projectId: stringValue("attendus-staging")};
  const doc = (local, fields) => ({name: "projects/attendus-staging/databases/(default)/documents/" + local,
    fields: {...common, ...fields}, createTime: "2026-10-04T10:00:00.000000001Z", updateTime: "2026-10-04T11:00:00.000000001Z"});
  const docs = [doc(`QualificationScopes/${runId}`, {status: stringValue("retired"), mode: stringValue("capture"), actorUids: {arrayValue: {}}, recipientUids: {arrayValue: {values: []}}}),
    doc("QualificationBindings/account_" + "b".repeat(64), {state: stringValue("retired"), runId: stringValue(runId)}),
    doc(`QualificationSetup/${runId}`, {state: stringValue("retired"), sourceSha: stringValue(sourceSha), candidateRunId: stringValue(candidateRunId)})];
  const run = {runId, sourceSha, candidateRunId, cleanupEvidenceSha256: "c".repeat(64), documents: []};
  const manifest = {schemaVersion: 1, projectId: "attendus-staging", runs: [run]};
  const repin = () => {run.documents = docs.map((d) => ({path: d.name.split("/documents/")[1], sha256: digest(d)}));}; repin();
  const calls = [], client = {request: async (request) => {calls.push(request); assert.equal(request.method, undefined);
    const collection = new URL(request.url).pathname.split("/").at(-1);
    if (collection === "accounts:batchGet") return {data: {users: [{localId: "retained-unrelated-anonymous"}]}};
    return {data: {documents: docs.filter((d) => d.name.includes(`/documents/${collection}/`))}};
  }};
  return {docs, manifest, run, repin, calls, client};
}
test("exact reviewed retired records survive an otherwise empty-site check", async () => {
  const f = fixture(), proof = await assertEmpty(f.client, {retiredManifest: f.manifest});
  assert.equal(proof.anonymousAuthCount, 1);
  assert.deepEqual(proof.collections, Object.fromEntries(EMPTY_COLLECTIONS.map((name) => [name, 0])));
  assert.deepEqual(proof.retiredIsolation.counts, {QualificationScopes: 1, QualificationBindings: 1, QualificationSetup: 1});
  assert.equal(r.validateProof(proof.retiredIsolation, f.manifest), true);
  assert.equal(f.calls.some((call) => call.method), false);
});
test("an empty manifest continues rejecting all unreviewed isolation state", async () => {
  const f = fixture(); await assert.rejects(() => r.observeRetired(f.client, r.emptyManifest()), /Unreviewed/);
});
test("active bindings and incomplete scope retirement are rejected even if repinned", async () => {
  for (const mutate of [(f) => {f.docs[1].fields.state.stringValue = "bound";},
    (f) => {f.docs[0].fields.status.stringValue = "active";},
    (f) => {f.docs[0].fields.actorUids.arrayValue.values = [{stringValue: "actor"}];},
    (f) => {f.docs[0].fields.recipientUids = {arrayValue: null};}]) {
    const f = fixture(); mutate(f); f.repin(); await assert.rejects(() => r.observeRetired(f.client, f.manifest), /Active|Retired scope/);
  }
});
test("nanosecond version drift and missing tombstones stop the rehearsal", async () => {
  const f = fixture(); f.docs[1].updateTime = "2026-10-04T11:00:00.000000002Z";
  await assert.rejects(() => r.observeRetired(f.client, f.manifest), /content\/version/);
  const g = fixture(); g.docs.splice(1, 1); await assert.rejects(() => r.observeRetired(g.client, g.manifest), /missing/);
});
test("unexpected setup records, missing-parent records and duplicate responses are rejected", async () => {
  for (const mutate of [(f) => {f.docs.push({...clone(f.docs[2]), name: f.docs[2].name + "foreign"});},
    (f) => {delete f.docs[1].fields; delete f.docs[1].createTime; delete f.docs[1].updateTime;},
    (f) => {f.docs.push(clone(f.docs[1]));}]) {
    const f = fixture(); mutate(f); await assert.rejects(() => r.observeRetired(f.client, f.manifest), /Unreviewed|content\/version/);
  }
});
test("incomplete pagination cannot masquerade as an empty isolation store", async () => {
  const client = {request: async () => ({data: {documents: [], nextPageToken: "same-page"}})};
  await assert.rejects(() => r.observeRetired(client, r.emptyManifest()), /pagination/);
});
test("malformed and falsey API bodies/tokens do not masquerade as empty", async () => {
  for (const data of [false, 0, [], null, undefined, {nextPageToken: 0}, {nextPageToken: false}, {nextPageToken: null}, {documents: null}]) {
    await assert.rejects(() => r.observeRetired({request: async () => ({data})}, r.emptyManifest()), /Malformed/);
  }
});
test("manifest rejects cross-project, duplicate and incomplete lineage", () => {
  for (const mutate of [(m) => {m.projectId = "orgami-66nxok";}, (m) => {m.runs.push(clone(m.runs[0]));},
    (m) => {m.runs[0].documents.pop();}, (m) => {m.runs[0].documents[0].path = "QualificationScopes/foreign";},
    (m) => {m.runs[0].documents[1].path = "QualificationBindings/../escape";}]) {
    const f = fixture(); mutate(f.manifest); assert.throws(() => r.validateManifest(f.manifest), /Invalid|Incomplete/);
  }
});
test("a repinned foreign setup source remains invalid", async () => {
  const f = fixture(); f.docs[2].fields.sourceSha.stringValue = "d".repeat(40); f.repin();
  await assert.rejects(() => r.observeRetired(f.client, f.manifest), /setup lineage/);
});
test("retained evidence cannot omit or alter pinned records/counts", async () => {
  const f = fixture(), proof = await r.observeRetired(f.client, f.manifest);
  assert.throws(() => r.validateProof(undefined, f.manifest), /proof differs/);
  proof.counts.QualificationBindings = 0;
  assert.throws(() => r.validateProof(proof, f.manifest), /proof differs/);
  assert.throws(() => r.validateProof(undefined, r.emptyManifest()), /proof differs/);
  assert.equal(r.validateProof(undefined, r.emptyManifest(), {allowLegacyEmpty: true}), true);
});
test("actual active events and identified accounts remain forbidden", async () => {
  for (const kind of ["event", "auth"]) {
    const f = fixture(), original = f.client.request;
    f.client.request = async (request) => {
      if (kind === "event" && request.url.endsWith("/Events")) return {data: {documents: [{name: "active"}]}};
      if (kind === "auth" && request.url.endsWith("accounts:batchGet")) return {data: {users: [{localId: "unexpected", email: "person@example.test"}]}};
      return original(request);
    };
    await assert.rejects(() => assertEmpty(f.client, {retiredManifest: f.manifest}), /requires empty|no identified/);
  }
});
test("manifest loading pins frozen bytes and preserves historical empty-only candidates", (t) => {
  const temporaryBase = fs.realpathSync(os.tmpdir()), root = fs.mkdtempSync(path.join(temporaryBase, "attendus-retired-proof-")), owned = fs.realpathSync(root);
  t.after(() => {if (fs.realpathSync(os.tmpdir()) !== temporaryBase || fs.lstatSync(root).isSymbolicLink() || fs.realpathSync(root) !== owned || !owned.startsWith(temporaryBase + path.sep)) throw Error("Unsafe test cleanup"); fs.rmSync(owned, {recursive: true});});
  fs.mkdirSync(path.join(root, "config")); const bytes = JSON.stringify(fixture().manifest, null, 2) + "\n"; fs.writeFileSync(path.join(root, r.FILE), bytes);
  assert.deepEqual(r.loadManifest({}, root), r.emptyManifest());
  assert.equal(r.loadManifest({sourceFiles: {[r.FILE]: sha256(bytes)}}, root).runs.length, 1);
  fs.writeFileSync(path.join(root, r.FILE), bytes.replace(/\n/g, "\r\n"));
  assert.equal(r.loadManifest({sourceFiles: {[r.FILE]: sha256(bytes)}}, root).runs.length, 1);
  fs.writeFileSync(path.join(root, r.FILE), bytes + " ");
  assert.throws(() => r.loadManifest({sourceFiles: {[r.FILE]: sha256(bytes)}}, root), /frozen source/);
  assert.throws(() => r.loadManifest({sourceFiles: {[r.FILE]: "a".repeat(64)}}, root), /frozen source/);
});
