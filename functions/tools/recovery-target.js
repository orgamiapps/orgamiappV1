"use strict";

const fs = require("node:fs");
const path = require("node:path");
const {createHash} = require("node:crypto");
const RECOVERY_PROJECT = "attendus-recovery-20261004";
const FIRESTORE_DENY_ALL = "rules_version = '2'; service cloud.firestore { match /databases/{database}/documents { match /{document=**} { allow read, write: if false; } } }";
const STORAGE_DENY_ALL = "rules_version = '2'; service firebase.storage { match /b/{bucket}/o { match /{allPaths=**} { allow read, write: if false; } } }";
const hash = (value) => createHash("sha256").update(value).digest("hex");
const normalize = (value) => value.replace(/\/\/[^\n\r]*/g, "").replace(/\/\*[\s\S]*?\*\//g, "").replace(/\s+/g, "");

function validateRecoveryTarget(proof, {sourceProject, now = Date.now(), maxAgeMs = 15 * 60 * 1000, readEvidence} = {}) {
  if (!proof || proof.schemaVersion !== 1 || proof.projectId !== RECOVERY_PROJECT || proof.projectId === sourceProject || proof.database !== "(default)" || proof.purpose !== "isolated-recovery-proof") throw Error("Recovery must use the dedicated isolated recovery project");
  if (!Number.isFinite(Date.parse(proof.capturedAt)) || now - Date.parse(proof.capturedAt) > maxAgeMs || Date.parse(proof.capturedAt) > now + 60000) throw Error("Recovery target proof is stale");
  if (typeof readEvidence !== "function") throw Error("Raw API evidence reader is required");
  function raw(name) {
    const entry = proof.evidence?.[name];
    if (!entry || !/^[a-f0-9]{64}$/.test(entry.sha256 || "") || typeof entry.path !== "string" || entry.path.startsWith("/") || entry.path.includes("\\") || entry.path.includes(":") || entry.path.split("/").some((part) => !part || part === ".." || part === ".")) throw Error(`Missing or unsafe recovery evidence: ${name}`);
    const bytes = readEvidence(entry.path);
    if (hash(bytes) !== entry.sha256) throw Error(`Recovery evidence hash mismatch: ${name}`);
    return JSON.parse(bytes.toString());
  }
  const project = raw("project");
  if (project.projectId !== RECOVERY_PROJECT || project.lifecycleState !== "ACTIVE" ||
      !(project.labels?.attendus_purpose === "recovery-proof" || project.labels?.purpose === "attendus-release-recovery" && project.labels?.environment === "recovery" && project.labels?.["source-project"] === "orgami-66nxok")) throw Error("Recovery project metadata or labels differ");
  let disabledServices = null;
  if (proof.evidence.enabledServices) {
    const services = raw("enabledServices");
    const pagination = raw("enabledServicesPagination");
    const iam = raw("iam");
    const roles = proof.evidence.customRoles ? raw("customRoles") : [];
    if (project.parent || !/^\d+$/.test(String(project.projectNumber || "")) || !Array.isArray(services) || services.some((service) => !service.name?.startsWith(`projects/${project.projectNumber}/services/`) || service.state !== "ENABLED")) throw Error("Disabled-service proof needs complete project-scoped Service Usage evidence and no unexamined inherited IAM");
    if (pagination.projectId !== RECOVERY_PROJECT || pagination.complete !== true || pagination.nextPageToken || !Array.isArray(pagination.requestUrls) || !pagination.requestUrls.length || pagination.requestUrls.some((url) => url !== `https://serviceusage.googleapis.com/v1/projects/${project.projectNumber}/services`)) throw Error("Complete project-scoped Service Usage pagination proof is required");
    if (!Array.isArray(iam.bindings) || !iam.etag || !Array.isArray(roles)) throw Error("Recovery IAM inventory unavailable");
    const readonly = new Set(["roles/datastore.viewer", "roles/viewer", "roles/storage.objectViewer"]);
    for (const role of roles) {
      if (!role.name?.startsWith(`projects/${RECOVERY_PROJECT}/roles/`) || role.deleted || !Array.isArray(role.includedPermissions) || !role.includedPermissions.length || role.includedPermissions.some((permission) => !/\.(?:get|list|read|getIamPolicy)$/.test(permission) && !["datastore.databases.getMetadata", "serviceusage.services.use"].includes(permission))) throw Error("Recovery custom role includes unapproved mutation permissions");
      readonly.add(role.name);
    }
    const system = new Map([
      ["roles/firebaserules.system", `serviceAccount:service-${project.projectNumber}@firebase-rules.iam.gserviceaccount.com`],
      ["roles/firestore.serviceAgent", `serviceAccount:service-${project.projectNumber}@gcp-sa-firestore.iam.gserviceaccount.com`],
    ]);
    for (const binding of iam.bindings) {
      if (!Array.isArray(binding.members) || !binding.members.length || binding.members.some((member) => member === "allUsers" || member === "allAuthenticatedUsers")) throw Error("Recovery IAM principal inventory invalid");
      if (readonly.has(binding.role)) continue;
      const allowed = binding.role === "roles/owner" ? "user:orgamiapps@gmail.com" : system.get(binding.role);
      if (!allowed || binding.members.some((member) => member !== allowed)) throw Error("Recovery IAM allows an unapproved service creator");
    }
    disabledServices = new Set(services.map((service) => service.config?.name || service.name.split("/").at(-1)));
  }
  const keys = {functions: "functions", cloudRunServices: "services", eventarcTriggers: "triggers", schedulerJobs: "jobs", hostingSites: "sites"};
  const apis = {functions: "cloudfunctions.googleapis.com", cloudRunServices: "run.googleapis.com", eventarcTriggers: "eventarc.googleapis.com", schedulerJobs: "cloudscheduler.googleapis.com", hostingSites: "firebasehosting.googleapis.com"};
  for (const [name, key] of Object.entries(keys)) {
    if (!proof.evidence[name] && disabledServices && !disabledServices.has(apis[name])) continue;
    const response = raw(name);
    if (response.projectId !== RECOVERY_PROJECT || response.complete !== true || !Array.isArray(response[key]) || response[key].length || response.nextPageToken || !Array.isArray(response.requestUrls) || !response.requestUrls.length || response.requestUrls.some((url) => typeof url !== "string" || !url.includes(`/projects/${RECOVERY_PROJECT}/`))) throw Error(`Recovery project has listeners or incomplete inventory: ${name}`);
  }
  const rules = raw("rules");
  if (rules.projectId !== RECOVERY_PROJECT || !Array.isArray(rules.releases) || !rules.releases.length) throw Error("Recovery rules inventory is incomplete");
  let firestore = false;
  for (const release of rules.releases) {
    if (!release.name?.startsWith(`projects/${RECOVERY_PROJECT}/releases/`) || !release.rulesetName?.startsWith(`projects/${RECOVERY_PROJECT}/rulesets/`) || release.files?.length !== 1) throw Error("Recovery rules release provenance differs");
    const isFirestore = release.name.endsWith("/cloud.firestore");
    if (!isFirestore && !release.name.includes("/firebase.storage/")) throw Error("Unexpected recovery rules release");
    if (normalize(release.files[0].content || "") !== normalize(isFirestore ? FIRESTORE_DENY_ALL : STORAGE_DENY_ALL)) throw Error("Recovery data rules must be exactly deny-all");
    firestore ||= isFirestore;
  }
  if (!firestore) throw Error("Recovery Firestore deny-all rules missing");
  return {projectId: RECOVERY_PROJECT, capturedAt: proof.capturedAt, proofSha256: hash(JSON.stringify(proof)), isolated: true};
}
function readRecoveryTargetProof(file, options = {}) {
  const root = path.dirname(path.resolve(file));
  return validateRecoveryTarget(JSON.parse(fs.readFileSync(file, "utf8")), {...options,
    readEvidence: (relative) => fs.readFileSync(path.join(root, relative))});
}
module.exports = {RECOVERY_PROJECT, FIRESTORE_DENY_ALL, STORAGE_DENY_ALL, validateRecoveryTarget, readRecoveryTargetProof};
