"use strict";
const test = require("node:test"), assert = require("node:assert/strict");
const c = require("./web_release_contract");
const {LIMITS, selectedTargets, verifyHosting} = require("./verify_web_hosting");
function fixture(environment = "staging") {
  const hash = "a".repeat(64), projectId = c.PROJECTS[environment];
  const bytes = Object.fromEntries(["index.html", "flutter_bootstrap.js", "firebase-messaging-sw.js", "flutter_service_worker.js", "release-manifest.json",
    `releases/${hash}/main.dart.js`, `public-web/v1/assets/${hash}/public.css`].map((name) => [name, Buffer.from(`sealed:${name}`)]));
  const candidate = {schemaVersion: 1, sourceSha: "b".repeat(40), candidateRunId: "123", environment, projectId, releaseId: hash, sourceFiles: {},
    webFiles: Object.fromEntries(Object.entries(bytes).map(([name, data]) => [name, c.sha256(data)])),
    deployment: {functions: ["publicWeb"], deleteFunctions: [], retryAcknowledgements: [], firebaseConfigSha256: hash},
    predecessor: {production: {hostingVersion: "prior"}, staging: {hostingVersion: "prior"}}};
  candidate.sourceManifestSha256 = c.digest(candidate.sourceFiles); candidate.webSha256 = c.digest(candidate.webFiles); candidate.deploymentSha256 = c.digest(candidate.deployment);
  candidate.configSha256 = c.digest({environment, projectId, firebaseConfig: hash, worker: candidate.webFiles["firebase-messaging-sw.js"]});
  const hosting = {config: {rewrites: [{glob: "**", path: "/index.html"}]}, files: {"index.html": hash}};
  hosting.configSha256 = c.digest(hosting.config); hosting.filesSha256 = c.digest(hosting.files);
  const identity = {projectId, hostingVersion: `sites/${projectId}/versions/live123`, hostingRelease: `sites/${projectId}/releases/123`, hosting};
  let clock = Date.parse("2026-10-04T13:00:00Z"); const calls = [], snapshots = [];
  const f = {candidate, expectedHostingIdentity: identity, readHostingIdentity: async () => structuredClone(identity),
    onEvidence: (value) => snapshots.push(value), now: () => clock, clock: () => clock, sleep: async (ms) => {clock += ms;},
    fetchImpl: async (url, options) => {calls.push({url, options}); return new Response(bytes[new URL(url).pathname === "/" ? "index.html" : decodeURIComponent(new URL(url).pathname.slice(1))], {status: 200});}};
  return {f, calls, snapshots, bytes, identity, advance: (ms) => {clock += ms;}};
}
async function failed(f) {try {await verifyHosting(f); assert.fail("Expected verifier failure");} catch (error) {assert.ok(error.receipt, "Failure must retain proof"); return error.receipt;}}

test("exact sealed bytes on both canonical origins and root require stable release/config/files", async () => {
  const {f, calls, snapshots} = fixture(); const receipt = await verifyHosting(f);
  assert.equal(receipt.status, "verified"); assert.equal(receipt.attempts.length, 16); assert.equal(receipt.matchedUrls.length, 16);
  assert.deepEqual(receipt.identities.map((row) => row.phase), ["before", "after"]); assert.match(receipt.verifierSha256, /^[a-f0-9]{64}$/);
  assert.ok(calls.every(({url, options}) => !new URL(url).search && options.cache === "no-store" && options.redirect === "manual" && options.method === "GET"));
  assert.ok(calls.some((row) => row.url === "https://attendus-staging.web.app/")); assert.ok(calls.some((row) => row.url === "https://attendus-staging.firebaseapp.com/"));
  assert.equal(snapshots.at(-1).status, "verified"); assert.equal(snapshots[0].attempts.length, 0);
});

test("production selection preserves only its two actual canonical origins", () => {
  const {f} = fixture("production"), targets = selectedTargets(f.candidate);
  assert.deepEqual([...new Set(targets.map((target) => new URL(target.url).origin))], ["https://attendus.app", "https://orgami-66nxok.web.app"]);
  assert.equal(targets.find((row) => row.url === "https://attendus.app/").expectedSha256, f.candidate.webFiles["index.html"]);
});

test("old200 bytes retry unchanged URL/hash and retain actual mismatch/cache metadata", async () => {
  const {f, snapshots} = fixture(), normal = f.fetchImpl, url = "https://attendus-staging.web.app/index.html"; let first = true;
  f.fetchImpl = (address, options) => {if (address === url && first) {first = false; return new Response("old bytes", {headers: {etag: "prior", "x-cache": "HIT", "set-cookie": "private=not-retained"}});} return normal(address, options);};
  const receipt = await verifyHosting(f), rows = receipt.attempts.filter((row) => row.url === url);
  assert.deepEqual(rows.map((row) => row.result), ["hash_mismatch", "matched"]); assert.equal(rows[0].sha256, c.sha256("old bytes"));
  assert.equal(rows[0].headers.etag, "prior"); assert.equal(rows[0].headers["x-cache"], "HIT"); assert.equal(rows[0].headers["set-cookie"], undefined);
  assert.equal(rows[0].expectedSha256, rows[1].expectedSha256); assert.ok(Date.parse(rows[1].requestedAt) - Date.parse(rows[0].requestedAt) >= 3000);
  assert.ok(snapshots.some((snapshot) => snapshot.status === "verifying" && snapshot.attempts.some((row) => row.result === "hash_mismatch")));
});

for (const status of [408, 429, 503]) test(`transient HTTP${status} records its body digest and may converge`, async () => {
  const {f} = fixture(), normal = f.fetchImpl; let first = true;
  f.fetchImpl = (url, options) => {if (first) {first = false; return new Response("retry later", {status});} return normal(url, options);};
  const receipt = await verifyHosting(f); assert.equal(receipt.status, "verified");
  const failure = receipt.attempts.find((row) => row.status === status); assert.equal(failure.result, "transient_http"); assert.equal(failure.sha256, c.sha256("retry later"));
});

for (const status of [302, 401, 403, 404]) test(`HTTP${status} is terminal and never followed or silently retried`, async () => {
  const {f} = fixture(); let calls = 0;
  f.fetchImpl = async () => {calls++; return new Response("wrong destination", {status, headers: {location: "https://example.invalid/private"}});};
  const receipt = await failed(f); assert.equal(receipt.status, "failed"); assert.ok(calls <= LIMITS.concurrency);
  assert.ok(receipt.attempts.every((row) => row.round === 1 && row.status === status)); assert.equal(JSON.stringify(receipt).includes("example.invalid"), false);
  assert.ok(receipt.identities.some((row) => row.phase === "after_failure"));
});

test("persistent mismatch exhausts one fixed90second budget; callers cannot enlarge it", async () => {
  const {f} = fixture(); f.fetchImpl = async () => new Response("still old"); f.budgetMs = 3600000;
  const receipt = await failed(f); assert.equal(Date.parse(receipt.finishedAt) - Date.parse(receipt.startedAt), LIMITS.budgetMs);
  assert.equal(receipt.limits.budgetMs, 90000); assert.ok(receipt.attempts.every((row) => row.result === "hash_mismatch"));
});

test("backward UTC clock correction cannot extend the monotonic90second budget", async () => {
  const {f, advance} = fixture(); let utc = Date.parse("2026-10-04T13:00:00Z");
  f.now = () => utc; f.sleep = async (ms) => {advance(ms); utc -= 3600000;}; f.fetchImpl = async () => new Response("old bytes");
  const receipt = await failed(f); assert.equal(receipt.elapsedMs, 90000); assert.equal(receipt.status, "failed");
  assert.ok(Date.parse(receipt.finishedAt) < Date.parse(receipt.startedAt), "UTC change remains visible in diagnostics");
});

test("request timeout actually aborts hanging reads and retains partial evidence", async (t) => {
  t.mock.timers.enable({apis: ["setTimeout"]});
  const {f, advance} = fixture(); let started; const began = new Promise((resolve) => {started = resolve;}); const signals = [];
  f.fetchImpl = (url, {signal}) => {signals.push(signal); advance(LIMITS.budgetMs); started(); return new Promise(() => {});};
  const result = failed(f); await began; t.mock.timers.tick(LIMITS.requestMs); const receipt = await result;
  assert.equal(receipt.status, "failed"); assert.ok(signals.every((signal) => signal.aborted));
  assert.ok(receipt.attempts.some((row) => row.result === "read_timeout")); assert.equal(receipt.matchedUrls.length, 0);
});

test("decompressed body cap rejects oversized streams without keeping payloads", async () => {
  const {f} = fixture(); let cancelled = 0;
  f.fetchImpl = async () => ({status: 200, headers: new Headers(), body: {getReader: () => ({read: async () => ({done: false, value: {byteLength: LIMITS.bodyBytes + 1}}),
    cancel: async () => {cancelled++;}, releaseLock: () => {}})}});
  const receipt = await failed(f); assert.ok(cancelled > 0); assert.ok(receipt.attempts.every((row) => row.result === "body_limit" && !row.completeBody && row.sha256 === null));
});

test("release drift before or after matching bytes cannot qualify", async () => {
  for (const phase of ["before", "after"]) {
    const {f, identity, calls} = fixture(); let reads = 0;
    f.readHostingIdentity = async () => {reads++; const value = structuredClone(identity); if (phase === "before" || reads > 1) value.hostingRelease = value.hostingRelease + "changed"; return value;};
    const receipt = await failed(f); assert.equal(receipt.failure, "hosting_identity_changed"); if (phase === "before") assert.equal(calls.length, 0);
  }
});

test("same release with changed ServingConfig or file inventory also blocks", async () => {
  for (const kind of ["config", "files"]) {
    const {f, identity} = fixture(); let reads = 0;
    f.readHostingIdentity = async () => {const value = structuredClone(identity); if (++reads > 1) {value.hosting[kind].changed = "different"; value.hosting[kind + "Sha256"] = c.digest(value.hosting[kind]);} return value;};
    assert.equal((await failed(f)).failure, "hosting_identity_changed");
  }
});

test("HTTP concurrency stays at4 and snapshots cannot mutate internal proof", async () => {
  const {f} = fixture(), normal = f.fetchImpl; let active = 0, maximum = 0;
  f.fetchImpl = async (url, options) => {maximum = Math.max(maximum, ++active); await new Promise((resolve) => setImmediate(resolve)); active--; return normal(url, options);};
  f.onEvidence = (snapshot) => {snapshot.attempts.length = 0; snapshot.targets.length = 0;};
  const receipt = await verifyHosting(f); assert.equal(maximum, 4); assert.equal(receipt.attempts.length, 16); assert.equal(receipt.targets.length, 16);
});

test("evidence IO failure stops scheduling and preserves a failure receipt", async () => {
  const {f} = fixture(); f.onEvidence = (snapshot) => {if (snapshot.attempts.length) throw Error("Bearer private-token");};
  const receipt = await failed(f); assert.equal(receipt.evidenceWriteFailed, true); assert.ok(receipt.attempts.length <= 4);
  assert.equal(JSON.stringify(receipt).includes("private-token"), false);
});

test("malformed sealed path/hash/identity rejects before any HTTP reads", async () => {
  const {f, calls} = fixture(); f.candidate.webFiles["releases/" + f.candidate.releaseId + "/../secret"] = "a".repeat(64); f.candidate.webSha256 = c.digest(f.candidate.webFiles);
  await assert.rejects(verifyHosting(f), /Unsafe artifact path/); assert.equal(calls.length, 0);
  delete f.candidate.webFiles["releases/" + f.candidate.releaseId + "/../secret"]; f.candidate.webSha256 = c.digest(f.candidate.webFiles);
  f.expectedHostingIdentity.projectId = "foreign"; await assert.rejects(verifyHosting(f), /Hosting release identity/); assert.equal(calls.length, 0);
});
