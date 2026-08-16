"use strict";

const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const test = require("node:test");
const {validate} = require("./check_firestore_query_contracts");

const root = path.resolve(__dirname, "..");

function manifest() {
  return JSON.parse(fs.readFileSync(path.join(root, "firestore.indexes.json"), "utf8"));
}

test("manifest covers every collection-group query contract", () => {
  assert.doesNotThrow(() => validate(root, manifest()));
});

test("missing Followers.userId index fails the contract check", () => {
  const value = manifest();
  value.fieldOverrides = value.fieldOverrides.filter((entry) =>
    entry.collectionGroup !== "Followers" || entry.fieldPath !== "userId",
  );
  assert.throws(() => validate(root, value), /Followers\.userId/);
});
