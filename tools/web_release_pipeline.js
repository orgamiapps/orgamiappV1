"use strict";

const fs = require("node:fs");
const path = require("node:path");
const {execFileSync} = require("node:child_process");
const c = require("./web_release_contract");
const {captureState, verifyState, firebase} = require("./web_release_state");
const assets = require("./bridge_web_assets");
const root = path.resolve(__dirname, "..");
const read = (file) => JSON.parse(fs.readFileSync(file, "utf8"));
const write = (file, value) => { fs.mkdirSync(path.dirname(file), {recursive: true}); fs.writeFileSync(file, JSON.stringify(value, null, 2) + "\n"); };
function options(args) {
  const output = {};
  for (let i = 0; i < args.length; i += 2) {
    if (!/^--[a-z-]+$/.test(args[i]) || !args[i + 1] || args[i + 1].startsWith("--") || Object.hasOwn(output, args[i].slice(2))) throw Error("Expected unique --option value arguments");
    output[args[i].slice(2)] = args[i + 1];
  }
  return output;
}
function gitSha() { return execFileSync("git", ["rev-parse", "HEAD"], {cwd: root, encoding: "utf8"}).trim(); }
function repository() {
  const value = process.env.GITHUB_REPOSITORY || execFileSync("gh", ["repo", "view", "--json", "nameWithOwner", "--jq", ".nameWithOwner"], {cwd: root, encoding: "utf8"}).trim();
  if (!/^[A-Za-z0-9_.-]+\/[A-Za-z0-9_.-]+$/.test(value)) throw Error("Invalid repository identity");
  return value;
}
function github(api) { return JSON.parse(execFileSync("gh", ["api", api], {encoding: "utf8", maxBuffer: 20 * 1024 * 1024})); }
function extract(zip, output) {
  fs.mkdirSync(output, {recursive: true});
  const script = "import sys,zipfile,pathlib; z=zipfile.ZipFile(sys.argv[1]); root=pathlib.Path(sys.argv[2]).resolve(); assert all(not i.is_dir() or True for i in z.infolist()); assert all(not (i.external_attr>>16 & 0o170000)==0o120000 and '\\\\' not in i.filename and ':' not in i.filename and (root/pathlib.Path(i.filename)).resolve().is_relative_to(root) for i in z.infolist()), 'Unsafe artifact archive'; z.extractall(root)";
  execFileSync(process.platform === "win32" ? "python" : "python3", ["-c", script, zip, output], {stdio: "inherit"});
}
function download(runId, kind, artifactName, output, sha = gitSha()) {
  if (!/^[1-9][0-9]*$/.test(String(runId))) throw Error("Run ID must be an immutable numeric ID");
  const repo = repository(); const run = github(`repos/${repo}/actions/runs/${runId}`);
  c.validateRun(run, kind, sha, repo);
  const artifacts = github(`repos/${repo}/actions/runs/${runId}/artifacts?per_page=100`).artifacts;
  const matches = artifacts.filter((artifact) => artifact.name === artifactName && !artifact.expired);
  if (matches.length !== 1 || matches[0].workflow_run?.head_sha !== sha) throw Error(`Missing or ambiguous immutable artifact: ${artifactName}`);
  const artifact = matches[0];
  const bytes = execFileSync("gh", ["api", `repos/${repo}/actions/artifacts/${artifact.id}/zip`], {maxBuffer: 1024 * 1024 * 1024});
  if (artifact.digest && artifact.digest !== `sha256:${c.sha256(bytes)}`) throw Error("GitHub artifact digest mismatch");
  const zip = `${output}.zip`; fs.mkdirSync(path.dirname(zip), {recursive: true}); fs.writeFileSync(zip, bytes); extract(zip, output);
  return {runId: String(runId), artifactId: artifact.id, artifactSha256: c.sha256(bytes), workflow: run.path, sourceSha: sha};
}
function loadCandidate(directory, environment) {
  return c.validateCandidate(read(path.join(directory, "candidate.json")), environment);
}
function materializeBackend(candidate, sourceRoot = root, buildRoot = path.join(root, "build"), readSources = c.gitSourceFiles) {
  fs.mkdirSync(buildRoot, {recursive: true});
  const directory = fs.mkdtempSync(path.join(buildRoot, "frozen-functions-"));
  const committed = readSources(sourceRoot, "functions/");
  for (const [name, expected] of Object.entries(candidate.sourceFiles)) {
    if (!name.startsWith("functions/")) continue;
    const relative = c.relativeFile(name.slice("functions/".length));
    const bytes = committed[name];
    if (!bytes) throw Error(`Frozen backend source missing: ${name}`);
    if (c.sha256(bytes) !== expected) throw Error(`Frozen backend source changed: ${name}`);
    const target = path.join(directory, relative); fs.mkdirSync(path.dirname(target), {recursive: true}); fs.writeFileSync(target, bytes);
  }
  if (!fs.existsSync(path.join(directory, "package-lock.json")) || !fs.existsSync(path.join(directory, "index.js"))) throw Error("Frozen backend entrypoint or lockfile missing");
  return directory;
}
function materializeRules(candidate, sourceRoot = root, buildRoot = path.join(root, "build"), readSources = c.gitSourceFiles) {
  fs.mkdirSync(buildRoot, {recursive: true});
  const directory = fs.mkdtempSync(path.join(buildRoot, "frozen-rules-"));
  const names = ["firebase.json", "firestore.rules", "firestore.indexes.json", "storage.rules"];
  const committed = readSources(sourceRoot, names);
  for (const name of names) {
    const bytes = committed[name];
    if (!bytes || c.sha256(bytes) !== candidate.sourceFiles[name]) throw Error(`Frozen deployment source changed: ${name}`);
    fs.writeFileSync(path.join(directory, name), bytes);
  }
  return directory;
}
async function seal(args) {
  const environment = args.environment; const web = path.resolve(args.web || "build/web");
  if (!c.PROJECTS[environment] || !args.output || !args.predecessor) throw Error("seal requires environment, output and predecessor");
  if (execFileSync("git", ["status", "--porcelain", "--untracked-files=all"], {cwd: root, encoding: "utf8"}).trim()) throw Error("A deployable candidate requires a clean committed source");
  const sourceSha = gitSha(); const runId = process.env.GITHUB_RUN_ID;
  if (process.env.GITHUB_SHA !== sourceSha || !runId) throw Error("Candidate must be sealed in its source workflow");
  const source = c.sourceFiles(root); const webFiles = c.files(web); const deployment = c.deploymentManifest(root, source);
  const releaseId = c.sha256(`${sourceSha}:${runId}:${environment}`);
  const candidate = {schemaVersion: 1, sourceSha, candidateRunId: runId, environment, projectId: c.PROJECTS[environment], releaseId,
    createdAt: new Date().toISOString(), sourceFiles: source, sourceManifestSha256: c.digest(source), webFiles, webSha256: c.digest(webFiles),
    deployment, deploymentSha256: c.digest(deployment), predecessor: read(args.predecessor),
    configSha256: c.digest({environment, projectId: c.PROJECTS[environment], firebaseConfig: deployment.firebaseConfigSha256, worker: webFiles["firebase-messaging-sw.js"]})};
  c.validateCandidate(candidate, environment);
  // The final sealed artifact must retain the immutable paths needed by cached
  // predecessor HTML and a backend rollback. No asset is added after sealing.
  assets.planBridge(candidate, web, candidate.predecessor[environment]);
  const output = path.resolve(args.output); fs.mkdirSync(output, {recursive: true});
  fs.cpSync(web, path.join(output, "web"), {recursive: true, errorOnExist: true, force: false});
  write(path.join(output, "candidate.json"), candidate);
}
async function verifyLive(candidate, {expectedHostingIdentity = null, output = null, client = null} = {}) {
  client ||= await require("./web_release_state").googleClient();
  const readHostingIdentity = ({signal, timeoutMs = 12000} = {}) => assets.currentHosting(candidate.projectId, {
    request: (options) => client.request({...options, signal,
      timeout: Math.min(options.timeout || timeoutMs, timeoutMs)}),
  });
  expectedHostingIdentity ||= await readHostingIdentity();
  return require("./verify_web_hosting").verifyHosting({candidate, expectedHostingIdentity, readHostingIdentity,
    onEvidence: (receipt) => { if (output) write(output, receipt); }});
}
async function verifyPublishedDeployment(candidate, publishedHosting, {output, client},
    {capture = captureState, http = verifyLive, manifest = read(path.join(root, "firestore.indexes.json"))} = {}) {
  const retain = (phase, snapshot) => write(path.join(path.dirname(output), `hosting-state-${phase}-verification.json`), {
    schemaVersion: 1, sourceSha: candidate.sourceSha, candidateRunId: candidate.candidateRunId,
    candidateSha256: c.digest(candidate), ...snapshot,
  });
  // Full deployment captures are separate from the verifier's fixed HTTP budget.
  // Retain both observations even when candidate or drift checks then reject them.
  const before = await capture(candidate.projectId); retain("before", before);
  verifyState(candidate, before, manifest);
  if (c.digest(assets.hostingPart(before.state)) !== c.digest(publishedHosting)) throw Error("Hosting release changed before live byte verification");
  const live = await http(candidate, {expectedHostingIdentity: publishedHosting, client,
    output: path.join(path.dirname(output), "hosting-live-verification.json")});
  const after = await capture(candidate.projectId); retain("after", after);
  verifyState(candidate, after, manifest);
  if (c.digest(assets.hostingPart(after.state)) !== c.digest(publishedHosting)) throw Error("Hosting release changed after live byte verification");
  if (c.digest(before.state) !== c.digest(after.state)) throw Error("Full deployment state changed during live byte verification");
  return {live, before, after};
}
function validateFunctionCompletion(receipt, candidate, predecessor, preflight, invokedAt) {
  const adapter = require("./deploy_web_functions");
  const mode = preflight ? "preflight" : "deploy", status = preflight ? "preflight-passed" : "success";
  const started = Date.parse(receipt?.startedAt), finished = Date.parse(receipt?.finishedAt);
  if (receipt?.schemaVersion !== 1 || receipt.mode !== mode || receipt.status !== status || receipt.error ||
      receipt.projectId !== candidate.projectId || receipt.sourceSha !== candidate.sourceSha ||
      receipt.candidateRunId !== candidate.candidateRunId || receipt.candidateSha256 !== c.digest(candidate) ||
      receipt.predecessorFunctionsSha256 !== c.digest(predecessor.functions) || receipt.globalForce !== false ||
      receipt.firebaseToolsVersion !== adapter.VERSION || c.digest(receipt.moduleHashes) !== c.digest(adapter.PINS) ||
      !Number.isFinite(started) || !Number.isFinite(finished) || started < invokedAt || finished < started || finished > Date.now() ||
      !Array.isArray(receipt.plans) || !receipt.plans.some((plan) => plan.phase === "prepare-before-upload") ||
      (preflight ? receipt.plans.some((plan) => plan.phase !== "prepare-before-upload") : !receipt.plans.some((plan) => plan.phase === "release"))) {
    throw Error("Functions command did not retain a completed, matching deployment receipt");
  }
  return receipt;
}
function runFunctionsCommand({candidate, configPath, predecessor, candidateFile, predecessorFile, receiptPath, preflight}, execute = execFileSync) {
  if (fs.existsSync(receiptPath)) throw Error("Functions receipt already exists; reconcile the prior attempt before continuing");
  const invokedAt = Date.now();
  const output = execute(process.execPath, ["tools/deploy_web_functions.js", candidateFile, configPath, predecessorFile,
    receiptPath, ...(preflight ? ["--preflight"] : [])],
  {cwd: root, encoding: "utf8", maxBuffer: 20 * 1024 * 1024, stdio: ["ignore", "pipe", "inherit"]});
  // A pending promise alone does not keep a Node child alive. Exit zero is not
  // sufficient: the pinned CLI can leave queued work unsettled after failure.
  try {
    let receipt;
    try { receipt = read(receiptPath); } catch (_) { throw Error("Functions command did not retain a readable completion receipt"); }
    validateFunctionCompletion(receipt, candidate, predecessor, preflight, invokedAt);
  } catch (error) { error.stdout = output; throw error; }
  return output;
}
async function deploy(candidate, bundle, expectedState, output) {
  c.validateArtifact(candidate, root, path.join(bundle, "web"));
  const before = await captureState(candidate.projectId);
  if (c.digest(before.state) !== c.digest(expectedState)) throw Error("Prior deployment changed; prepare and qualify a new candidate");
  if (candidate.environment === "staging") {
    const rehearsal = require("./rehearse_web_backend");
    const startedAt = new Date().toISOString();
    // The same strict pre-fixture check also runs immediately before and during
    // rollback. Check here before materialization, CLI preparation (which may
    // enable APIs), or any Hosting/rules/Functions deployment can change state.
    const checks = await rehearsal.assertEmpty(await require("./web_release_state").googleClient());
    write(path.join(path.dirname(output), "staging-empty-prerequisite.json"), {
      schemaVersion: 1, kind: "staging-empty-prerequisite", environment: "staging", projectId: candidate.projectId,
      sourceSha: candidate.sourceSha, candidateRunId: candidate.candidateRunId, candidateSha256: c.digest(candidate),
      predecessorStateSha256: c.digest(before.state), startedAt, verifiedAt: checks.checkedAt, checks,
      workflowRunId: process.env.GITHUB_RUN_ID || null,
    });
    rehearsal.validateArchives(read(path.join(root, "config/web_backend_predecessor_archives.json")), before.state);
  }
  assets.planBridge(candidate, path.join(bundle, "web"), expectedState);
  const rulesRoot = materializeRules(candidate);
  const configuration = read(path.join(rulesRoot, "firebase.json"));
  if (Array.isArray(configuration.hosting) || (Array.isArray(configuration.functions) && configuration.functions.length !== 1)) throw Error("Review multi-target deployment explicitly");
  configuration.hosting.public = path.resolve(bundle, "web");
  const functionsConfig = Array.isArray(configuration.functions) ? configuration.functions[0] : configuration.functions;
  functionsConfig.source = materializeBackend(candidate);
  // Populate only ignored dependencies in the isolated, allowlisted source tree.
  // The existing Firebase predeploy lint runs against that exact copied source.
  if (process.platform === "win32") execFileSync("cmd.exe", ["/d", "/s", "/c", "npm ci"], {cwd: functionsConfig.source, stdio: "inherit"});
  else execFileSync("npm", ["ci"], {cwd: functionsConfig.source, stdio: "inherit"});
  for (const [name, hash] of Object.entries(candidate.sourceFiles)) if (name.startsWith("functions/") && c.sha256(fs.readFileSync(path.join(functionsConfig.source, name.slice(10)))) !== hash) throw Error("Dependency installation changed frozen backend source");
  configuration.firestore.rules = path.join(rulesRoot, "firestore.rules"); configuration.firestore.indexes = path.join(rulesRoot, "firestore.indexes.json");
  configuration.storage.rules = path.join(rulesRoot, "storage.rules");
  const configPath = path.join(root, "build", `frozen-firebase-${candidate.environment}.json`); write(configPath, configuration);
  const functionCandidate = path.join(root, "build", `frozen-function-candidate-${candidate.environment}.json`);
  const functionPredecessor = path.join(root, "build", `frozen-function-predecessor-${candidate.environment}.json`);
  write(functionCandidate, candidate); write(functionPredecessor, before.state);
  function deployStep(name, selectors, execute = null) {
    let result;
    try { result = execute ? execute() : firebase(["deploy", "--config", configPath, "--project", candidate.projectId, "--only", selectors, "--non-interactive"]); }
    catch (error) { result = String(error.stdout || "Deployment failed; consult the workflow's standard error output."); throw error; }
    finally {
      const safeOutput = String(result || "").replace(/(authorization\s*[:=]\s*|Bearer\s+)[^\s]+/gi, "$1[REDACTED]").replace(/([?&](?:token|access_token|key)=)[^\s&]+/gi, "$1[REDACTED]");
      fs.mkdirSync(path.dirname(output), {recursive: true}); fs.writeFileSync(path.join(path.dirname(output), `${name}.txt`), safeOutput);
    }
  }
  function deployFunctionsStep(preflight) {
    return deployStep(preflight ? "functions-preflight" : "functions", null, () => runFunctionsCommand({candidate,
      configPath, predecessor: before.state, candidateFile: functionCandidate, predecessorFile: functionPredecessor,
      receiptPath: path.join(path.dirname(output), preflight ? "function-preflight-plan.json" : "function-deployment-plan.json"), preflight}));
  }
  // Real CLI preparation precedes Hosting/rule changes. Dry-run can enable
  // prerequisite APIs, but the adapter forbids Function upload and release.
  deployFunctionsStep(true);
  // Existing HTML/Flutter/rewrites stay byte-for-byte intact while physical
  // content-addressed assets become available to the new Functions renderer.
  const bridge = await assets.publishBridge({candidate, webRoot: path.join(bundle, "web"), predecessor: before.state,
    output: path.join(path.dirname(output), "hosting-asset-bridge.json")});
  const bridged = await captureState(candidate.projectId);
  assets.assertBridgeState(bridged.state, bridge);
  if (c.digest(bridged.state) !== c.digest({...before.state, ...bridge.live})) throw Error("Non-Hosting deployment changed while publishing the asset bridge");
  // Explicit resources only. Missing-function retirement and index deletion never use --force.
  deployStep("rules-indexes-storage", "firestore:rules,firestore:indexes,storage");
  execFileSync(process.execPath, ["tools/verify_firestore_indexes.js", candidate.projectId, "1800"], {cwd: root, stdio: "inherit"});
  execFileSync(process.execPath, ["tools/check_function_secrets.js", candidate.projectId], {cwd: root, stdio: "inherit"});
  assets.assertBridgeState(await assets.currentHosting(candidate.projectId, await require("./web_release_state").googleClient()), bridge);
  deployFunctionsStep(false);
  const backendState = verifyState(candidate, await captureState(candidate.projectId), read(path.join(root, "firestore.indexes.json")));
  assets.assertBridgeState(backendState.state, bridge);
  write(path.join(path.dirname(output), "function-source-verification.json"),
      await require("./verify_web_function_sources").verifyFunctionSources({candidate, state: backendState.state}));
  if (candidate.environment === "staging") {
    const rehearsal = require("./rehearse_web_backend");
    const manifest = read(path.join(root, "config/web_backend_predecessor_archives.json"));
    const receipt = await rehearsal.rehearse({candidate, predecessor: expectedState, manifest,
      output: path.join(path.dirname(output), "backend-rehearsal.json")});
    write(path.join(path.dirname(output), "backend-rehearsal-verified.json"), await rehearsal.verifyRehearsal({candidate, receipt, manifest}));
    const rehearsed = verifyState(candidate, await captureState(candidate.projectId), read(path.join(root, "firestore.indexes.json")));
    assets.assertBridgeState(rehearsed.state, bridge);
  }
  c.validateArtifact(candidate, root, path.join(bundle, "web"));
  assets.assertBridgeState(await assets.currentHosting(candidate.projectId, await require("./web_release_state").googleClient()), bridge);
  deployStep("hosting", "hosting");
  const hostingClient = await require("./web_release_state").googleClient();
  const publishedHosting = await assets.currentHosting(candidate.projectId, hostingClient);
  if (publishedHosting.hostingVersion === bridge.live.hostingVersion || publishedHosting.hostingRelease === bridge.live.hostingRelease) throw Error("Hosting command did not publish a new final release");
  write(path.join(path.dirname(output), "hosting-publication.json"), {schemaVersion: 1, sourceSha: candidate.sourceSha,
    candidateRunId: candidate.candidateRunId, candidateSha256: c.digest(candidate), capturedAt: new Date().toISOString(), hosting: publishedHosting});
  const verified = await verifyPublishedDeployment(candidate, publishedHosting, {output, client: hostingClient});
  const {live, after} = verified;
  write(output, {schemaVersion: 1, environment: candidate.environment, sourceSha: candidate.sourceSha,
    candidateSha256: c.digest(candidate), verifiedAt: after.capturedAt, stateSha256: after.stateSha256,
    state: after.state, predecessor: before.state, hostingAssetBridgeSha256: c.digest(bridge),
    hostingLiveVerificationSha256: c.digest(live), hostingStateBeforeVerificationSha256: verified.before.stateSha256,
    hostingStateAfterVerificationSha256: after.stateSha256, workflowRunId: process.env.GITHUB_RUN_ID || null});
}
async function qualify(args) {
  const directory = path.resolve(args.output || "build/web-qualification"); const runId = args["candidate-run"];
  const provenance = {staging: download(runId, "candidate", "web-candidate-staging", path.join(directory, "staging")),
    production: download(runId, "candidate", "web-candidate-production", path.join(directory, "production")),
    deployment: download(runId, "candidate", "web-staging-deployment", path.join(directory, "deployment"))};
  const staging = loadCandidate(path.join(directory, "staging"), "staging"); const production = loadCandidate(path.join(directory, "production"), "production");
  const reports = []; const evidence = [];
  const runIds = [...new Set((args["evidence-runs"] || "").split(","))];
  if (runIds.length < 2 || runIds.length > 200) throw Error("Supply 2..200 retained observation/evidence run IDs");
  for (const id of runIds) {
    const evidenceRoot = path.join(directory, "evidence", id); evidence.push(download(id, "evidence", "web-staging-evidence", evidenceRoot));
    const index = read(path.join(evidenceRoot, "reports.json"));
    for (const file of index.reports) {
      const report = read(path.join(evidenceRoot, c.relativeFile(file)));
      if (String(report.workflowRunId) !== id) throw Error("Report workflow identity mismatch");
      c.validateEvidence(report, staging, evidenceRoot); reports.push(report);
    }
  }
  const receipt = c.qualify(staging, production, read(path.join(directory, "deployment", "deployment.json")), reports);
  const current = await captureState(c.PROJECTS.staging);
  if (current.stateSha256 !== receipt.stagingStateSha256) throw Error("Staging deployment changed after observation");
  write(path.join(directory, "qualification.json"), {...receipt, provenance, evidence, workflowRunId: process.env.GITHUB_RUN_ID});
}
async function promote(args) {
  const directory = path.resolve(args.output || "build/web-promotion");
  const qualificationProvenance = download(args["qualification-run"], "qualification", "web-qualification", path.join(directory, "qualification"));
  const receipt = read(path.join(directory, "qualification", "qualification.json"));
  if (String(receipt.workflowRunId) !== String(args["qualification-run"]) || receipt.sourceSha !== gitSha() || c.digest(receipt.requiredGates) !== c.digest(c.GATES) || Date.now() - Date.parse(receipt.qualifiedAt) > 86400000 || Date.parse(receipt.finishedAt) - Date.parse(receipt.startedAt) < 86400000) throw Error("Invalid or expired qualification receipt");
  const provenance = download(receipt.candidateRunId, "candidate", "web-candidate-production", path.join(directory, "candidate"));
  if (provenance.artifactId !== receipt.provenance.production.artifactId || provenance.artifactSha256 !== receipt.provenance.production.artifactSha256) throw Error("Production artifact provenance changed");
  const candidate = loadCandidate(path.join(directory, "candidate"), "production");
  if (c.digest(candidate) !== receipt.productionCandidateSha256 || c.digest(candidate.predecessor.production) !== receipt.predecessorProductionSha256) throw Error("Qualified candidate/predecessor changed");
  if (!args["expected-prior-release"] || args["expected-prior-release"] !== candidate.predecessor.production.hostingVersion) throw Error("Explicit expected prior Hosting version is required");
  if ((await captureState(c.PROJECTS.staging)).stateSha256 !== receipt.stagingStateSha256) throw Error("Qualified staging deployment drifted");
  await deploy(candidate, path.join(directory, "candidate"), candidate.predecessor.production, path.join(directory, "production-deployment.json"));
  write(path.join(directory, "promotion-provenance.json"), {qualificationProvenance, provenance});
}
async function main() {
  const [command, ...rest] = process.argv.slice(2); const args = options(rest);
  if (command === "seal") return seal(args);
  if (command === "capture-predecessors") {
    const [staging, production] = await Promise.all([captureState(c.PROJECTS.staging), captureState(c.PROJECTS.production)]);
    await require("./capture_web_predecessor").capture({state: staging.state, output: path.join(path.dirname(args.output), "staging-predecessor")});
    return write(args.output, {staging: staging.state, production: production.state});
  }
  if (command === "stage") {
    const candidate = loadCandidate(args.bundle, "staging");
    if (candidate.candidateRunId !== process.env.GITHUB_RUN_ID || candidate.sourceSha !== process.env.GITHUB_SHA) throw Error("Staging requires the current candidate workflow");
    return deploy(candidate, args.bundle, candidate.predecessor.staging, args.output);
  }
  if (command === "qualify") return qualify(args);
  if (command === "promote") return promote(args);
  throw Error("Expected capture-predecessors, seal, stage, qualify or promote");
}
if (require.main === module) main().catch((error) => { console.error(error.stack); process.exitCode = 1; });
module.exports = {download, loadCandidate, materializeBackend, materializeRules, options, verifyLive, verifyPublishedDeployment, validateFunctionCompletion, runFunctionsCommand, deploy, qualify, promote, write};
