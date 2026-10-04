"use strict";

const fs = require("node:fs");
const path = require("node:path");
const c = require("./web_release_contract");
const {download, loadCandidate, options, write} = require("./web_release_pipeline");
const {captureState, verifyState} = require("./web_release_state");
const root = path.resolve(__dirname, "..");
const PRODUCERS = Object.freeze({browser: "tools/web_release_producers/browser.js", backend: "tools/web_release_producers/backend.js", operations: "tools/web_release_producers/operations.js", safari: "tools/web_release_producers/safari.js"});
function evidenceFile(output, name) {
  c.relativeFile(name);
  if (/(?:^|\/)(?:\.env|.*debug.*\.log|.*credentials.*|.*private.*|gha-creds-.*)/i.test(name) || !/\.(?:json|png|txt|csv)$/.test(name)) throw Error("Unreviewed private/debug evidence cannot be uploaded");
  let file = output;
  for (const component of name.split("/")) {
    file = path.join(file, component);
    if (fs.lstatSync(file).isSymbolicLink()) throw Error("Evidence symlink is forbidden");
  }
  if (!fs.statSync(file).isFile()) throw Error("Evidence must be a regular file");
  return file;
}
function publishEvidence(output, reports) {
  const names = new Set(["reports.json", ...reports]);
  for (const reportPath of reports) {
    const report = JSON.parse(fs.readFileSync(path.join(output, reportPath), "utf8"));
    for (const name of Object.keys(report.rawFiles)) names.add(name);
  }
  const published = `${output}-publish`;
  for (const name of names) {
    const file = evidenceFile(output, name);
    const target = path.join(published, name); fs.mkdirSync(path.dirname(target), {recursive: true}); fs.copyFileSync(file, target);
  }
  return published;
}
function retainReports({output, candidate, producerPath, source, startedAt, finishedAt, after, result, requestedGates, collectionFailure = null}) {
  const reports = []; const diagnosticReports = []; const failures = [];
  if (after) write(path.join(output, "deployment-state.json"), after);
  for (const [gate, evidence] of Object.entries(result?.gates || {})) {
    if (requestedGates && !requestedGates.includes(gate)) continue;
    if (![...c.GATES, "observation"].includes(gate)) { failures.push("unknown-gate"); continue; }
    const rawFiles = {}; const validationErrors = [];
    if (!Array.isArray(evidence?.rawPaths) || !evidence.rawPaths.length) validationErrors.push("missing-raw-evidence");
    for (const name of new Set([...(Array.isArray(evidence?.rawPaths) ? evidence.rawPaths : []), ...(after ? ["deployment-state.json"] : [])])) {
      try { rawFiles[name] = c.sha256(fs.readFileSync(evidenceFile(output, name))); }
      catch (_) { validationErrors.push("unsafe-or-unavailable-raw-evidence"); }
    }
    const report = {schemaVersion: 1, gate, environment: "staging", projectId: candidate.projectId, sourceSha: candidate.sourceSha,
      candidateRunId: candidate.candidateRunId, candidateSha256: c.digest(candidate), webSha256: candidate.webSha256,
      deploymentSha256: candidate.deploymentSha256, configSha256: candidate.configSha256, producer: producerPath, producerSha256: source,
      workflowRunId: process.env.GITHUB_RUN_ID, startedAt, finishedAt, observedStateSha256: after?.stateSha256 || null,
      assertions: evidence?.assertions, blockers: evidence?.blockers, rawFiles,
      ...(evidence?.window ? {window: evidence.window} : {})};
    if (collectionFailure) validationErrors.push(collectionFailure);
    try { c.validateEvidence(report, candidate, output); }
    catch (_) { validationErrors.push("gate-validation-failed"); }
    const accepted = validationErrors.length === 0;
    const filename = `${accepted ? "reports" : "diagnostics"}/${gate}.json`;
    // Failed assertions and their safe raw evidence remain reviewable, but they
    // never appear in the passing report list consumed by qualification.
    write(path.join(output, filename), {...report, qualificationStatus: accepted ? "passed" : "blocked", validationErrors});
    (accepted ? reports : diagnosticReports).push(filename);
    if (!accepted) failures.push(gate);
  }
  if (!Object.keys(result?.gates || {}).length) failures.push("producer-emitted-no-gates");
  if (requestedGates?.some((gate) => !result?.gates?.[gate])) failures.push("missing-requested-gate");
  if (collectionFailure) failures.push(collectionFailure);
  const index = {schemaVersion: 1, reports, diagnosticReports, qualificationStatus: failures.length ? "blocked" : "passed", failures: [...new Set(failures)]};
  write(path.join(output, "reports.json"), index);
  publishEvidence(output, [...reports, ...diagnosticReports]);
  return index;
}
async function run(args) {
  const producerPath = PRODUCERS[args.producer];
  if (!producerPath || !args.output) throw Error("An allowlisted producer and output directory are required");
  const output = path.resolve(args.output); const bundle = `${output}-candidate`; const deployed = `${output}-deployment`;
  download(args["candidate-run"], "candidate", "web-candidate-staging", bundle);
  download(args["candidate-run"], "candidate", "web-staging-deployment", deployed);
  const candidate = loadCandidate(bundle, "staging");
  c.validateArtifact(candidate, root, path.join(bundle, "web"));
  const previous = `${output}-predecessor`;
  download(args["candidate-run"], "candidate", "web-staging-predecessor", previous);
  const priorBundle = JSON.parse(fs.readFileSync(path.join(previous, "predecessor.json"), "utf8"));
  if (priorBundle.hostingVersion !== candidate.predecessor.staging.hostingVersion || priorBundle.deploymentStateSha256 !== c.digest(candidate.predecessor.staging) || c.digest(priorBundle.files) !== priorBundle.filesSha256 || c.digest(c.files(path.join(previous, "web"))) !== priorBundle.filesSha256) throw Error("Prior staging artifact differs from captured predecessor");
  const deployment = JSON.parse(fs.readFileSync(path.join(deployed, "deployment.json"), "utf8"));
  const backendRehearsal = JSON.parse(fs.readFileSync(path.join(deployed, "backend-rehearsal.json"), "utf8"));
  const before = verifyState(candidate, await captureState(candidate.projectId), JSON.parse(fs.readFileSync(path.join(root, "firestore.indexes.json"), "utf8")));
  if (deployment.candidateSha256 !== c.digest(candidate) || before.stateSha256 !== deployment.stateSha256) throw Error("Staging changed since deployment");
  const source = c.sha256(c.gitSourceFiles(root, "tools/web_release_producers/")[producerPath]);
  if (candidate.sourceFiles[producerPath] !== source) throw Error("Producer source changed since candidate freeze");
  fs.mkdirSync(output, {recursive: true});
  const fixture = JSON.parse(process.env.STAGING_WEB_QA_CONTEXT_JSON || "{}");
  fixture.cacheUpgrade = {...fixture.cacheUpgrade, previousFiles: priorBundle.files, previousHostingVersion: priorBundle.hostingVersion};
  if (args.gates && args.gates !== "observation" && args.gates !== "all") throw Error("Only all or observation gate selection is allowed");
  const requestedGates = args.gates === "observation" ? ["observation"] : null;
  const priorEvidence = [];
  const priorRuns = args["prior-evidence-runs"] ? [...new Set(args["prior-evidence-runs"].split(","))] : [];
  if (priorRuns.length > 200) throw Error("Too many prior evidence runs");
  for (const id of priorRuns) {
    const priorRoot = `${output}-prior-${id}`;
    download(id, "evidence", "web-staging-evidence", priorRoot);
    const index = JSON.parse(fs.readFileSync(path.join(priorRoot, "reports.json"), "utf8"));
    for (const file of index.reports) {
      const report = JSON.parse(fs.readFileSync(path.join(priorRoot, c.relativeFile(file)), "utf8"));
      if (String(report.workflowRunId) !== id || report.observedStateSha256 !== deployment.stateSha256) throw Error("Prior evidence deployment or run differs");
      c.validateEvidence(report, candidate, priorRoot); priorEvidence.push({report, outputDir: priorRoot});
    }
  }
  const context = {candidateRunId: candidate.candidateRunId, sourceSha: candidate.sourceSha, projectId: candidate.projectId,
    baseUrl: "https://attendus-staging.web.app", releaseId: candidate.releaseId, webSha256: candidate.webSha256,
    deploymentSha256: candidate.deploymentSha256, configSha256: candidate.configSha256, deployment, backendRehearsal, fixture, priorEvidence, requestedGates,
    candidateRoot: path.join(bundle, "web"), artifacts: {webRoot: path.join(bundle, "web"), previousStagingRoot: path.join(previous, "web"), previousStagingFiles: priorBundle.files, previousStagingHostingVersion: priorBundle.hostingVersion}};
  const startedAt = new Date().toISOString();
  const module = require(path.join(root, producerPath));
  const produce = typeof module === "function" ? module : module.produce;
  if (typeof produce !== "function") throw Error("Producer must export executable produce function");
  let result; let after; let collectionFailure = null;
  try { result = await produce({candidate, context, outputDir: output}); }
  catch (_) { collectionFailure = "producer-execution-failed"; }
  try {
    after = await captureState(candidate.projectId);
    if (after.stateSha256 !== before.stateSha256) collectionFailure = "deployment-drift-during-collection";
  } catch (_) { collectionFailure ||= "deployment-recheck-failed"; }
  const index = retainReports({output, candidate, producerPath, source, startedAt, finishedAt: new Date().toISOString(), after, result, requestedGates, collectionFailure});
  if (index.qualificationStatus !== "passed") throw Error("Qualification evidence is blocked; curated reports and raw hashes were retained in the diagnostic artifact");
}
if (require.main === module) run(options(process.argv.slice(2))).catch((error) => { console.error(error.stack); process.exitCode = 1; });
module.exports = {run, PRODUCERS, publishEvidence, retainReports, evidenceFile};
