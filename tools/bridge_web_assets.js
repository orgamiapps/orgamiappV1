"use strict";

// A preparatory release may add immutable public assets, but must preserve every
// predecessor file and its complete ServingConfig. It never switches Flutter or
// a rewrite. Only the guarded deployment pipeline calls publishBridge.
const fs = require("node:fs");
const path = require("node:path");
const {gzipSync} = require("node:zlib");
const c = require("./web_release_contract");
const API = "https://firebasehosting.googleapis.com/v1beta1/";
const PREFIX = "public-web/v1/assets/";
const ASSET = /^public-web\/v1\/assets\/([a-f0-9]{64})\/(public\.css|registration-email-v2\.css|actions-email-v2\.js)$/;
const HASH = /^[a-f0-9]{64}$/;
const origins = (project) => project === c.PROJECTS.production ? ["https://attendus.app", "https://orgami-66nxok.web.app"] : ["https://attendus-staging.web.app", "https://attendus-staging.firebaseapp.com"];
const same = (a, b) => c.digest(a) === c.digest(b);
function project(value) {
  if (!Object.values(c.PROJECTS).includes(value)) throw Error("Unsupported Hosting bridge project");
  return value;
}
function versionName(value, projectId) {
  project(projectId);
  if (typeof value !== "string" || !new RegExp(`^sites/${projectId}/versions/[A-Za-z0-9_-]+$`).test(value)) throw Error("Cross-project or invalid Hosting version");
  return value;
}
function validateHosting(hosting) {
  if (!hosting || !hosting.config || Array.isArray(hosting.config) || !hosting.files ||
      c.digest(hosting.config) !== hosting.configSha256 || c.digest(hosting.files) !== hosting.filesSha256) throw Error("Captured Hosting configuration/file identity is missing or changed");
  const names = Object.keys(hosting.files);
  if (!names.length || names.length > 20000 || !hosting.files["index.html"]) throw Error("Unexpected Hosting file inventory");
  for (const name of names) if (c.relativeFile(name) !== name || !HASH.test(hosting.files[name])) throw Error("Invalid Hosting file hash");
  return hosting;
}
async function hostingIdentity(projectId, version, client, status = "FINALIZED") {
  versionName(version, projectId);
  const metadata = (await client.request({url: API + version, timeout: 60000})).data;
  if (metadata.name !== version || metadata.status !== status || !metadata.config || typeof metadata.config !== "object") throw Error("Hosting version/configuration is unavailable or has an unexpected status");
  const files = Object.create(null); let token; let count = 0; const tokens = new Set();
  do {
    const response = (await client.request({url: `${API}${version}/files`, params: {pageSize: 1000, ...(token ? {pageToken: token} : {})}, timeout: 60000})).data;
    if (!Array.isArray(response.files) || ++count > 100) throw Error("Incomplete Hosting file inventory");
    for (const entry of response.files) {
      const name = c.relativeFile(entry.path?.replace(/^\//, ""));
      if (Object.hasOwn(files, name) || !HASH.test(entry.hash || "") || entry.status !== "ACTIVE") throw Error("Duplicate, unavailable or unhashed Hosting file");
      files[name] = entry.hash;
    }
    token = response.nextPageToken;
    if (token && tokens.has(token)) throw Error("Repeated Hosting inventory page");
    tokens.add(token);
  } while (token);
  return validateHosting({config: metadata.config, configSha256: c.digest(metadata.config), files, filesSha256: c.digest(files)});
}
async function currentHosting(projectId, client) {
  project(projectId);
  const release = (await client.request({url: `${API}sites/${projectId}/releases`, params: {pageSize: 1}, timeout: 60000})).data.releases?.[0];
  if (!release?.name?.startsWith(`sites/${projectId}/releases/`)) throw Error("Live Hosting release identity is unavailable");
  const version = versionName(release.version?.name, projectId);
  return {projectId, hostingVersion: version, hostingRelease: release.name, hosting: await hostingIdentity(projectId, version, client)};
}
function hostingPart(state) {
  versionName(state.hostingVersion, state.projectId); validateHosting(state.hosting);
  return {projectId: state.projectId, hostingVersion: state.hostingVersion, hostingRelease: state.hostingRelease, hosting: state.hosting};
}
function planBridge(candidate, webRoot, predecessor) {
  if (candidate.projectId !== predecessor.projectId || c.PROJECTS[candidate.environment] !== candidate.projectId) throw Error("Bridge candidate/predecessor project differs");
  const prior = hostingPart(predecessor); const assets = Object.create(null); const uploads = new Map();
  for (const [name, rawHash] of Object.entries(candidate.webFiles).filter(([name]) => name.startsWith(PREFIX))) {
    const match = ASSET.exec(name);
    if (!match || match[1] !== rawHash) throw Error("Public asset path does not identify its frozen raw bytes");
    const file = path.join(webRoot, name);
    if (!fs.lstatSync(file).isFile()) throw Error("Public asset must be an ordinary frozen file");
    const bytes = fs.readFileSync(file);
    if (bytes.length > 2 * 1024 * 1024 || c.sha256(bytes) !== rawHash) throw Error("Frozen public asset bytes changed or exceed their size budget");
    const gzip = gzipSync(bytes, {level: 9}); const uploadHash = c.sha256(gzip);
    assets[name] = {rawSha256: rawHash, uploadSha256: uploadHash, size: bytes.length}; uploads.set(uploadHash, gzip);
  }
  if (Object.keys(assets).length < 3 || Object.keys(assets).length > 300 || new Set(Object.keys(assets).map((name) => ASSET.exec(name)[2])).size !== 3) throw Error("Complete bounded immutable public assets are required");
  const manifest = candidate.deployment?.publicAssets;
  if (manifest?.schemaVersion !== 1 || manifest.algorithm !== "sha256-lf" || !same(Object.keys(manifest.assets || {}).sort(), ["actions-email-v2.js", "public.css", "registration-email-v2.css"])) throw Error("Frozen renderer public asset manifest is required");
  for (const [name, hash] of Object.entries(manifest.assets)) if (!HASH.test(hash) || !assets[`${PREFIX}${hash}/${name}`]) throw Error("Frozen renderer refers to an unavailable immutable public asset");
  for (const name of Object.keys(prior.hosting.files).filter((name) => name.startsWith(PREFIX))) {
    if (!ASSET.test(name) || !assets[name]) throw Error(`Candidate removes a predecessor immutable asset: ${name}`);
  }
  const additions = Object.fromEntries(Object.entries(assets).filter(([name]) => !Object.hasOwn(prior.hosting.files, name)).map(([name, entry]) => [name, entry.uploadSha256]));
  const files = {...prior.hosting.files, ...additions};
  return {prior, assets, additions, files, filesSha256: c.digest(files), uploads};
}
async function expectCurrent(expected, client) {
  const actual = await currentHosting(expected.projectId, client);
  if (!same(actual, hostingPart(expected))) throw Error("Live Hosting drifted outside the recorded asset transition");
  return actual;
}
function assertBridgeState(state, receipt) {
  if (receipt.phase !== "verified" || !same(hostingPart(state), receipt.live)) throw Error("Hosting changed after the verified asset bridge");
}
async function verifyHttp(projectId, assets, http = fetch) {
  const results = [];
  for (const origin of origins(projectId)) for (const [name, entry] of Object.entries(assets)) {
    const response = await http(`${origin}/${name}`, {signal: AbortSignal.timeout(60000), cache: "no-store", redirect: "error"});
    if (!response.ok || c.sha256(Buffer.from(await response.arrayBuffer())) !== entry.rawSha256) throw Error(`Immutable public asset is unavailable or has wrong bytes: ${origin}/${name}`);
    results.push({origin, path: name, rawSha256: entry.rawSha256, status: response.status});
  }
  return results;
}
async function pollClone(operation, client, {now, sleep, timeoutMs}) {
  // The service owns the operation resource name. Never accept a URL, query or
  // cross-site path returned by an unexpected response.
  if (!/^(?:operations|projects\/[A-Za-z0-9_-]+\/(?:locations\/[A-Za-z0-9_-]+\/)?operations)\/[A-Za-z0-9_-]+$/.test(operation.name || "")) throw Error("Unexpected Hosting clone operation resource");
  const name = operation.name, deadline = now() + timeoutMs;
  while (!operation.done) {
    if (now() >= deadline) throw Error("Hosting clone operation timed out; inspect retained operation before retrying");
    await sleep(1000);
    operation = (await client.request({url: API + name, timeout: 60000})).data;
    if (operation.name !== name) throw Error("Hosting clone operation identity changed");
  }
  if (operation.error || !operation.response?.name) throw Error("Hosting clone operation did not complete successfully");
  return operation;
}
async function publishBridge({candidate, webRoot, predecessor, output, client, http = fetch, now = Date.now,
  sleep = (ms) => new Promise((resolve) => setTimeout(resolve, ms)), timeoutMs = 600000}) {
  const plan = planBridge(candidate, webRoot, predecessor);
  if (!output) throw Error("A retained Hosting bridge receipt path is required");
  if (fs.existsSync(output)) throw Error("Existing bridge receipt requires review; uncertain transitions never automatically resume");
  client ||= await require("./web_release_state").googleClient();
  const receipt = {schemaVersion: 1, sourceSha: candidate.sourceSha, candidateSha256: c.digest(candidate), candidateRunId: candidate.candidateRunId,
    workflowRunId: process.env.GITHUB_RUN_ID || null, projectId: candidate.projectId, predecessor: plan.prior, assets: plan.assets,
    additions: plan.additions, targetFilesSha256: plan.filesSha256, startedAt: new Date(now()).toISOString(), phase: "prepared", transitions: []};
  fs.mkdirSync(path.dirname(output), {recursive: true});
  let ownsReceipt = false;
  const save = (phase, data = {}) => {
    Object.assign(receipt, data, {phase}); receipt.transitions.push({phase, at: new Date(now()).toISOString()});
    const bytes = JSON.stringify(receipt, null, 2) + "\n";
    if (!ownsReceipt) {fs.writeFileSync(output, bytes, {flag: "wx"}); ownsReceipt = true;}
    else {
      const temporary = `${output}.${process.pid}.tmp`;
      fs.writeFileSync(temporary, bytes, {flag: "wx"}); fs.renameSync(temporary, output);
    }
  };
  try {
    save("prepared"); await expectCurrent(predecessor, client);
    let live = plan.prior;
    if (Object.keys(plan.additions).length) {
      save("clone-requested");
      const operation = (await client.request({method: "POST", url: `${API}sites/${candidate.projectId}/versions:clone`,
        data: {sourceVersion: predecessor.hostingVersion, finalize: false}, retry: false, timeout: 60000})).data;
      save("clone-pending", {cloneOperation: {name: operation.name}});
      const completed = await pollClone(operation, client, {now, sleep, timeoutMs});
      const version = versionName(completed.response.name, candidate.projectId);
      if (version === predecessor.hostingVersion) throw Error("Clone returned predecessor instead of a new version");
      save("cloned", {cloneOperation: {name: completed.name, done: completed.done, version}, bridgeVersion: version});
      const cloned = await hostingIdentity(candidate.projectId, version, client, "CREATED");
      if (!same(cloned, plan.prior.hosting)) throw Error("Cloned predecessor files or ServingConfig differ");
      const pairs = Object.entries(plan.additions);
      for (let index = 0; index < pairs.length; index += 1000) {
        save("populate-requested");
        const requested = Object.fromEntries(pairs.slice(index, index + 1000).map(([name, hash]) => [`/${name}`, hash]));
        const populated = (await client.request({method: "POST", url: `${API}${version}:populateFiles`, data: {files: requested}, retry: false, timeout: 60000})).data;
        const expectedUploadUrl = `https://upload-firebasehosting.googleapis.com/upload/${version}/files`;
        if (populated.uploadUrl !== expectedUploadUrl || !Array.isArray(populated.uploadRequiredHashes || [])) throw Error("Unexpected Hosting asset upload endpoint");
        for (const hash of new Set(populated.uploadRequiredHashes || [])) {
          if (!Object.values(requested).includes(hash) || !plan.uploads.has(hash)) throw Error("Hosting requested bytes outside the new public assets");
          save("upload-requested");
          await client.request({method: "POST", url: `${expectedUploadUrl}/${hash}`, data: plan.uploads.get(hash), headers: {"Content-Type": "application/octet-stream"}, retry: false, timeout: 60000});
        }
      }
      const populated = await hostingIdentity(candidate.projectId, version, client, "CREATED");
      if (populated.filesSha256 !== plan.filesSha256 || populated.configSha256 !== plan.prior.hosting.configSha256) throw Error("Asset population changed predecessor files/configuration");
      await expectCurrent(predecessor, client);
      save("finalize-requested");
      await client.request({method: "PATCH", url: API + version, params: {updateMask: "status"}, data: {status: "FINALIZED"}, retry: false, timeout: 60000});
      const finalized = await hostingIdentity(candidate.projectId, version, client);
      if (!same(finalized, populated)) throw Error("Finalized Hosting bridge differs from its verified file/configuration identity");
      await expectCurrent(predecessor, client);
      save("release-requested");
      const release = (await client.request({method: "POST", url: `${API}sites/${candidate.projectId}/releases`, params: {versionName: version},
        data: {message: `Attendus immutable public assets ${candidate.sourceSha}`}, retry: false, timeout: 60000})).data;
      if (!release.name?.startsWith(`sites/${candidate.projectId}/releases/`) || release.version?.name !== version) throw Error("Hosting bridge release acknowledgement is ambiguous");
      live = {projectId: candidate.projectId, hostingVersion: version, hostingRelease: release.name, hosting: finalized};
      save("released", {live});
    }
    await expectCurrent(live, client);
    const httpProof = await verifyHttp(candidate.projectId, plan.assets, http);
    await expectCurrent(live, client);
    save("verified", {live, httpProof, completedAt: new Date(now()).toISOString()});
    return receipt;
  } catch (error) {
    const failedPhase = receipt.phase;
    if (ownsReceipt) save("failed", {failedPhase, uncertainTransition: true, failure: "Hosting asset bridge did not verify; inspect recorded transition and live state before any further deployment."});
    throw error;
  }
}
module.exports = {ASSET, PREFIX, hostingIdentity, currentHosting, hostingPart, planBridge, assertBridgeState, verifyHttp, pollClone, publishBridge};
