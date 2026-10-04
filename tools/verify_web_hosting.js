"use strict";

// Canonical URLs and sealed hashes never change while waiting for live bytes.
// This verifier performs reads only; the caller owns deployment and evidence IO.
const crypto = require("node:crypto");
const fs = require("node:fs");
const {performance} = require("node:perf_hooks");
const c = require("./web_release_contract");
const {PREFIX} = require("./bridge_web_assets");
const LIMITS = Object.freeze({budgetMs: 90000, requestMs: 12000, retryMs: 3000, concurrency: 4, bodyBytes: 64 * 1024 * 1024, targets: 2048, rounds: 31});
const BASE = ["index.html", "flutter_bootstrap.js", "firebase-messaging-sw.js", "flutter_service_worker.js", "release-manifest.json"];
const CACHE_HEADERS = ["cache-control", "age", "etag", "last-modified", "date", "content-type", "content-encoding", "content-length", "x-cache", "x-cache-hits", "x-served-by"];
const HASH = /^[a-f0-9]{64}$/;
const defaultSleep = (ms) => new Promise((resolve) => setTimeout(resolve, ms));

function selectedTargets(candidate) {
  c.validateCandidate(candidate, candidate.environment);
  if (!["staging", "production"].includes(candidate.environment) || BASE.some((name) => !HASH.test(candidate.webFiles[name] || ""))) throw Error("Sealed Hosting entrypoint inventory is incomplete");
  const origins = candidate.environment === "production" ? ["https://attendus.app", "https://orgami-66nxok.web.app"] :
    ["https://attendus-staging.web.app", "https://attendus-staging.firebaseapp.com"];
  const names = Object.keys(candidate.webFiles).filter((name) => BASE.includes(name) || name.startsWith(`releases/${candidate.releaseId}/`) || name.startsWith(PREFIX)).sort();
  if (names.length * origins.length + origins.length > LIMITS.targets) throw Error("Hosting verification inventory exceeds its read budget");
  for (const name of names) if (c.relativeFile(name) !== name || !HASH.test(candidate.webFiles[name])) throw Error("Invalid sealed Hosting target");
  return origins.flatMap((origin) => [
    {url: `${origin}/`, name: "index.html", expectedSha256: candidate.webFiles["index.html"]},
    ...names.map((name) => ({url: `${origin}/${name.split("/").map(encodeURIComponent).join("/")}`, name, expectedSha256: candidate.webFiles[name]})),
  ]);
}

function hostingIdentity(value, projectId) {
  if (value?.projectId !== projectId || !new RegExp(`^sites/${projectId}/versions/[A-Za-z0-9_-]+$`).test(value.hostingVersion || "") ||
      !new RegExp(`^sites/${projectId}/releases/[A-Za-z0-9_-]+$`).test(value.hostingRelease || "") ||
      !HASH.test(value.hosting?.configSha256 || "") || !HASH.test(value.hosting?.filesSha256 || "") ||
      c.digest(value.hosting.config) !== value.hosting.configSha256 || c.digest(value.hosting.files) !== value.hosting.filesSha256) throw Error("Hosting release identity is incomplete");
  return {projectId, hostingVersion: value.hostingVersion, hostingRelease: value.hostingRelease,
    configSha256: value.hosting.configSha256, filesSha256: value.hosting.filesSha256};
}

async function verifyHosting({candidate, expectedHostingIdentity, readHostingIdentity, onEvidence = () => {}, fetchImpl = globalThis.fetch,
  now = Date.now, clock = () => performance.now(), sleep = defaultSleep}) {
  const targets = selectedTargets(candidate), expected = hostingIdentity(expectedHostingIdentity, candidate.projectId);
  if (typeof readHostingIdentity !== "function" || typeof fetchImpl !== "function" || typeof onEvidence !== "function") throw Error("Read-only identity, HTTP and evidence adapters are required");
  const started = clock(), deadline = started + LIMITS.budgetMs, iso = () => new Date(now()).toISOString();
  const receipt = {schemaVersion: 1, kind: "canonical-hosting-byte-verification", status: "verifying", sourceSha: candidate.sourceSha,
    candidateRunId: candidate.candidateRunId, candidateSha256: c.digest(candidate), projectId: candidate.projectId, environment: candidate.environment,
    verifierSha256: c.sha256(fs.readFileSync(__filename)),
    expectedHosting: expected, limits: LIMITS, startedAt: iso(), targets, attempts: [], identities: [], matchedUrls: [],
    limitation: "Earlier failed responses not retained by historical code cannot be diagnosed from later matching bytes"};
  let stopped = false, evidenceFailed = false;
  const emit = async () => {
    try {
      // The pipeline writes synchronously to its local evidence file. Bound an
      // injected asynchronous sink as well, without withholding a final local
      // failure snapshot merely because the HTTP budget has just expired.
      const result = onEvidence(JSON.parse(JSON.stringify(receipt)));
      if (result && typeof result.then === "function") await bounded(() => result);
    }
    catch (_) {stopped = true; evidenceFailed = true; throw Error("Evidence persistence failed");}
  };
  const remaining = () => Math.max(0, deadline - clock());
  async function bounded(task, maxMs = LIMITS.requestMs) {
    const ms = Math.min(maxMs, remaining());
    if (ms <= 0) {const error = Error("Verification time budget exhausted"); error.verificationCode = "deadline"; throw error;}
    const controller = new AbortController(); let timer;
    const timeout = new Promise((_, reject) => {timer = setTimeout(() => {
      controller.abort(); const error = Error("Bounded read timed out"); error.verificationCode = "read_timeout"; reject(error);
    }, ms);});
    try {return await Promise.race([Promise.resolve().then(() => task(controller.signal, ms)), timeout]);}
    finally {clearTimeout(timer); controller.abort();}
  }
  async function observeIdentity(phase) {
    const observed = hostingIdentity(await bounded((signal, timeoutMs) => readHostingIdentity({signal, timeoutMs})), candidate.projectId);
    receipt.identities.push({phase, observedAt: iso(), ...observed}); await emit();
    if (c.digest(observed) !== c.digest(expected)) throw Error("Hosting release/version/configuration/files changed during verification");
  }
  async function attempt(target, round) {
    const record = {url: target.url, expectedSha256: target.expectedSha256, round, requestedAt: iso(), status: null, headers: {}, bytes: 0, sha256: null, completeBody: false};
    let retryable = false, terminal = false;
    try {
      await bounded(async (signal) => {
        const response = await fetchImpl(target.url, {method: "GET", redirect: "manual", cache: "no-store", signal});
        if (signal.aborted) return;
        record.status = response.status;
        record.headers = Object.fromEntries(CACHE_HEADERS.flatMap((key) => response.headers.get(key) === null ? [] : [[key, response.headers.get(key).slice(0, 1024)]]));
        if (response.status >= 300 && response.status < 400) {terminal = true; record.result = "redirect_rejected"; await response.body?.cancel(); return;}
        if (response.status !== 200) {
          retryable = [408, 429].includes(response.status) || response.status >= 500 && response.status <= 599;
          terminal = !retryable; record.result = retryable ? "transient_http" : "http_rejected";
        }
        if (Number(response.headers.get("content-length")) > LIMITS.bodyBytes) {
          terminal = true; retryable = false; record.result = "body_limit"; await response.body?.cancel(); return;
        }
        const hash = crypto.createHash("sha256"), reader = response.body?.getReader();
        if (!reader) {terminal = true; retryable = false; record.result = "missing_body"; return;}
        const cancel = () => {void reader.cancel().catch(() => {});}; signal.addEventListener("abort", cancel, {once: true});
        try {
          for (;;) {
            const chunk = await reader.read(); if (signal.aborted) return;
            if (chunk.done) break;
            record.bytes += chunk.value.byteLength;
            if (record.bytes > LIMITS.bodyBytes) {terminal = true; retryable = false; record.result = "body_limit"; await reader.cancel(); return;}
            hash.update(chunk.value);
          }
          record.sha256 = hash.digest("hex"); record.completeBody = true;
        } finally {signal.removeEventListener("abort", cancel); reader.releaseLock();}
        if (response.status === 200) {
          retryable = record.sha256 !== target.expectedSha256;
          record.result = retryable ? "hash_mismatch" : "matched";
        }
      });
    } catch (error) {
      // Do not retain arbitrary transport errors: URLs/headers can contain credentials.
      record.result = error.verificationCode === "read_timeout" ? "read_timeout" : error.verificationCode === "deadline" ? "deadline" : "network_error";
      retryable = true;
    }
    record.completedAt = iso(); receipt.attempts.push(record);
    if (record.result === "matched") receipt.matchedUrls.push(target.url);
    if (terminal) stopped = true;
    await emit();
    return {target, matched: record.result === "matched", retryable, terminal};
  }
  try {
    await emit(); await observeIdentity("before");
    let pending = targets;
    for (let round = 1; pending.length && round <= LIMITS.rounds; round++) {
      if (!remaining()) throw Error("Canonical Hosting bytes did not converge within the fixed90-second budget");
      const queue = [...pending], outcomes = [];
      const workers = await Promise.allSettled(Array.from({length: Math.min(LIMITS.concurrency, queue.length)}, async () => {
        try {while (queue.length && !stopped && remaining()) outcomes.push(await attempt(queue.shift(), round));}
        catch (error) {stopped = true; throw error;}
      }));
      const rejected = workers.find((worker) => worker.status === "rejected");
      if (rejected) throw rejected.reason;
      if (outcomes.some((row) => row.terminal)) throw Error("Canonical Hosting URL returned a non-retryable response");
      pending = [...queue, ...outcomes.filter((row) => !row.matched).map((row) => row.target)];
      if (pending.length) {
        if (!remaining() || round === LIMITS.rounds) throw Error("Canonical Hosting bytes did not converge within the fixed verification budget");
        await bounded(() => sleep(Math.min(LIMITS.retryMs, remaining())), LIMITS.retryMs + 1);
      }
    }
    if (receipt.matchedUrls.length !== targets.length || new Set(receipt.matchedUrls).size !== targets.length) throw Error("Hosting byte verification is incomplete");
    await observeIdentity("after");
    if (!remaining()) throw Error("Hosting identity verification exceeded the fixed deadline");
    receipt.status = "verified"; receipt.finishedAt = iso(); receipt.elapsedMs = Math.max(0, clock() - started); await emit(); return receipt;
  } catch (error) {
    stopped = true;
    if (!evidenceFailed && remaining() && receipt.identities.some((row) => row.phase === "before") && !receipt.identities.some((row) => row.phase === "after")) {
      try {await observeIdentity("after_failure");} catch (_) {receipt.finalIdentityUnverified = true;}
    }
    receipt.status = "failed"; receipt.finishedAt = iso(); receipt.elapsedMs = Math.max(0, clock() - started);
    receipt.failure = String(error.message).startsWith("Hosting release/") ? "hosting_identity_changed" : "canonical_byte_verification_failed";
    const failure = Error("Canonical Hosting verification failed; inspect retained attempt and identity evidence");
    try {await emit();} catch (_) {receipt.evidenceWriteFailed = true;}
    failure.receipt = JSON.parse(JSON.stringify(receipt)); throw failure;
  }
}

module.exports = {LIMITS, selectedTargets, hostingIdentity, verifyHosting};
