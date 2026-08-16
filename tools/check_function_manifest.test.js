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
