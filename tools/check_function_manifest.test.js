"use strict";

const assert = require("node:assert/strict");
const test = require("node:test");
const {
  expectedFunctions,
  verifyInventory,
} = require("./check_function_manifest");

test("manifest parser finds exported functions", () => {
  assert.deepEqual(
      [...expectedFunctions("exports.alpha = value;\nexports.beta = value;")]
          .sort(),
      ["alpha", "beta"],
  );
});

test("manifest verifier reports drift and inactive deployments", () => {
  const result = verifyInventory(new Set(["alpha", "beta"]), [
    {id: "alpha", state: "ACTIVE"},
    {id: "legacy", state: "FAILED"},
  ]);
  assert.deepEqual(result.liveOnly, ["legacy"]);
  assert.deepEqual(result.sourceOnly, ["beta"]);
  assert.deepEqual(result.inactive, ["legacy:FAILED"]);
});

test("source inventory matches every runtime Firebase endpoint", () => {
  const fs = require("node:fs");
  const path = require("node:path");
  const entry = path.join(__dirname, "../functions/index.js");
  const runtime = require(entry);
  const endpoints = Object.keys(runtime).filter((name) => runtime[name].__endpoint);
  assert.deepEqual([...expectedFunctions(fs.readFileSync(entry, "utf8"))].sort(), endpoints.sort());
  assert.ok(endpoints.includes("previewEventChangeV1"));
  assert.ok(endpoints.includes("listMyAdmissionsV1"));
});
