#!/usr/bin/env node
"use strict";

const fs = require("node:fs");
const path = require("node:path");
const contracts = require("./firestore_query_contracts");

const ignoredDirectories = new Set([
  ".dart_tool", ".git", "build", "node_modules", "stale-web-releases",
]);

function sourceFiles(directory) {
  const files = [];
  for (const entry of fs.readdirSync(directory, {withFileTypes: true})) {
    if (ignoredDirectories.has(entry.name)) continue;
    const target = path.join(directory, entry.name);
    if (entry.isDirectory()) files.push(...sourceFiles(target));
    else if (target.endsWith(".js") || target.endsWith(".dart")) files.push(target);
  }
  return files;
}

function discoverQueries(root) {
  const discovered = [];
  for (const relative of ["functions", "lib", "apps"]) {
    const directory = path.join(root, relative);
    if (!fs.existsSync(directory)) continue;
    for (const file of sourceFiles(directory)) {
      const source = fs.readFileSync(file, "utf8");
      for (const match of source.matchAll(/\.collectionGroup\(\s*["']([^"']+)["']/g)) {
        const tail = source.slice(match.index, match.index + 1200);
        const statement = tail.split(";")[0];
        const fields = [...statement.matchAll(/\.where\(\s*["']([^"']+)["']/g)]
            .map((field) => field[1]);
        discovered.push({collectionGroup: match[1], fields, file});
      }
    }
  }
  const deletion = fs.readFileSync(
      path.join(root, "functions", "account", "deletion.js"), "utf8",
  );
  const block = deletion.match(/COLLECTION_GROUP_QUERIES\s*=\s*Object\.freeze\(\[([\s\S]*?)\]\);/);
  for (const match of (block?.[1] || "").matchAll(/\["([^"]+)",\s*"([^"]+)"\]/g)) {
    discovered.push({collectionGroup: match[1], fields: [match[2]], file: "account/deletion.js"});
  }
  return discovered;
}

function hasGroupFieldOverride(manifest, collectionGroup, fieldPath) {
  const override = (manifest.fieldOverrides || []).find((entry) =>
    entry.collectionGroup === collectionGroup && entry.fieldPath === fieldPath,
  );
  return Boolean(override?.indexes?.some((index) =>
    index.queryScope === "COLLECTION_GROUP" && index.order === "ASCENDING",
  ));
}

function hasCompositeIndex(manifest, contract) {
  const fields = contract.filters.map((filter) => `${filter.fieldPath}:ASCENDING`);
  return (manifest.indexes || []).some((index) =>
    index.collectionGroup === contract.collectionGroup &&
    index.queryScope === "COLLECTION_GROUP" &&
    index.fields.map((field) => `${field.fieldPath}:${field.order}`).join("|") ===
      fields.join("|"),
  );
}

function validate(root, manifest) {
  const errors = [];
  for (const query of discoverQueries(root)) {
    for (const fieldPath of query.fields) {
      if (!contracts.some((contract) =>
        contract.collectionGroup === query.collectionGroup &&
        contract.filters.some((filter) => filter.fieldPath === fieldPath),
      )) {
        errors.push(`Undeclared collection-group query ${query.collectionGroup}.${fieldPath} in ${query.file}`);
      }
    }
  }
  for (const contract of contracts) {
    if (contract.filters.length === 1) {
      const field = contract.filters[0].fieldPath;
      if (!hasGroupFieldOverride(manifest, contract.collectionGroup, field)) {
        errors.push(`Missing collection-group field index ${contract.collectionGroup}.${field}`);
      }
    } else if (!hasCompositeIndex(manifest, contract)) {
      errors.push(`Missing collection-group composite index ${contract.collectionGroup}(` +
        `${contract.filters.map((filter) => filter.fieldPath).join(", ")})`);
    }
  }
  if (errors.length) throw new Error(errors.join("\n"));
  return {contracts: contracts.length, queries: discoverQueries(root).length};
}

function main() {
  const root = path.resolve(__dirname, "..");
  const manifest = JSON.parse(fs.readFileSync(path.join(root, "firestore.indexes.json"), "utf8"));
  const result = validate(root, manifest);
  process.stdout.write(
      `Verified ${result.contracts} Firestore query contracts across ` +
      `${result.queries} collection-group call sites.\n`,
  );
}

if (require.main === module) {
  try {
    main();
  } catch (error) {
    process.stderr.write(`${error.stack || error.message}\n`);
    process.exit(1);
  }
}

module.exports = {discoverQueries, hasCompositeIndex, hasGroupFieldOverride, validate};
