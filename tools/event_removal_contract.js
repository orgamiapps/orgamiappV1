"use strict";

// Supplemental evidence only. Never edits the canonical seven-event pilot.
const fs = require("node:fs");
const path = require("node:path");
const crypto = require("node:crypto");
const {execFileSync} = require("node:child_process");
const ROLE_KEYS = Object.freeze(["owner", "viewer", "outsider"]);
const EVENT_KEYS = Object.freeze(["publicDelete", "privateDelete", "publicCancel", "privateCancel", "restricted", "race"]);
const PROJECT = "attendus-staging";
const ORIGIN = "https://attendus-staging.web.app";
const sha = bytes => crypto.createHash("sha256").update(bytes).digest("hex");
function canonical(value) {
  if (Array.isArray(value)) return `[${value.map(canonical).join(",")}]`;
  if (value && typeof value === "object") return `{${Object.keys(value).sort().map(key => `${JSON.stringify(key)}:${canonical(value[key])}`).join(",")}}`;
  return JSON.stringify(value);
}
const digest = value => sha(canonical(value));
function need(condition, code) { if (!condition) throw Object.assign(Error(code), {code}); }
const safeCode = error => /^[A-Z][A-Z0-9_]{1,100}$/.test(error?.code || "") ? error.code : "LIVE_CHECK_FAILED";
function validateContext({candidate, receipt, fixture}) {
  need(candidate?.environment === "staging" && candidate.projectId === PROJECT &&
    /^[a-f0-9]{40}$/.test(candidate.sourceSha || "") && /^\d+$/.test(String(candidate.candidateRunId || "")), "CANDIDATE_INVALID");
  need(receipt?.environment === "staging" && receipt.sourceSha === candidate.sourceSha &&
    receipt.candidateSha256 === digest(candidate) && /^[a-f0-9]{64}$/.test(receipt.stateSha256 || "") &&
    Number.isFinite(Date.parse(receipt.verifiedAt)), "DEPLOYMENT_RECEIPT_INVALID");
  need(fixture?.schemaVersion === 1 && fixture.purpose === "event-removal-live" && fixture.projectId === PROJECT &&
    /^webqa-\d{8}-[a-f0-9]{10}$/.test(fixture.runId || "") &&
    ["prepared", "seeding", "seeded"].includes(fixture.state) &&
    fixture.sourceSha === candidate.sourceSha && String(fixture.candidateRunId) === String(candidate.candidateRunId) &&
    fixture.candidateSha256 === digest(candidate) && fixture.stagingStateSha256 === receipt.stateSha256 &&
    fixture.deploymentReceiptSha256 === digest(receipt), "FIXTURE_PROVENANCE_INVALID");
  need(Array.isArray(fixture.canonicalEventIds) && fixture.canonicalEventIds.length === 7 &&
    new Set(fixture.canonicalEventIds).size === 7 && fixture.canonicalEventIds.every(id => typeof id === "string" && id) &&
    typeof fixture.canonicalRunId === "string" && fixture.canonicalRunId !== fixture.runId, "CANONICAL_SCOPE_INVALID");
  const owned = fixture.ownedFixtureIds;
  need(Array.isArray(owned) && new Set(owned).size === owned.length, "OWNED_IDS_INVALID");
  const ids = [];
  for (const role of ROLE_KEYS) {
    const actor = fixture.roles?.[role];
    need(actor?.uid === `${fixture.runId}-${role}` && actor.email === `${actor.uid}@example.test` &&
      typeof actor.password === "string" && actor.password.length >= 20 && owned.includes(actor.uid), "ACTOR_SCOPE_INVALID");
    ids.push(actor.uid);
  }
  for (const key of EVENT_KEYS) {
    const event = fixture.events?.[key];
    need(event?.id === `${fixture.runId}-${key}` && typeof event.title === "string" &&
      event.title.startsWith("Removal QA ") && event.title.length <= 150 &&
      event.private === ["privateDelete", "privateCancel", "restricted"].includes(key) &&
      owned.includes(event.id) && !fixture.canonicalEventIds.includes(event.id), "EVENT_SCOPE_INVALID");
    ids.push(event.id);
  }
  need(fixture.organizationId === `${fixture.runId}-community` && owned.includes(fixture.organizationId) &&
    new Set(ids).size === ids.length && !owned.some(id => fixture.canonicalEventIds.includes(id)), "FIXTURE_SCOPE_OVERLAP");
  const historyIds = [];
  for (const key of ["publicCancel", "privateCancel"]) {
    const history = fixture.history?.[key];
    for (const [field, suffix] of [["registrationId", "registration"], ["ticketId", "ticket"], ["attendanceId", "attendance"]]) {
      need(history?.[field] === `${fixture.runId}-${key}-${suffix}`, "HISTORY_SCOPE_INVALID");
      historyIds.push(history[field]);
    }
  }
  need(digest([...owned].sort()) === digest([...ids, fixture.organizationId, ...historyIds].sort()), "OWNED_SCOPE_NOT_EXACT");
  need(fixture.firebase?.projectId === PROJECT && fixture.firebase.projectNumber === "925344893088" &&
    /^AIza[0-9A-Za-z_-]{35}$/.test(fixture.firebase.apiKey || "") &&
    typeof fixture.firebase.appId === "string" && fixture.firebase.appId.startsWith("1:925344893088:web:") &&
    fixture.firebase.storageBucket === "attendus-staging.firebasestorage.app" &&
    /^[A-Za-z0-9_-]{20,100}$/.test(fixture.firebase.appCheckSiteKey || ""), "FIREBASE_SCOPE_INVALID");
  need(/^AIza[0-9A-Za-z_-]{35}$/.test(fixture.mapsApiKey || ""), "STAGING_MAPS_KEY_REQUIRED");
  return fixture;
}
function assertLiveEnvironment(environment = process.env) {
  need(!Object.entries(environment).some(([key, value]) => value && (/EMULATOR/.test(key) ||
    /APPCHECK.*DEBUG|APP_CHECK.*DEBUG/.test(key))), "LIVE_ENVIRONMENT_REQUIRED");
}
function sourceCheck(repo, candidate) {
  const git = args => execFileSync("git", args, {cwd: repo, encoding: "utf8", stdio: ["ignore", "pipe", "pipe"]}).trim();
  need(git(["rev-parse", "HEAD"]) === candidate.sourceSha && git(["status", "--porcelain"]) === "", "SOURCE_NOT_FROZEN");
  const committed = require(path.join(repo, "tools/web_release_contract")).gitSourceFiles(repo, "tools/");
  for (const name of ["tools/event_removal_contract.js", "tools/event_removal_live_acceptance.js",
    "tools/event_removal_observer.js", "tools/seed_event_removal_qualification.js"]) {
    need(committed[name] && candidate.sourceFiles?.[name] === sha(committed[name]), "HARNESS_NOT_IN_CANDIDATE");
    const checkout = fs.readFileSync(path.join(repo, name));
    need(sha(checkout) === sha(committed[name]) ||
      sha(Buffer.from(checkout.toString("utf8").replace(/\r\n/g, "\n"))) === sha(committed[name]), "HARNESS_CHECKOUT_DIFFERS");
  }
}
function privateDirectory(repo, directory) {
  const target = path.resolve(directory), build = path.resolve(repo, "build");
  need(target.startsWith(build + path.sep) && !fs.existsSync(target), "PRIVATE_OUTPUT_MUST_BE_NEW");
  let parent = path.dirname(target);
  while (!fs.existsSync(parent)) parent = path.dirname(parent);
  need(fs.realpathSync(parent) === parent && !fs.lstatSync(parent).isSymbolicLink(), "PRIVATE_OUTPUT_LINK_FORBIDDEN");
  execFileSync("git", ["check-ignore", "--quiet", target], {cwd: repo, stdio: "pipe"});
  fs.mkdirSync(target, {recursive: true, mode: 0o700});
  return target;
}
function save(file, value) {
  fs.writeFileSync(file, JSON.stringify(value, null, 2) + "\n", {flag: "wx", mode: 0o600});
}
function createJournal(directory) {
  fs.mkdirSync(directory, {mode: 0o700});
  let sequence = 0;
  return (kind, value = {}) => {
    need(/^[a-z0-9-]{1,60}$/.test(kind), "JOURNAL_KIND_INVALID");
    save(path.join(directory, `${String(++sequence).padStart(4, "0")}-${kind}.json`),
      {at: new Date().toISOString(), kind, ...value});
  };
}
function options(args) {
  const result = {};
  for (let i = 0; i < args.length; i += 2) {
    need(/^--[a-z-]+$/.test(args[i] || "") && args[i + 1] && !args[i + 1].startsWith("--"), "ARGUMENTS_INVALID");
    need(!Object.hasOwn(result, args[i].slice(2)), "DUPLICATE_ARGUMENT");
    result[args[i].slice(2)] = args[i + 1];
  }
  return result;
}
module.exports = {ROLE_KEYS, EVENT_KEYS, PROJECT, ORIGIN, digest, sha, need, safeCode, validateContext,
  assertLiveEnvironment, sourceCheck, privateDirectory, save, createJournal, options};
