"use strict";
const test = require("node:test");
const assert = require("node:assert/strict");
const {boundSecrets, deploymentSecrets} = require("./check_function_secrets");
test("collect deployed endpoint bindings", () => {
  assert.deepEqual([...boundSecrets({core: {__endpoint: {secretEnvironmentVariables: [{key: "CORE"}]}},
    disabledProvider: {__endpoint: {secretEnvironmentVariables: []}}, helper: () => {}})], ["CORE"]);
});
test("provider-disabled source manifest has no Apple or Google Wallet binding", () => {
  delete process.env.ATTENDANCE_APPLE_DELIVERY_ENABLED;
  delete process.env.ATTENDANCE_GOOGLE_DELIVERY_ENABLED;
  const functions = require("../functions/index");
  const {declaredParams} = require(require.resolve("firebase-functions/params", {paths: [require("node:path").join(__dirname, "../functions")]}));
  const names = deploymentSecrets(functions, declaredParams);
  assert.ok(names.has("ATTENDANCE_PASS_SIGNING_KEY"));
  assert.equal(names.has("APPLE_WALLET_SIGNING"), false);
  assert.equal(names.has("GOOGLE_WALLET_SERVICE_ACCOUNT_JSON"), false);
});


test("unbound declared secret parameters are deployment dependencies", () => {
  assert.deepEqual([...deploymentSecrets({}, [{toSpec: () => ({type: "secret", name: "UNBOUND"})},
    {toSpec: () => ({type: "string", name: "PUBLIC_SETTING"})}])], ["UNBOUND"]);
});
