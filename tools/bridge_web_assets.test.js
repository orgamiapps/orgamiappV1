"use strict";
const test = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");
const os = require("node:os");
const path = require("node:path");
const {gzipSync, gunzipSync} = require("node:zlib");
const c = require("./web_release_contract");
const b = require("./bridge_web_assets");
const clone = (value) => JSON.parse(JSON.stringify(value));
function fixture(t) {
  const directory = fs.mkdtempSync(path.join(os.tmpdir(), "attendus-asset-bridge-"));
  t.after(() => {assert.equal(path.dirname(directory), os.tmpdir()); fs.rmSync(directory, {recursive: true, force: true});});
  const projectId = "attendus-staging", prior = `sites/${projectId}/versions/prior`, version = `sites/${projectId}/versions/bridge`;
  const rawFiles = {"index.html": Buffer.from("<main>EXACT PREDECESSOR FLUTTER</main>"), "main.dart.js": Buffer.from("old Flutter bytes"), "public-web/v1/public.css": Buffer.from("old public css")};
  const assetNames = ["public.css", "registration-email-v2.css", "actions-email-v2.js"], manifest = {schemaVersion: 1, algorithm: "sha256-lf", assets: {}};
  const webFiles = {};
  for (const name of assetNames) {
    const bytes = Buffer.from(`new ${name}\n`), hash = c.sha256(bytes), key = `${b.PREFIX}${hash}/${name}`;
    manifest.assets[name] = hash; rawFiles[key] = bytes; webFiles[key] = hash;
    const target = path.join(directory, key); fs.mkdirSync(path.dirname(target), {recursive: true}); fs.writeFileSync(target, bytes);
  }
  const priorFiles = Object.fromEntries(Object.entries(rawFiles).filter(([name]) => !name.startsWith(b.PREFIX)).map(([name, bytes]) => [name, c.sha256(gzipSync(bytes, {level: 9}))]));
  const config = {rewrites: [{glob: "/event/**", function: "publicWeb"}, {glob: "**", path: "/index.html"}], headers: [{glob: "/**", headers: {"X-Content-Type-Options": "nosniff"}}]};
  const hosting = {config, files: priorFiles, configSha256: c.digest(config), filesSha256: c.digest(priorFiles)};
  const predecessor = {projectId, hostingVersion: prior, hostingRelease: `sites/${projectId}/releases/old`, hosting};
  const candidate = {environment: "staging", projectId, sourceSha: "a".repeat(40), candidateRunId: "42", webFiles, deployment: {publicAssets: manifest}};
  const versions = new Map([[prior, {name: prior, status: "FINALIZED", config: clone(config), files: {...priorFiles}}]]);
  const state = {live: {name: predecessor.hostingRelease, version: {name: prior}}, versions, calls: [], hooks: {}, uploads: [], polls: 0};
  const output = path.join(directory, "receipt.json");
  const client = {request: async (request) => {
    const {url, method = "GET", data, params = {}} = request;
    state.calls.push({url, method, data: Buffer.isBuffer(data) ? "gzip-bytes" : data});
    if (method !== "GET") {
      assert.equal(request.retry, false); assert.equal(fs.existsSync(output), true, "intent receipt must precede any mutation");
    }
    const intercepted = await state.hooks.request?.(request, state);
    if (intercepted) return intercepted;
    if (url.endsWith("/releases") && method === "GET") return {data: {releases: [clone(state.live)]}};
    if (url.endsWith(":clone")) {
      assert.deepEqual(data, {sourceVersion: prior, finalize: false});
      versions.set(version, {...clone(versions.get(prior)), name: version, status: "CREATED"});
      state.hooks.cloned?.(versions.get(version));
      return {data: {name: `projects/925344893088/operations/clone-1`, done: false}};
    }
    if (url.endsWith("/operations/clone-1")) {state.polls++; return {data: {name: "projects/925344893088/operations/clone-1", done: true, response: {name: version}}};}
    if (url.endsWith(":populateFiles")) {
      assert.deepEqual(Object.keys(data.files).sort(), Object.keys(webFiles).map((name) => `/${name}`).sort());
      for (const [name, hash] of Object.entries(data.files)) versions.get(version).files[name.slice(1)] = hash;
      state.hooks.populated?.(versions.get(version));
      return {data: {uploadUrl: `https://upload-firebasehosting.googleapis.com/upload/${version}/files`, uploadRequiredHashes: Object.values(data.files)}};
    }
    if (url.startsWith("https://upload-firebasehosting.googleapis.com/")) {
      const hash = url.split("/").at(-1); assert.equal(c.sha256(data), hash);
      assert.ok(Object.values(rawFiles).some((bytes) => bytes.equals(gunzipSync(data)))); state.uploads.push(hash); return {data: {}};
    }
    if (url.endsWith("/releases") && method === "POST") {
      assert.equal(params.versionName, version); state.live = {name: `sites/${projectId}/releases/new`, version: {name: version}};
      state.hooks.released?.(state); return {data: clone(state.live)};
    }
    const resource = url.replace("https://firebasehosting.googleapis.com/v1beta1/", "");
    if (resource.endsWith("/files")) return {data: {files: Object.entries(versions.get(resource.slice(0, -6)).files).map(([name, hash]) => ({path: `/${name}`, hash, status: "ACTIVE"}))}};
    const row = versions.get(resource);
    if (row && method === "PATCH") {assert.deepEqual(params, {updateMask: "status"}); assert.deepEqual(data, {status: "FINALIZED"}); row.status = data.status; return {data: clone(row)};}
    if (row) {const {files: _files, ...metadata} = row; return {data: clone(metadata)};}
    throw Error(`Unexpected API request ${method} ${url}`);
  }};
  const http = async (url) => {
    const name = new URL(url).pathname.slice(1);
    assert.equal(state.live.version.name, version);
    const bytes = state.hooks.http?.(name) || rawFiles[name];
    return {ok: true, status: 200, arrayBuffer: async () => bytes};
  };
  return {directory, output, predecessor, candidate, state, client, http, prior, version, rawFiles,
    run: () => b.publishBridge({candidate, predecessor, webRoot: directory, output, client, http, sleep: async () => {}})};
}
test("bridge preserves the exact old files/config and uploads only new immutable gzip bytes before release", async (t) => {
  const f = fixture(t); const receipt = await f.run();
  assert.equal(receipt.phase, "verified"); assert.equal(receipt.httpProof.length, 6); assert.equal(f.state.polls, 1); assert.equal(f.state.uploads.length, 3);
  assert.deepEqual(receipt.live.hosting.config, f.predecessor.hosting.config);
  for (const [name, hash] of Object.entries(f.predecessor.hosting.files)) assert.equal(receipt.live.hosting.files[name], hash);
  assert.deepEqual(f.candidate.webFiles, Object.fromEntries(Object.entries(receipt.assets).map(([name, entry]) => [name, entry.rawSha256])));
  assert.notEqual(Object.values(receipt.assets)[0].rawSha256, Object.values(receipt.assets)[0].uploadSha256);
  b.assertBridgeState(receipt.live, receipt);
  assert.throws(() => b.assertBridgeState({...receipt.live, hostingVersion: f.prior}, receipt), /changed/);
  assert.equal(f.state.calls.some((call) => call.method === "DELETE"), false);
});
test("seal rejects removal of prior hash paths, renderer omissions, bad raw bytes and cross-project predecessors", (t) => {
  const f = fixture(t); const name = Object.keys(f.candidate.webFiles)[0];
  const original = fs.readFileSync(path.join(f.directory, name));
  fs.writeFileSync(path.join(f.directory, name), "changed"); assert.throws(() => b.planBridge(f.candidate, f.directory, f.predecessor), /bytes changed/);
  fs.writeFileSync(path.join(f.directory, name), original);
  const oldPath = `${b.PREFIX}${"b".repeat(64)}/public.css`, prior = clone(f.predecessor);
  prior.hosting.files[oldPath] = "d".repeat(64); prior.hosting.filesSha256 = c.digest(prior.hosting.files);
  assert.throws(() => b.planBridge(f.candidate, f.directory, prior), /removes a predecessor/);
  const changed = clone(f.candidate); changed.deployment.publicAssets.assets["public.css"] = "0".repeat(64);
  assert.throws(() => b.planBridge(changed, f.directory, f.predecessor), /renderer refers/);
  assert.throws(() => b.planBridge(f.candidate, f.directory, {...f.predecessor, projectId: "orgami-66nxok"}), /project differs/);
});
test("cloned file/config mutations stop before asset population or publication", async (t) => {
  for (const kind of ["files", "config"]) await t.test(kind, async (t) => {
    const f = fixture(t); f.state.hooks.cloned = (version) => {if (kind === "files") version.files["main.dart.js"] = "0".repeat(64); else version.config.rewrites = [];};
    await assert.rejects(f.run(), /files or ServingConfig differ/);
    assert.equal(f.state.calls.some((row) => row.url.endsWith(":populateFiles")), false);
    assert.equal(f.state.live.version.name, f.prior);
    const receipt = JSON.parse(fs.readFileSync(f.output)); assert.equal(receipt.phase, "failed"); assert.equal(receipt.failedPhase, "cloned");
  });
});
test("population cannot change old files, add unrelated paths or edit ServingConfig", async (t) => {
  for (const alter of [row => {delete row.files["main.dart.js"];}, row => {row.files["injected.js"] = "0".repeat(64);}, row => {row.config.headers = [];}]) await t.test("fail closed", async (t) => {
    const f = fixture(t); f.state.hooks.populated = alter; await assert.rejects(f.run(), /population changed/);
    assert.equal(f.state.calls.some((call) => call.method === "PATCH"), false); assert.equal(f.state.live.version.name, f.prior);
  });
});
test("live predecessor drift and unexpected upload endpoints cannot publish", async (t) => {
  for (const kind of ["live-drift", "upload-host"]) await t.test(kind, async (t) => {
    const f = fixture(t);
    if (kind === "live-drift") f.state.live.name = "sites/attendus-staging/releases/other";
    else f.state.hooks.request = async (request) => request.url.endsWith(":populateFiles") ? {data: {uploadUrl: "https://attacker.invalid/upload", uploadRequiredHashes: []}} : null;
    await assert.rejects(f.run(), /drifted|upload endpoint/);
    assert.equal(f.state.live.version.name, f.prior); assert.equal(f.state.uploads.length, 0);
  });
});
test("wrong live raw bytes retain the released version receipt and cannot qualify or silently resume", async (t) => {
  const f = fixture(t); f.state.hooks.http = () => Buffer.from("old bytes under new path");
  await assert.rejects(f.run(), /wrong bytes/);
  const saved = fs.readFileSync(f.output, "utf8"), receipt = JSON.parse(saved);
  assert.equal(receipt.live.hostingVersion, f.version); assert.equal(receipt.failedPhase, "released");
  assert.equal(receipt.uncertainTransition, true); assert.throws(() => b.assertBridgeState(receipt.live, receipt), /changed/);
  const calls = f.state.calls.length; await assert.rejects(f.run(), /Existing bridge receipt/);
  assert.equal(f.state.calls.length, calls); assert.equal(fs.readFileSync(f.output, "utf8"), saved);
});
test("lost release acknowledgement leaves recorded intent and never performs rollback or retry", async (t) => {
  const f = fixture(t); f.state.hooks.request = async ({method, url}) => {
    if (method === "POST" && url.endsWith("/releases")) throw Error("lost acknowledgement");
  };
  await assert.rejects(f.run(), /lost acknowledgement/);
  const receipt = JSON.parse(fs.readFileSync(f.output)); assert.equal(receipt.failedPhase, "release-requested"); assert.equal(receipt.bridgeVersion, f.version);
  assert.equal(f.state.calls.filter((row) => row.method === "POST" && row.url.endsWith("/releases")).length, 1);
});
test("an already available complete immutable set is verified without creating another Hosting version", async (t) => {
  const f = fixture(t), plan = b.planBridge(f.candidate, f.directory, f.predecessor);
  f.predecessor.hosting.files = plan.files; f.predecessor.hosting.filesSha256 = plan.filesSha256;
  f.state.versions.get(f.prior).files = {...plan.files};
  const receipt = await b.publishBridge({candidate: f.candidate, predecessor: f.predecessor, webRoot: f.directory, output: f.output, client: f.client,
    http: async (url) => ({ok: true, status: 200, arrayBuffer: async () => f.rawFiles[new URL(url).pathname.slice(1)]})});
  assert.equal(receipt.phase, "verified"); assert.equal(receipt.live.hostingVersion, f.prior); assert.equal(f.state.calls.some((row) => row.method !== "GET"), false);
});
test("a retained path in prior Hosting still requires correct raw HTTP bytes before Functions can proceed", async (t) => {
  const f = fixture(t), plan = b.planBridge(f.candidate, f.directory, f.predecessor);
  f.predecessor.hosting.files = plan.files; f.predecessor.hosting.filesSha256 = plan.filesSha256;
  f.state.versions.get(f.prior).files = {...plan.files};
  await assert.rejects(b.publishBridge({candidate: f.candidate, predecessor: f.predecessor, webRoot: f.directory, output: f.output, client: f.client,
    http: async () => ({ok: true, status: 200, arrayBuffer: async () => Buffer.from("wrong prior raw bytes")})}), /wrong bytes/);
  assert.equal(JSON.parse(fs.readFileSync(f.output)).phase, "failed");
  assert.equal(f.state.calls.some((row) => row.method !== "GET"), false);
});
test("incomplete inventories and foreign operation/version identities are rejected", async (t) => {
  const f = fixture(t); f.state.hooks.request = async ({url}) => url.endsWith("/files") ? {data: {files: [{path: "/index.html", hash: "a".repeat(64), status: "EXPECTED"}]}} : null;
  await assert.rejects(f.run(), /unavailable or unhashed/);
  await assert.rejects(b.pollClone({name: "https://attacker.invalid/token"}, f.client, {}), /operation resource/);
  await assert.rejects(b.hostingIdentity("attendus-staging", "sites/orgami-66nxok/versions/wrong", f.client), /Cross-project/);
});
