#!/usr/bin/env node
"use strict";

const {execFileSync} = require("node:child_process");
const fs = require("node:fs");
const path = require("node:path");

function normalizeField(field) {
  if (field.order) return `${field.fieldPath}:order:${field.order}`;
  if (field.arrayConfig) return `${field.fieldPath}:arrayConfig:${field.arrayConfig}`;
  if (field.vectorConfig) {
    return `${field.fieldPath}:vectorConfig:${JSON.stringify(field.vectorConfig)}`;
  }
  throw new Error(`Unsupported index field: ${JSON.stringify(field)}`);
}

function normalizeIndex(collectionGroup, queryScope, fields) {
  const userFields = fields.filter((field) => field.fieldPath !== "__name__");
  return [collectionGroup, queryScope, ...userFields.map(normalizeField)].join("|");
}

function normalizeFieldIndex(fieldPath, index) {
  return normalizeIndex(fieldPath, index.queryScope || "COLLECTION", [{
    fieldPath,
    order: index.order || index.fields?.[0]?.order,
    arrayConfig: index.arrayConfig || index.fields?.[0]?.arrayConfig,
  }]);
}

function fieldResource(name) {
  const match = name.match(/\/collectionGroups\/([^/]+)\/fields\/(.+)$/);
  if (!match) throw new Error(`Unexpected Firestore field name: ${name}`);
  return {collectionGroup: decodeURIComponent(match[1]), fieldPath: decodeURIComponent(match[2])};
}

function remoteCollectionGroup(index) {
  const match = index.name.match(/\/collectionGroups\/([^/]+)\/indexes\//);
  if (!match) throw new Error(`Unexpected Firestore index name: ${index.name}`);
  return decodeURIComponent(match[1]);
}

function expectedState(manifest) {
  const composites = new Map();
  for (const index of manifest.indexes || []) {
    const key = normalizeIndex(index.collectionGroup, index.queryScope, index.fields);
    if (composites.has(key)) throw new Error(`Duplicate composite index: ${key}`);
    composites.set(key, index);
  }
  const fields = new Map();
  for (const field of manifest.fieldOverrides || []) {
    const key = `${field.collectionGroup}|${field.fieldPath}`;
    if (fields.has(key)) throw new Error(`Duplicate field override: ${key}`);
    fields.set(key, {
      indexes: new Set((field.indexes || []).map((index) =>
        normalizeFieldIndex(field.fieldPath, index),
      )),
      ttl: field.ttl === true,
    });
  }
  return {composites, fields};
}

function inspect(manifest, remoteIndexes, remoteFields) {
  const expected = expectedState(manifest);
  const remoteComposites = new Map();
  for (const index of remoteIndexes) {
    remoteComposites.set(
        normalizeIndex(remoteCollectionGroup(index), index.queryScope, index.fields), index,
    );
  }
  const remoteOverrides = new Map();
  for (const field of remoteFields) {
    const parsed = fieldResource(field.name);
    if (parsed.collectionGroup === "__default__") continue;
    remoteOverrides.set(`${parsed.collectionGroup}|${parsed.fieldPath}`, field);
  }

  const missing = [];
  const pending = [];
  const terminal = [];
  for (const key of expected.composites.keys()) {
    const index = remoteComposites.get(key);
    if (!index) missing.push(`composite:${key}`);
    else if (index.state === "CREATING") pending.push(`composite:${key}`);
    else if (index.state !== "READY") terminal.push(`composite:${key} (${index.state || "UNKNOWN"})`);
  }
  for (const [key, expectedField] of expected.fields) {
    const field = remoteOverrides.get(key);
    if (!field) {
      missing.push(`field:${key}`);
      continue;
    }
    const parsed = fieldResource(field.name);
    const remoteFieldIndexes = new Set((field.indexConfig?.indexes || []).map((index) =>
      normalizeFieldIndex(parsed.fieldPath, index),
    ));
    for (const index of expectedField.indexes) {
      if (!remoteFieldIndexes.has(index)) missing.push(`field-index:${key}|${index}`);
    }
    for (const index of field.indexConfig?.indexes || []) {
      if (index.state === "CREATING") pending.push(`field-index:${key}`);
      else if (index.state && index.state !== "READY") {
        terminal.push(`field-index:${key} (${index.state})`);
      }
    }
    if (expectedField.ttl && field.ttlConfig?.state !== "ACTIVE") {
      if (field.ttlConfig?.state === "CREATING") pending.push(`ttl:${key}`);
      else terminal.push(`ttl:${key} (${field.ttlConfig?.state || "MISSING"})`);
    }
  }
  const extra = [
    ...[...remoteComposites.keys()].filter((key) => !expected.composites.has(key))
        .map((key) => `composite:${key}`),
    ...[...remoteOverrides.keys()].filter((key) => !expected.fields.has(key))
        .map((key) => `field:${key}`),
  ];
  return {missing, pending, terminal, extra};
}

function gcloudJson(projectId, type) {
  const command = type === "composite" ?
    `gcloud firestore indexes composite list --project=${projectId} ` +
      "--database=^(default^) --format=json" :
    `gcloud firestore indexes fields list --project=${projectId} ` +
      "--database=^(default^) --format=json";
  if (process.platform === "win32") {
    return JSON.parse(execFileSync("cmd.exe", ["/d", "/s", "/c", command], {
      encoding: "utf8",
    }));
  }
  const args = type === "composite" ?
    ["firestore", "indexes", "composite", "list"] :
    ["firestore", "indexes", "fields", "list"];
  return JSON.parse(execFileSync("gcloud", [
    ...args, `--project=${projectId}`, "--database=(default)", "--format=json",
  ], {encoding: "utf8"}));
}

async function verify(projectId, timeoutSeconds, manifest, readRemote = gcloudJson) {
  const deadline = Date.now() + timeoutSeconds * 1000;
  while (true) {
    const result = inspect(
        manifest, readRemote(projectId, "composite"), readRemote(projectId, "field"),
    );
    if (result.terminal.length) {
      throw new Error(`Firestore indexes entered a terminal state:\n${result.terminal.join("\n")}`);
    }
    if (!result.missing.length && !result.pending.length) {
      if (result.extra.length) {
        throw new Error(`Deployed index drift detected in ${projectId}:\n${result.extra.join("\n")}`);
      }
      return;
    }
    if (Date.now() >= deadline) {
      throw new Error(
          `Timed out waiting for Firestore indexes in ${projectId}. ` +
          `Missing: ${result.missing.length}; creating: ${result.pending.length}.`,
      );
    }
    console.log(
        `Waiting for Firestore indexes in ${projectId}: ` +
        `${result.missing.length} missing, ${result.pending.length} creating.`,
    );
    await new Promise((resolve) => setTimeout(resolve, 15000));
  }
}

async function main() {
  const projectId = process.argv[2];
  const timeoutSeconds = Number(process.argv[3] || 1800);
  if (!projectId || !Number.isFinite(timeoutSeconds) || timeoutSeconds <= 0 ||
      !/^[a-z][a-z0-9-]{4,29}$/.test(projectId)) {
    throw new Error("Usage: node tools/verify_firestore_indexes.js <project-id> [timeout-seconds]");
  }
  const manifest = JSON.parse(fs.readFileSync(path.resolve("firestore.indexes.json"), "utf8"));
  await verify(projectId, timeoutSeconds, manifest);
  const expected = expectedState(manifest);
  console.log(
      `Verified ${expected.composites.size} composite indexes and ` +
      `${expected.fields.size} field overrides in ${projectId}.`,
  );
}

if (require.main === module) {
  main().catch((error) => {
    console.error(error instanceof Error ? error.stack : error);
    process.exit(1);
  });
}

module.exports = {expectedState, inspect, normalizeFieldIndex, normalizeIndex, verify};
