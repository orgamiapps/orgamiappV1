"use strict";

const fs = require("node:fs");
const path = require("node:path");
const {DISCOVERY_CATEGORIES} = require("../functions/discovery/category-catalog");

const dartCatalogPath = path.join(__dirname, "..", "lib", "models", "discovery_category.dart");

function readDartCatalog(source = fs.readFileSync(dartCatalogPath, "utf8")) {
  const entries = [];
  const pattern = /DiscoveryCategory\(\s*'([^']+)'\s*,\s*'([^']+)'\s*,/g;
  for (const match of source.matchAll(pattern)) {
    entries.push({id: match[1], label: match[2]});
  }
  return entries;
}

function catalogDifference(backend, flutter) {
  const normalize = (entries) => entries.map(({id, label}) => ({id, label}));
  return JSON.stringify(normalize(backend)) === JSON.stringify(normalize(flutter)) ? null :
    {backend: normalize(backend), flutter: normalize(flutter)};
}

function verifyDiscoveryCategoryCatalog() {
  const flutter = readDartCatalog();
  const difference = catalogDifference(DISCOVERY_CATEGORIES, flutter);
  if (difference) {
    throw new Error(`Discovery category catalog drift:\n${JSON.stringify(difference, null, 2)}`);
  }
  return flutter.length;
}

if (require.main === module) {
  const count = verifyDiscoveryCategoryCatalog();
  console.log(`Discovery category catalog verified (${count} categories).`);
}

module.exports = {catalogDifference, readDartCatalog, verifyDiscoveryCategoryCatalog};
