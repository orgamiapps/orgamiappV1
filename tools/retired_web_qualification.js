"use strict";

// Preserve exact reviewed suppression tombstones during later empty-site
// rehearsals. This never retires, deletes or changes a fixture.
const fs = require("node:fs");
const path = require("node:path");
const {digest, sha256} = require("./web_release_contract");
const PROJECT = "attendus-staging";
const FILE = "config/web_retired_qualification_fixtures.json";
const COLLECTIONS = Object.freeze(["QualificationScopes", "QualificationBindings", "QualificationSetup"]);
const PREFIX = `projects/${PROJECT}/databases/(default)/documents/`;
const HASH = /^[a-f0-9]{64}$/;
const RUN = /^webqa-[0-9]{8}-[a-f0-9]{10}$/;
const emptyManifest = () => ({schemaVersion: 1, projectId: PROJECT, runs: []});

function validateManifest(manifest) {
  if (manifest?.schemaVersion !== 1 || manifest.projectId !== PROJECT || !Array.isArray(manifest.runs) || manifest.runs.length > 100) throw Error("Invalid retired qualification manifest");
  const runs = new Set(), paths = new Set();
  for (const run of manifest.runs) {
    if (!RUN.test(run.runId || "") || runs.has(run.runId) || !/^[a-f0-9]{40}$/.test(run.sourceSha || "") || !/^[1-9][0-9]*$/.test(run.candidateRunId || "") || !HASH.test(run.cleanupEvidenceSha256 || "") || !Array.isArray(run.documents) || run.documents.length < 3 || run.documents.length > 10000) throw Error("Invalid retired run provenance");
    runs.add(run.runId);
    const kinds = {QualificationScopes: 0, QualificationBindings: 0, QualificationSetup: 0};
    for (const doc of run.documents) {
      const parts = typeof doc.path === "string" ? doc.path.split("/") : [];
      if (parts.length !== 2 || !COLLECTIONS.includes(parts[0]) || paths.has(doc.path) || !HASH.test(doc.sha256 || "") ||
          (parts[0] === "QualificationBindings" ? !/^(account|event|organization|conversation)_[a-f0-9]{64}$/.test(parts[1]) : parts[1] !== run.runId)) throw Error("Invalid or duplicate retired document");
      kinds[parts[0]]++; paths.add(doc.path);
    }
    if (kinds.QualificationScopes !== 1 || kinds.QualificationSetup !== 1 || kinds.QualificationBindings < 1) throw Error("Incomplete retired isolation lineage");
  }
  return manifest;
}

function loadManifest(candidate, root = path.resolve(__dirname, "..")) {
  const expected = candidate?.sourceFiles?.[FILE];
  // Older candidates were required to have an entirely empty isolation store.
  if (expected === undefined) return emptyManifest();
  const bytes = fs.readFileSync(path.join(root, FILE));
  // Git may expand LF source to CRLF on Windows. Permit only that exact
  // checkout conversion; semantic JSON equivalence is insufficient.
  if (!HASH.test(expected) || sha256(bytes) !== expected && sha256(bytes.toString("utf8").replace(/\r\n/g, "\n")) !== expected) throw Error("Retired qualification manifest differs from frozen source");
  return validateManifest(JSON.parse(bytes));
}

function validateDocument(doc, expected, run) {
  if (doc?.name !== PREFIX + expected.path || digest(doc) !== expected.sha256 || !doc.createTime || !doc.updateTime) throw Error("Retired document content/version differs from reviewed manifest");
  const f = doc.fields || {}, kind = expected.path.split("/")[0];
  if (f.schemaVersion?.integerValue !== "1" || f.projectId?.stringValue !== PROJECT) throw Error("Invalid retired isolation project/schema");
  if (kind === "QualificationBindings") {
    if (f.state?.stringValue !== "retired" || f.runId?.stringValue !== run.runId) throw Error("Active or foreign isolation binding");
  } else if (kind === "QualificationScopes") {
    const empty = (field) => field?.arrayValue && typeof field.arrayValue === "object" && !Array.isArray(field.arrayValue) &&
      (field.arrayValue.values === undefined || Array.isArray(field.arrayValue.values) && field.arrayValue.values.length === 0);
    if (f.status?.stringValue !== "retired" || f.mode?.stringValue !== "capture" || !empty(f.actorUids) || !empty(f.recipientUids)) throw Error("Retired scope still active or retaining deletion-blocking actors");
  } else if (f.state?.stringValue !== "retired" || f.sourceSha?.stringValue !== run.sourceSha || f.candidateRunId?.stringValue !== run.candidateRunId) throw Error("Retired setup lineage differs");
  return {path: expected.path, sha256: expected.sha256};
}

async function observeRetired(client, manifest) {
  validateManifest(manifest);
  const expected = new Map(manifest.runs.flatMap((run) => run.documents.map((doc) => [doc.path, {doc, run}])));
  const seen = new Set(), documents = [], counts = {};
  for (const collection of COLLECTIONS) {
    let token; const tokens = new Set(); counts[collection] = 0;
    do {
      const response = (await client.request({url: `https://firestore.googleapis.com/v1/${PREFIX}${collection}`, params: {pageSize: 100, showMissing: true, ...(token ? {pageToken: token} : {})}})).data;
      if (!response || typeof response !== "object" || Array.isArray(response) ||
          Object.hasOwn(response, "nextPageToken") && typeof response.nextPageToken !== "string") throw Error("Malformed isolation response/pagination");
      if (response.documents !== undefined && !Array.isArray(response.documents)) throw Error("Malformed isolation inventory");
      for (const doc of response.documents || []) {
        const local = typeof doc.name === "string" && doc.name.startsWith(PREFIX) ? doc.name.slice(PREFIX.length) : "";
        const pin = expected.get(local);
        if (!pin || !local.startsWith(collection + "/") || seen.has(local)) throw Error("Unreviewed or duplicate retained isolation document");
        documents.push(validateDocument(doc, pin.doc, pin.run)); seen.add(local); counts[collection]++;
      }
      token = response.nextPageToken;
      if (token && (typeof token !== "string" || tokens.has(token) || tokens.size >= 100)) throw Error("Incomplete isolation pagination");
      if (token) tokens.add(token);
    } while (token);
  }
  if (seen.size !== expected.size) throw Error("Reviewed isolation tombstone missing");
  documents.sort((a, b) => a.path.localeCompare(b.path));
  return {schemaVersion: 1, manifestSha256: digest(manifest), counts, documents};
}

function validateProof(proof, manifest, {allowLegacyEmpty = false} = {}) {
  validateManifest(manifest);
  // Historical all-empty receipts had no retained-isolation field.
  if (!proof && manifest.runs.length === 0 && allowLegacyEmpty) return true;
  const documents = manifest.runs.flatMap((run) => run.documents).sort((a, b) => a.path.localeCompare(b.path));
  const counts = Object.fromEntries(COLLECTIONS.map((collection) => [collection, documents.filter((doc) => doc.path.startsWith(collection + "/")).length]));
  if (proof?.schemaVersion !== 1 || proof.manifestSha256 !== digest(manifest) || digest(proof.documents) !== digest(documents) || digest(proof.counts) !== digest(counts)) throw Error("Retained-isolation rehearsal proof differs");
  return true;
}

module.exports = {FILE, COLLECTIONS, emptyManifest, validateManifest, loadManifest, validateDocument, observeRetired, validateProof};
