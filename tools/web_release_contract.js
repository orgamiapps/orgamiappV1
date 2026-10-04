"use strict";

const fs = require("node:fs");
const path = require("node:path");
const crypto = require("node:crypto");
const {execFileSync} = require("node:child_process");
const {expectedFunctions} = require("./check_function_manifest");

const PROJECTS = Object.freeze({staging: "attendus-staging", production: "orgami-66nxok"});
const REPOSITORY = "orgamiapps/orgamiappV1";
const GATES = Object.freeze([
  "browser-auth-guest-organizer", "account-switch-privacy", "cache-upgrade-deeplinks",
  "accessibility-responsive", "data-migration-recovery", "owned-staging-pilot",
  "event-close-replay-observation", "rules-storage-indexes-TTL", "backend-trigger-canaries",
  "rollback-rehearsal", "notification-delivery-isolation", "large-roster-export-download-expiry", "safari-web-acceptance",
]);
const AUXILIARY_GATES = Object.freeze(["observation", "post-close-replay"]);
const WORKFLOWS = Object.freeze({candidate: ".github/workflows/firebase-release.yml",
  evidence: ".github/workflows/web-release-observe.yml", qualification: ".github/workflows/web-release-qualify.yml"});
const GATE_PRODUCERS = Object.freeze(Object.fromEntries([
  ...["browser-auth-guest-organizer", "account-switch-privacy", "cache-upgrade-deeplinks", "accessibility-responsive", "large-roster-export-download-expiry"].map((gate) => [gate, ["browser"]]),
  ...["data-migration-recovery", "event-close-replay-observation", "backend-trigger-canaries", "notification-delivery-isolation"].map((gate) => [gate, ["backend"]]),
  ...["owned-staging-pilot", "rules-storage-indexes-TTL", "rollback-rehearsal"].map((gate) => [gate, ["operations"]]),
  ["safari-web-acceptance", ["safari"]],
  ["observation", ["backend", "operations"]],
  ["post-close-replay", ["browser"]],
]));
const fail = (message) => { throw new Error(message); };
const sha256 = (value) => crypto.createHash("sha256").update(value).digest("hex");
function canonical(value) {
  if (Array.isArray(value)) return `[${value.map(canonical).join(",")}]`;
  if (value && typeof value === "object") return `{${Object.keys(value).sort().map((key) => `${JSON.stringify(key)}:${canonical(value[key])}`).join(",")}}`;
  return JSON.stringify(value);
}
const digest = (value) => sha256(canonical(value));
function relativeFile(value) {
  if (typeof value !== "string" || !value || /[\x00-\x1f\x7f]/.test(value) || value.includes("\\") || value.startsWith("/") || value.includes(":") || value.split("/").some((part) => !part || part === "." || part === "..")) fail("Unsafe artifact path");
  return value;
}
function files(root, prefix = "") {
  const output = Object.create(null);
  for (const entry of fs.readdirSync(path.join(root, prefix), {withFileTypes: true}).sort((a, b) => a.name.localeCompare(b.name))) {
    const name = relativeFile(prefix ? `${prefix}/${entry.name}` : entry.name);
    if (entry.isSymbolicLink()) fail(`Artifact symlink is forbidden: ${name}`);
    if (entry.isDirectory()) Object.assign(output, files(root, name));
    else if (entry.isFile()) output[name] = sha256(fs.readFileSync(path.join(root, name)));
    else fail(`Unsupported artifact entry: ${name}`);
  }
  return output;
}
function decodeGitBlobs(entries, output) {
  let offset = 0; const result = Object.create(null);
  for (const entry of entries) {
    const newline = output.indexOf(10, offset);
    if (newline < 0) fail("Truncated Git source batch");
    const header = output.subarray(offset, newline).toString("utf8").split(" ");
    const size = Number(header[2]);
    if (header[0] !== entry.oid || header[1] !== "blob" || !Number.isSafeInteger(size) || size < 0 || newline + size + 1 >= output.length) fail("Invalid Git source batch");
    result[entry.name] = output.subarray(newline + 1, newline + 1 + size);
    offset = newline + size + 2;
  }
  if (offset !== output.length) fail("Unexpected bytes in Git source batch");
  return result;
}
function gitSourceFiles(root, prefix = "") {
  // Git's clean filter permits platform line endings, while actual source edits
  // still fail. Hash/copy committed bytes so Windows and Linux use one artifact.
  try { execFileSync("git", ["diff", "--quiet", "HEAD", "--"], {cwd: root, stdio: "pipe"}); }
  catch (_) { fail("Tracked source changed from the frozen Git revision"); }
  const tree = execFileSync("git", ["ls-tree", "-r", "-z", "HEAD", "--", ...(Array.isArray(prefix) ? prefix : prefix ? [prefix] : [])], {cwd: root, encoding: "utf8"});
  const entries = tree.split("\0").filter(Boolean).map((record) => {
    const tab = record.indexOf("\t"); const [mode, type, oid] = record.slice(0, tab).split(" ");
    const name = relativeFile(record.slice(tab + 1));
    if (!["100644", "100755"].includes(mode) || type !== "blob" || !/^[a-f0-9]{40,64}$/.test(oid)) fail(`Unsupported source entry: ${name}`);
    return {name, oid};
  });
  if (!entries.length) fail("Frozen Git source is empty");
  const output = execFileSync("git", ["cat-file", "--batch"], {cwd: root, input: entries.map((entry) => `${entry.oid}\n`).join(""), maxBuffer: 1024 * 1024 * 1024});
  return decodeGitBlobs(entries, output);
}
function sourceFiles(root) {
  return Object.fromEntries(Object.entries(gitSourceFiles(root)).map(([name, bytes]) => [name, sha256(bytes)]));
}
function deploymentManifest(root, source) {
  const names = [...expectedFunctions(fs.readFileSync(path.join(root, "functions/index.js"), "utf8"))].sort();
  if (!names.includes("triggerAIInsights") || !names.includes("triggerAIInsightsV2")) fail("Both analytics trigger generations must remain exported");
  return {
    functions: names, deleteFunctions: [],
    publicAssets: JSON.parse(fs.readFileSync(path.join(root, "functions/public-web/asset-manifest.json"), "utf8")),
    backendSha256: digest(Object.fromEntries(Object.entries(source).filter(([name]) => name.startsWith("functions/")))),
    firestoreRulesSha256: source["firestore.rules"], storageRulesSha256: source["storage.rules"],
    indexesSha256: source["firestore.indexes.json"], firebaseConfigSha256: source["firebase.json"],
    triggerTransition: {
      document: "event_analytics/{docId}", region: "us-central1",
      legacy: {name: "triggerAIInsights", eventType: "google.cloud.firestore.document.v1.updated"},
      replacement: {name: "triggerAIInsightsV2", eventType: "google.cloud.firestore.document.v1.written"},
      retirement: "separate-explicit-approved-operation-after-observation",
    },
  };
}
function validateCandidate(candidate, environment) {
  if (candidate.schemaVersion !== 1 || candidate.environment !== environment || candidate.projectId !== PROJECTS[environment]) fail("Candidate environment/project mismatch");
  if (!/^[a-f0-9]{40}$/.test(candidate.sourceSha || "") || !/^[a-f0-9]{64}$/.test(candidate.releaseId || "")) fail("Invalid source or release identity");
  if (!/^[1-9][0-9]*$/.test(String(candidate.candidateRunId || ""))) fail("Missing candidate run identity");
  if (digest(candidate.sourceFiles) !== candidate.sourceManifestSha256 || digest(candidate.webFiles) !== candidate.webSha256 || digest(candidate.deployment) !== candidate.deploymentSha256) fail("Candidate manifest digest mismatch");
  if (candidate.deployment.deleteFunctions.length || !candidate.deployment.functions.length || candidate.deployment.functions.some((name) => !/^[A-Za-z][A-Za-z0-9_]+$/.test(name))) fail("Unsafe function deployment selectors");
  if (!candidate.webFiles["index.html"] || !candidate.webFiles[`releases/${candidate.releaseId}/main.dart.js`]) fail("Candidate lacks immutable web entrypoint");
  if (!candidate.predecessor?.production || !candidate.predecessor?.staging || !candidate.predecessor.production.hostingVersion) fail("Missing captured predecessor deployment state");
  if (candidate.configSha256 !== digest({environment, projectId: candidate.projectId, firebaseConfig: candidate.deployment.firebaseConfigSha256, worker: candidate.webFiles["firebase-messaging-sw.js"]})) fail("Candidate configuration digest mismatch");
  return candidate;
}
function validateArtifact(candidate, root, webRoot) {
  validateCandidate(candidate, candidate.environment);
  if (digest(sourceFiles(root)) !== candidate.sourceManifestSha256) fail("Source has changed since candidate packaging");
  if (digest(files(webRoot)) !== candidate.webSha256) fail("Frozen web artifact changed");
  if (digest(deploymentManifest(root, candidate.sourceFiles)) !== candidate.deploymentSha256) fail("Deployment manifest changed");
}
function validateRun(run, kind, sourceSha, repository) {
  if (repository !== REPOSITORY) fail("Release provenance must belong to the Attendus repository");
  if (run.repository?.full_name !== repository || run.head_repository?.full_name !== repository || run.head_sha !== sourceSha || run.path !== WORKFLOWS[kind] || run.event !== "workflow_dispatch" || run.status !== "completed" || run.conclusion !== "success" || run.run_attempt !== 1) fail(`Untrusted ${kind} workflow provenance`);
  if (run.head_branch !== "main" && !/^codex\/[A-Za-z0-9._/-]+$/.test(run.head_branch || "")) fail("Workflow branch is outside the approved branch policy");
  return run;
}
function validateAssertions(report) {
  if (!Array.isArray(report.assertions) || report.assertions.length === 0) fail("Evidence has no executable assertions");
  const ids = new Set();
  for (const assertion of report.assertions) {
    if (!assertion.id || ids.has(assertion.id) || !Object.hasOwn(assertion, "expected") || !Object.hasOwn(assertion, "actual") || canonical(assertion.expected) !== canonical(assertion.actual)) fail("Evidence assertion failed or duplicated");
    ids.add(assertion.id);
  }
  if (!report.rawFiles || !Object.keys(report.rawFiles).length) fail("Raw evidence is missing");
  if (!Array.isArray(report.blockers) || report.blockers.length) fail("Unresolved active journey blockers");
}
function validateEvidence(report, candidate, rawRoot) {
  if (report.schemaVersion !== 1 || ![...GATES, ...AUXILIARY_GATES].includes(report.gate) || report.environment !== "staging" || report.projectId !== PROJECTS.staging || report.sourceSha !== candidate.sourceSha || report.candidateRunId !== candidate.candidateRunId || report.candidateSha256 !== digest(candidate) || report.webSha256 !== candidate.webSha256 || report.deploymentSha256 !== candidate.deploymentSha256 || report.configSha256 !== candidate.configSha256) fail("Evidence is bound to a different candidate");
  const start = Date.parse(report.startedAt); const end = Date.parse(report.finishedAt);
  if (!Number.isFinite(start) || !Number.isFinite(end) || end < start || end > Date.now() + 60000) fail("Invalid evidence time");
  if (!/^[a-f0-9]{64}$/.test(report.producerSha256 || "") || !GATE_PRODUCERS[report.gate]?.some((producer) => report.producer === `tools/web_release_producers/${producer}.js`)) fail("Missing or unauthorized executable producer identity");
  if (candidate.sourceFiles[report.producer] !== report.producerSha256) fail("Producer does not belong to frozen source");
  validateAssertions(report);
  if (rawRoot) for (const [name, hash] of Object.entries(report.rawFiles)) {
    if (sha256(fs.readFileSync(path.join(rawRoot, relativeFile(name)))) !== hash) fail(`Raw evidence changed: ${name}`);
  }
  return report;
}
function qualify(candidate, productionCandidate, deployment, reports, now = Date.now()) {
  validateCandidate(candidate, "staging"); validateCandidate(productionCandidate, "production");
  if (candidate.sourceSha !== productionCandidate.sourceSha || candidate.candidateRunId !== productionCandidate.candidateRunId || candidate.sourceManifestSha256 !== productionCandidate.sourceManifestSha256 || candidate.deploymentSha256 !== productionCandidate.deploymentSha256 || digest(candidate.predecessor) !== digest(productionCandidate.predecessor)) fail("Environment candidates are not one frozen source");
  if (deployment.candidateSha256 !== digest(candidate) || deployment.environment !== "staging" || !deployment.verifiedAt || !deployment.stateSha256) fail("Missing verified staging deployment");
  const deploymentTime = Date.parse(deployment.verifiedAt);
  for (const report of reports) { validateEvidence(report, candidate); if (Date.parse(report.startedAt) < deploymentTime) fail("Evidence predates staging deployment"); }
  for (const gate of GATES) if (!reports.some((report) => report.gate === gate)) fail(`Required gate missing: ${gate}`);
  const observations = reports.filter((report) => report.gate === "observation").sort((a, b) => Date.parse(a.finishedAt) - Date.parse(b.finishedAt));
  if (observations.length < 2) fail("Continuous staging observations missing");
  const first = Date.parse(observations[0].finishedAt); const last = Date.parse(observations.at(-1).finishedAt);
  if (last - first < 86400000 || first - deploymentTime > 1200000 || now - last > 4500000 || last > now + 60000) fail("The staging pilot must span 24 hours and remain fresh");
  for (let i = 1; i < observations.length; i++) if (Date.parse(observations[i].finishedAt) - Date.parse(observations[i - 1].finishedAt) > 4500000) fail("Staging observation gap exceeds 75 minutes");
  const close = reports.find((report) => report.gate === "event-close-replay-observation");
  const closedAt = Date.parse(close?.window?.eventClosesAt); const replayedAt = Date.parse(close?.window?.replayObservedAt);
  if (!Number.isFinite(closedAt) || !Number.isFinite(replayedAt) || replayedAt - closedAt < 86400000 || last - closedAt < 86400000 || replayedAt > Date.parse(close.finishedAt)) fail("A verified event close and replay observation must span 24 hours");
  const replay = reports.find((report) => report.gate === "post-close-replay" && digest(report) === close.window.replayReportSha256);
  const effectiveClose = Date.parse(close.window.effectiveClosesAt), executedAt = Date.parse(close.window.replayExecutedAt);
  if (!replay || !Number.isFinite(effectiveClose) || effectiveClose < closedAt || !Number.isFinite(executedAt) ||
      executedAt <= effectiveClose || executedAt > replayedAt || Date.parse(replay.startedAt) <= effectiveClose ||
      executedAt > Date.parse(replay.finishedAt) || replay.window?.replayExecutedAt !== close.window.replayExecutedAt ||
      replay.window?.effectiveClosesAt !== close.window.effectiveClosesAt || replay.window?.eventClosesAt !== close.window.eventClosesAt) fail("An immutable authenticated post-close browser replay is required");
  if (reports.some((report) => report.observedStateSha256 !== deployment.stateSha256)) fail("Staging deployment drifted during qualification");
  return {schemaVersion: 1, sourceSha: candidate.sourceSha, candidateRunId: candidate.candidateRunId,
    stagingCandidateSha256: digest(candidate), productionCandidateSha256: digest(productionCandidate),
    predecessorProductionSha256: digest(candidate.predecessor.production), stagingStateSha256: deployment.stateSha256,
    startedAt: new Date(first).toISOString(), finishedAt: new Date(last).toISOString(), qualifiedAt: new Date(now).toISOString(),
    gateReports: reports.map((report) => ({gate: report.gate, sha256: digest(report), runId: report.workflowRunId})), requiredGates: GATES};
}

module.exports = {PROJECTS, REPOSITORY, GATES, AUXILIARY_GATES, GATE_PRODUCERS, WORKFLOWS, canonical, digest, sha256, relativeFile, files, decodeGitBlobs, gitSourceFiles, sourceFiles, deploymentManifest, validateCandidate, validateArtifact, validateRun, validateEvidence, validateAssertions, qualify};
