"use strict";
const test = require("node:test");
const assert = require("node:assert/strict");
const {createHash} = require("node:crypto");
const {RECOVERY_PROJECT, FIRESTORE_DENY_ALL, validateRecoveryTarget} = require("../tools/recovery-target");
function fixture() {
  const data = {project: {projectId: RECOVERY_PROJECT, lifecycleState: "ACTIVE", labels: {attendus_purpose: "recovery-proof"}},
    rules: {projectId: RECOVERY_PROJECT, releases: [{name: `projects/${RECOVERY_PROJECT}/releases/cloud.firestore`, rulesetName: `projects/${RECOVERY_PROJECT}/rulesets/one`, files: [{content: FIRESTORE_DENY_ALL}]}]}};
  for (const [name, key] of Object.entries({functions: "functions", cloudRunServices: "services", eventarcTriggers: "triggers", schedulerJobs: "jobs", hostingSites: "sites"})) data[name] = {projectId: RECOVERY_PROJECT, complete: true, requestUrls: [`https://example.googleapis.com/v1/projects/${RECOVERY_PROJECT}/locations/-/${key}`], [key]: []};
  const proof = {schemaVersion: 1, projectId: RECOVERY_PROJECT, purpose: "isolated-recovery-proof", database: "(default)", capturedAt: new Date().toISOString(), evidence: {}};
  const build = () => {
    const bytes = Object.fromEntries(Object.entries(data).map(([key, value]) => [`${key}.json`, Buffer.from(JSON.stringify(value))]));
    for (const [name, value] of Object.entries(bytes)) proof.evidence[name.slice(0, -5)] = {path: name, sha256: createHash("sha256").update(value).digest("hex")};
    return {proof, readEvidence: (name) => bytes[name]};
  };
  return {proof, data, build};
}
test("complete isolated recovery target proof accepts raw deny-all sources", () => {
  const {proof, readEvidence} = fixture().build();
  assert.equal(validateRecoveryTarget(proof, {sourceProject: "orgami-66nxok", readEvidence}).isolated, true);
});
test("staging and production can never be restore targets", () => {
  for (const projectId of ["attendus-staging", "orgami-66nxok"]) {
    const {proof, readEvidence} = fixture().build(); proof.projectId = projectId;
    assert.throws(() => validateRecoveryTarget(proof, {readEvidence}), /dedicated/);
  }
});
test("active listener, incomplete page and permissive rules each reject recovery", () => {
  for (const change of [(data) => data.functions.functions.push({name: "listener"}), (data) => { data.schedulerJobs.nextPageToken = "more"; }, (data) => { data.rules.releases[0].files[0].content = FIRESTORE_DENY_ALL.replace("false", "true"); }]) {
    const f = fixture(); change(f.data); const {proof, readEvidence} = f.build();
    assert.throws(() => validateRecoveryTarget(proof, {readEvidence}), /listeners|deny-all/);
  }
});
test("modified raw output and stale proof are rejected", () => {
  const {proof, readEvidence} = fixture().build();
  assert.throws(() => validateRecoveryTarget(proof, {readEvidence: () => Buffer.from("{}")}), /hash mismatch/);
  assert.throws(() => validateRecoveryTarget(proof, {readEvidence, now: Date.now() + 16 * 60 * 1000}), /stale/);
});

function disabledFixture() {
  const f = fixture();
  for (const key of ["functions", "cloudRunServices", "eventarcTriggers", "schedulerJobs", "hostingSites"]) delete f.data[key];
  f.data.project.projectNumber = "123456789";
  f.data.enabledServices = [{name: "projects/123456789/services/firestore.googleapis.com", state: "ENABLED", config: {name: "firestore.googleapis.com"}}];
  f.data.enabledServicesPagination = {projectId: RECOVERY_PROJECT, complete: true, requestUrls: ["https://serviceusage.googleapis.com/v1/projects/123456789/services"]};
  f.data.iam = {etag: "current", bindings: [{role: "roles/owner", members: ["user:orgamiapps@gmail.com"]}, {role: `projects/${RECOVERY_PROJECT}/roles/reader`, members: ["serviceAccount:reader@example.iam.gserviceaccount.com"]}]};
  f.data.customRoles = [{name: `projects/${RECOVERY_PROJECT}/roles/reader`, includedPermissions: ["datastore.databases.getMetadata", "serviceusage.services.use", "resourcemanager.projects.getIamPolicy"]}];
  return f;
}
test("disabled listener APIs require current complete inventory and only readonly extra IAM", () => {
  const {proof, readEvidence} = disabledFixture().build();
  assert.equal(validateRecoveryTarget(proof, {readEvidence}).isolated, true);
});
test("disabled API proof rejects incomplete pagination, enabled listeners, mutating roles and unapproved owners", () => {
  for (const change of [
    (data) => { data.enabledServicesPagination.complete = false; },
    (data) => { data.enabledServices.push({name: "projects/123456789/services/run.googleapis.com", state: "ENABLED"}); },
    (data) => { data.customRoles[0].includedPermissions.push("serviceusage.services.enable"); },
    (data) => { data.iam.bindings[0].members.push("user:other@example.com"); },
  ]) {
    const f = disabledFixture(); change(f.data); const {proof, readEvidence} = f.build();
    assert.throws(() => validateRecoveryTarget(proof, {readEvidence}), /pagination|Missing|mutation|creator/);
  }
});
