"use strict";
// Read-only API collector. Disabled services are proven by the complete enabled
// service inventory plus protected project IAM; no API is enabled by this tool.
const fs = require("node:fs"), path = require("node:path"), crypto = require("node:crypto");
const {googleClient} = require("./web_release_state");
const {RECOVERY_PROJECT, validateRecoveryTarget} = require("../functions/tools/recovery-target");
const hash = (value) => crypto.createHash("sha256").update(value).digest("hex");
async function captureRecoveryTarget({outputDir, sourceProject = "orgami-66nxok", client = null}) {
  client ||= await googleClient();
  fs.mkdirSync(outputDir, {recursive: true});
  const evidence = {}, raw = {};
  const record = (name, value) => {
    const relative = `${name}.json`, bytes = Buffer.from(JSON.stringify(value, null, 2) + "\n");
    fs.writeFileSync(path.join(outputDir, relative), bytes); raw[relative] = bytes; evidence[name] = {path: relative, sha256: hash(bytes)};
  };
  async function pages(url, key, params = {}) {
    const values = [], requestUrls = []; let token;
    do {
      const response = (await client.request({url, params: {...params, ...(token ? {pageToken: token} : {})}})).data;
      if (!response || response[key] !== undefined && !Array.isArray(response[key])) throw Error(`Invalid recovery inventory response for ${key}`);
      requestUrls.push(url); values.push(...(response[key] || [])); token = response.nextPageToken;
      if (requestUrls.length > 100) throw Error("Recovery API pagination exceeded the bounded inventory budget");
    } while (token);
    return {values, requestUrls};
  }
  const project = (await client.request({url: `https://cloudresourcemanager.googleapis.com/v1/projects/${RECOVERY_PROJECT}`})).data;
  record("project", project);
  if (project.projectId !== RECOVERY_PROJECT || !/^\d+$/.test(project.projectNumber || "")) throw Error("Recovery project identity differs");
  const services = await pages(`https://serviceusage.googleapis.com/v1/projects/${project.projectNumber}/services`, "services", {filter: "state:ENABLED", pageSize: 200});
  record("enabledServices", services.values);
  record("enabledServicesPagination", {projectId: RECOVERY_PROJECT, requestUrls: services.requestUrls, complete: true});
  const iam = (await client.request({url: `https://cloudresourcemanager.googleapis.com/v1/projects/${RECOVERY_PROJECT}:getIamPolicy`, method: "POST", data: {options: {requestedPolicyVersion: 3}}})).data;
  record("iam", iam);
  const roleNames = [...new Set((iam.bindings || []).map((binding) => binding.role).filter((name) => name?.startsWith("projects/") || name?.startsWith("organizations/")))];
  if (roleNames.length > 30) throw Error("Recovery custom role inventory is unexpectedly large");
  const roles = [];
  for (const name of roleNames) {
    if (!name.startsWith(`projects/${RECOVERY_PROJECT}/roles/`)) throw Error("Recovery IAM references a role outside the reviewed project");
    roles.push((await client.request({url: `https://iam.googleapis.com/v1/${name}`})).data);
  }
  record("customRoles", roles);
  const enabled = new Set(services.values.map((service) => service.config?.name || service.name?.split("/").at(-1)));
  const specs = [
    ["functions", "cloudfunctions.googleapis.com", "functions", [`https://cloudfunctions.googleapis.com/v1/projects/${RECOVERY_PROJECT}/locations/-/functions`, `https://cloudfunctions.googleapis.com/v2/projects/${RECOVERY_PROJECT}/locations/-/functions`]],
    ["cloudRunServices", "run.googleapis.com", "services", [`https://run.googleapis.com/v2/projects/${RECOVERY_PROJECT}/locations/-/services`]],
    ["eventarcTriggers", "eventarc.googleapis.com", "triggers", [`https://eventarc.googleapis.com/v1/projects/${RECOVERY_PROJECT}/locations/-/triggers`]],
    ["schedulerJobs", "cloudscheduler.googleapis.com", "jobs", [`https://cloudscheduler.googleapis.com/v1/projects/${RECOVERY_PROJECT}/locations/-/jobs`]],
    ["hostingSites", "firebasehosting.googleapis.com", "sites", [`https://firebasehosting.googleapis.com/v1beta1/projects/${RECOVERY_PROJECT}/sites`]],
  ];
  for (const [name, api, key, urls] of specs) {
    if (!enabled.has(api)) continue;
    const entries = [], requestUrls = [];
    for (const url of urls) { const response = await pages(url, key); entries.push(...response.values); requestUrls.push(...response.requestUrls); }
    record(name, {projectId: RECOVERY_PROJECT, complete: true, requestUrls, [key]: entries});
  }
  const releases = await pages(`https://firebaserules.googleapis.com/v1/projects/${RECOVERY_PROJECT}/releases`, "releases");
  const rules = [];
  for (const release of releases.values) {
    if (!release.rulesetName?.startsWith(`projects/${RECOVERY_PROJECT}/rulesets/`)) throw Error("Unexpected recovery ruleset provenance");
    const set = (await client.request({url: `https://firebaserules.googleapis.com/v1/${release.rulesetName}`})).data;
    rules.push({name: release.name, rulesetName: release.rulesetName, files: set.source?.files || []});
  }
  record("rules", {projectId: RECOVERY_PROJECT, releases: rules});
  const proof = {schemaVersion: 1, projectId: RECOVERY_PROJECT, purpose: "isolated-recovery-proof", database: "(default)", capturedAt: new Date().toISOString(), evidence};
  const verified = validateRecoveryTarget(proof, {sourceProject, readEvidence: (relative) => raw[relative]});
  const proofPath = path.join(outputDir, "recovery-target-proof.json");
  fs.writeFileSync(proofPath, JSON.stringify(proof, null, 2) + "\n");
  return {proofPath, proof, verified, rawPaths: [...Object.keys(raw), "recovery-target-proof.json"]};
}
if (require.main === module) {
  const outputDir = process.argv[2];
  if (!outputDir) throw Error("Usage: node tools/capture_recovery_target.js <private-evidence-directory>");
  captureRecoveryTarget({outputDir}).then((result) => process.stdout.write(JSON.stringify(result.verified) + "\n")).catch((error) => { process.stderr.write(error.message + "\n"); process.exitCode = 1; });
}
module.exports = {captureRecoveryTarget};
