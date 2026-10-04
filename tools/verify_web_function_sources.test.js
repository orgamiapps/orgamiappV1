"use strict";
const test = require("node:test"), assert = require("node:assert/strict"), {execFileSync} = require("node:child_process");
const c = require("./web_release_contract");
const {archiveManifest, verifyFunctionSources} = require("./verify_web_function_sources");
function zip(entries) {
  return execFileSync(process.platform === "win32" ? "python" : "python3", ["-c",
    "import io,zipfile,json,sys; b=io.BytesIO(); z=zipfile.ZipFile(b,'w',zipfile.ZIP_DEFLATED); [z.writestr(n,s) for n,s in json.loads(sys.argv[1])]; z.close(); sys.stdout.buffer.write(b.getvalue())", JSON.stringify(entries)], {stdio: ["ignore", "pipe", "pipe"]});
}
const files = [["index.js", "exports.alpha = 1;"], ["package-lock.json", "{}"]];
function fixture() {
  const candidate = {environment: "staging", projectId: "attendus-staging", sourceSha: "a".repeat(40), candidateRunId: "123",
    sourceFiles: Object.fromEntries(files.map(([name, content]) => [`functions/${name}`, c.sha256(content)])), deployment: {functions: ["alpha", "beta"]}};
  const state = {projectId: candidate.projectId, functionSources: candidate.deployment.functions.map((id) => ({name: `projects/attendus-staging/locations/us-central1/functions/${id}`,
    environment: "GEN_2", source: {bucket: "gcf-v2-sources-925344893088-us-central1", object: `${id}/function-source.zip`, generation: "7"}}))};
  const bytes = zip(files), archives = {alpha: bytes, beta: bytes}, reads = [];
  let live = state.functionSources.map((fn) => ({name: fn.name, environment: fn.environment, state: "ACTIVE", buildConfig: {source: {storageSource: {...fn.source}}}}));
  const client = {async request(request) {
    assert.equal(request.method, undefined); reads.push(request);
    if (request.url.startsWith("https://cloudfunctions.googleapis.com/")) return {data: {functions: live}};
    assert.ok(request.url.startsWith("https://storage.googleapis.com/storage/v1/b/gcf-v2-sources-925344893088-us-central1/o/"));
    assert.equal(request.params.generation, "7");
    const object = decodeURIComponent(request.url.split("/o/")[1]), id = object.split("/")[0];
    if (request.params.alt === "media") return {data: archives[id]};
    return {data: {bucket: "gcf-v2-sources-925344893088-us-central1", name: object, generation: "7", size: String(archives[id].length)}};
  }};
  return {candidate, state, client, reads, archives, setLive(value) {live = value;}, getLive() {return live;}};
}
test("source ZIP verifier hashes actual contents and rejects duplicate/traversal/malformed archives", () => {
  assert.deepEqual(archiveManifest(zip(files)), Object.fromEntries(files.map(([name, value]) => [name, c.sha256(value)])));
  for (const entries of [[["../index.js", "x"]], [["index.js", "x"], ["index.js", "x"]], [["INDEX.js", "x"], ["index.js", "x"]], [["C:/x", "x"]]]) {
    assert.throws(() => archiveManifest(zip(entries)), /invalid or unsafe/);
  }
  // Python's Windows writer normalizes backslashes; mutate the equal-length
  // local/central filename bytes to exercise an actual unsafe archive name.
  const backslash = Buffer.from(zip([["a/b", "x"]]).toString("latin1").replaceAll("a/b", "a\\b"), "latin1");
  assert.throws(() => archiveManifest(backslash), /invalid or unsafe/);
  assert.throws(() => archiveManifest(Buffer.from("not a zip")), /invalid or unsafe/);
});
test("all pinned deployed sources must contain the complete exact frozen backend", async () => {
  const f = fixture(); let inspected = 0;
  const proof = await verifyFunctionSources({...f, inspectArchive(bytes) {inspected++; return archiveManifest(bytes);}});
  assert.equal(proof.functions.length, 2); assert.equal(proof.uniqueArchives, 1); assert.equal(inspected, 1);
  assert.equal(proof.candidateSha256, c.digest(f.candidate));
  assert.ok(proof.functions.every((fn) => fn.sha256 === c.sha256(f.archives.alpha) && fn.fileCount === 2));
  assert.equal(f.reads.filter((request) => request.params?.alt === "media").length, 2);
});
test("an ACTIVE deployment with one old, missing, extra or changed source cannot pass", async () => {
  for (const entries of [[["index.js", "old"], files[1]], [files[0]], [...files, ["extra.env", "must not deploy"]]]) {
    const f = fixture(); f.archives.beta = zip(entries);
    await assert.rejects(verifyFunctionSources(f), /differs from frozen candidate: beta/);
  }
});
test("source identity drift and inactive state during reads invalidate verification", async () => {
  for (const change of [
    (f) => {f.getLive()[0].buildConfig.source.storageSource.generation = "8";},
    (f) => {f.getLive()[0].state = "DEPLOYING";},
    (f) => {f.setLive(f.getLive().slice(1));},
  ]) {
    const f = fixture(); change(f);
    await assert.rejects(verifyFunctionSources(f), /changed|Incomplete/);
  }
});
test("cross-project, duplicate and missing inventories fail before any cloud read", async () => {
  for (const change of [
    (f) => {f.state.projectId = "orgami-66nxok";},
    (f) => {f.state.functionSources[0].source.bucket = "gcf-v2-sources-951311475019-us-central1";},
    (f) => {f.state.functionSources.push(f.state.functionSources[0]);},
    (f) => {f.state.functionSources.pop();},
  ]) {
    const f = fixture(); change(f);
    await assert.rejects(verifyFunctionSources(f)); assert.equal(f.reads.length, 0);
  }
});
